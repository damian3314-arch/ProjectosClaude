-- ---------------------------------------------------------------------
-- 0035 — Pagó y no vino: clases por disfrutar
--
-- EL PROBLEMA
-- Alguien paga su clase y no aparece. Hoy eso no se puede ni anotar: en
-- la lista de la puerta o se marca que entró o se queda sin marcar, y
-- "sin marcar" también es lo que le pasa a quien todavía no ha llegado.
-- A las nueve de la noche nadie sabe quién faltó, y al día siguiente esa
-- persona escribe diciendo que pagó, con razón, y no hay dónde mirarlo.
--
-- LO QUE HACE
-- Un tercer estado en la puerta: "no vino". Marcarlo no borra el pago —
-- esa plata entró y está bien contada— sino que le abre a la persona un
-- crédito de TRES DÍAS para usar esa clase otro día.
--
-- POR QUÉ TRES DÍAS Y NO "para siempre"
-- Porque un crédito sin fecha es un pasivo que crece solo y que nadie
-- vuelve a mirar. Tres días es lo que pidió el negocio, y la fecha se
-- calcula desde la clase que se perdió, no desde el día que alguien
-- se acordó de marcarlo.
--
-- POR QUÉ NO SE BORRA NADA AL VENCER
-- La fila se queda como está: `no_vino_at` puesto y `credito_vence`
-- pasado. Deja de salir en la pantalla, que es lo que se pidió, pero
-- si alguien reclama en una semana se puede mirar qué pasó. Borrar
-- para que una lista se vea corta es perder la única prueba.
-- ---------------------------------------------------------------------

alter table reservas add column if not exists no_vino_at     timestamptz;
alter table reservas add column if not exists credito_vence  date;
alter table reservas add column if not exists reprogramada_a uuid references reservas(id);
alter table reservas add column if not exists viene_de       uuid references reservas(id);

comment on column reservas.no_vino_at is
  'Se marcó en la puerta que pagó y no asistió. El pago se queda donde está: lo que se abre es un crédito.';
comment on column reservas.credito_vence is
  'Último día para usar la clase que no disfrutó. Se cuenta desde la clase perdida, no desde el día que se marcó.';
comment on column reservas.reprogramada_a is
  'La reserva nueva a la que se movió. Puesto esto, el crédito ya se usó.';

create index if not exists reservas_por_disfrutar on reservas (credito_vence)
  where no_vino_at is not null and reprogramada_a is null;


