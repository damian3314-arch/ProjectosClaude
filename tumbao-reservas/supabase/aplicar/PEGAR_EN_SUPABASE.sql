-- ═══════════════════════════════════════════════════════════════
--
--   TUMBAO — PEGA TODO ESTO Y DALE RUN. NADA MÁS.
--
--   Esto hace las tres cosas de una:
--     1. crea todo lo que falta en la base
--     2. carga el horario de las próximas 3 semanas
--     3. te emite el token del panel y te lo muestra al final
--
--   Cuando termine, abajo aparece una tabla con TU TOKEN.
--   Cópialo de una: no se puede volver a ver.
--
--   Se puede correr las veces que quieras. No duplica nada.
--
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 0007_desempate_por_nombre.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- Desempate por el nombre de quien envió el dinero
--
-- EL PROBLEMA
-- El QR Bre-B es estático (verificado en su payload EMVCo: tag 01 = 11)
-- y el precio de la clase suelta es fijo. No se puede pedir un monto
-- distinto a cada persona: solo pagan quienes no tienen mensualidad, y
-- el valor es el de la clase.
--
-- Consecuencia: dos personas pagando en la misma ventana producen dos
-- pagos idénticos en monto. Antes eso mandaba las DOS a validación
-- humana, que en hora pico puede ser la mayoría.
--
-- LA SEÑAL QUE SÍ EXISTE
-- El correo del banco trae el nombre de quien envió:
--   "recibiste una transferencia de CAMILA ROJAS DUQUE por $15000.00"
--
-- Se compara contra el nombre que la persona escribió al reservar.
--
-- POR QUÉ NO LA HORA
-- El pago siempre llega después de la reserva, y eso ya se usa como
-- filtro de ventana. Pero dentro de esa ventana dos personas pueden
-- reservar con segundos de diferencia y pagar en cualquier orden, así
-- que el orden temporal no distingue quién es quién. El nombre sí.
-- =====================================================================

create extension if not exists unaccent with schema extensions;


-- Tokens normalizados de un nombre: sin acentos, en mayúsculas, sin
-- palabras de menos de 3 letras (para que "de", "la", "Jo" no cuenten).
create or replace function tokens_nombre(p_nombre text) returns text[]
language sql
immutable
set search_path = public, extensions, pg_temp
as $$
  select coalesce(array_agg(t), array[]::text[])
  from (
    select distinct t
    from regexp_split_to_table(
           upper(extensions.unaccent(coalesce(p_nombre, ''))),
           '[^A-Z]+'
         ) AS t
    where length(t) >= 3
  ) x;
$$;


-- Fracción de los tokens del nombre de la reserva que aparecen en el
-- nombre del remitente.
--   'Camila'       vs 'CAMILA ROJAS DUQUE' -> 1.00
--   'Camila Rojas' vs 'CAMILA GOMEZ'       -> 0.50
--   'Ana'          vs 'CAMILA ROJAS DUQUE' -> 0.00
--   'José'         vs 'JOSE ANDRES MERCADO'-> 1.00  (acentos resueltos)
create or replace function similitud_nombre(p_reserva text, p_remitente text)
returns numeric
language sql
immutable
set search_path = public, extensions, pg_temp
as $$
  select case
    when cardinality(tokens_nombre(p_reserva)) = 0
      or cardinality(tokens_nombre(p_remitente)) = 0
    then 0::numeric
    else (
      select count(*)::numeric / cardinality(tokens_nombre(p_reserva))
      from unnest(tokens_nombre(p_reserva)) tr
      where tr = any (tokens_nombre(p_remitente))
    )
  end;
$$;

revoke execute on function tokens_nombre(text)          from public, anon, authenticated;
revoke execute on function similitud_nombre(text, text) from public, anon, authenticated;


-- ─────────────────────────────────────────────
-- 0008_conciliacion_con_nombre.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- Conciliación usando el nombre del remitente como desempate
--
-- Reglas, en orden:
--   0 candidatas  -> se registra el pago y nada más
--   1 candidata   -> se confirma, AUNQUE el nombre no calce. Es normal
--                    que pague la mamá, la pareja o un amigo.
--   2 o más       -> gana la única cuyo nombre calce con el remitente.
--                    Si ninguna calza, o calzan varias, va a validación
--                    humana igual que antes.
--
-- Nunca empeora respecto a la versión anterior: los casos que antes
-- iban a un humano siguen yendo, y algunos que antes iban ahora se
-- resuelven solos.
--
-- Verificado sobre el proyecto real:
--   · 2 esperando + paga CAMILA        -> confirma a Camila (metodo: nombre_remitente)
--   · luego paga ANDRES               -> confirma a Andrés
--   · 2 esperando + paga ROSA (ajena)  -> 0 confirmadas, va a humano
--   · 1 esperando + paga la mamá       -> confirma (metodo: monto_unico)
-- =====================================================================

