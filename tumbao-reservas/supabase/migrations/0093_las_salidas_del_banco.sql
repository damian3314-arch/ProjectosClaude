-- 0093 — Las salidas del banco dejan de botarse
--
-- POR QUÉ
--
-- Damián: «cada vez que sale dinero de la cuenta de Tumbao llega ese
-- correo del banco… que exista como algo de notificación que hay gastos
-- sin procesar, y que al tomar esa información se pueda poner el gasto a
-- que corresponde».
--
-- El correo ya llegaba y ya se guardaba. El parser incluso lo reconocía:
--
--   const VERBOS_SALIDA = [/transferiste/i, /pagaste/i, /compraste/i, …]
--   if (salida) return { es_ingreso: false, motivo: 'movimiento_de_salida' };
--
-- Lo reconocía para tirarlo. De los últimos veinte correos del banco,
-- cuatro eran salidas. Una quinta parte de los movimientos de la cuenta
-- se estaba perdiendo en la puerta.
--
-- El correo trae esto:
--
--   «Transferiste $MONTO desde tu cuenta *4619 a la cuenta *3007726093
--    el 19/09/26 a las 19:21»
--
-- Monto, cuenta de origen, cuenta de destino, fecha y hora. Lo que NO
-- trae es a quién: solo el número. Por eso esto no se puede clasificar
-- solo, y por eso la bandeja tiene sentido — alguien tiene que decir a
-- qué corresponde. Lo que sí se puede es acordarse: la segunda vez que
-- salga plata a la misma cuenta, ya se sabe de quién era.
--
-- ── POR QUÉ TABLA APARTE Y NO UN `gasto` PENDIENTE ──────────────────
--
-- Porque Tanya también reporta esos mismos pagos en el chat de gastos, y
-- de ahí salieron los 116 renglones que ya están cargados. Si la salida
-- del banco entrara directo a `gastos`, cada pago quedaría dos veces y
-- la tesorería que acabamos de cuadrar volvería a mentir, ahora al revés.
--
-- Así que una salida del banco no es un gasto todavía: es un aviso de que
-- salió plata. Se vuelve gasto cuando alguien dice qué era — y en ese
-- momento puede además decir «esto ya estaba registrado», y se descarta.
-- Mientras tanto no suma en ningún total. `admin_tesoreria` no se toca.

-- Un gasto que nace de una alerta del banco tiene una procedencia nueva.
-- Importa poder distinguirlo: es el único que no lo escribió una persona.
alter table gastos drop constraint if exists gastos_fuente_ck;
alter table gastos add  constraint gastos_fuente_ck
  check (fuente in ('whatsapp', 'mano', 'caja', 'banco'));

create table if not exists salidas_banco (
  id            uuid primary key default extensions.gen_random_uuid(),
  -- El message-id del correo. Es lo que hace que reprocesar el buzón no
  -- cree la misma salida dos veces.
  ref_banco     text not null,
  valor_cop     int  not null,
  ocurrio_at    timestamptz not null,
  cuenta_origen text,
  cuenta_destino text,
  -- Cuando el correo sí lo dice («Pagaste $X a Gasoriente»). En las
  -- transferencias no viene y queda null.
  destinatario  text,
  patron        text,
  confianza     text,
  raw           text,
  estado        text not null default 'pendiente',
  -- El gasto que se creó al clasificarla, si se clasificó.
  gasto_id      uuid references gastos(id),
  nota          text,
  atendida_at   timestamptz,
  atendida_por  uuid,
  creado_at     timestamptz not null default now(),
  constraint salidas_banco_valor_ck  check (valor_cop > 0),
  constraint salidas_banco_estado_ck check (estado in
    ('pendiente', 'clasificada', 'descartada'))
);

create unique index if not exists salidas_banco_ref on salidas_banco (ref_banco);
-- La bandeja pregunta siempre por lo mismo: qué falta por clasificar.
create index if not exists salidas_banco_pendientes
  on salidas_banco (ocurrio_at desc) where estado = 'pendiente';
create index if not exists salidas_banco_destino on salidas_banco (cuenta_destino);

