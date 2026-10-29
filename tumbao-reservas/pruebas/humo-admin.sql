-- Prueba de humo del panel de admin (0011).
-- Corre despues de humo-supabase.sql, que deja horario y membresias.
--
--   psql -d tumbao -f pruebas/humo-admin.sql

\set ON_ERROR_STOP on
set timezone = 'America/Bogota';

do $$
declare
  v_tok   text;
  v_r     jsonb;
  v_lun   date;
  v_clase uuid;
  v_n     int;
  v_cupo  int;
  v_cod   text;
begin
  -- Reset completo: la prueba llena clases y las apaga, así que sin esto
  -- la segunda corrida se encuentra las clases del día anterior llenas y
  -- falla por algo que no tiene que ver con lo que se está probando.
  delete from admin_tokens;
  delete from reservas;
  delete from pagos;
  delete from clases;
  perform generar_horario(current_date, current_date + 13);

  -- ── token ──────────────────────────────────────────────────
  select crear_token_admin('Tania') into v_r;
  if (v_r->>'ok')::boolean is not true then raise exception 'no se emitio el token: %', v_r; end if;
  v_tok := v_r->>'token';
  if length(v_tok) < 20 then raise exception 'el token salio muy corto: %', v_tok; end if;
  -- Lo que se guarda es el hash, no el token.
  if exists (select 1 from admin_tokens where token_hash = v_tok) then
    raise exception 'el token quedo guardado en claro';
  end if;
  if verificar_token_admin(v_tok) is null then raise exception 'el token recien creado no verifica'; end if;
  if verificar_token_admin('inventado') is not null then raise exception 'un token inventado paso'; end if;
  if verificar_token_admin('') is not null then raise exception 'el token vacio paso'; end if;
  raise notice 'token: emitido, guardado hasheado, verifica';

  -- Sin token no se hace nada. Se prueban todas, no solo una.
  if (admin_semana('malo', current_date)->>'error') <> 'NO_AUTORIZADO'
     or (admin_guardar_semana('malo', '[]'::jsonb)->>'error') <> 'NO_AUTORIZADO'
     or (admin_pendientes('malo')->>'error') <> 'NO_AUTORIZADO'
     or (admin_confirmar('malo', 'XXXXXX')->>'error') <> 'NO_AUTORIZADO'
     or (admin_rechazar('malo', 'XXXXXX')->>'error') <> 'NO_AUTORIZADO'
     or (admin_reservas_de_clase('malo', extensions.gen_random_uuid())->>'error') <> 'NO_AUTORIZADO' then
    raise exception 'alguna funcion de admin dejo pasar un token invalido';
  end if;
  raise notice 'permisos: las 6 funciones rebotan sin token';

  -- ── ver la semana ──────────────────────────────────────────
  select admin_semana(v_tok, current_date) into v_r;
  if (v_r->>'ok')::boolean is not true then raise exception 'admin_semana fallo: %', v_r; end if;
  if jsonb_array_length(v_r->'dias') <> 7 then
    raise exception 'la semana deberia traer 7 dias, trajo %', jsonb_array_length(v_r->'dias');
  end if;
  raise notice 'semana: 7 dias';

  -- Un día entre semana que todavía no ha empezado. `fecha_hora > now()`
  -- no basta: a las 6 de la tarde la clase de las 7 de HOY sigue siendo
  -- futura, v_lun caía en hoy, y abrir una clase a las 5 pm de hoy
  -- fallaba con "esa hora ya paso". La prueba se caía por la hora a la
  -- que se corriera, no por el código.
  select fecha_hora::date into v_lun from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') between 1 and 5
     and (fecha_hora at time zone 'America/Bogota')::date
         > (now() at time zone 'America/Bogota')::date
   order by fecha_hora limit 1;

  -- ── abrir una clase que no existe en el molde ───────────────
  -- 5:00 pm no esta en el horario normal. Tiene que poder abrirse.
  select admin_guardar_semana(v_tok, jsonb_build_array(jsonb_build_object(
    'fecha', v_lun::text, 'hora', '17:00', 'activa', true,
    'cupo_manual', 12, 'aforo', 30, 'profesor', 'Kevin'))) into v_r;
  if (v_r->>'creadas')::int <> 1 then raise exception 'no se creo la clase de 5pm: %', v_r; end if;

  select id, cupo_total into v_clase, v_cupo from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_lun
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 17;
  if v_clase is null then raise exception 'la clase de 5pm no aparece'; end if;
  if v_cupo <> 12 then raise exception 'la clase de 5pm deberia tener 12 cupos, tiene %', v_cupo; end if;
  raise notice 'clase fuera del molde: creada con 12 cupos';

  -- El cupo manual tiene que sobrevivir a recalcular_cupos. Esto es lo
  -- que se rompia antes: recalcular pisaba el ajuste a mano.
  perform recalcular_cupos();
  select cupo_total, cupo_manual into v_cupo, v_n from clases where id = v_clase;
  if v_cupo <> 12 then raise exception 'recalcular_cupos piso el cupo manual: quedo en %', v_cupo; end if;
  raise notice 'cupo manual: sobrevive a recalcular_cupos';

  -- Y al soltarlo vuelve al automatico.
  select admin_guardar_semana(v_tok, jsonb_build_array(jsonb_build_object(
    'fecha', v_lun::text, 'hora', '17:00', 'activa', true,
    'cupo_manual', null, 'aforo', 30))) into v_r;
  perform recalcular_cupos();
  select cupo_total into v_cupo from clases where id = v_clase;
  if v_cupo <> 30 then
    raise exception 'sin cupo manual y sin planes a las 5pm deberian quedar 30, quedaron %', v_cupo;
  end if;
  raise notice 'cupo automatico: vuelve solo al soltar el manual';

  -- ── apagar una clase ───────────────────────────────────────
  select admin_guardar_semana(v_tok, jsonb_build_array(jsonb_build_object(
    'fecha', v_lun::text, 'hora', '17:00', 'activa', false))) into v_r;
  if (v_r->>'apagadas')::int <> 1 then raise exception 'no se apago la clase: %', v_r; end if;
  if (select activa from clases where id = v_clase) then raise exception 'la clase sigue activa'; end if;
  raise notice 'apagar clase vacia: OK';

  -- Pero una clase con gente adentro no se apaga.
  select id into v_clase from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_lun
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 18;
  select tomar_cupo(v_clase, 'Alguien Ya Reservo', '3007770001', null, 'web', 'suelta') into v_r;
  if (v_r->>'ok')::boolean is not true then raise exception 'no se pudo sembrar la reserva: %', v_r; end if;

  select admin_guardar_semana(v_tok, jsonb_build_array(jsonb_build_object(
    'fecha', v_lun::text, 'hora', '18:00', 'activa', false))) into v_r;
  if (v_r->>'apagadas')::int <> 0 then raise exception 'se apago una clase con reservas: %', v_r; end if;
  if not (select activa from clases where id = v_clase) then
    raise exception 'la clase con reservas quedo apagada';
  end if;
  if jsonb_array_length(v_r->'avisos') = 0 then raise exception 'no aviso por que no la apago'; end if;
  raise notice 'apagar clase con gente: se niega y avisa (%)', v_r->'avisos'->0->>'aviso';

  -- Tampoco se puede bajar el cupo por debajo de lo ya reservado.
  select admin_guardar_semana(v_tok, jsonb_build_array(jsonb_build_object(
    'fecha', v_lun::text, 'hora', '18:00', 'activa', true, 'cupo_manual', 0))) into v_r;
  select cupo_total, cupo_tomado into v_cupo, v_n from clases where id = v_clase;
  if v_cupo < v_n then raise exception 'el cupo (%) quedo por debajo de lo reservado (%)', v_cupo, v_n; end if;
  raise notice 'cupo por debajo de lo reservado: se frena en % ', v_cupo;

  -- ── no se crean clases en el pasado ────────────────────────
  select admin_guardar_semana(v_tok, jsonb_build_array(jsonb_build_object(
    'fecha', (current_date - 3)::text, 'hora', '10:00', 'activa', true))) into v_r;
  if (v_r->>'creadas')::int <> 0 then raise exception 'creo una clase en el pasado: %', v_r; end if;
  raise notice 'clase en el pasado: no se crea';