create or replace function registrar_pago_y_conciliar(
  p_banco      text,
  p_valor_cop  int,
  p_fecha_pago timestamptz,
  p_referencia text default null,
  p_remitente  text default null,
  p_ultimos_4  text default null,
  p_confianza  numeric default 1.0,
  p_raw_email  text default null,
  p_hoja_fila  text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_pago       pagos%rowtype;
  v_reserva    reservas%rowtype;
  v_candidatos int;
  v_con_nombre int;
  v_metodo     text := 'monto_unico';
begin
  if p_valor_cop is null or p_valor_cop <= 0 then
    return jsonb_build_object('ok', false, 'error', 'valor_invalido');
  end if;

  insert into pagos (banco, valor_cop, fecha_pago, referencia,
                     remitente, ultimos_4, raw_email, hoja_fila)
  values (p_banco, p_valor_cop, p_fecha_pago, p_referencia,
          p_remitente, p_ultimos_4, p_raw_email, p_hoja_fila)
  on conflict (banco, valor_cop, fecha_pago, coalesce(referencia, ''))
  do nothing
  returning * into v_pago;

  if not found then
    select * into v_pago from pagos
     where banco = p_banco and valor_cop = p_valor_cop
       and fecha_pago = p_fecha_pago
       and coalesce(referencia, '') = coalesce(p_referencia, '');
    return jsonb_build_object('ok', true, 'duplicado', true,
      'pago_id', v_pago.id, 'accion', 'ninguna');
  end if;

  if p_confianza < 0.9 then
    return jsonb_build_object('ok', true, 'duplicado', false,
      'pago_id', v_pago.id, 'accion', 'solo_registrado',
      'motivo', 'confianza_baja');
  end if;

  create temp table if not exists _cand (id uuid, puntaje numeric) on commit drop;
  delete from _cand;

  insert into _cand (id, puntaje)
  select r.id, similitud_nombre(r.nombre, p_remitente)
    from reservas r
    join clases c on c.id = r.clase_id
   where r.estado in ('verificando', 'pendiente_validacion')
     and r.pago_id is null
     and c.precio_cop = p_valor_cop
     and p_fecha_pago between r.created_at - interval '15 minutes'
                          and r.created_at + interval '3 hours';

  select count(*) into v_candidatos from _cand;

  if v_candidatos = 0 then
    return jsonb_build_object('ok', true, 'duplicado', false,
      'pago_id', v_pago.id, 'accion', 'sin_reserva_que_casar');
  end if;

  if v_candidatos = 1 then
    select r.* into v_reserva from reservas r
     where r.id = (select id from _cand limit 1)
       for update skip locked;
  else
    select count(*) into v_con_nombre from _cand where puntaje >= 0.5;

    if v_con_nombre <> 1 then
      return jsonb_build_object('ok', true, 'duplicado', false,
        'pago_id', v_pago.id, 'accion', 'ambiguo',
        'candidatos', v_candidatos,
        'con_nombre_parecido', v_con_nombre,
        'remitente', p_remitente);
    end if;

    v_metodo := 'nombre_remitente';
    select r.* into v_reserva from reservas r
     where r.id = (select id from _cand where puntaje >= 0.5 limit 1)
       for update skip locked;
  end if;

  if not found then
    return jsonb_build_object('ok', true, 'duplicado', false,
      'pago_id', v_pago.id, 'accion', 'sin_reserva_que_casar');
  end if;

  update reservas
     set estado = 'confirmada', pago_id = v_pago.id, updated_at = now()
   where id = v_reserva.id;

  update pagos set consumido = true where id = v_pago.id;

  return jsonb_build_object('ok', true, 'duplicado', false,
    'pago_id', v_pago.id, 'accion', 'reserva_confirmada',
    'metodo', v_metodo, 'candidatos', v_candidatos,
    'reserva_id', v_reserva.id, 'codigo', v_reserva.codigo,
    'nombre', v_reserva.nombre, 'telefono', v_reserva.telefono);
end;
$$;


create or replace function conciliar_reserva(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_reserva reservas%rowtype;
  v_clase   clases%rowtype;
  v_pago    pagos%rowtype;
  v_cand    int;
  v_metodo  text := 'monto_unico';
begin
  select * into v_reserva from reservas
   where upper(btrim(codigo)) = upper(btrim(p_codigo))
     for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_encontrada');
  end if;

  select * into v_clase from clases where id = v_reserva.clase_id;

  if v_reserva.estado <> 'verificando' then
    return jsonb_build_object('ok', true, 'estado', v_reserva.estado,
      'codigo', v_reserva.codigo, 'clase', v_clase.nombre,
      'fecha_hora', v_clase.fecha_hora);
  end if;

  select count(*) into v_cand
    from pagos p
   where not p.consumido
     and p.valor_cop = v_clase.precio_cop
     and p.fecha_pago between v_reserva.created_at - interval '15 minutes'
                          and v_reserva.created_at + interval '3 hours';

  if v_cand = 1 then
    select * into v_pago from pagos p
     where not p.consumido
       and p.valor_cop = v_clase.precio_cop
       and p.fecha_pago between v_reserva.created_at - interval '15 minutes'
                            and v_reserva.created_at + interval '3 hours'
       for update skip locked;
  elsif v_cand > 1 then
    select * into v_pago from pagos p
     where not p.consumido
       and p.valor_cop = v_clase.precio_cop
       and p.fecha_pago between v_reserva.created_at - interval '15 minutes'
                            and v_reserva.created_at + interval '3 hours'
       and similitud_nombre(v_reserva.nombre, p.remitente) >= 0.5
       for update skip locked;
    if found then v_metodo := 'nombre_remitente'; end if;
  end if;

  if v_pago.id is not null then
    update reservas
       set estado = 'confirmada', pago_id = v_pago.id, updated_at = now()
     where id = v_reserva.id;
    update pagos set consumido = true where id = v_pago.id;

    return jsonb_build_object('ok', true, 'estado', 'confirmada',
      'metodo', v_metodo, 'codigo', v_reserva.codigo,
      'clase', v_clase.nombre, 'fecha_hora', v_clase.fecha_hora);
  end if;

  return jsonb_build_object('ok', true, 'estado', 'verificando',
    'codigo', v_reserva.codigo, 'clase', v_clase.nombre,
    'fecha_hora', v_clase.fecha_hora, 'candidatos', v_cand);
end;
$$;

revoke execute on function registrar_pago_y_conciliar(text,int,timestamptz,text,text,text,numeric,text,text) from public, anon, authenticated;
revoke execute on function conciliar_reserva(text) from public, anon, authenticated;
grant execute on function registrar_pago_y_conciliar(text,int,timestamptz,text,text,text,numeric,text,text) to service_role;
grant execute on function conciliar_reserva(text) to service_role;


-- ─────────────────────────────────────────────
-- 0009_cupos_desde_membresias.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- Los cupos de clase suelta salen de cuántos afiliados hay con plan
-- activo en ese horario
--
-- REGLA DE NEGOCIO
-- La sala tiene un aforo fijo. Los afiliados con mensualidad tienen su
-- puesto asegurado en SU horario. Lo que sobra es lo que se puede
-- vender como clase suelta.
--     cupos_sueltos = aforo − afiliados_activos_en_ese_horario
-- Ejemplo dado: 25 activos a las 6pm con aforo 30 → 5 cupos sueltos.
--
-- DE DÓNDE SALE EL DATO
-- Del "Reporte Afiliados con Membresía Activa" que se descarga a diario
-- a Drive. Es un .xlsx, no un Google Sheet. Columnas:
--     Afiliado | Membresía | # Documento | Celular | Correo |
--     Dirección | Inicio Membresía | Final Membresía
--
-- La columna Membresía trae la hora dentro del texto:
--     "PLAN MENSUALIDAD 7:00AM"   "MEDIA MENSUALIDAD 6:00PM"
--
-- Sobre el archivo del 26/07/2026, 61 afiliados activos repartidos así:
--     7:00 AM → 19     6:00 PM → 26     7:00 PM → 16
-- Con aforo 30 eso da 11, 4 y 14 cupos sueltos respectivamente.
--
-- OJO CON LAS FECHAS
-- Cada membresía tiene Inicio y Final. Varias terminan el 29, 30 y 31
-- de julio. "Activo" NO es un número fijo: depende de la fecha de cada
-- clase. Por eso se guarda el rango y se recalcula por clase, en vez de
-- guardar un conteo del día.
-- =====================================================================

-- Aforo de la sala. Separado de cupo_total porque cupo_total es lo que
-- queda para clase suelta y cambia cada día con las membresías.
alter table clases add column if not exists aforo int not null default 30
  check (aforo > 0);

alter table clases add column if not exists activos_plan int not null default 0
  check (activos_plan >= 0);


-- ---------------------------------------------------------------------
-- Espejo del reporte de afiliados. Se reemplaza entero en cada importe.
-- ---------------------------------------------------------------------
create table if not exists membresias (
  id           bigserial primary key,
  afiliado     text not null,
  membresia    text not null,          -- texto original, para depurar
  hora         time not null,          -- extraída del texto
  tipo         text not null           -- 'plan' o 'media'
                 check (tipo in ('plan','media','otro')),
  documento    text,
  celular      text,
  correo       text,
  inicio       date not null,
  fin          date not null,
  importado_at timestamptz not null default now(),
  constraint rango_valido check (fin >= inicio)
);

create index if not exists membresias_hora_rango on membresias (hora, inicio, fin);


-- ---------------------------------------------------------------------
-- Generar el horario de un rango de fechas
--   Lunes a viernes: 7:00 am, 6:00 pm, 7:00 pm
--   Sábado:          8:00 am, 9:00 am
--   Cada clase dura una hora.
-- Idempotente: no duplica clases que ya existan a esa hora.
-- ---------------------------------------------------------------------
create or replace function generar_horario(
  p_desde date,
  p_hasta date,
  p_precio_cop int default 15000,
  p_aforo int default 30,
  p_profesor text default 'Por asignar',
  p_lugar text default 'Sede Tumbao'
) returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_creadas int;
begin
  with horario as (
    -- dow: 1=lunes … 5=viernes, 6=sábado
    select * from (values
      (array[1,2,3,4,5], time '07:00', 'Clase 7:00 am'),
      (array[1,2,3,4,5], time '18:00', 'Clase 6:00 pm'),
      (array[1,2,3,4,5], time '19:00', 'Clase 7:00 pm'),
      (array[6],         time '08:00', 'Clase 8:00 am'),
      (array[6],         time '09:00', 'Clase 9:00 am')
    ) as h(dows, hora, nombre)
  ),
  dias as (
    select d::date as dia
    from generate_series(p_desde, p_hasta, interval '1 day') d
  ),
  nuevas as (
    insert into clases (nombre, profesor, fecha_hora, duracion_min,
                        cupo_total, precio_cop, lugar, aforo, activa)
    select h.nombre, p_profesor,
           (dias.dia + h.hora) at time zone 'America/Bogota',
           60, p_aforo, p_precio_cop, p_lugar, p_aforo, true
    from dias
    join horario h on extract(dow from dias.dia)::int = any(h.dows)
    where not exists (
      select 1 from clases c
       where c.fecha_hora = (dias.dia + h.hora) at time zone 'America/Bogota'
    )
    returning 1
  )
  select count(*)::int into v_creadas from nuevas;

  return v_creadas;
end;
$$;


-- ---------------------------------------------------------------------
-- Recalcular los cupos sueltos de todas las clases futuras
--
-- Se cuenta, para la FECHA de cada clase, cuántas membresías de esa
-- hora la cubren. No un conteo global del día.
--
-- El greatest(cupo_tomado, ...) evita violar el CHECK
-- cupo_tomado <= cupo_total si entran afiliados nuevos después de que
-- alguien ya reservó una suelta. Preferimos pasarnos un puesto antes
-- que dejar la base en un estado inválido o cancelarle a alguien que ya
-- pagó.
-- ---------------------------------------------------------------------
create or replace function recalcular_cupos()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_afectadas int;
  v_apretadas int;
begin
  with calculo as (
    select c.id,
           c.aforo,
           c.cupo_tomado,
           (select count(*)
              from membresias m
             where m.hora = (c.fecha_hora at time zone 'America/Bogota')::time
               and (c.fecha_hora at time zone 'America/Bogota')::date
                   between m.inicio and m.fin)::int as activos
      from clases c
     where c.fecha_hora > now()
  ),
  aplicado as (
    update clases c
       set activos_plan = k.activos,
           cupo_total   = greatest(k.cupo_tomado, greatest(k.aforo - k.activos, 0))
      from calculo k
     where c.id = k.id
       and (c.activos_plan is distinct from k.activos
            or c.cupo_total is distinct from greatest(k.cupo_tomado, greatest(k.aforo - k.activos, 0)))
     returning c.id, k.aforo - k.activos as ideal, c.cupo_total as real
  )
  select count(*)::int,
         count(*) filter (where real > greatest(ideal, 0))::int
    into v_afectadas, v_apretadas
    from aplicado;

  return jsonb_build_object(
    'ok', true,
    'clases_actualizadas', v_afectadas,
    'clases_sobrevendidas_por_reservas_previas', v_apretadas);
end;
$$;


revoke execute on function generar_horario(date, date, int, int, text, text) from public, anon, authenticated;
revoke execute on function recalcular_cupos()                                from public, anon, authenticated;
grant  execute on function generar_horario(date, date, int, int, text, text) to service_role;
grant  execute on function recalcular_cupos()                                to service_role;

alter table membresias enable row level security;


-- ─────────────────────────────────────────────
-- 0010_miembros_y_sueltas.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- Dos caminos en la página: miembro o clase suelta
--
-- REGLA
-- El plan (mensualidad o media) asegura las clases ENTRE SEMANA en el
-- horario del plan. El sábado NO está cubierto: ahí el miembro también
-- tiene que reservar, pero sin pagar.
--
-- La persona elige al principio y eso decide todo lo demás:
--   miembro       -> no se le pide soporte de pago
--   clase suelta  -> paga y sube el soporte
--
-- POR QUÉ SE VERIFICA Y NO SE CREE NOMÁS
-- Ya tenemos la tabla `membresias` con celular y documento, así que
-- comprobar cuesta cero. Sin comprobar, cualquiera escribe "miembro" y
-- entra gratis.
--
-- UN PROBLEMA QUE HAY QUE ATAJAR
-- Los cupos de clase suelta ya se calculan como aforo − activos_plan.
-- El puesto del miembro entre semana YA está descontado ahí. Si además
-- lo dejáramos reservar entre semana, consumiría un cupo suelto y
-- estaríamos contando su puesto dos veces: la clase se vería llena
-- teniendo sitio. Por eso entre semana, en su propio horario, no se le
-- deja reservar — se le dice que ya está cubierto y que solo llegue.
-- =====================================================================

do $$ begin
  create type tipo_reserva as enum ('suelta', 'miembro');
exception when duplicate_object then null; end $$;

alter table reservas add column if not exists tipo tipo_reserva not null default 'suelta';
alter table reservas add column if not exists membresia_id bigint references membresias(id);

create index if not exists reservas_por_tipo on reservas (tipo, estado);


-- ---------------------------------------------------------------------
-- Solo dígitos, y sin el indicativo 57 de Colombia.
-- ---------------------------------------------------------------------
create or replace function solo_digitos(p text) returns text
language sql immutable
set search_path = public, extensions, pg_temp
as $$
  select case
    when length(regexp_replace(coalesce(p,''), '[^0-9]', '', 'g')) = 12
     and left(regexp_replace(coalesce(p,''), '[^0-9]', '', 'g'), 2) = '57'
    then substr(regexp_replace(coalesce(p,''), '[^0-9]', '', 'g'), 3)
    else regexp_replace(coalesce(p,''), '[^0-9]', '', 'g')
  end;
$$;


-- ---------------------------------------------------------------------
-- tomar_cupo con los dos caminos
-- ---------------------------------------------------------------------
drop function if exists tomar_cupo(uuid, text, text, text, text);

create or replace function tomar_cupo(
  p_clase_id uuid,
  p_nombre   text,
  p_telefono text,
  p_email    text,
  p_origen   text,
  p_tipo     text default 'suelta'
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_clase     clases%rowtype;
  v_reserva   reservas%rowtype;
  v_memb      membresias%rowtype;
  v_codigo    text;
  v_intentos  int := 0;
  v_tel       text;
  v_fecha     date;
  v_hora      time;
  v_es_sabado boolean;
  v_estado    estado_reserva := 'pendiente_pago';
  v_memb_id   bigint := null;
begin
  select * into v_clase from clases where id = p_clase_id for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'CLASE_NO_EXISTE',
      'mensaje', 'Esa clase ya no está disponible.');
  end if;
  if not v_clase.activa then
    return jsonb_build_object('ok', false, 'error', 'CLASE_INACTIVA',
      'mensaje', 'Esa clase fue cancelada.');
  end if;
  if v_clase.fecha_hora < now() then
    return jsonb_build_object('ok', false, 'error', 'CLASE_YA_PASO',
      'mensaje', 'Esa clase ya empezó. Elige otro horario.');
  end if;

  v_tel       := solo_digitos(p_telefono);
  v_fecha     := (v_clase.fecha_hora at time zone 'America/Bogota')::date;
  v_hora      := (v_clase.fecha_hora at time zone 'America/Bogota')::time;
  v_es_sabado := extract(dow from v_fecha)::int = 6;

  ------------------------------------------------------------------
  -- Camino miembro
  ------------------------------------------------------------------
  if p_tipo = 'miembro' then
    select * into v_memb
      from membresias m
     where v_fecha between m.inicio and m.fin
       and (solo_digitos(m.celular) = v_tel or solo_digitos(m.documento) = v_tel)
     order by m.fin desc
     limit 1;

    if not found then
      return jsonb_build_object('ok', false, 'error', 'MEMBRESIA_NO_ENCONTRADA',
        'mensaje', 'No encontramos una mensualidad activa con ese celular. '
                || 'Si crees que es un error escríbenos por WhatsApp; si vienes '
                || 'por clase suelta, elige esa opción.');
    end if;

    v_memb_id := v_memb.id;

    if not v_es_sabado then
      if v_memb.hora = v_hora then
        -- Su puesto ya está contado en activos_plan. Dejarlo reservar
        -- consumiría además un cupo suelto: el mismo puesto dos veces.
        return jsonb_build_object('ok', false, 'error', 'PLAN_YA_CUBRE',
          'mensaje', 'Tu plan ya te cubre esta clase, no necesitas reservar. '
                  || 'Solo llega 10 minutos antes.');
      else
        return jsonb_build_object('ok', false, 'error', 'OTRO_HORARIO',
          'mensaje', 'Tu plan es de las ' || to_char(v_memb.hora, 'HH12:MI am')
                  || '. Venir a otra hora entre semana es clase suelta: '
                  || 'elige esa opción.',
          'hora_plan', to_char(v_memb.hora, 'HH12:MI am'));
      end if;
    end if;

    -- Sábado: el plan no lo cubre, reserva sin pagar.
    v_estado := 'confirmada';
  end if;

  ------------------------------------------------------------------
  -- Cupo
  ------------------------------------------------------------------
  if v_clase.cupo_tomado >= v_clase.cupo_total then
    return jsonb_build_object('ok', false, 'error', 'SIN_CUPO',
      'mensaje', 'Esa clase se llenó. Elige otro horario.');
  end if;

  update clases set cupo_tomado = cupo_tomado + 1 where id = p_clase_id;

  loop
    v_intentos := v_intentos + 1;
    v_codigo := generar_codigo_reserva();
    begin
      insert into reservas (codigo, clase_id, nombre, telefono, email,
                            origen, tipo, estado, membresia_id)
      values (v_codigo, p_clase_id, p_nombre, v_tel, p_email,
              p_origen, p_tipo::tipo_reserva, v_estado, v_memb_id)
      returning * into v_reserva;
      exit;
    exception when unique_violation then
      if v_intentos >= 5 then raise; end if;
    end;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'tipo',        p_tipo,
    'requiere_pago', v_estado = 'pendiente_pago',
    'reserva_id',  v_reserva.id,
    'codigo',      v_reserva.codigo,
    'nombre',      v_reserva.nombre,
    'telefono',    v_reserva.telefono,
    'estado',      v_reserva.estado,
    'expira_en',   v_reserva.expira_en,
    'clase',       v_clase.nombre,
    'profesor',    v_clase.profesor,
    'fecha_hora',  v_clase.fecha_hora,
    'lugar',       v_clase.lugar,
    'precio_cop',  v_clase.precio_cop,
    'cupos_restantes', v_clase.cupo_total - v_clase.cupo_tomado - 1);
end;
$$;


-- ---------------------------------------------------------------------
-- Importar el reporte de afiliados
--
-- Reemplaza la tabla entera dentro de una transacción y recalcula los
-- cupos. Si algo falla, no queda a medias.
--
-- Recibe el array ya parseado por n8n: cada fila con afiliado,
-- membresia, hora, tipo, documento, celular, correo, inicio, fin.
-- ---------------------------------------------------------------------
create or replace function importar_membresias(p_filas jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_n        int;
  v_recalc   jsonb;
begin
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'formato_invalido');
  end if;

  select count(*) into v_n from jsonb_array_elements(p_filas);

  -- Un archivo vacío casi siempre es un error de exportación, no que
  -- Tumbao se quedó sin afiliados. Borrar todo dejaría cupos inflados.
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'error', 'archivo_vacio',
      'mensaje', 'El archivo no trajo filas. No se toca nada.');
  end if;

  delete from membresias;

  insert into membresias (afiliado, membresia, hora, tipo, documento,
                          celular, correo, inicio, fin)
  select f->>'afiliado',
         f->>'membresia',
         (f->>'hora')::time,
         coalesce(f->>'tipo', 'otro'),
         f->>'documento',
         f->>'celular',
         f->>'correo',
         (f->>'inicio')::date,
         (f->>'fin')::date
    from jsonb_array_elements(p_filas) f
   where f->>'hora' is not null
     and f->>'inicio' is not null
     and f->>'fin' is not null;

  get diagnostics v_n = row_count;

  v_recalc := recalcular_cupos();

  return jsonb_build_object('ok', true, 'membresias', v_n, 'cupos', v_recalc);
