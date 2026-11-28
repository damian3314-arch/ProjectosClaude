-- ¿El tablero dice la verdad?
--
-- Es una pantalla de solo lectura, así que el riesgo no es que rompa
-- nada: es que muestre un número tranquilizador que no corresponde con
-- la sala. Aquí se monta un día con datos conocidos y se comprueba cada
-- casilla contra lo que debería salir a mano.
--
-- La que más importa es `en_sala`: gente con plan (que no reserva, solo
-- llega) más las reservas vivas. Es el número que decide si cabe una
-- persona más.
--
--   psql -d tumbao -f pruebas/humo-tablero.sql

\set ON_ERROR_STOP on
set timezone = 'America/Bogota';

do $$
declare
  v_tok  text;
  v_lun  date; v_sab date;
  v_c18  uuid; v_c07 uuid; v_csab uuid;
  v_t    jsonb; v_c jsonb; v_r jsonb; v_res jsonb;
  v_cod  text;
begin
  delete from reservas where true;
  delete from pagos where true;
  delete from membresias where true;
  delete from clases where true;
  delete from admin_tokens where true;
  perform generar_horario(current_date, current_date + 13);

  v_tok := (crear_token_admin('humo del tablero'))->>'token';

  -- 27 con plan de 6pm y 19 de 7am, como en la vida real.
  perform importar_membresias((
    select jsonb_agg(f) from (
      select jsonb_build_object(
        'afiliado', 'Socia ' || g, 'membresia', 'PLAN MENSUALIDAD',
        'hora', case when g <= 27 then '18:00:00' else '07:00:00' end,
        'tipo', 'plan', 'documento', (700000 + g)::text,
        'celular', '300' || lpad(g::text, 7, '0'), 'correo', null,
        'inicio', (current_date - 3)::text, 'fin', (current_date + 25)::text) as f
      from generate_series(1, 46) g
    ) s));

  -- Un día COMPLETO por delante, no "la próxima clase". Corriendo esto
  -- por la tarde, la de las 7 pm de hoy sigue siendo futura y v_lun caía
  -- en hoy — pero la de las 7 am ya pasó, así que sus 19 afiliados no
  -- sumaban y el resumen daba 27 en vez de 46. Fallaba por la hora a la
  -- que se corriera, no por el código.
  select (fecha_hora at time zone 'America/Bogota')::date into v_lun
    from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') between 1 and 5
     and (fecha_hora at time zone 'America/Bogota')::date
         > (now() at time zone 'America/Bogota')::date
   order by fecha_hora limit 1;
  select (fecha_hora at time zone 'America/Bogota')::date into v_sab
    from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') = 6
     and (fecha_hora at time zone 'America/Bogota')::date
         > (now() at time zone 'America/Bogota')::date
   order by fecha_hora limit 1;

  select id into v_c18 from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_lun
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 18;
  select id into v_c07 from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_lun
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 7;

  -- ── 1. un día entre semana, sin reservas todavía ────────────
  v_t := admin_tablero(v_tok, v_lun);
  if (v_t->>'ok')::boolean is not true then
    raise exception 'el tablero no respondio: %', v_t;
  end if;
  if jsonb_array_length(v_t->'clases') <> 3 then
    raise exception 'entre semana hay 3 clases, el tablero trajo %',
      jsonb_array_length(v_t->'clases');
  end if;

  select c into v_c from jsonb_array_elements(v_t->'clases') c
   where c->>'hora' = '18:00';
  if (v_c->>'con_plan')::int <> 27 then
    raise exception 'las 6pm deberian tener 27 con plan, dice %', v_c->>'con_plan';
  end if;
  if (v_c->>'a_la_venta')::int <> 3 then
    raise exception '30 - 27 son 3 a la venta, dice %', v_c->>'a_la_venta';
  end if;
  if (v_c->>'reservadas')::int <> 0 or (v_c->>'libres')::int <> 3 then
    raise exception 'sin reservas deberian quedar 3 libres: %', v_c;
  end if;
  if (v_c->>'en_sala')::int <> 27 then
    raise exception 'en sala deberian ir los 27 con plan, dice %', v_c->>'en_sala';
  end if;
  raise notice '1. 6pm: aforo 30, 27 con plan, 3 a la venta, 27 en sala';

  -- ── 2. cada reserva mueve las tres casillas a la vez ────────
  select tomar_cupo(v_c18, 'Clara Velasquez', '3165241919', null, 'web', 'suelta') into v_r;
  v_cod := v_r->>'codigo';
  select tomar_cupo(v_c18, 'Lorena Rivera', '3194113242', null, 'web', 'suelta') into v_r;

  v_t := admin_tablero(v_tok, v_lun);
  select c into v_c from jsonb_array_elements(v_t->'clases') c where c->>'hora' = '18:00';
  if (v_c->>'reservadas')::int <> 2 then
    raise exception 'deberian ir 2 reservas, dice %', v_c->>'reservadas';
  end if;
  if (v_c->>'libres')::int <> 1 then
    raise exception 'deberia quedar 1 libre, dice %', v_c->>'libres';
  end if;
  if (v_c->>'en_sala')::int <> 29 then
    raise exception '27 con plan + 2 reservas = 29 en sala, dice %', v_c->>'en_sala';
  end if;
  -- Recien creadas estan esperando el pago, no confirmadas.
  if (v_c->>'confirmadas')::int <> 0 or (v_c->>'esperando')::int <> 2 then
    raise exception 'las 2 nuevas deberian estar esperando pago: %', v_c;
  end if;
  raise notice '2. dos reservas: 2 reservadas, 1 libre, 29 en sala, 0 confirmadas';

  -- ── 3. confirmar mueve de "esperando" a "confirmada" ────────
  update reservas set estado = 'pendiente_validacion' where codigo = v_cod;
  v_t := admin_tablero(v_tok, v_lun);
  select c into v_c from jsonb_array_elements(v_t->'clases') c where c->>'hora' = '18:00';
  if (v_c->>'por_validar')::int <> 1 or (v_c->>'esperando')::int <> 1 then
    raise exception 'deberia haber 1 por validar y 1 esperando: %', v_c;
  end if;

  perform admin_confirmar(v_tok, v_cod, null);
  v_t := admin_tablero(v_tok, v_lun);
  select c into v_c from jsonb_array_elements(v_t->'clases') c where c->>'hora' = '18:00';
  if (v_c->>'confirmadas')::int <> 1 or (v_c->>'por_validar')::int <> 0 then
    raise exception 'tras confirmar deberia haber 1 confirmada: %', v_c;
  end if;
  if (v_c->>'ingreso_cop')::int <> 15000 then
    raise exception '1 confirmada de $15.000 deberia dar 15000, da %', v_c->>'ingreso_cop';
  end if;
  -- Confirmar no cambia cuanta gente entra: ya tenia el cupo tomado.
  if (v_c->>'en_sala')::int <> 29 then
    raise exception 'confirmar no deberia mover en_sala, dice %', v_c->>'en_sala';
  end if;
  raise notice '3. confirmar: 1 confirmada, $15.000, y en sala sigue en 29';

  -- ── 4. rechazar suelta el cupo y baja en_sala ───────────────
  select codigo into v_cod from reservas
   where clase_id = v_c18 and estado <> 'confirmada' limit 1;
  update reservas set estado = 'pendiente_validacion' where codigo = v_cod;
  perform admin_rechazar(v_tok, v_cod);
  v_t := admin_tablero(v_tok, v_lun);
  select c into v_c from jsonb_array_elements(v_t->'clases') c where c->>'hora' = '18:00';
  if (v_c->>'reservadas')::int <> 1 or (v_c->>'libres')::int <> 2 then
    raise exception 'tras rechazar deberian quedar 1 reservada y 2 libres: %', v_c;
  end if;
  if (v_c->>'en_sala')::int <> 28 then
    raise exception 'rechazar deberia bajar en_sala a 28, dice %', v_c->>'en_sala';
  end if;
  raise notice '4. rechazar: suelta el cupo y baja la sala a 28';

  -- ── 5. el resumen no puede contradecir a las tarjetas ───────
  v_res := v_t->'resumen';
  if (v_res->>'clases')::int <> jsonb_array_length(v_t->'clases') then
    raise exception 'el resumen cuenta % clases y hay %',
      v_res->>'clases', jsonb_array_length(v_t->'clases');
  end if;
  if (v_res->>'con_plan')::int <> 46 then
    raise exception 'los 46 afiliados deberian sumar en el resumen, suma %',
      v_res->>'con_plan';
  end if;
  if (v_res->>'en_sala')::int
     <> (select sum((c->>'en_sala')::int) from jsonb_array_elements(v_t->'clases') c) then
    raise exception 'el resumen no cuadra con la suma de las tarjetas';
  end if;
  if (v_res->>'ingreso_cop')::int <> 15000 then
    raise exception 'el ingreso del dia deberia ser 15000, es %', v_res->>'ingreso_cop';
  end if;
  raise notice '5. el resumen cuadra con la suma de las tarjetas';

  -- ── 6. el sabado: nadie con plan, aforo entero a la venta ───
  select id into v_csab from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_sab
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 8;
  select tomar_cupo(v_csab, 'Socia 1', '3000000001', null, 'web', 'miembro') into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'el miembro no pudo reservar el sabado: %', v_r;
  end if;

  v_t := admin_tablero(v_tok, v_sab);
  select c into v_c from jsonb_array_elements(v_t->'clases') c where c->>'hora' = '08:00';
  if (v_c->>'con_plan')::int <> 0 then
    raise exception 'el sabado nadie tiene plan, dice %', v_c->>'con_plan';
  end if;
  -- 0058: el sabado ya no vende el aforo de entre semana sino la suma
  -- de sus dos lados: 15 afiliados + 20 sueltas.
  if (v_c->>'a_la_venta')::int <> 35 then
    raise exception 'el sabado salen los 35, dice %', v_c->>'a_la_venta';
  end if;
  -- El miembro del sabado reserva sin pagar: entra confirmado de una.
  if (v_c->>'confirmadas')::int <> 1 then
    raise exception 'la reserva del miembro deberia entrar confirmada: %', v_c;
  end if;
  if (v_c->>'en_sala')::int <> 1 then
    raise exception 'el sabado en sala = reservas, deberia ser 1, dice %',
      v_c->>'en_sala';
  end if;
  -- Y no cobra: su plan ya esta pago, la reserva es solo para el aforo.
  if (v_c->>'ingreso_cop')::int <> 15000 then
    raise notice '   (ojo: el miembro del sabado cuenta como ingreso, revisar si molesta)';
  end if;
  raise notice '6. sabado: 0 con plan, 30 a la venta, 1 en sala';

  -- ── 7. un dia sin clases no revienta ───────────────────────
  v_t := admin_tablero(v_tok, current_date + 400);
  if (v_t->>'ok')::boolean is not true then
    raise exception 'un dia lejano deberia responder ok: %', v_t;
  end if;
  if jsonb_array_length(v_t->'clases') <> 0 then
    raise exception 'no deberia haber clases dentro de 400 dias';
  end if;
  if (v_t->'resumen'->>'en_sala')::int <> 0 then
    raise exception 'un dia vacio deberia sumar 0, suma %', v_t->'resumen'->>'en_sala';
  end if;
  raise notice '7. un dia sin clases responde en ceros, no en error';

  -- ── 8. sin token no se ve nada ─────────────────────────────
  v_t := admin_tablero('token-inventado', v_lun);
  if (v_t->>'error') <> 'NO_AUTORIZADO' then
    raise exception 'un token falso vio el tablero: %', v_t;
  end if;
  raise notice '8. token falso: NO_AUTORIZADO';

  -- ── 9. la cola de validacion trae con que agrupar ───────────
  select tomar_cupo(v_c07, 'Otra Persona', '3110000001', null, 'web', 'suelta') into v_r;
  update reservas set estado = 'pendiente_validacion'
   where codigo = v_r->>'codigo';

  v_r := admin_pendientes(v_tok);
  if jsonb_array_length(v_r->'reservas') < 1 then
    raise exception 'la cola deberia traer al menos una';
  end if;
  if (v_r->'reservas'->0->>'clase_id') is null then
    raise exception 'sin clase_id no se puede agrupar por horario';
  end if;
  if (v_r->'reservas'->0->>'tipo') is null then
    raise exception 'falta el tipo (miembro o suelta)';
  end if;
  raise notice '9. la cola trae clase_id y tipo para agrupar';
end $$;

-- ── 10. el tablero no puede escribir nada ────────────────────
do $$
declare v_mal text;
begin
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('admin_tablero')
     and (has_function_privilege('anon', p.oid, 'execute')
       or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_mal is not null then
    raise exception 'el tablero esta abierto a la llave publica: %', v_mal;
  end if;
  raise notice '10. el tablero no es ejecutable con la llave anon';
end $$;

select 'TODO EN VERDE' as resultado;