-- ---------------------------------------------------------------------
-- Marcar que no vino
--
-- Solo sobre reservas confirmadas: si no pagó, no hay nada que
-- devolverle, y marcarlo solo ensuciaría la lista. Y solo sobre sueltas:
-- quien tiene mensualidad no perdió una clase pagada, perdió un día de
-- su plan, y eso no se arregla con un crédito.
-- ---------------------------------------------------------------------
create or replace function admin_marcar_no_vino(
  p_token text, p_clase_id uuid, p_ref text, p_no_vino boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_res   reservas%rowtype;
  v_clase clases%rowtype;
  v_dias  constant int := 3;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_clase from clases where id = p_clase_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'CLASE_NO_EXISTE');
  end if;

  -- Misma forma de referencia que usa la lista de la puerta: 'r:CODIGO'.
  if split_part(p_ref, ':', 1) <> 'r' then
    return jsonb_build_object('ok', false, 'error', 'SOLO_RESERVAS',
      'mensaje', 'Solo se marca en quien reservó y pagó, no en quien viene por plan.');
  end if;

  select * into v_res from reservas
   where codigo = upper(trim(substring(p_ref from position(':' in p_ref) + 1)))
     and clase_id = p_clase_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE',
      'mensaje', 'Esa reserva no es de esta clase.');
  end if;

  if not p_no_vino then
    update reservas set no_vino_at = null, credito_vence = null, updated_at = now()
     where id = v_res.id;
    return jsonb_build_object('ok', true, 'no_vino', false,
      'codigo', v_res.codigo, 'nombre', v_res.nombre,
      'mensaje', 'Se quitó la marca.');
  end if;

  if v_res.estado <> 'confirmada' then
    return jsonb_build_object('ok', false, 'error', 'NO_PAGO',
      'mensaje', 'Esa reserva no está confirmada: no hay clase pagada que guardarle. '
              || 'Si el cupo hay que soltarlo, usa Liberar.');
  end if;
  if v_res.tipo <> 'suelta' then
    return jsonb_build_object('ok', false, 'error', 'ES_MIEMBRO',
      'mensaje', 'Quien viene por mensualidad no pierde una clase pagada.');
  end if;
  if v_res.reprogramada_a is not null then
    return jsonb_build_object('ok', false, 'error', 'YA_REPROGRAMADA',
      'mensaje', 'Esa clase ya se movió a otro día.');
  end if;

  -- No vino: si alguien le había marcado la entrada, sobra.
  delete from asistencias where reserva_id = v_res.id and clase_id = p_clase_id;

  update reservas
     set no_vino_at    = now(),
         -- Desde la clase que se perdió. Marcarlo tres días tarde no le
         -- regala tres días más a nadie.
         credito_vence = (v_clase.fecha_hora at time zone 'America/Bogota')::date + v_dias,
         updated_at    = now()
   where id = v_res.id;

  return jsonb_build_object('ok', true, 'no_vino', true,
    'codigo', v_res.codigo, 'nombre', v_res.nombre,
    'vence', (v_clase.fecha_hora at time zone 'America/Bogota')::date + v_dias,
    'entraron', (select count(*)::int from asistencias where clase_id = p_clase_id),
    'mensaje', 'Anotado. Tiene ' || v_dias || ' días para usar esa clase.');
end;
$$;