end;
$$;


revoke execute on function tomar_cupo(uuid, text, text, text, text, text) from public, anon, authenticated;
revoke execute on function importar_membresias(jsonb)                     from public, anon, authenticated;
revoke execute on function solo_digitos(text)                             from public, anon, authenticated;
grant  execute on function tomar_cupo(uuid, text, text, text, text, text) to service_role;
grant  execute on function importar_membresias(jsonb)                     to service_role;


-- ─────────────────────────────────────────────
-- 0011_admin.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- Panel de administración
--
-- Tres cosas que hoy no se pueden hacer:
--
--   1. Armar el horario de una semana a mano. generar_horario() aplica
--      siempre el mismo molde (L-V 7am/6pm/7pm, sáb 8am/9am). Si una
--      semana hay festivo, o se abre una clase extra, no hay por dónde.
--
--   2. Forzar los cupos de una clase. Hoy salen siempre de
--      aforo − afiliados_activos. Si un día caben menos porque hay
--      evento, o se quieren soltar más, no hay perilla.
--
--   3. Darle el check a un pago que no concilió solo. Esto estaba en el
--      flujo desde el principio — "el humano da el check y le envía un
--      mensaje por WhatsApp" — pero no existía la función. Las reservas
--      caían en pendiente_validacion y ahí se quedaban para siempre.
--
-- Todo pasa por un token de admin. Sin token no se ejecuta nada.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Cupo forzado a mano
--
-- null  = automático (aforo − activos), que es el comportamiento normal
-- un nº = se respeta ese, pase lo que pase con las membresías
-- ---------------------------------------------------------------------
alter table clases add column if not exists cupo_manual int
  check (cupo_manual is null or cupo_manual >= 0);