end $$;


-- ── la cola de validacion humana y el check ────────────────────
do $$
declare
  v_tok   text;
  v_r     jsonb;
  v_clase uuid;
  v_cod   text;
  v_estado text;
  v_tomado_antes int;
  v_tomado_despues int;
begin
  select 'x' into v_tok;   -- se reemplaza abajo
  select token_hash into v_tok from admin_tokens limit 1;
  -- El token en claro no se puede recuperar, asi que se emite otro.
  delete from admin_tokens;
  select (crear_token_admin('Tania')->>'token') into v_tok;

  select id into v_clase from clases
   where fecha_hora > now() and activa
   order by fecha_hora limit 1;

  -- Alguien que dijo que pago y el banco nunca aviso.
  select tomar_cupo(v_clase, 'Paula Andrea Nieto', '3006660001', null, 'web', 'suelta') into v_r;
  v_cod := v_r->>'codigo';
  update reservas set estado = 'pendiente_validacion', updated_at = now() where codigo = v_cod;

  select admin_pendientes(v_tok) into v_r;
  if (v_r->>'ok')::boolean is not true then raise exception 'admin_pendientes fallo: %', v_r; end if;
  if not exists (
    select 1 from jsonb_array_elements(v_r->'reservas') e where e->>'codigo' = v_cod
  ) then raise exception 'la reserva pendiente no aparece en la cola'; end if;
  raise notice 'cola de validacion: aparece %', v_cod;

  -- El check.
  select admin_confirmar(v_tok, v_cod) into v_r;
  if (v_r->>'ok')::boolean is not true then raise exception 'el check fallo: %', v_r; end if;
  select estado::text into v_estado from reservas where codigo = v_cod;
  if v_estado <> 'confirmada' then raise exception 'tras el check quedo en %', v_estado; end if;
  -- Y trae el telefono, que es lo que hace falta para escribir por WhatsApp.
  if coalesce(v_r->>'telefono', '') = '' then
    raise exception 'el check no devolvio el telefono para avisarle a la persona';
  end if;
  raise notice 'check: confirmada y devuelve el telefono (%)', v_r->>'telefono';

  -- Darle el check dos veces no rompe nada.
  select admin_confirmar(v_tok, v_cod) into v_r;
  if (v_r->>'ok')::boolean is not true then raise exception 'el segundo check reboto: %', v_r; end if;

  -- Ya confirmada no se puede rechazar de un click.
  select admin_rechazar(v_tok, v_cod) into v_r;
  if (v_r->>'error') <> 'YA_CONFIRMADA' then
    raise exception 'dejo rechazar una reserva ya confirmada: %', v_r;
  end if;
  raise notice 'rechazar una confirmada: se niega';

  -- Rechazar sí suelta el cupo.
  select tomar_cupo(v_clase, 'Se Arrepintio', '3006660002', null, 'web', 'suelta') into v_r;
  v_cod := v_r->>'codigo';
  select cupo_tomado into v_tomado_antes from clases where id = v_clase;
  select admin_rechazar(v_tok, v_cod) into v_r;
  if (v_r->>'ok')::boolean is not true then raise exception 'el rechazo fallo: %', v_r; end if;
  select cupo_tomado into v_tomado_despues from clases where id = v_clase;
  if v_tomado_despues <> v_tomado_antes - 1 then
    raise exception 'rechazar no solto el cupo: % -> %', v_tomado_antes, v_tomado_despues;
  end if;
  raise notice 'rechazar: suelta el cupo (% -> %)', v_tomado_antes, v_tomado_despues;

  -- Un codigo que no existe.
  if (admin_confirmar(v_tok, 'ZZZZZZ')->>'error') <> 'NO_EXISTE' then
    raise exception 'confirmo un codigo inexistente';
  end if;

  -- Quien viene a la clase.
  select admin_reservas_de_clase(v_tok, v_clase) into v_r;
  if (v_r->>'ok')::boolean is not true then raise exception 'admin_reservas_de_clase fallo: %', v_r; end if;
  if exists (select 1 from jsonb_array_elements(v_r->'reservas') e where e->>'estado' = 'rechazada') then
    raise exception 'la lista de asistentes incluye rechazadas';
  end if;
  raise notice 'lista de la clase: % personas, sin rechazadas',
    jsonb_array_length(v_r->'reservas');