alter table salidas_banco enable row level security;
revoke all on table salidas_banco from public, anon, authenticated;


-- ── la puerta de entrada, para el Worker del correo ─────────────────
--
-- No lleva token: la llama el Worker con la llave de servicio, igual que
-- `registrar_pago_y_conciliar`. Es idempotente por `ref_banco`, así que
-- si el mismo correo se reprocesa no pasa nada.

create or replace function public.banco_salida_apuntar(
  p_ref            text,
  p_valor_cop      int,
  p_ocurrio_at     timestamptz,
  p_cuenta_origen  text default null,
  p_cuenta_destino text default null,
  p_destinatario   text default null,
  p_patron         text default null,
  p_confianza      text default null,
  p_raw            text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_id uuid; v_ya boolean := false;
begin
  if coalesce(btrim(p_ref), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'SIN_REFERENCIA');
  end if;
  if coalesce(p_valor_cop, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'VALOR_INVALIDO');
  end if;

  select id into v_id from salidas_banco where ref_banco = btrim(p_ref);
  if found then
    return jsonb_build_object('ok', true, 'id', v_id, 'ya_estaba', true);
  end if;

  insert into salidas_banco (ref_banco, valor_cop, ocurrio_at, cuenta_origen,
                             cuenta_destino, destinatario, patron, confianza, raw)
  values (btrim(p_ref), p_valor_cop, p_ocurrio_at,
          nullif(btrim(coalesce(p_cuenta_origen, '')), ''),
          nullif(btrim(coalesce(p_cuenta_destino, '')), ''),
          nullif(btrim(coalesce(p_destinatario, '')), ''),
          p_patron, p_confianza, left(coalesce(p_raw, ''), 4000))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id, 'ya_estaba', false);
end;
$function$;

