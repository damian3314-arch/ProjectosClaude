-- Cambio de horario (0095): una de mensualidad de las 7am puede pedir la
-- clase de las 6pm, pero eso NO es lo mismo que una suelta ni un miembro
-- normal — es un tercer cupo, chiquito y aparte, porque no todo el que
-- tiene plan a esa hora llega a ocuparlo.
--
-- Damián, 22 de septiembre: "siempre la prioridad van a ser las clases
-- sueltas... luego la cantidad de membresías activas que tengamos para
-- ese horario... eso se podría manejar entre cuatro cambios... y ya luego
-- de que intenten hacerle en la página y les salga algún aviso... les
-- invite a contactarse al WhatsApp".
--
-- Cinco cosas que no pueden fallar:
--
--   1. En su propia hora, el plan sigue cubriendo (PLAN_YA_CUBRE), sin
--      volverse un cambio.
--   2. En otra hora entre semana, ya no rebota de una: entra como
--      'cambio' si hay cupo del lado del cambio.
--   3. Un cambio NUNCA suma a cupo_tomado ni compite por el techo de la
--      sala — puede entrar aunque la sala esté "llena" en el papel,
--      porque su cupo es independiente.
--   4. El tope de cambios (4 por defecto) sí manda: el quinto rebota con
--      CAMBIO_LLENO y un mensaje que invita al WhatsApp.
--   5. El sábado no se toca: ahí cualquier miembro activo entra como
--      'miembro' sin pasar por nada de esto.
--
--   psql -d tumbao -f pruebas/humo-cambio-de-horario.sql

\set ON_ERROR_STOP on
set timezone = 'America/Bogota';

do $$
declare
  v_lun date;
  v_c7 uuid; v_c18 uuid; v_sab uuid;
  v_r jsonb; v_n int; v_tok text;