end $$;

-- ── la forma de la fecha, que es contrato con la página ────────
-- admin_semana tiene que devolver AAAA-MM-DD pelado. Cuando devolvía
-- "2026-07-28T00:00:00+00:00" la cuadrícula se caía entera con
-- "Invalid time value", y como el error subía hasta el login parecía
-- que el token estuviera mal. Se comprueba en las tres zonas horarias
-- porque el valor viejo cambiaba según la zona de la conexión.
do $$
declare
  v_tok text; v_r jsonb; v_f text; v_tz text;
begin
  delete from admin_tokens where true;
  v_tok := (crear_token_admin('forma de fecha'))->>'token';

  foreach v_tz in array array['UTC', 'America/Bogota', 'Asia/Tokyo'] loop
    execute format('set local timezone = %L', v_tz);
    v_r := admin_semana(v_tok, date '2026-07-27');

    if jsonb_array_length(v_r->'dias') <> 7 then
      raise exception '% : la semana no trajo 7 dias', v_tz;
    end if;
    for v_f in select d->>'fecha' from jsonb_array_elements(v_r->'dias') d loop
      if v_f !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception '% : fecha con forma impintable: %', v_tz, v_f;
      end if;
    end loop;
    if (v_r->'dias'->0->>'fecha') <> '2026-07-27'
       or (v_r->'dias'->6->>'fecha') <> '2026-08-02' then
      raise exception '% : la semana no va del 27 al 2: % .. %', v_tz,
        v_r->'dias'->0->>'fecha', v_r->'dias'->6->>'fecha';
    end if;
    -- El 27 de julio de 2026 es lunes: dow 1. Si esto se corre, el dia
    -- de la semana tampoco depende ya de la zona de la conexion.
    if (v_r->'dias'->0->>'dow')::int <> 1 then
      raise exception '% : el lunes salio con dow %', v_tz, v_r->'dias'->0->>'dow';
    end if;
  end loop;
  reset timezone;
  raise notice 'fechas de la semana: AAAA-MM-DD en las tres zonas';
end $$;

-- ── permisos, otra vez, ahora con las de admin ─────────────────
do $$
declare v_mal text;
begin
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (has_function_privilege('anon', p.oid, 'execute')
       or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_mal is not null then
    raise exception 'funciones abiertas a la llave publica: %', v_mal;
  end if;
  raise notice 'permisos: nada ejecutable con la llave anon';
end $$;

select 'TODO EN VERDE' as resultado;