comment on column clases.cupo_manual is
  'Cupos sueltos forzados a mano. null = calculado desde las membresias.';


-- ---------------------------------------------------------------------
-- Tokens de admin
--
-- Se guarda el hash, no el token. Si alguien se lleva la tabla no puede
-- entrar; y si se pierde el token no hay forma de recuperarlo, se emite
-- otro y listo.
-- ---------------------------------------------------------------------
create table if not exists admin_tokens (
  id          uuid primary key default extensions.gen_random_uuid(),
  nombre      text not null,
  token_hash  text not null unique,
  creado_at   timestamptz not null default now(),
  ultimo_uso  timestamptz,
  activo      boolean not null default true
);

alter table admin_tokens enable row level security;


create or replace function hash_token(p_token text)
returns text
language sql
immutable
set search_path = public, extensions, pg_temp
as $$
  select encode(extensions.digest(p_token, 'sha256'), 'hex');
$$;


-- Emite un token nuevo. Lo devuelve UNA sola vez: después ya no se
-- puede volver a leer, solo emitir otro.
create or replace function crear_token_admin(p_nombre text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_token text;
begin
  if coalesce(trim(p_nombre), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'sin_nombre',
      'mensaje', 'Ponle un nombre para saber de quien es el token.');
  end if;

  -- 32 bytes en base64url: suficiente y sin caracteres que se rompan
  -- al pegarlos en una URL.
  v_token := translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_');

  insert into admin_tokens (nombre, token_hash)
  values (trim(p_nombre), hash_token(v_token));

  return jsonb_build_object('ok', true, 'token', v_token,
    'mensaje', 'Guardalo ya. No se puede volver a ver.');
end;
$$;


create or replace function verificar_token_admin(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_id uuid;
begin
  if coalesce(p_token, '') = '' then return null; end if;

  select id into v_id
    from admin_tokens
   where token_hash = hash_token(p_token)
     and activo
   limit 1;

  if v_id is not null then
    update admin_tokens set ultimo_uso = now() where id = v_id;
  end if;
  return v_id;
end;
$$;


-- ---------------------------------------------------------------------
-- recalcular_cupos, ahora respetando el cupo forzado a mano
--
-- Cambia solo eso respecto a 0009: si cupo_manual tiene valor, ese
-- manda. El greatest(cupo_tomado, ...) se mantiene porque el CHECK
-- cupo_tomado <= cupo_total sigue ahi, y preferimos pasarnos un puesto
-- antes que cancelarle a alguien que ya pago.
-- ---------------------------------------------------------------------
create or replace function recalcular_cupos()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_afectadas int;
  v_apretadas int;
  v_manuales  int;
begin
  with calculo as (
    select c.id,
           c.aforo,
           c.cupo_tomado,
           c.cupo_manual,
           (select count(*)
              from membresias m
             where m.hora = (c.fecha_hora at time zone 'America/Bogota')::time
               and (c.fecha_hora at time zone 'America/Bogota')::date
                   between m.inicio and m.fin)::int as activos
      from clases c
     where c.fecha_hora > now()
  ),
  objetivo as (
    select k.*,
           greatest(
             k.cupo_tomado,
             coalesce(k.cupo_manual, greatest(k.aforo - k.activos, 0))
           ) as meta
      from calculo k
  ),
  aplicado as (
    update clases c
       set activos_plan = o.activos,
           cupo_total   = o.meta
      from objetivo o
     where c.id = o.id
       and (c.activos_plan is distinct from o.activos
            or c.cupo_total is distinct from o.meta)
     returning c.id,
               o.cupo_manual,
               coalesce(o.cupo_manual, greatest(o.aforo - o.activos, 0)) as ideal,
               c.cupo_total as real
  )
  select count(*)::int,
         count(*) filter (where real > ideal)::int,
         count(*) filter (where cupo_manual is not null)::int
    into v_afectadas, v_apretadas, v_manuales
    from aplicado;

  return jsonb_build_object(
    'ok', true,
    'clases_actualizadas', v_afectadas,
    'clases_con_cupo_manual', v_manuales,
    'clases_sobrevendidas_por_reservas_previas', v_apretadas);
end;
$$;


-- ---------------------------------------------------------------------
-- La semana, como la ve el panel
--
-- Devuelve siempre los 7 días completos, existan clases o no, para que
-- la cuadrícula se pueda pintar sin adivinar.
-- ---------------------------------------------------------------------
create or replace function admin_semana(p_token text, p_desde date)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_dias  jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select coalesce(jsonb_agg(d order by d->>'fecha'), '[]'::jsonb) into v_dias
  from (
    select jsonb_build_object(
      'fecha', dia,
      'dow',   extract(dow from dia)::int,
      'clases', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'clase_id',    c.id,
                 'nombre',      c.nombre,
                 'hora',        to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'),
                 'profesor',    c.profesor,
                 'activa',      c.activa,
                 'aforo',       c.aforo,
                 'activos_plan', c.activos_plan,
                 'cupo_total',  c.cupo_total,
                 'cupo_tomado', c.cupo_tomado,
                 'cupo_manual', c.cupo_manual,
                 'ya_paso',     c.fecha_hora <= now()
               ) order by c.fecha_hora)
          from clases c
         where (c.fecha_hora at time zone 'America/Bogota')::date = dia
      ), '[]'::jsonb)
    ) as d
    from generate_series(p_desde, p_desde + 6, interval '1 day') g(dia)
  ) s;

  return jsonb_build_object('ok', true, 'desde', p_desde,
    'hasta', p_desde + 6, 'dias', v_dias);