begin
  delete from asistencias where true;
  delete from reservas where true;
  delete from pagos where true;
  delete from membresias where true;
  delete from clases where true;
  delete from admin_tokens where true;
  perform generar_horario(current_date, current_date + 13);

  select (fecha_hora at time zone 'America/Bogota')::date into v_lun
    from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') between 1 and 5
     and (fecha_hora at time zone 'America/Bogota')::date
         > (now() at time zone 'America/Bogota')::date
   order by fecha_hora limit 1;
  select id into v_c7 from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_lun
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 7;
  select id into v_c18 from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_lun
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 18;
  select id into v_sab from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') = 6
     and (fecha_hora at time zone 'America/Bogota')::date
         > (now() at time zone 'America/Bogota')::date
   order by fecha_hora limit 1;

  v_tok := (crear_token_admin('humo cambio de horario'))->>'token';

  -- Una afiliada de plan de las 7am.
  perform importar_membresias(jsonb_build_array(jsonb_build_object(
    'afiliado', 'Siete Uno', 'membresia', 'PLAN MENSUALIDAD 7:00AM',
    'hora', '07:00:00', 'tipo', 'plan',
    'documento', '900000001', 'celular', '3009990001', 'correo', null,
    'inicio', (current_date - 3)::text, 'fin', (current_date + 25)::text)));

  -- ── 1. su propia hora sigue igual ──────────────────────────
  select tomar_cupo(v_c7, 'Siete Uno', '3009990001', null, 'web', 'miembro') into v_r;
  if (v_r->>'ok')::boolean is not false or (v_r->>'error') <> 'PLAN_YA_CUBRE' then
    raise exception 'en su hora deberia decir PLAN_YA_CUBRE, dijo: %', v_r;
  end if;
  raise notice '1. en su propia hora, PLAN_YA_CUBRE de siempre';

  -- ── 2. otra hora entre semana entra como cambio ────────────
  select tomar_cupo(v_c18, 'Siete Uno', '3009990001', null, 'web', 'miembro') into v_r;
  if (v_r->>'ok')::boolean is not true or (v_r->>'tipo') <> 'cambio' then
    raise exception 'el cambio deberia entrar, dijo: %', v_r;
  end if;
  if (v_r->>'requiere_pago')::boolean is not false then
    raise exception 'un cambio no se paga, dijo requiere_pago: %', v_r->>'requiere_pago';
  end if;
  raise notice '2. otra hora entre semana entra como cambio, sin pago';

  -- ── 3. el cambio no toca cupo_tomado ni el techo ───────────
  select cupo_tomado into v_n from clases where id = v_c18;
  if v_n <> 0 then
    raise exception 'el cambio no debia sumar a cupo_tomado, quedo en %', v_n;
  end if;
  -- Llenamos la sala de sueltas hasta el techo (5, para la prueba) y
  -- comprobamos que un cambio nuevo AUN ASI entra.
  update clases set cupo_total = 5, cupo_tomado = 5 where id = v_c18;
  select tomar_cupo(v_c18, 'Suelta de Mas', '3111110001', null, 'web', 'suelta') into v_r;
  if (v_r->>'error') <> 'SIN_CUPO' then
    raise exception 'con la sala llena una suelta de mas no debia entrar: %', v_r;
  end if;
  perform importar_membresias(jsonb_build_array(jsonb_build_object(
    'afiliado', 'Siete Dos', 'membresia', 'PLAN MENSUALIDAD 7:00AM',
    'hora', '07:00:00', 'tipo', 'plan',
    'documento', '900000002', 'celular', '3009990002', 'correo', null,
    'inicio', (current_date - 3)::text, 'fin', (current_date + 25)::text)));
  select tomar_cupo(v_c18, 'Siete Dos', '3009990002', null, 'web', 'miembro') into v_r;
  if (v_r->>'ok')::boolean is not true or (v_r->>'tipo') <> 'cambio' then
    raise exception 'con la sala llena, el cambio SI debia entrar: %', v_r;
  end if;
  raise notice '3. el cambio no suma al cupo de la sala, ni lo respeta como techo';

  -- ── 4. el tope de cambios (4 por defecto) manda ────────────
  -- Van dos (Siete Uno, Siete Dos). Dos mas para llegar a 4, y el
  -- quinto debe rebotar con CAMBIO_LLENO.
  for v_n in 3..4 loop
    perform importar_membresias(jsonb_build_array(jsonb_build_object(
      'afiliado', 'Siete ' || v_n, 'membresia', 'PLAN MENSUALIDAD 7:00AM',
      'hora', '07:00:00', 'tipo', 'plan',
      'documento', '90000000' || v_n, 'celular', '300999000' || v_n,
      'correo', null,
      'inicio', (current_date - 3)::text, 'fin', (current_date + 25)::text)));
    select tomar_cupo(v_c18, 'Siete ' || v_n, '300999000' || v_n, null, 'web', 'miembro') into v_r;
    if (v_r->>'ok')::boolean is not true or (v_r->>'tipo') <> 'cambio' then
      raise exception 'el cambio %/4 debia entrar, dijo: %', v_n, v_r;
    end if;
  end loop;
  perform importar_membresias(jsonb_build_array(jsonb_build_object(
    'afiliado', 'Siete Cinco', 'membresia', 'PLAN MENSUALIDAD 7:00AM',
    'hora', '07:00:00', 'tipo', 'plan',
    'documento', '900000005', 'celular', '3009990005', 'correo', null,
    'inicio', (current_date - 3)::text, 'fin', (current_date + 25)::text)));
  select tomar_cupo(v_c18, 'Siete Cinco', '3009990005', null, 'web', 'miembro') into v_r;
  if (v_r->>'error') <> 'CAMBIO_LLENO' then
    raise exception 'el quinto cambio debia rebotar con CAMBIO_LLENO: %', v_r;
  end if;
  if not (v_r->>'mensaje' ~* 'whatsapp') then
    raise exception 'el mensaje de CAMBIO_LLENO no invita al whatsapp: %', v_r->>'mensaje';
  end if;
  raise notice '4. el quinto cambio rebota con CAMBIO_LLENO e invita al whatsapp';

  -- ── el propietario puede mover el tope a mano ──────────────
  select admin_cambios_tope(v_tok, 5) into v_r;
  if (v_r->>'ok')::boolean is not true or (v_r->>'tope')::int <> 5 then
    raise exception 'admin_cambios_tope no guardo el tope: %', v_r;
  end if;
  select tomar_cupo(v_c18, 'Siete Cinco', '3009990005', null, 'web', 'miembro') into v_r;
  if (v_r->>'ok')::boolean is not true or (v_r->>'tipo') <> 'cambio' then
    raise exception 'con el tope en 5, el quinto SI debia entrar: %', v_r;
  end if;
  raise notice '5. el propietario sube el tope y el que rebotaba ahora entra';

  -- ── 6. el sabado no se toca ─────────────────────────────────
  select tomar_cupo(v_sab, 'Siete Uno', '3009990001', null, 'web', 'miembro') into v_r;
  if (v_r->>'ok')::boolean is not true or (v_r->>'tipo') <> 'miembro' then
    raise exception 'el sabado no debia cambiar de comportamiento: %', v_r;
  end if;
  raise notice '6. el sabado sigue exactamente igual';

  delete from admin_tokens where nombre = 'humo cambio de horario';
end $$;

select 'TODO EN VERDE' as resultado;