revoke all on function public.banco_salida_apuntar(text, int, timestamptz, text, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.banco_salida_apuntar(text, int, timestamptz, text, text, text, text, text, text)
  to service_role;


-- ── la bandeja ──────────────────────────────────────────────────────
--
-- La ve recepción. Es a propósito: clasificar una salida no es ver la
-- nómina, es decir a qué corresponde un movimiento que ya ocurrió, y es
-- justo lo que Damián pidió que ella pudiera hacer. No toca su caja: el
-- dinero salió de la cuenta, no de su cajón.
--
-- Cada salida viene con dos ayudas:
--   · `sugerencia`: qué se dijo la última vez que salió plata a esa misma
--     cuenta. La segunda transferencia a Fabián ya llega con su nombre.
--   · `quizas_repetida`: un gasto ya cargado del mismo valor y de por ahí
--     mismo. Es el aviso de «esto ya lo reportó Tanya en el chat», que es
--     como se evita contarlo dos veces.

create or replace function public.admin_salidas_pendientes(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_admin record; v_hoy date; v_lista jsonb;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  v_hoy := (now() at time zone 'America/Bogota')::date;

  select coalesce(jsonb_agg(x order by x.ocurrio_at desc), '[]'::jsonb)
    into v_lista
    from (
      select s.id, s.valor_cop, s.ocurrio_at,
             (s.ocurrio_at at time zone 'America/Bogota')::date as dia,
             s.cuenta_destino, s.destinatario, s.confianza,
             -- Lo que se dijo la última vez que salió plata a esta cuenta.
             (select jsonb_build_object('categoria', g.categoria,
                                        'a_quien',   g.a_quien,
                                        'concepto',  g.concepto)
                from salidas_banco s2
                join gastos g on g.id = s2.gasto_id
               where s2.cuenta_destino is not null
                 and s2.cuenta_destino = s.cuenta_destino
                 and s2.estado = 'clasificada'
               order by s2.atendida_at desc nulls last
               limit 1) as sugerencia,
             -- Un gasto del mismo valor por las mismas fechas: es el
             -- aviso de que Tanya ya lo reportó en el chat.
             (select jsonb_build_object('dia', g.dia, 'concepto', g.concepto,
                                        'categoria', g.categoria)
                from gastos g
               where not g.anulado
                 and g.valor_cop = s.valor_cop
                 and g.dia between
                     (s.ocurrio_at at time zone 'America/Bogota')::date - 2
                 and (s.ocurrio_at at time zone 'America/Bogota')::date + 2
               order by abs(g.dia - (s.ocurrio_at at time zone 'America/Bogota')::date)
               limit 1) as quizas_repetida
        from salidas_banco s
       where s.estado = 'pendiente'
    ) x;

  return jsonb_build_object(
    'ok', true,
    'hoy', v_hoy,
    'cuantas', jsonb_array_length(v_lista),
    'cop', (select coalesce(sum(valor_cop), 0) from salidas_banco
             where estado = 'pendiente'),
    'salidas', v_lista);
end;
$function$;

revoke all on function public.admin_salidas_pendientes(text) from public, anon, authenticated;
grant execute on function public.admin_salidas_pendientes(text) to service_role;


-- ── clasificarla: aquí sí se vuelve un gasto ────────────────────────

create or replace function public.admin_salida_clasificar(
  p_token     text,
  p_id        uuid,
  p_categoria text,
  p_concepto  text,
  p_a_quien   text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_admin record; v_s salidas_banco; v_gasto uuid;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_s from salidas_banco where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;
  if v_s.estado <> 'pendiente' then
    return jsonb_build_object('ok', true, 'ya_estaba', true,
      'estado', v_s.estado, 'gasto_id', v_s.gasto_id);
  end if;

  if coalesce(btrim(p_concepto), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'SIN_CONCEPTO',
      'mensaje', 'Escribe a qué corresponde esta salida.');
  end if;

  -- La categoría la valida el check de `gastos`; si no es una de las
  -- suyas, el insert falla y no se marca nada.
  insert into gastos (dia, valor_cop, concepto, categoria, medio, a_quien,
                      fuente, creado_por, nota)
  values ((v_s.ocurrio_at at time zone 'America/Bogota')::date,
          v_s.valor_cop, btrim(p_concepto), p_categoria, 'banco',
          nullif(btrim(coalesce(p_a_quien, '')), ''),
          'banco', v_admin.id,
          'Clasificada desde la alerta del banco'
          || coalesce(' · a la cuenta ' || v_s.cuenta_destino, '')
          || ' · ' || to_char(v_s.ocurrio_at at time zone 'America/Bogota',
                              'DD/MM/YYYY HH24:MI'))
  returning id into v_gasto;

  update salidas_banco
     set estado = 'clasificada', gasto_id = v_gasto,
         atendida_at = now(), atendida_por = v_admin.id
   where id = p_id;

  return jsonb_build_object('ok', true, 'gasto_id', v_gasto,
    'quedan', (select count(*) from salidas_banco where estado = 'pendiente'));
end;
$function$;

revoke all on function public.admin_salida_clasificar(text, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_salida_clasificar(text, uuid, text, text, text)
  to service_role;


-- ── descartarla: ya estaba registrada, o no era un gasto ────────────

create or replace function public.admin_salida_descartar(
  p_token text, p_id uuid, p_nota text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_admin record; v_s salidas_banco;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_s from salidas_banco where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;
  if v_s.estado <> 'pendiente' then
    return jsonb_build_object('ok', true, 'ya_estaba', true, 'estado', v_s.estado);
  end if;

  -- Se pide el porqué. Una salida descartada sin razón es un agujero que
  -- dentro de tres meses nadie sabe tapar.
  if coalesce(btrim(p_nota), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'SIN_NOTA',
      'mensaje', 'Di por qué se descarta: «ya estaba en el chat», «fue un traslado»…');
  end if;

  update salidas_banco
     set estado = 'descartada', nota = btrim(p_nota),
         atendida_at = now(), atendida_por = v_admin.id
   where id = p_id;

  return jsonb_build_object('ok', true,
    'quedan', (select count(*) from salidas_banco where estado = 'pendiente'));
end;
$function$;

revoke all on function public.admin_salida_descartar(text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.admin_salida_descartar(text, uuid, text)
  to service_role;
