-- ---------------------------------------------------------------------
-- 0043 — "Paga al llegar": la plata entra cuando entra la persona
--
-- LO QUE FALTABA EN LA 0042
-- La 0042 hizo que apuntar a mano preguntara cómo pagó, y que el
-- efectivo entrara al cajón en la misma llamada. Pero "efectivo" tapaba
-- dos cosas distintas:
--
--   a) La persona está en el mostrador y entrega los 15.000 ahora.
--   b) Llama o escribe, se le aparta el cupo, y paga cuando llegue.
--
-- En el caso (b) el cajón todavía no tiene esa plata. Registrarla al
-- apuntar deja el arqueo esperando un dinero que no está — y si esa
-- persona no aparece, no está nunca.
--
-- POR QUÉ NO SE ARREGLA DESDE "NO VINO"
-- Era lo primero que se pensó: que marcar "no vino" descontara la plata.
-- Pero "no vino" hoy significa "PAGÓ y no vino", y por eso le guarda un
-- crédito de tres días. Si además descontara, a quien sí pagó en el
-- mostrador y luego no apareció se le quitaría del cajón una plata que
-- sí está. Dos situaciones distintas no pueden compartir un botón.
--
-- LA REGLA, QUE ES LA ÚNICA QUE HACE AUDITABLE UNA CAJA
-- La plata entra al cajón cuando la plata entra al cajón. Ni antes.
--
-- CÓMO QUEDA
--   'efectivo'      ya la entregó       -> entra ahora  (0042)
--   'transferencia' está en el banco    -> no toca caja (0042)
--   'en_puerta'     paga cuando llegue  -> entra al marcarle la entrada
--
-- Y así el caso que preocupaba se resuelve solo: si no viene, nunca se
-- registró nada y no hay nada que deshacer.
--
-- SE APOYA EN ALGO QUE YA SE HACE
-- Marcar quién entró no es una costumbre nueva que haya que crear: en
-- los días revisados estaba marcado el 100% —5 de 5, 10 de 10, 6 de 6—.
-- El cobro viaja pegado a un gesto que ya existe.
--
-- SI SE DESMARCA LA ENTRADA
-- Se anula el movimiento. Un clic equivocado no puede dejar en la caja
-- un ingreso que nadie entregó, que es el mismo problema al revés.
-- ---------------------------------------------------------------------

-- Aditivo: ninguna fila existente cambia de sentido.
alter table reservas
  add column if not exists cobra_en_puerta boolean not null default false;
alter table reservas
  add column if not exists cobrado_en_puerta_at timestamptz;
-- Se guarda el movimiento para poder anular EXACTAMENTE ese si alguien
-- desmarca la entrada. Sin esto habría que adivinar cuál era.
alter table reservas
  add column if not exists cobro_mov_id uuid;

comment on column reservas.cobra_en_puerta is
  'Se apuntó a mano con "paga al llegar": el efectivo entra al marcarle la entrada, no antes.';


