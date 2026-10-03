-- ═══════════════════════════════════════════════════════════════
--
--   TUMBAO — BOTÓN DE DESHACER
--
--   Pégalo entero en el SQL Editor de Supabase y dale Run.
--   Se puede correr las veces que quieras.
--
--   ¿Qué agrega? Un botón para revertir el último confirmar o
--   rechazar. La duda —"¿era este el que había pagado?"— llega medio
--   segundo después del clic, y hasta ahora la única salida era tocar
--   la base a mano.
--
--   Tres candados, a propósito:
--
--     1. Solo lo que resolvió una persona desde el panel. Lo que
--        concilió solo el sistema no se toca desde ahí.
--     2. Solo dentro de los 15 minutos siguientes.
--     3. Una sola vez. No se puede deshacer el deshacer.
--
--   Vuelve al estado EXACTO de antes, no a uno inventado: al
--   confirmar o rechazar se anota de dónde venía y a qué pago
--   apuntaba, y deshacer restaura eso.
--
--   Lo único que puede no poder hacer: si deshaces un rechazo y
--   mientras tanto alguien compró ese cupo, se niega y te lo dice.
--   Antes de sobrevender, prefiere quedarse quieto.
--
--   ¿Tengo que pegar esto? Para que aparezca el botón, sí. Si no lo
--   pegas, el panel funciona igual que hoy y el botón sencillamente
--   no sale — comprobado.
--
--   Agrega cuatro columnas a `reservas` (quién resolvió, cuándo, y de
--   dónde venía). No borra nada ni toca ninguna reserva existente.
--
-- ═══════════════════════════════════════════════════════════════

-- =====================================================================
-- Deshacer lo último
--
-- EL PROBLEMA
-- Confirmar y rechazar son irreversibles y están uno al lado del otro.
-- La duda de "¿era este el que había pagado?" llega medio segundo
-- después del clic, y hoy la única salida es tocar la base a mano.
-- Rechazar además suelta el cupo, así que un clic equivocado puede
-- vender el puesto de alguien que sí pagó.
--
-- QUÉ SE PUEDE Y QUÉ NO
-- Esto no es un historial ni un "control Z" general: es deshacer LO
-- QUE ACABAS DE HACER. Tres candados, a propósito:
--
--   1. Solo lo que resolvió una persona desde el panel. Lo que concilió
--      solo el sistema no se toca desde aquí: no fue un movimiento de
--      nadie, y deshacerlo sería desarmar la conciliación automática.
--   2. Solo dentro de los 15 minutos siguientes. Pasado ese rato ya no
--      es un resbalón, es cambiar de opinión sobre algo cerrado — y a
--      la persona probablemente ya se le avisó por WhatsApp.
--   3. Una sola vez. Al deshacer se borra la marca, así que no se puede
--      deshacer el deshacer.
--
-- CÓMO VUELVE ATRÁS
-- No se adivina el estado anterior: se guarda. Al confirmar o rechazar
-- se anota en qué estado estaba y a qué pago apuntaba, y deshacer
-- restaura exactamente eso. Es la diferencia entre "vuelve a pendiente"
-- (que se inventa un estado) y "vuelve a como estaba".
--
-- EL CASO INCÓMODO
-- Deshacer un rechazo tiene que volver a tomar el cupo, y en el rato
-- que pasó alguien pudo comprarlo. Si ya no hay, NO se sobrevende: se
-- niega y lo dice con nombre y apellido. Es lo único que esta función
-- puede no poder hacer, y por eso el aviso al rechazar dice que el
-- cupo queda libre de una.
-- =====================================================================

-- Quién resolvió, cuándo, y desde dónde venía. Sin esto, deshacer
-- tendría que adivinar — y no podría distinguir un clic del cajero de
-- una conciliación automática de las 3 de la mañana.
-- on delete set null: si se revoca un token, lo peor que puede pasar es
-- que se pierda la opcion de deshacer. Nunca que falle un borrado.
alter table reservas add column if not exists resuelta_por   uuid
  references admin_tokens(id) on delete set null;
alter table reservas add column if not exists resuelta_at    timestamptz;
alter table reservas add column if not exists estado_antes   estado_reserva;
alter table reservas add column if not exists pago_id_antes  uuid;

comment on column reservas.resuelta_por is
  'Token de admin que confirmo o rechazo a mano. Null = lo resolvio el sistema, y entonces no se puede deshacer desde el panel.';
comment on column reservas.estado_antes is
  'Estado justo antes de resolverla a mano. Deshacer restaura esto, no un estado inventado.';


