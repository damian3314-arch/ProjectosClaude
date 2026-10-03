-- ¿La página tiene de verdad la última palabra sobre los cupos?
--
-- La promesa es: si la página dice 3, se venden 3 y ni uno más. Eso
-- descansa en tres cosas, y aquí se prueban las tres:
--
--   1. cupo_total = aforo − gente con plan activo a esa hora
--   2. cada reserva descuenta exactamente uno
--   3. dos personas NO pueden llevarse el último cupo a la vez
--
-- La tercera es la que importa de verdad y la que no se puede probar
-- "a ojo": necesita dos sesiones peleando por la misma fila. Va en
-- pruebas/carrera-cupos.mjs, que llama a esta base en paralelo.
--
--   psql -d tumbao -f pruebas/humo-aforo.sql

\set ON_ERROR_STOP on
set timezone = 'America/Bogota';

do $$
declare
  v_lun date; v_sab date;
  v_c18 uuid; v_csab uuid;
  v_r jsonb; v_n int; v_cupo int; v_tomado int; v_activos int;
begin
  delete from reservas where true;
  delete from pagos where true;
  delete from membresias where true;
  delete from clases where true;
  perform generar_horario(current_date, current_date + 13);

  -- 27 personas con plan de 6pm, como en la vida real hoy.
  perform importar_membresias((
    select jsonb_agg(f) from (
      select jsonb_build_object(
        'afiliado', 'Socia ' || g, 'membresia', 'PLAN MENSUALIDAD 6:00PM',
        'hora', '18:00:00', 'tipo', 'plan',
        'documento', (700000 + g)::text, 'celular', '300' || lpad(g::text, 7, '0'),
        'correo', null,
        'inicio', (current_date - 3)::text, 'fin', (current_date + 25)::text) as f
      from generate_series(1, 27) g
    ) s));

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

  select id, aforo, activos_plan, cupo_total into v_c18, v_n, v_activos, v_cupo
    from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_lun
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 18;

  -- ── 1. la resta ────────────────────────────────────────────
  if v_n <> 30 then raise exception 'el aforo deberia ser 30, es %', v_n; end if;
  if v_activos <> 27 then raise exception 'activos: se esperaban 27, hay %', v_activos; end if;
  if v_cupo <> 3 then raise exception '30 - 27 deberia dar 3 cupos, dio %', v_cupo; end if;
  raise notice '1. aforo 30 − 27 con plan = % cupos sueltos', v_cupo;

  -- ── 2. cada reserva descuenta uno ──────────────────────────
  select tomar_cupo(v_c18, 'Primera', '3000000001', null, 'web', 'suelta') into v_r;
  if (v_r->>'cupos_restantes')::int <> 2 then
    raise exception 'tras la 1a deberian quedar 2, quedan %', v_r->>'cupos_restantes';
  end if;
  select tomar_cupo(v_c18, 'Segunda', '3000000002', null, 'web', 'suelta') into v_r;
  select tomar_cupo(v_c18, 'Tercera', '3000000003', null, 'web', 'suelta') into v_r;
  if (v_r->>'cupos_restantes')::int <> 0 then
    raise exception 'tras la 3a deberian quedar 0, quedan %', v_r->>'cupos_restantes';
  end if;
  raise notice '2. tres reservas dejaron el cupo en 0';

  -- ── 3. la cuarta no entra ──────────────────────────────────
  select tomar_cupo(v_c18, 'Cuarta', '3000000004', null, 'web', 'suelta') into v_r;
  if (v_r->>'ok')::boolean is not false or (v_r->>'error') <> 'SIN_CUPO' then
    raise exception 'la cuarta persona entro en una clase de 3 cupos: %', v_r;
  end if;
  select cupo_tomado, cupo_total into v_tomado, v_cupo from clases where id = v_c18;
  if v_tomado > v_cupo then
    raise exception 'se vendieron % de % cupos', v_tomado, v_cupo;
  end if;
  raise notice '3. la cuarta rebota con SIN_CUPO (% de %)', v_tomado, v_cupo;

  -- ── 4. el sabado: aforo entero, y el miembro tambien reserva ──
  select id, activos_plan, cupo_total into v_csab, v_activos, v_cupo
    from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_sab
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 8;
  if v_activos <> 0 then
    raise exception 'el sabado nadie tiene plan, pero salen % activos', v_activos;
  end if;
  -- 0058: el sabado dejo de heredar el aforo de entre semana. Su techo
  -- es la suma de sus dos lados, 15 afiliados + 20 sueltas = 35, y por
  -- eso nace con aforo y cupo_total propios.
  if v_cupo <> 35 then raise exception 'el sabado deberian ser 35 cupos, son %', v_cupo; end if;

  -- Una socia del plan de 6pm: entre semana no reserva, el sabado si.
  select tomar_cupo(v_csab, 'Socia 1', '3000000001', null, 'web', 'miembro') into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'el miembro no pudo reservar el sabado: %', v_r;
  end if;
  select cupo_tomado into v_tomado from clases where id = v_csab;
  if v_tomado <> 1 then raise exception 'el miembro del sabado no descontro cupo'; end if;
  raise notice '4. sabado: 35 cupos, y la reserva del miembro descuenta igual';

  -- Y su reserva de sabado sale del mismo pozo que las sueltas.
  select tomar_cupo(v_csab, 'Suelta Sabado', '3000000009', null, 'web', 'suelta') into v_r;
  -- 0058: 35 menos los dos que acaban de entrar. Antes eran 28 porque
  -- el techo del sabado era el aforo de entre semana.
  if (v_r->>'cupos_restantes')::int <> 33 then
    raise exception 'miembro y suelta deberian compartir el aforo, quedan %',
      v_r->>'cupos_restantes';
  end if;
  raise notice '   miembro y clase suelta comparten los mismos 35';

  -- ── 5. si crecen los planes, no se cancela a quien ya reservo ──
  -- Se agregan 2 socias mas de 6pm: el ideal seria 30-29=1, pero ya hay
  -- 3 reservas vendidas. Se prefiere quedar apretado antes que echar a
  -- alguien que ya pago, y eso queda REPORTADO, no escondido.
  -- importar_membresias ya recalcula por dentro: el resultado de los
  -- cupos viene en su propia respuesta. Llamar recalcular_cupos aparte
  -- devolveria 0 cambios porque ya no queda nada que cambiar.
  select importar_membresias((
    select jsonb_agg(f) from (
      select jsonb_build_object(
        'afiliado', 'Socia ' || g, 'membresia', 'PLAN MENSUALIDAD 6:00PM',
        'hora', '18:00:00', 'tipo', 'plan',
        'documento', (700000 + g)::text, 'celular', '300' || lpad(g::text, 7, '0'),
        'correo', null,
        'inicio', (current_date - 3)::text, 'fin', (current_date + 25)::text) as f
      from generate_series(1, 29) g
    ) s)) into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'la importacion con un miembro ya inscrito fallo: %', v_r;
  end if;
  v_r := v_r->'cupos';
  select cupo_tomado, cupo_total into v_tomado, v_cupo from clases where id = v_c18;
  if v_cupo < v_tomado then
    raise exception 'recalcular dejo cupo_total (%) por debajo de lo vendido (%)', v_cupo, v_tomado;
  end if;
  if (v_r->>'clases_sobrevendidas_por_reservas_previas')::int < 1 then
    raise exception 'no reporto la clase apretada: %', v_r;
  end if;
  raise notice '5. crecieron los planes: no se cancela a nadie y se reporta (% apretada(s))',
    v_r->>'clases_sobrevendidas_por_reservas_previas';
end $$;

select 'TODO EN VERDE' as resultado;