-- ---------------------------------------------------------------------
-- admin_crear_reserva — ahora acepta 'en_puerta'
-- ---------------------------------------------------------------------
create or replace function admin_crear_reserva(
  p_token    text,
  p_clase_id uuid,
  p_nombre   text,
  p_telefono text,
  p_tipo     text default 'suelta',
  p_nota     text default null,
  p_medio    text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_tel    text;
  v_r      jsonb;
  v_cod    text;
  v_medio  text;
  v_precio int;
  v_caja   jsonb;
  v_ef_ok  boolean := null;
  v_ef_msg text := null;
  v_puerta boolean := false;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  if length(btrim(coalesce(p_nombre, ''))) < 2 then
    return jsonb_build_object('ok', false, 'error', 'NOMBRE_CORTO',
      'mensaje', 'Escribe el nombre de la persona.');
  end if;

  v_tel := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  if length(v_tel) = 12 and left(v_tel, 2) = '57' then
    v_tel := substr(v_tel, 3);
  end if;
  if length(v_tel) <> 10 then
    return jsonb_build_object('ok', false, 'error', 'CELULAR_INVALIDO',
      'mensaje', 'El celular debe tener 10 dígitos.');
  end if;

  -- Se valida ANTES de tomar el cupo: un cupo tomado con la plata sin
  -- resolver es el peor de los estados.
  v_medio := nullif(btrim(lower(coalesce(p_medio, ''))), '');
  if v_medio is not null and v_medio not in ('efectivo', 'transferencia', 'en_puerta') then
    return jsonb_build_object('ok', false, 'error', 'MEDIO_INVALIDO',
      'mensaje', 'El pago tiene que ser efectivo, transferencia o al llegar.');
  end if;

  v_r := tomar_cupo(p_clase_id, btrim(p_nombre), v_tel, null,
                    'recepcion',
                    case when p_tipo = 'miembro' then 'miembro' else 'suelta' end);

  if (v_r->>'ok')::boolean is not true then
    return v_r;
  end if;

  v_cod := v_r->>'codigo';

  if (v_r->>'estado') <> 'confirmada' then
    update reservas
       set estado = 'confirmada',
           resuelta_por = v_admin,
           resuelta_at = now(),
           updated_at = now()
     where codigo = v_cod;
  end if;

  if p_nota is not null and btrim(p_nota) <> '' then
    update reservas set pagador_nombre = left(btrim(p_nota), 80) where codigo = v_cod;
  end if;

  v_precio := coalesce((v_r->>'precio_cop')::int, 0);

  -- ── ya pagó en efectivo: entra ahora ──
  if v_medio = 'efectivo' and (v_r->>'tipo') <> 'miembro' and v_precio > 0 then
    v_caja := caja_registrar(
      p_token, 'ingreso', 'clase_suelta', v_precio, 'efectivo',
      'Reserva ' || v_cod || ' — ' || btrim(p_nombre));

    v_ef_ok := coalesce((v_caja->>'ok')::boolean, false);
    if not v_ef_ok then
      v_ef_msg := coalesce(
        v_caja->>'mensaje',
        'No se pudo registrar el efectivo (' || coalesce(v_caja->>'error', 'motivo desconocido') || ').')
        || ' La reserva SÍ quedó: apunta esos '
        || to_char(v_precio, 'FM999G999G999') || ' en la caja a mano.';
    else
      update reservas set cobro_mov_id = (v_caja->>'id')::uuid,
                          cobrado_en_puerta_at = now()
       where codigo = v_cod;
    end if;
  end if;

  -- ── paga al llegar: NO entra todavía ──
  -- Se deja marcada, y el cobro lo dispara marcarle la entrada. Si no
  -- viene, no se registró nada y no hay nada que deshacer.
  if v_medio = 'en_puerta' and (v_r->>'tipo') <> 'miembro' and v_precio > 0 then
    update reservas set cobra_en_puerta = true where codigo = v_cod;
    v_puerta := true;
  end if;

  return jsonb_build_object(
    'ok', true,
    'codigo', v_cod,
    'nombre', btrim(p_nombre),
    'telefono', v_tel,
    'tipo', v_r->>'tipo',
    'clase', v_r->>'clase',
    'fecha_hora', v_r->>'fecha_hora',
    'precio_cop', v_precio,
    'medio', v_medio,
    'efectivo_registrado', v_ef_ok,
    'aviso_efectivo', v_ef_msg,
    -- true = queda pendiente de cobrar cuando llegue
    'cobra_en_puerta', v_puerta,
    'mensaje', 'Reserva creada y confirmada.');
end;
$$;

revoke execute on function admin_crear_reserva(text, uuid, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function admin_crear_reserva(text, uuid, text, text, text, text, text)
  to service_role;


-- ---------------------------------------------------------------------
-- admin_marcar_asistencia — cobra al entrar, devuelve al desmarcar
--
-- Es la 0018 con el cobro añadido. La parte de las membresías no se
-- toca: quien viene por plan no paga en la puerta.
-- ---------------------------------------------------------------------
create or replace function admin_marcar_asistencia(
  p_token text, p_clase_id uuid, p_ref text, p_asistio boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_tipo   text;
  v_valor  text;
  v_res    reservas%rowtype;
  v_memb   membresias%rowtype;
  v_clase  clases%rowtype;
  v_hora   time;
  v_fecha  date;
  v_caja   jsonb;
  v_cobro  int := null;
  v_cobro_ok boolean := null;
  v_cobro_msg text := null;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_clase from clases where id = p_clase_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'CLASE_NO_EXISTE');
  end if;

  v_tipo  := split_part(p_ref, ':', 1);
  v_valor := substring(p_ref from position(':' in p_ref) + 1);
  if v_valor is null or v_valor = '' then
    return jsonb_build_object('ok', false, 'error', 'REF_INVALIDA');
  end if;

  ------------------------------------------------------------------
  -- Una reserva
  ------------------------------------------------------------------
  if v_tipo = 'r' then
    select * into v_res from reservas
     where codigo = upper(trim(v_valor)) and clase_id = p_clase_id
     for update;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'NO_EXISTE',
        'mensaje', 'Esa reserva no es de esta clase.');
    end if;

    if p_asistio then
      insert into asistencias (clase_id, reserva_id, nombre, telefono,
                               origen, marcada_por)
      values (p_clase_id, v_res.id, v_res.nombre, v_res.telefono,
              'reserva', v_admin)
      on conflict do nothing;          -- marcar dos veces no cuenta dos

      -- ── el cobro de quien pagaba al llegar ──
      -- La condición de `cobrado_en_puerta_at is null` es lo que hace
      -- que marcar dos veces no cobre dos veces, igual que el
      -- `on conflict do nothing` de arriba.
      if v_res.cobra_en_puerta and v_res.cobrado_en_puerta_at is null then
        v_caja := caja_registrar(
          p_token, 'ingreso', 'clase_suelta',
          coalesce(v_clase.precio_cop, 0), 'efectivo',
          'Reserva ' || v_res.codigo || ' — ' || v_res.nombre || ' (pagó al llegar)');

        v_cobro_ok := coalesce((v_caja->>'ok')::boolean, false);
        if v_cobro_ok then
          v_cobro := coalesce(v_clase.precio_cop, 0);
          update reservas
             set cobrado_en_puerta_at = now(),
                 cobro_mov_id = (v_caja->>'id')::uuid,
                 updated_at = now()
           where id = v_res.id;
        else
          v_cobro_msg := coalesce(v_caja->>'mensaje',
            'No se pudo registrar el cobro (' || coalesce(v_caja->>'error', '?') || ').');
        end if;
      end if;

    else
      delete from asistencias where reserva_id = v_res.id and clase_id = p_clase_id;

      -- Si se le había cobrado al entrar y ahora se desmarca, se anula
      -- ese movimiento. Un clic equivocado no puede dejar en la caja un
      -- ingreso que nadie entregó.
      if v_res.cobra_en_puerta and v_res.cobrado_en_puerta_at is not null
         and v_res.cobro_mov_id is not null then
        v_caja := caja_anular(p_token, v_res.cobro_mov_id);
        if coalesce((v_caja->>'ok')::boolean, false) then
          update reservas
             set cobrado_en_puerta_at = null, cobro_mov_id = null,
                 updated_at = now()
           where id = v_res.id;
          v_cobro := -coalesce(v_clase.precio_cop, 0);
        else
          v_cobro_msg := coalesce(v_caja->>'mensaje',
            'Se quitó la entrada pero el cobro sigue en la caja: quítalo a mano.');
        end if;
      end if;
    end if;

    return jsonb_build_object('ok', true, 'ref', p_ref, 'asistio', p_asistio,
      'nombre', v_res.nombre,
      -- Cuánto se movió en la caja por esto: positivo al cobrar,
      -- negativo al devolver, null si no había nada que cobrar.
      'cobrado_cop', v_cobro,
      'aviso_cobro', v_cobro_msg,
      'entraron', (select count(*)::int from asistencias where clase_id = p_clase_id));
  end if;

  ------------------------------------------------------------------
  -- Alguien con plan — copiado LETRA POR LETRA de la 0018
  --
  -- Quien viene por mensualidad no paga en la puerta, así que aquí no
  -- hay nada que cobrar. Y esta parte no se toca: al reescribirla de
  -- memoria la primera vez se buscó la membresía por id, cuando la
  -- referencia que manda la puerta trae el celular o el nombre. La
  -- prueba humo-puerta lo cazó al instante.
  ------------------------------------------------------------------
  if v_tipo = 'p' then
    v_fecha := (v_clase.fecha_hora at time zone 'America/Bogota')::date;
    v_hora  := (v_clase.fecha_hora at time zone 'America/Bogota')::time;

    select * into v_memb from membresias m
     where m.hora = v_hora
       and v_fecha between m.inicio and m.fin
       and (solo_digitos(m.celular) = solo_digitos(v_valor) or m.afiliado = v_valor)
     order by m.fin desc limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'NO_EXISTE',
        'mensaje', 'No hay un plan activo de esa hora con ese celular.');
    end if;

    if p_asistio then
      insert into asistencias (clase_id, membresia_id, nombre, telefono,
                               origen, marcada_por)
      values (p_clase_id, v_memb.id, v_memb.afiliado, v_memb.celular,
              'plan', v_admin)
      on conflict do nothing;
    else
      delete from asistencias
       where clase_id = p_clase_id and origen = 'plan'
         and solo_digitos(telefono) = solo_digitos(v_memb.celular);
    end if;

    return jsonb_build_object('ok', true, 'ref', p_ref, 'asistio', p_asistio,
      'nombre', v_memb.afiliado, 'cobrado_cop', null,
      'entraron', (select count(*)::int from asistencias where clase_id = p_clase_id));
  end if;

  return jsonb_build_object('ok', false, 'error', 'REF_INVALIDA');