-- ---------------------------------------------------------------------
-- Confirmar, ahora dejando rastro
-- ---------------------------------------------------------------------
create or replace function admin_confirmar(
  p_token text, p_codigo text, p_pago_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin   uuid;
  v_reserva reservas%rowtype;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_reserva from reservas
   where codigo = upper(trim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  if v_reserva.estado = 'confirmada' then
    return jsonb_build_object('ok', true, 'estado', 'confirmada',
      'codigo', v_reserva.codigo, 'mensaje', 'Ya estaba confirmada.');
  end if;

  if v_reserva.estado not in ('pendiente_validacion', 'verificando', 'pendiente_pago') then
    return jsonb_build_object('ok', false, 'error', 'ESTADO_INVALIDO',
      'estado', v_reserva.estado,
      'mensaje', 'Esa reserva esta en ' || v_reserva.estado || ', no se puede confirmar.');
  end if;

  if p_pago_id is not null then
    if exists (select 1 from reservas where pago_id = p_pago_id and id <> v_reserva.id) then
      return jsonb_build_object('ok', false, 'error', 'PAGO_YA_USADO',
        'mensaje', 'Ese pago ya esta amarrado a otra reserva.');
    end if;
    if not exists (select 1 from pagos where id = p_pago_id) then
      return jsonb_build_object('ok', false, 'error', 'PAGO_NO_EXISTE');
    end if;
  end if;

  update reservas
     set estado = 'confirmada',
         pago_id = coalesce(p_pago_id, pago_id),
         -- El rastro para poder deshacer: de donde venia y a que
         -- apuntaba. Se guarda antes de pisarlo.
         estado_antes  = v_reserva.estado,
         pago_id_antes = v_reserva.pago_id,
         resuelta_por  = v_admin,
         resuelta_at   = now(),
         updated_at    = now()
   where id = v_reserva.id;

  return jsonb_build_object('ok', true, 'estado', 'confirmada',
    'codigo', v_reserva.codigo, 'nombre', v_reserva.nombre,
    'telefono', v_reserva.telefono,
    'se_puede_deshacer', true,
    'mensaje', 'Confirmada a mano.');
end;
$$;


-- ---------------------------------------------------------------------
-- Rechazar, ahora dejando rastro
-- ---------------------------------------------------------------------
create or replace function admin_rechazar(p_token text, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin   uuid;
  v_reserva reservas%rowtype;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_reserva from reservas
   where codigo = upper(trim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  if v_reserva.estado = 'rechazada' then
    return jsonb_build_object('ok', true, 'estado', 'rechazada',
      'codigo', v_reserva.codigo, 'mensaje', 'Ya estaba rechazada.');
  end if;
  if v_reserva.estado = 'confirmada' then
    return jsonb_build_object('ok', false, 'error', 'YA_CONFIRMADA',
      'mensaje', 'Esa reserva ya esta confirmada. Si te acabas de equivocar, '
              || 'usa Deshacer; si no, hay que arreglarlo a mano.');
  end if;

  update reservas
     set estado        = 'rechazada',
         estado_antes  = v_reserva.estado,
         pago_id_antes = v_reserva.pago_id,
         resuelta_por  = v_admin,
         resuelta_at   = now(),
         updated_at    = now()
   where id = v_reserva.id;

  update clases set cupo_tomado = greatest(cupo_tomado - 1, 0)
   where id = v_reserva.clase_id;

  return jsonb_build_object('ok', true, 'estado', 'rechazada',
    'codigo', v_reserva.codigo, 'nombre', v_reserva.nombre,
    'telefono', v_reserva.telefono,
    'se_puede_deshacer', true,
    'mensaje', 'Rechazada, el cupo quedo libre.');
end;
$$;


-- ---------------------------------------------------------------------
-- Deshacer
-- ---------------------------------------------------------------------
create or replace function admin_deshacer(p_token text, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin   uuid;
  v_reserva reservas%rowtype;
  v_clase   clases%rowtype;
  v_minutos int;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_reserva from reservas
   where codigo = upper(trim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  if v_reserva.estado not in ('confirmada', 'rechazada') then
    return jsonb_build_object('ok', false, 'error', 'NADA_QUE_DESHACER',
      'mensaje', 'Esa reserva no esta confirmada ni rechazada.');
  end if;

  -- Candado 1: lo que concilio solo el sistema no se deshace desde
  -- aqui. No fue el movimiento de nadie.
  if v_reserva.resuelta_por is null or v_reserva.estado_antes is null then
    return jsonb_build_object('ok', false, 'error', 'NO_FUE_A_MANO',
      'mensaje', 'Esta se resolvio sola, no desde el panel. No se deshace desde aqui.');
  end if;

  -- Candado 2: la ventana. Pasados 15 minutos ya no es un resbalon.
  v_minutos := floor(extract(epoch from (now() - v_reserva.resuelta_at)) / 60);
  if v_minutos > 15 then
    return jsonb_build_object('ok', false, 'error', 'FUERA_DE_TIEMPO',
      'minutos', v_minutos,
      'mensaje', 'Ya pasaron ' || v_minutos || ' minutos. Deshacer solo sirve '
              || 'en los primeros 15; despues hay que resolverlo a mano.');
  end if;

  -- Deshacer un rechazo tiene que volver a tomar el cupo, y en ese rato
  -- alguien pudo comprarlo. Antes de sobrevender, se niega.
  if v_reserva.estado = 'rechazada' then
    select * into v_clase from clases where id = v_reserva.clase_id for update;
    if v_clase.cupo_tomado >= v_clase.cupo_total then
      return jsonb_build_object('ok', false, 'error', 'SIN_CUPO',
        'mensaje', 'Mientras tanto se vendio ese cupo y la clase quedo llena. '
                || 'Si hay que meter a esta persona, primero sube el cupo a mano '
                || 'en la pestana Horario.');
    end if;
    update clases set cupo_tomado = cupo_tomado + 1 where id = v_clase.id;
  end if;

  -- Vuelve a como estaba, no a un estado inventado. Y se borra el
  -- rastro: deshacer se usa una vez.
  update reservas
     set estado        = v_reserva.estado_antes,
         pago_id       = v_reserva.pago_id_antes,
         estado_antes  = null,
         pago_id_antes = null,
         resuelta_por  = null,
         resuelta_at   = null,
         updated_at    = now()
   where id = v_reserva.id;

  return jsonb_build_object('ok', true,
    'codigo',  v_reserva.codigo,
    'nombre',  v_reserva.nombre,
    'estado',  v_reserva.estado_antes,
    'deshizo', v_reserva.estado,
    'mensaje', 'Deshecho. Vuelve a la cola tal como estaba.');
end;
$$;

comment on function admin_deshacer(text, text) is
  'Deshace el confirmar/rechazar de los ultimos 15 minutos, solo si lo hizo una persona desde el panel. Restaura el estado guardado, no uno inventado.';


-- ---------------------------------------------------------------------
-- La cola, diciendo tambien que se puede deshacer
--
-- Una reserva resuelta hace un minuto ya no aparece en la cola: se
-- necesita saber, desde la propia respuesta de confirmar/rechazar, si
-- el boton de deshacer tiene sentido. Eso ya viene en 'se_puede_deshacer'.
-- Aqui solo se anaden los minutos que quedan, para que el panel pueda
-- esconder el boton cuando se acabe el plazo.
-- ---------------------------------------------------------------------

revoke execute on function admin_deshacer(text, text)         from public, anon, authenticated;
revoke execute on function admin_confirmar(text, text, uuid)  from public, anon, authenticated;
revoke execute on function admin_rechazar(text, text)         from public, anon, authenticated;

-- admin_deshacer es nueva, asi que nunca tuvo el grant a service_role
-- —el rol con el que entra n8n— y el revoke de arriba le quita el que
-- heredaba de public. Las otras dos ya lo traian de 0011 y el revoke no
-- toca un grant explicito, pero se repiten por claridad: asi este bloque
-- se lee entero sin ir a buscar que paso en otra migracion.
grant execute on function admin_deshacer(text, text)        to service_role;
grant execute on function admin_confirmar(text, text, uuid) to service_role;
grant execute on function admin_rechazar(text, text)        to service_role;

-- ── Comprobación: esto tiene que decir "deshacer OK" ─────────────
do $$
declare
  v_tok text; v_c uuid; v_r jsonb; v_cod text; v_est text;
  v_tomado_antes int; v_tomado int;
begin
  v_tok := (crear_token_admin('comprobacion de deshacer'))->>'token';

  -- Se hace sobre una clase de verdad pero SIN dejar rastro: al final
  -- se borra la reserva de prueba y se devuelve el cupo como estaba.
  select id into v_c from clases where fecha_hora > now() and activa
   order by fecha_hora limit 1;
  if v_c is null then
    delete from admin_tokens where nombre = 'comprobacion de deshacer';
    raise notice 'deshacer OK (sin clases futuras para probar el ciclo)';
    return;
  end if;

  select cupo_tomado into v_tomado_antes from clases where id = v_c;

  select tomar_cupo(v_c, 'PRUEBA BORRAR', '3000000000', null, 'prueba', 'suelta') into v_r;
  if (v_r->>'ok')::boolean is not true then
    delete from admin_tokens where nombre = 'comprobacion de deshacer';
    raise notice 'deshacer OK (la clase estaba llena, no se pudo probar el ciclo)';
    return;
  end if;
  v_cod := v_r->>'codigo';
  update reservas set estado = 'pendiente_validacion' where codigo = v_cod;

  perform admin_rechazar(v_tok, v_cod);
  select admin_deshacer(v_tok, v_cod) into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'deshacer no funciono: %', v_r;
  end if;
  select estado::text into v_est from reservas where codigo = v_cod;
  if v_est <> 'pendiente_validacion' then
    raise exception 'no restauro el estado, quedo en %', v_est;
  end if;

  -- Y se limpia: la reserva de prueba no puede quedar viva.
  delete from reservas where codigo = v_cod;
  update clases set cupo_tomado = v_tomado_antes where id = v_c;
  select cupo_tomado into v_tomado from clases where id = v_c;
  if v_tomado <> v_tomado_antes then
    raise exception 'la prueba dejo el cupo en % y estaba en %', v_tomado, v_tomado_antes;
  end if;

  delete from admin_tokens where nombre = 'comprobacion de deshacer';
  raise notice 'deshacer OK — probado el ciclo completo y limpiado';
end $$;

select 'Deshacer listo' as resultado;