end;
$$;


-- ---------------------------------------------------------------------
-- Guardar la semana de un golpe
--
-- p_celdas = [{fecha, hora, activa, cupo_manual, aforo, profesor}, ...]
--   fecha 'YYYY-MM-DD', hora 'HH:MM'
--   activa false      -> la clase se apaga (no se borra: si alguien ya
--                        reservó, borrarla se llevaría la reserva por
--                        delante)
--   cupo_manual null  -> vuelve al cálculo automático
--
-- Se hace todo en una transacción: o entra la semana entera o no entra
-- nada. Así no queda media semana guardada si algo falla.
-- ---------------------------------------------------------------------
create or replace function admin_guardar_semana(p_token text, p_celdas jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin    uuid;
  v_celda    jsonb;
  v_fecha    date;
  v_hora     time;
  v_momento  timestamptz;
  v_clase    clases%rowtype;
  v_creadas  int := 0;
  v_editadas int := 0;
  v_apagadas int := 0;
  v_avisos   jsonb := '[]'::jsonb;
  v_cupo_manual int;
  v_aforo    int;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  if p_celdas is null or jsonb_typeof(p_celdas) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'SIN_DATOS',
      'mensaje', 'No llego ninguna celda que guardar.');
  end if;

  for v_celda in select * from jsonb_array_elements(p_celdas) loop
    v_fecha := (v_celda->>'fecha')::date;
    v_hora  := (v_celda->>'hora')::time;
    v_momento := (v_fecha + v_hora) at time zone 'America/Bogota';

    v_cupo_manual := case
      when v_celda->>'cupo_manual' is null then null
      else (v_celda->>'cupo_manual')::int end;
    v_aforo := coalesce((v_celda->>'aforo')::int, 30);

    select * into v_clase from clases where fecha_hora = v_momento;

    if not found then
      -- No se crean clases en el pasado: no sirven para nada y ensucian.
      if v_momento <= now() then
        v_avisos := v_avisos || jsonb_build_object(
          'fecha', v_fecha, 'hora', to_char(v_hora, 'HH24:MI'),
          'aviso', 'no se creo, esa hora ya paso');
        continue;
      end if;
      if coalesce((v_celda->>'activa')::boolean, true) then
        insert into clases (nombre, profesor, fecha_hora, duracion_min,
                            cupo_total, precio_cop, lugar, aforo, activa, cupo_manual)
        values (
          coalesce(nullif(trim(v_celda->>'nombre'), ''),
                   'Clase ' || trim(to_char(v_fecha + v_hora, 'HH12:MI am'))),
          coalesce(nullif(trim(v_celda->>'profesor'), ''), 'Por asignar'),
          v_momento, 60,
          coalesce(v_cupo_manual, v_aforo),
          coalesce((v_celda->>'precio_cop')::int, 15000),
          'Sede Tumbao', v_aforo, true, v_cupo_manual);
        v_creadas := v_creadas + 1;
      end if;
      continue;
    end if;

    -- Apagar una clase que ya tiene gente adentro es peor que dejarla.
    if coalesce((v_celda->>'activa')::boolean, true) = false
       and v_clase.cupo_tomado > 0 then
      v_avisos := v_avisos || jsonb_build_object(
        'fecha', v_fecha, 'hora', to_char(v_hora, 'HH24:MI'),
        'aviso', 'no se apago: ya tiene ' || v_clase.cupo_tomado || ' reserva(s)');
      continue;
    end if;

    -- Un cupo manual por debajo de lo ya reservado dejaria la tabla en
    -- un estado invalido; se sube a lo minimo posible y se avisa.
    if v_cupo_manual is not null and v_cupo_manual < v_clase.cupo_tomado then
      v_avisos := v_avisos || jsonb_build_object(
        'fecha', v_fecha, 'hora', to_char(v_hora, 'HH24:MI'),
        'aviso', 'se dejo en ' || v_clase.cupo_tomado ||
                 ': ya hay esas reservas, no se puede bajar mas');
      v_cupo_manual := v_clase.cupo_tomado;
    end if;

    update clases
       set activa      = coalesce((v_celda->>'activa')::boolean, activa),
           aforo       = v_aforo,
           cupo_manual = v_cupo_manual,
           cupo_total  = greatest(cupo_tomado,
                                  coalesce(v_cupo_manual,
                                           greatest(v_aforo - activos_plan, 0))),
           profesor    = coalesce(nullif(trim(v_celda->>'profesor'), ''), profesor)
     where id = v_clase.id;

    if coalesce((v_celda->>'activa')::boolean, true) = false then
      v_apagadas := v_apagadas + 1;
    else
      v_editadas := v_editadas + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true,
    'creadas', v_creadas, 'editadas', v_editadas, 'apagadas', v_apagadas,
    'avisos', v_avisos);
