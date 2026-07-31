-- =====================================================================
-- Cuántos de los que ocupan puesto vencen ese mismo día
--
-- EL PROBLEMA, TAL CUAL PASA
-- Una mensualidad que termina hoy sigue contando hoy: su puesto está
-- descontado del aforo y el sistema no ofrece esa silla a clase suelta.
-- Correcto — pero esa persona puede no venir, y si no viene tampoco
-- renueva. Resultado: se guardó un puesto que nadie usó y se dejó de
-- vender una suelta que sí se habría vendido.
--
-- Lo que hace falta no es que el sistema decida por su cuenta, sino que
-- diga el número: "de los 27 que tienen plan a las 6, 2 vencen hoy".
-- Con eso se puede arriesgar a vender 2 sueltas de más sabiendo
-- exactamente cuánto se arriesga.
--
-- POR QUÉ NO SE SUMA A `cupo_total`
-- Porque no es un cupo: es una apuesta. Si los dos aparecen —y suelen
-- aparecer, la gente renueva el último día— y además se vendieron dos
-- sueltas, la sala queda apretada y a alguien le toca de pie. Que la
-- decisión la tome una persona, con el número delante, no una función.
--
-- CÓMO SE CUENTA
-- Mismo criterio que `recalcular_cupos` usa para `activos_plan`, más
-- `fin = ese día`. Así el número nuevo siempre es un subconjunto del que
-- ya sale en la tarjeta y los dos no se pueden contradecir.
--
-- Se cuenta contra la fecha DE LA CLASE, no contra hoy: el tablero se
-- mueve día a día, y en la tarjeta del lunes que viene tiene que salir
-- quién vence el lunes que viene.
-- =====================================================================

create or replace function admin_tablero(p_token text, p_dia date default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_dia    date;
  v_clases jsonb;
  v_hoy    date;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  v_hoy := (now() at time zone 'America/Bogota')::date;
  v_dia := coalesce(p_dia, v_hoy);

  select coalesce(jsonb_agg(x order by x->>'hora'), '[]'::jsonb) into v_clases
  from (
    select jsonb_build_object(
      'clase_id',    c.id,
      'nombre',      c.nombre,
      'hora',        to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'),
      'activa',      c.activa,
      'ya_paso',     c.fecha_hora <= now(),
      -- de dónde sale el cupo
      'aforo',       c.aforo,
      'con_plan',    c.activos_plan,
      'a_la_venta',  c.cupo_total,
      'cupo_manual', c.cupo_manual,
      -- de los que tienen plan, cuántos se les acaba ESE día
      'vencen',      v.vencen,
      -- qué se ha vendido
      'reservadas',  c.cupo_tomado,
      'libres',      greatest(c.cupo_total - c.cupo_tomado, 0),
      'confirmadas', n.confirmadas,
      'por_validar', n.por_validar,
      'esperando',   n.esperando,
      -- cuánta gente entra
      'en_sala',     c.activos_plan + c.cupo_tomado,
      'ingreso_cop', n.confirmadas * c.precio_cop
    ) as x
    from clases c
    cross join lateral (
      select
        count(*) filter (where r.estado = 'confirmada')::int            as confirmadas,
        count(*) filter (where r.estado = 'pendiente_validacion')::int  as por_validar,
        count(*) filter (where r.estado in ('pendiente_pago','verificando'))::int as esperando
      from reservas r where r.clase_id = c.id
    ) n
    cross join lateral (
      -- Mismo filtro que recalcular_cupos, y encima `fin = ese dia`. Al
      -- ser un subconjunto, nunca puede salir mayor que `con_plan`.
      select count(*)::int as vencen
        from membresias m
       where m.hora = (c.fecha_hora at time zone 'America/Bogota')::time
         and (c.fecha_hora at time zone 'America/Bogota')::date
             between m.inicio and m.fin
         and m.fin = (c.fecha_hora at time zone 'America/Bogota')::date
    ) v
   where (c.fecha_hora at time zone 'America/Bogota')::date = v_dia
  ) s;

  return jsonb_build_object(
    'ok', true,
    'dia', v_dia,
    'es_hoy', v_dia = v_hoy,
    'clases', v_clases,
    'resumen', jsonb_build_object(
      'clases',      jsonb_array_length(v_clases),
      'aforo',       coalesce((select sum((c->>'aforo')::int)       from jsonb_array_elements(v_clases) c), 0),
      'con_plan',    coalesce((select sum((c->>'con_plan')::int)    from jsonb_array_elements(v_clases) c), 0),
      'vencen',      coalesce((select sum((c->>'vencen')::int)      from jsonb_array_elements(v_clases) c), 0),
      'a_la_venta',  coalesce((select sum((c->>'a_la_venta')::int)  from jsonb_array_elements(v_clases) c), 0),
      'reservadas',  coalesce((select sum((c->>'reservadas')::int)  from jsonb_array_elements(v_clases) c), 0),
      'libres',      coalesce((select sum((c->>'libres')::int)      from jsonb_array_elements(v_clases) c), 0),
      'confirmadas', coalesce((select sum((c->>'confirmadas')::int) from jsonb_array_elements(v_clases) c), 0),
      'por_validar', coalesce((select sum((c->>'por_validar')::int) from jsonb_array_elements(v_clases) c), 0),
      'esperando',   coalesce((select sum((c->>'esperando')::int)   from jsonb_array_elements(v_clases) c), 0),
      'en_sala',     coalesce((select sum((c->>'en_sala')::int)     from jsonb_array_elements(v_clases) c), 0),
      'ingreso_cop', coalesce((select sum((c->>'ingreso_cop')::int) from jsonb_array_elements(v_clases) c), 0)
    ));
end;
$$;

comment on function admin_tablero(text, date) is
  'Tarjetas del dia para el panel. `vencen` son los del plan a los que se les acaba ESE dia: no se suman al cupo, se muestran para poder decidir si se arriesga a vender sueltas de mas.';


-- ---------------------------------------------------------------------
-- Y en la puerta, marcados uno por uno
--
-- Es el momento en que esa persona está enfrente. Saber que su plan se
-- acaba hoy convierte la lista de acceso en la mejor oportunidad de
-- renovación que hay: no hay que llamar a nadie, ya llegó.
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
      'marcada_at', a.marcada_at
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

revoke execute on function admin_tablero(text, date)     from public, anon, authenticated;
revoke execute on function admin_lista_clase(text, uuid) from public, anon, authenticated;

-- `create or replace` conserva los permisos, asi que el grant de 0016 y
-- 0018 sobrevive y esto es redundante. Va igual: si alguien aplica esta
-- migracion sola, o cambia el orden, el permiso queda puesto de todos
-- modos. Un grant de mas no rompe nada; el que falta si.
grant execute on function admin_tablero(text, date)     to service_role;
grant execute on function admin_lista_clase(text, uuid) to service_role;
