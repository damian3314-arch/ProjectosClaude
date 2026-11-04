-- ¿La lista de la puerta sirve de verdad en la puerta?
--
-- El caso real: son las 5:55, hay cola, y alguien dice "yo reservé".
-- La lista tiene que responder en un vistazo y no puede mentir en
-- ninguna de estas tres:
--
--   1. Estar completa. Entre semana entran DOS grupos y solo uno
--      reserva. Una lista con solo las reservas deja al portero
--      mirando 3 nombres de las 30 personas que van a entrar.
--   2. No contar a nadie dos veces. El sábado el miembro sí reserva:
--      si sale en los dos grupos, el aforo se ve mal.
--   3. Aguantar la importación de la noche. `membresias` se borra
--      entera cada noche; si la asistencia colgara de ahí, la lista de
--      ayer se vaciaría sola.
--
--   psql -d tumbao -f pruebas/humo-puerta.sql

\set ON_ERROR_STOP on
set timezone = 'America/Bogota';

do $$
declare
  v_tok text; v_lun date; v_sab date;
  v_c18 uuid; v_csab uuid;
  v_l jsonb; v_r jsonb; v_p jsonb;
  v_cod text; v_ref text;
begin
  delete from asistencias where true;
  delete from reservas where true;
  delete from pagos where true;
  delete from membresias where true;
  delete from clases where true;
  delete from admin_tokens where true;
  perform generar_horario(current_date, current_date + 13);

  v_tok := (crear_token_admin('humo de puerta'))->>'token';

  -- 4 personas con plan de 6pm.
  perform importar_membresias((
    select jsonb_agg(f) from (
      select jsonb_build_object(
        'afiliado', 'Socia ' || g, 'membresia', 'PLAN MENSUALIDAD 6:00PM',
        'hora', '18:00:00', 'tipo', 'plan',
        'documento', (700000 + g)::text, 'celular', '300' || lpad(g::text, 7, '0'),
        'correo', null,
        'inicio', (current_date - 3)::text, 'fin', (current_date + 25)::text) as f
      from generate_series(1, 4) g
    ) s));

  select (fecha_hora at time zone 'America/Bogota')::date into v_lun
    from clases where extract(dow from fecha_hora at time zone 'America/Bogota') between 1 and 5
     and (fecha_hora at time zone 'America/Bogota')::date
         > (now() at time zone 'America/Bogota')::date order by fecha_hora limit 1;
  select (fecha_hora at time zone 'America/Bogota')::date into v_sab
    from clases where extract(dow from fecha_hora at time zone 'America/Bogota') = 6
     and (fecha_hora at time zone 'America/Bogota')::date
         > (now() at time zone 'America/Bogota')::date order by fecha_hora limit 1;

  select id into v_c18 from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_lun
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 18;
  select id into v_csab from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_sab
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 8;

  -- ── 1. la lista trae los dos grupos ────────────────────────
  select tomar_cupo(v_c18, 'Yenny Vergara', '3102543733', null, 'web', 'suelta') into v_r;
  v_cod := v_r->>'codigo';
  update reservas set estado = 'confirmada' where codigo = v_cod;

  v_l := admin_lista_clase(v_tok, v_c18);
  if (v_l->>'ok')::boolean is not true then
    raise exception 'la lista no respondio: %', v_l;
  end if;
  if jsonb_array_length(v_l->'reservas') <> 1 then
    raise exception 'deberia haber 1 reserva, hay %', jsonb_array_length(v_l->'reservas');
  end if;
  if jsonb_array_length(v_l->'con_plan') <> 4 then
    raise exception 'deberian salir las 4 con plan, salen %',
      jsonb_array_length(v_l->'con_plan');
  end if;
  if (v_l->'resumen'->>'esperados')::int <> 5 then
    raise exception 'se esperan 5 personas, dice %', v_l->'resumen'->>'esperados';
  end if;
  raise notice '1. la lista trae los dos grupos: 1 reserva + 4 con plan = 5 esperados';

  -- ── 2. marcar que entro ────────────────────────────────────
  select (e->>'ref') into v_ref from jsonb_array_elements(v_l->'reservas') e limit 1;
  select admin_marcar_asistencia(v_tok, v_c18, v_ref, true) into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'no dejo marcar: %', v_r;
  end if;
  v_l := admin_lista_clase(v_tok, v_c18);
  if (v_l->'reservas'->0->>'asistio')::boolean is not true then
    raise exception 'la marca no quedo';
  end if;
  if (v_l->'resumen'->>'entraron')::int <> 1 then
    raise exception 'deberia contar 1 entrada, cuenta %', v_l->'resumen'->>'entraron';
  end if;
  raise notice '2. marcar entrada: queda puesta y cuenta 1';

  -- ── 3. marcar dos veces no cuenta dos ──────────────────────
  -- En la puerta se dan clics repetidos y con prisa.
  perform admin_marcar_asistencia(v_tok, v_c18, v_ref, true);
  perform admin_marcar_asistencia(v_tok, v_c18, v_ref, true);
  v_l := admin_lista_clase(v_tok, v_c18);
  if (v_l->'resumen'->>'entraron')::int <> 1 then
    raise exception 'tres clics contaron % entradas', v_l->'resumen'->>'entraron';
  end if;
  raise notice '3. tres clics seguidos siguen contando 1';

  -- ── 4. desmarcar, por si fue un error ──────────────────────
  perform admin_marcar_asistencia(v_tok, v_c18, v_ref, false);
  v_l := admin_lista_clase(v_tok, v_c18);
  if (v_l->'reservas'->0->>'asistio')::boolean is not false then
    raise exception 'no se pudo desmarcar';
  end if;
  if (v_l->'resumen'->>'entraron')::int <> 0 then
    raise exception 'tras desmarcar deberian ser 0, son %', v_l->'resumen'->>'entraron';
  end if;
  perform admin_marcar_asistencia(v_tok, v_c18, v_ref, true);
  raise notice '4. desmarcar tambien funciona';

  -- ── 5. tambien se marca a quien tiene plan ─────────────────
  select (e->>'ref') into v_ref from jsonb_array_elements(v_l->'con_plan') e limit 1;
  select admin_marcar_asistencia(v_tok, v_c18, v_ref, true) into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'no dejo marcar a quien tiene plan: %', v_r;
  end if;
  v_l := admin_lista_clase(v_tok, v_c18);
  if (select count(*) from jsonb_array_elements(v_l->'con_plan') e
       where (e->>'asistio')::boolean) <> 1 then
    raise exception 'la marca del plan no quedo';
  end if;
  if (v_l->'resumen'->>'entraron')::int <> 2 then
    raise exception 'deberian ser 2 entradas, son %', v_l->'resumen'->>'entraron';
  end if;
  raise notice '5. quien tiene plan tambien se marca (2 entraron)';

  -- ── 6. la que no concilio sale, pero avisada ───────────────
  -- Alguien puede plantarse en la puerta con el pago hecho hace dos
  -- minutos. Tiene que verse, con la advertencia al lado.
  select tomar_cupo(v_c18, 'Lorena Rivera', '3194113242', null, 'web', 'suelta') into v_r;
  update reservas set estado = 'pendiente_validacion' where codigo = v_r->>'codigo';
  v_l := admin_lista_clase(v_tok, v_c18);
  if jsonb_array_length(v_l->'reservas') <> 2 then
    raise exception 'la que espera validacion tiene que salir igual';
  end if;
  if (v_l->'resumen'->>'sin_confirmar')::int <> 1 then
    raise exception 'deberia avisar 1 sin confirmar, avisa %',
      v_l->'resumen'->>'sin_confirmar';
  end if;
  raise notice '6. la que aun no concilia sale en la lista, marcada como sin confirmar';

  -- ── 7. la rechazada NO sale ────────────────────────────────
  select tomar_cupo(v_c18, 'No Pago', '3009998877', null, 'web', 'suelta') into v_r;
  update reservas set estado = 'pendiente_validacion' where codigo = v_r->>'codigo';
  perform admin_rechazar(v_tok, v_r->>'codigo');
  v_l := admin_lista_clase(v_tok, v_c18);
  if exists (select 1 from jsonb_array_elements(v_l->'reservas') e
              where e->>'nombre' = 'No Pago') then
    raise exception 'una reserva rechazada aparecio en la lista de la puerta';
  end if;
  raise notice '7. una rechazada no aparece en la puerta';

  -- ── 8. el sabado nadie sale dos veces ──────────────────────
  -- El sabado el miembro SI reserva. Si saliera en los dos grupos, el
  -- aforo se veria mal.
  select tomar_cupo(v_csab, 'Socia 1', '3000000001', null, 'web', 'miembro') into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'el miembro no pudo reservar el sabado: %', v_r;
  end if;
  v_l := admin_lista_clase(v_tok, v_csab);
  if jsonb_array_length(v_l->'con_plan') <> 0 then
    raise exception 'el sabado nadie tiene plan de esa hora, salen %',
      jsonb_array_length(v_l->'con_plan');
  end if;
  if (v_l->'resumen'->>'esperados')::int <> 1 then
    raise exception 'el sabado deberia esperarse 1 persona, dice %',
      v_l->'resumen'->>'esperados';
  end if;
  raise notice '8. sabado: el miembro sale una sola vez, en reservas';

  -- ── 9. la asistencia aguanta la importacion de la noche ────
  -- membresias se borra entera cada noche. Lo que paso por la puerta
  -- es un hecho: no puede desaparecer con la replica.
  perform importar_membresias((
    select jsonb_agg(f) from (
      select jsonb_build_object(
        'afiliado', 'Socia ' || g, 'membresia', 'PLAN MENSUALIDAD 6:00PM',
        'hora', '18:00:00', 'tipo', 'plan',
        'documento', (700000 + g)::text, 'celular', '300' || lpad(g::text, 7, '0'),
        'correo', null,
        'inicio', (current_date - 3)::text, 'fin', (current_date + 25)::text) as f
      from generate_series(1, 4) g
    ) s));

  v_l := admin_lista_clase(v_tok, v_c18);
  if (v_l->'resumen'->>'entraron')::int <> 2 then
    raise exception 'la importacion se llevo las asistencias: quedan %',
      v_l->'resumen'->>'entraron';
  end if;
  if (select count(*) from jsonb_array_elements(v_l->'con_plan') e
       where (e->>'asistio')::boolean) <> 1 then
    raise exception 'la marca del miembro no sobrevivio a la importacion';
  end if;
  raise notice '9. la importacion de la noche no borra lo que ya paso por la puerta';

  -- ── 10. sin token no se ve ni se marca ─────────────────────
  v_l := admin_lista_clase('token-inventado', v_c18);
  if (v_l->>'error') <> 'NO_AUTORIZADO' then
    raise exception 'un token falso vio la lista: %', v_l;
  end if;
  select admin_marcar_asistencia('token-inventado', v_c18, v_ref, true) into v_r;
  if (v_r->>'error') <> 'NO_AUTORIZADO' then
    raise exception 'un token falso pudo marcar: %', v_r;
  end if;
  raise notice '10. token falso: NO_AUTORIZADO';

  -- ── 11. no se marca a alguien de otra clase ────────────────
  select admin_marcar_asistencia(v_tok, v_csab, 'r:' || v_cod, true) into v_r;
  if (v_r->>'error') <> 'NO_EXISTE' then
    raise exception 'marco en el sabado a alguien del lunes: %', v_r;
  end if;
  raise notice '11. una reserva de otra clase no se puede marcar aqui';
end $$;

-- ── 12. nada de esto se toca con la llave publica ────────────
do $$
declare v_mal text;
begin
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('admin_lista_clase', 'admin_marcar_asistencia')
     and (has_function_privilege('anon', p.oid, 'execute')
       or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_mal is not null then
    raise exception 'abiertas a la llave publica: %', v_mal;
  end if;
  if not (select relrowsecurity from pg_class where relname = 'asistencias') then
    raise exception 'asistencias sin RLS';
  end if;
  raise notice '12. lista y marca no son ejecutables con la llave anon';
end $$;

select 'TODO EN VERDE' as resultado;