end;
$$;


-- ---------------------------------------------------------------------
-- La cola de validación humana
--
-- Lo que quedó esperando el check de alguien: o porque el correo del
-- banco no llegó en 5 minutos, o porque llegaron dos pagos iguales y no
-- se pudo saber cuál era cuál.
-- ---------------------------------------------------------------------
create or replace function admin_pendientes(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_out   jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select coalesce(jsonb_agg(x order by x->>'creada_at'), '[]'::jsonb) into v_out
  from (
    select jsonb_build_object(
      'codigo',     r.codigo,
      'nombre',     r.nombre,
      'telefono',   r.telefono,
      'estado',     r.estado,
      'creada_at',  r.created_at,
      'clase',      c.nombre,
      'fecha_hora', c.fecha_hora,
      'precio_cop', c.precio_cop,
      -- Pagos sin dueño de ese valor, para que quien valida tenga algo
      -- con que comparar en vez de adivinar.
      'pagos_sueltos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'pago_id',   p.id,
                 'valor_cop', p.valor_cop,
                 'fecha',     p.fecha_pago,
                 'remitente', p.remitente,
                 'parecido',  round(similitud_nombre(r.nombre, p.remitente), 2))
               order by p.fecha_pago desc)
          from pagos p
         where p.valor_cop = c.precio_cop
           and p.fecha_pago between r.created_at - interval '30 minutes'
                               and r.created_at + interval '3 hours'
           and not exists (select 1 from reservas r2 where r2.pago_id = p.id)
      ), '[]'::jsonb)
    ) as x
    from reservas r
    join clases c on c.id = r.clase_id
   where r.estado in ('pendiente_validacion', 'verificando')
  ) s;

  return jsonb_build_object('ok', true, 'reservas', v_out);