end;
$$;

revoke execute on function admin_marcar_asistencia(text, uuid, text, boolean)
  from public, anon, authenticated;
grant execute on function admin_marcar_asistencia(text, uuid, text, boolean)
  to service_role;


-- ---------------------------------------------------------------------
-- admin_por_cobrar_en_puerta — lo que falta cobrar hoy
--
-- Va aparte y no dentro de caja_del_dia a propósito: esa función ya
-- carga con medio cierre y parchearla otra vez es arriesgar lo que sí
-- funciona. Esto solo suma, y el cierre la llama para avisar.
--
-- Sin esto, "paga al llegar" cambia un problema por otro más callado:
-- alguien reservó, no vino, y en el arqueo no hay ni la plata ni el
-- rastro de que se esperaba.
-- ---------------------------------------------------------------------
create or replace function admin_por_cobrar_en_puerta(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_dia   date;
  v_lista jsonb;
  v_n     int;
  v_cop   int;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  v_dia := (now() at time zone 'America/Bogota')::date;

  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', r.codigo, 'nombre', r.nombre,
           'hora', to_char((c.fecha_hora at time zone 'America/Bogota'), 'HH24:MI'),
           'valor_cop', coalesce(c.precio_cop, 0))
         order by c.fecha_hora), '[]'::jsonb),
         count(*)::int,
         coalesce(sum(coalesce(c.precio_cop, 0)), 0)::int
    into v_lista, v_n, v_cop
    from reservas r
    join clases c on c.id = r.clase_id
   where r.cobra_en_puerta
     and r.cobrado_en_puerta_at is null
     and r.estado = 'confirmada'
     and (c.fecha_hora at time zone 'America/Bogota')::date = v_dia;

  return jsonb_build_object('ok', true, 'dia', v_dia,
    'n', v_n, 'total_cop', v_cop, 'reservas', v_lista);
end;
$$;

revoke execute on function admin_por_cobrar_en_puerta(text) from public, anon, authenticated;
grant execute on function admin_por_cobrar_en_puerta(text) to service_role;