-- ---------------------------------------------------------------------
-- Quiénes tienen clase pagada sin disfrutar
--
-- Sale ordenado por lo que se vence primero: es una lista para llamar
-- gente, y a quien le queda un día hay que llamarlo hoy.
-- ---------------------------------------------------------------------
create or replace function admin_por_disfrutar(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_hoy    date;
  v_out    jsonb;
  v_clases jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  v_hoy := (now() at time zone 'America/Bogota')::date;

  select coalesce(jsonb_agg(x order by x->>'vence', x->>'nombre'), '[]'::jsonb)
    into v_out
  from (
    select jsonb_build_object(
      'codigo',     r.codigo,
      'nombre',     r.nombre,
      'telefono',   r.telefono,
      'clase',      c.nombre,
      'clase_id',   c.id,
      'fecha_hora', c.fecha_hora,
      'precio_cop', c.precio_cop,
      'vence',      r.credito_vence,
      -- Cero = se vence hoy. Es el dato con el que se decide a quién
      -- llamar primero.
      'dias',       (r.credito_vence - v_hoy),
      'marcada_at', r.no_vino_at
    ) as x
    from reservas r
    join clases c on c.id = r.clase_id
   where r.no_vino_at is not null
     and r.reprogramada_a is null
     and r.estado = 'confirmada'
     and r.credito_vence >= v_hoy
  ) s;

  -- Y las clases a las que se puede mover a alguien, aquí mismo.
  --
  -- Se podría sacar del horario que el panel ya se trae para la
  -- cuadrícula, pero esa respuesta tiene otra forma —día y hora por
  -- separado— y armar una fecha a partir de ella es justo donde salen
  -- los "Invalid time value". Quien pinta el desplegable no debería
  -- tener que saber cómo se llaman los campos de otra pantalla.
  select coalesce(jsonb_agg(y order by y->>'fecha_hora'), '[]'::jsonb)
    into v_clases
  from (
    select jsonb_build_object(
             'clase_id',   c.id,
             'nombre',     c.nombre,
             'fecha_hora', c.fecha_hora,
             'libres',     greatest(c.cupo_total - c.cupo_tomado, 0)) as y
      from clases c
     where c.activa
       and c.fecha_hora > now()
       and c.cupo_tomado < c.cupo_total
     order by c.fecha_hora
     limit 40
  ) t;

  return jsonb_build_object('ok', true, 'gente', v_out,
                            'clases', v_clases, 'hoy', v_hoy);
end;
$$;


-- ---------------------------------------------------------------------
-- Reprogramar
--
-- Le da el cupo en otra clase sin volver a cobrar. La reserva vieja NO
-- se borra ni se rechaza: se queda confirmada y apuntando a la nueva.
-- Esa plata entró el día que entró y la caja de ese día ya cuadró;
-- moverla ahora descuadraría un cierre que ya se imprimió y se archivó.
-- ---------------------------------------------------------------------
create or replace function admin_reprogramar(
  p_token text, p_codigo text, p_clase_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_res    reservas%rowtype;
  v_hoy    date;
  v_nueva  jsonb;
  v_id     uuid;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  v_hoy := (now() at time zone 'America/Bogota')::date;

  select * into v_res from reservas
   where codigo = upper(trim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;
  if v_res.no_vino_at is null then
    return jsonb_build_object('ok', false, 'error', 'NO_TIENE_CREDITO',
      'mensaje', 'Esa reserva no está marcada como que no vino.');
  end if;
  if v_res.reprogramada_a is not null then
    return jsonb_build_object('ok', false, 'error', 'YA_REPROGRAMADA',
      'mensaje', 'Esa clase ya se movió a otro día.');
  end if;
  if v_res.credito_vence < v_hoy then
    return jsonb_build_object('ok', false, 'error', 'VENCIDA',
      'vencio', v_res.credito_vence,
      'mensaje', 'El plazo se venció el ' || to_char(v_res.credito_vence, 'DD/MM') ||
                 '. Si se le va a dar igual, hay que apuntarla a mano.');
  end if;
  if p_clase_id = v_res.clase_id then
    return jsonb_build_object('ok', false, 'error', 'MISMA_CLASE',
      'mensaje', 'Esa es la clase que se perdió. Escoge otra.');
  end if;

  -- El cupo lo da tomar_cupo con su bloqueo de fila: si la clase nueva
  -- está llena, aquí se acaba. Reprogramar no puede sobrevender.
  v_nueva := tomar_cupo(p_clase_id, v_res.nombre, v_res.telefono, v_res.email,
                        'reprogramada', 'suelta');
  if (v_nueva->>'ok')::boolean is not true then
    return v_nueva;   -- SIN_CUPO, CLASE_YA_PASO…
  end if;

  v_id := (v_nueva->>'reserva_id')::uuid;

  -- La nueva nace confirmada y sin pago propio: la plata ya entró con la
  -- vieja. `viene_de` es lo que deja ver, mirando una fila, que no es un
  -- cobro que se perdió sino una clase que se movió.
  update reservas
     set estado       = 'confirmada',
         viene_de     = v_res.id,
         resuelta_por = v_admin,
         resuelta_at  = now(),
         updated_at   = now()
   where id = v_id;

  update reservas
     set reprogramada_a = v_id, updated_at = now()
   where id = v_res.id;

  return jsonb_build_object('ok', true,
    'codigo',       v_nueva->>'codigo',
    'codigo_viejo', v_res.codigo,
    'nombre',       v_res.nombre,
    'telefono',     v_res.telefono,
    'clase',        v_nueva->>'clase',
    'fecha_hora',   v_nueva->>'fecha_hora',
    'mensaje',      'Reprogramada. Código nuevo: ' || (v_nueva->>'codigo') || '.');
end;
$$;


-- ---------------------------------------------------------------------
-- La lista de la puerta dice quién no vino
--
-- Se añaden dos campos a cada fila. Sin ellos el botón no sabría si ya
-- está marcado, y marcar dos veces se sentiría como que no responde.
-- ---------------------------------------------------------------------
create or replace function admin_lista_clase(p_token text, p_clase_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_clase  clases%rowtype;
  v_fecha  date;
  v_hora   time;
  v_res    jsonb;
  v_plan   jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_clase from clases where id = p_clase_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  v_fecha := (v_clase.fecha_hora at time zone 'America/Bogota')::date;
  v_hora  := (v_clase.fecha_hora at time zone 'America/Bogota')::time;

  select coalesce(jsonb_agg(x order by x->>'nombre'), '[]'::jsonb) into v_res
  from (
    select jsonb_build_object(
      'ref',        'r:' || r.codigo,
      'codigo',     r.codigo,
      'nombre',     r.nombre,
      'telefono',   r.telefono,
      'tipo',       r.tipo,
      'estado',     r.estado,
      'confirmada', r.estado = 'confirmada',
      'asistio',    a.id is not null,
      'marcada_at', a.marcada_at,
      -- Pagó y no vino. Sin esto el botón no sabría si ya está marcado,
      -- y volver a tocarlo se sentiría como que no responde.
      'no_vino',    r.no_vino_at is not null,
      'credito_vence', r.credito_vence
    ) as x
    from reservas r
    left join asistencias a on a.reserva_id = r.id
   where r.clase_id = p_clase_id
     and r.estado not in ('expirada', 'rechazada')
  ) s;

  select coalesce(jsonb_agg(x order by x->>'nombre'), '[]'::jsonb) into v_plan
  from (
    select jsonb_build_object(
      'ref',        'p:' || coalesce(solo_digitos(m.celular), m.afiliado),
      'nombre',     m.afiliado,
      'telefono',   m.celular,
      'membresia',  m.membresia,
      'hasta',      m.fin,
      'vence_hoy',  m.fin = v_fecha,
      'asistio',    a.id is not null,
      'marcada_at', a.marcada_at
    ) as x
    from membresias m
    left join asistencias a
           on a.clase_id = p_clase_id
          and a.origen = 'plan'
          and solo_digitos(a.telefono) = solo_digitos(m.celular)
   where m.hora = v_hora
     and v_fecha between m.inicio and m.fin
     and not exists (
       select 1 from reservas r
        where r.clase_id = p_clase_id
          and r.estado not in ('expirada', 'rechazada')
          and solo_digitos(r.telefono) = solo_digitos(m.celular))
  ) s;

  return jsonb_build_object(
    'ok', true,
    'clase', jsonb_build_object(
      'clase_id', v_clase.id,
      'nombre',   v_clase.nombre,
      'fecha',    v_fecha,
      'hora',     to_char(v_hora, 'HH24:MI'),
      'aforo',    v_clase.aforo,
      'ya_paso',  v_clase.fecha_hora <= now()),
    'reservas', v_res,
    'con_plan', v_plan,
    'resumen', jsonb_build_object(
      'reservas',        jsonb_array_length(v_res),
      'con_plan',        jsonb_array_length(v_plan),
      'esperados',       jsonb_array_length(v_res) + jsonb_array_length(v_plan),
      'entraron',        (select count(*)::int from asistencias where clase_id = p_clase_id),
      'vencen',          (select count(*)::int from jsonb_array_elements(v_plan) e
                           where (e->>'vence_hoy')::boolean),
      'sin_confirmar',   (select count(*)::int from jsonb_array_elements(v_res) e
                           where (e->>'confirmada')::boolean is not true)));
end;
$$;


-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke execute on function admin_marcar_no_vino(text, uuid, text, boolean)
  from public, anon, authenticated;
revoke execute on function admin_por_disfrutar(text) from public, anon, authenticated;
revoke execute on function admin_reprogramar(text, text, uuid)
  from public, anon, authenticated;
revoke execute on function admin_lista_clase(text, uuid) from public, anon, authenticated;

grant execute on function admin_marcar_no_vino(text, uuid, text, boolean) to service_role;
grant execute on function admin_por_disfrutar(text)                       to service_role;
grant execute on function admin_reprogramar(text, text, uuid)             to service_role;
grant execute on function admin_lista_clase(text, uuid)                   to service_role;