end;
$$;


-- ---------------------------------------------------------------------
-- El check
--
-- p_pago_id opcional: si se pasa, la reserva queda amarrada a ese pago
-- concreto (y ese pago ya no puede usarse para otra). Si no se pasa, se
-- confirma sin amarrar — para el caso de "me consta que pagó, lo vi".
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
         updated_at = now()
   where id = v_reserva.id;

  return jsonb_build_object('ok', true, 'estado', 'confirmada',
    'codigo', v_reserva.codigo, 'nombre', v_reserva.nombre,
    'telefono', v_reserva.telefono,
    'mensaje', 'Confirmada a mano.');
end;
$$;


-- ---------------------------------------------------------------------
-- Rechazar: suelta el cupo para que lo pueda tomar alguien más
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
      'mensaje', 'Esa reserva ya esta confirmada. Si hay que deshacerla, con cuidado y a mano.');
  end if;

  update reservas set estado = 'rechazada', updated_at = now()
   where id = v_reserva.id;

  update clases set cupo_tomado = greatest(cupo_tomado - 1, 0)
   where id = v_reserva.clase_id;

  return jsonb_build_object('ok', true, 'estado', 'rechazada',
    'codigo', v_reserva.codigo, 'nombre', v_reserva.nombre,
    'telefono', v_reserva.telefono,
    'mensaje', 'Rechazada, el cupo quedo libre.');
end;
$$;


-- ---------------------------------------------------------------------
-- Quién viene a una clase
-- ---------------------------------------------------------------------
create or replace function admin_reservas_de_clase(p_token text, p_clase_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_out   jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo',   r.codigo,
           'nombre',   r.nombre,
           'telefono', r.telefono,
           'tipo',     r.tipo,
           'estado',   r.estado,
           'creada_at', r.created_at)
         order by r.created_at), '[]'::jsonb)
    into v_out
    from reservas r
   where r.clase_id = p_clase_id
     and r.estado not in ('expirada', 'rechazada');

  return jsonb_build_object('ok', true, 'reservas', v_out);
end;
$$;


-- ---------------------------------------------------------------------
-- Permisos: nada de esto se toca con la llave publica
-- ---------------------------------------------------------------------
revoke execute on function hash_token(text)                        from public, anon, authenticated;
revoke execute on function crear_token_admin(text)                 from public, anon, authenticated;
revoke execute on function verificar_token_admin(text)             from public, anon, authenticated;
revoke execute on function admin_semana(text, date)                from public, anon, authenticated;
revoke execute on function admin_guardar_semana(text, jsonb)       from public, anon, authenticated;
revoke execute on function admin_pendientes(text)                  from public, anon, authenticated;
revoke execute on function admin_confirmar(text, text, uuid)       from public, anon, authenticated;
revoke execute on function admin_rechazar(text, text)              from public, anon, authenticated;
revoke execute on function admin_reservas_de_clase(text, uuid)     from public, anon, authenticated;
revoke execute on function recalcular_cupos()                      from public, anon, authenticated;

grant execute on function admin_semana(text, date)            to service_role;
grant execute on function admin_guardar_semana(text, jsonb)   to service_role;
grant execute on function admin_pendientes(text)              to service_role;
grant execute on function admin_confirmar(text, text, uuid)   to service_role;
grant execute on function admin_rechazar(text, text)          to service_role;
grant execute on function admin_reservas_de_clase(text, uuid) to service_role;
grant execute on function crear_token_admin(text)             to service_role;
grant execute on function recalcular_cupos()                  to service_role;


-- ═══════════════════════════════════════════════════════════════
--   Y ahora el horario y el token
-- ═══════════════════════════════════════════════════════════════

create temp table if not exists _tumbao_resultado (paso text, detalle text);
delete from _tumbao_resultado;

do $$
declare
  v_r jsonb;
  v_n int;
begin
  -- ── horario de las próximas 3 semanas ──────────────────────
  -- Lun–vie 7:00 am / 6:00 pm / 7:00 pm, sábado 8:00 am / 9:00 am.
  -- No pisa las clases que ya existan.
  perform generar_horario(current_date, current_date + 20);
  select count(*) into v_n from clases where fecha_hora > now() and activa;
  insert into _tumbao_resultado
    values ('1. Horario', v_n || ' clases cargadas (proximas 3 semanas)');

  -- ── cupos ──────────────────────────────────────────────────
  select recalcular_cupos() into v_r;
  insert into _tumbao_resultado
    values ('2. Cupos',
      'Calculados. Por ahora salen del aforo porque todavia no se ha ' ||
      'importado el listado de afiliados; el workflow de n8n los ajusta esta noche.');

  -- ── token del panel ────────────────────────────────────────
  -- Solo se emite si no hay ninguno activo, para que re-correr este
  -- archivo no llene la tabla de tokens sueltos.
  if exists (select 1 from admin_tokens where activo) then
    insert into _tumbao_resultado
      values ('3. Token del panel',
        'Ya habias emitido uno. Si lo perdiste, corre aparte:  ' ||
        'select crear_token_admin(''Tania'');');
  else
    select crear_token_admin('Tania') into v_r;
    insert into _tumbao_resultado
      values ('3. TU TOKEN DEL PANEL — copialo ya, no se vuelve a ver',
              v_r->>'token');
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════
--   RESULTADO — mira la tabla de abajo
-- ═══════════════════════════════════════════════════════════════
select * from _tumbao_resultado order by paso;
