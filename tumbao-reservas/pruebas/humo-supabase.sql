-- Prueba de humo de las funciones 0007-0010 contra un Postgres de verdad.
-- No basta con que las migraciones "apliquen": hay que ver que hagan lo suyo.
--
--   psql -d tumbao -f pruebas/humo-supabase.sql
--
-- Cada bloque grita si algo no cuadra, asi que si termina sin ERROR, paso.

\set ON_ERROR_STOP on
set timezone = 'America/Bogota';

do $$
declare
  v_sab date;
  v_lun date;
  v_clase_sab uuid;
  v_clase_lun18 uuid;
  v_clase_lun19 uuid;
  v_r jsonb;
  v_cupos int;
  v_activos int;
  v_n int;
begin
  -- Se limpia para poder correrla las veces que haga falta.
  delete from reservas;
  delete from pagos;
  delete from membresias;
  delete from clases;

  -- ── horario ────────────────────────────────────────────────
  perform generar_horario(current_date, current_date + 13);

  select count(*) into v_n from clases;
  if v_n = 0 then raise exception 'generar_horario no creo ninguna clase'; end if;

  -- Domingo no se trabaja.
  if exists (select 1 from clases where extract(dow from fecha_hora at time zone 'America/Bogota') = 0) then
    raise exception 'se generaron clases en domingo';
  end if;

  -- Entre semana: 7am, 6pm y 7pm. Sabado: 8am y 9am.
  if exists (
    select 1 from clases
    where extract(dow from fecha_hora at time zone 'America/Bogota') between 1 and 5
      and extract(hour from fecha_hora at time zone 'America/Bogota') not in (7, 18, 19)
  ) then raise exception 'hay una clase entre semana fuera de 7am/6pm/7pm'; end if;

  if exists (
    select 1 from clases
    where extract(dow from fecha_hora at time zone 'America/Bogota') = 6
      and extract(hour from fecha_hora at time zone 'America/Bogota') not in (8, 9)
  ) then raise exception 'hay una clase el sabado fuera de 8am/9am'; end if;

  raise notice 'horario: % clases en 14 dias', v_n;

  -- ── membresias ─────────────────────────────────────────────
  -- 25 personas con plan de 6pm, 1 de 7pm, 1 con plan ya vencido.
  -- Ojo: solo clases FUTURAS. recalcular_cupos no toca las que ya
  -- pasaron, asi que si se escoge el dia de hoy despues de la ultima
  -- clase, activos_plan sigue en 0 y la prueba falla por la hora a la
  -- que se corrio, no por un error de verdad.
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

  select importar_membresias((
    select jsonb_agg(f) from (
      select jsonb_build_object(
        'afiliado', 'Socia Numero ' || g,
        'membresia', 'Plan 6:00 p.m.',
        'hora', '18:00:00',
        'tipo', 'plan',
        'documento', (1000000 + g)::text,
        'celular', '300' || lpad(g::text, 7, '0'),
        'correo', null,
        'inicio', (current_date - 5)::text,
        'fin', (current_date + 25)::text
      ) as f from generate_series(1, 25) g
      union all
      select jsonb_build_object(
        'afiliado', 'Alba Camacho', 'membresia', 'Plan 7:00 p.m.', 'hora', '19:00:00',
        'tipo', 'plan', 'documento', '2000001', 'celular', '3009999991', 'correo', null,
        'inicio', (current_date - 5)::text, 'fin', (current_date + 25)::text)
      union all
      -- Vencida hace una semana: no debe contar para los cupos.
      select jsonb_build_object(
        'afiliado', 'Ya No Viene', 'membresia', 'Plan 6:00 p.m.', 'hora', '18:00:00',
        'tipo', 'plan', 'documento', '2000002', 'celular', '3009999992', 'correo', null,
        'inicio', (current_date - 40)::text, 'fin', (current_date - 7)::text)
    ) s
  )) into v_r;

  if (v_r->>'ok')::boolean is not true then
    raise exception 'importar_membresias fallo: %', v_r;
  end if;
  raise notice 'membresias: %', v_r;

  -- El archivo vacio no puede borrar el listado.
  select importar_membresias('[]'::jsonb) into v_r;
  if (v_r->>'ok')::boolean is not false or (v_r->>'error') <> 'archivo_vacio' then
    raise exception 'un archivo vacio deberia rechazarse, devolvio: %', v_r;
  end if;
  select count(*) into v_n from membresias;
  if v_n = 0 then raise exception 'el archivo vacio borro las membresias'; end if;

  -- ── cupos ──────────────────────────────────────────────────
  perform recalcular_cupos();

  select id, cupo_total, activos_plan into v_clase_lun18, v_cupos, v_activos
    from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_lun
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 18;

  -- Aforo 30, 25 con plan activo (la vencida no cuenta) -> 5 sueltas.
  if v_activos <> 25 then raise exception 'activos a las 6pm: se esperaban 25, hay %', v_activos; end if;
  if v_cupos <> 5 then raise exception 'cupos sueltos a las 6pm: se esperaban 5, hay %', v_cupos; end if;
  raise notice 'cupos 6pm: % activos -> % sueltas', v_activos, v_cupos;

  select id into v_clase_lun19 from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_lun
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 19;
  select id into v_clase_sab from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_sab
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 8;

  -- ── clase suelta ───────────────────────────────────────────
  select tomar_cupo(v_clase_lun18, 'Camila Rojas', '3002223344', null, 'web', 'suelta') into v_r;
  if (v_r->>'ok')::boolean is not true then raise exception 'la clase suelta no entro: %', v_r; end if;
  if (v_r->>'estado') <> 'pendiente_pago' then
    raise exception 'la suelta deberia quedar pendiente_pago, quedo en %', v_r->>'estado';
  end if;
  raise notice 'suelta: codigo % estado %', v_r->>'codigo', v_r->>'estado';

  -- Un cupo consumido, ni mas ni menos. Esto es justo lo que fallaba
  -- cuando tomar_cupo devolvia un compuesto: una llamada gastaba 16.
  select cupo_tomado into v_n from clases where id = v_clase_lun18;
  if v_n <> 1 then raise exception 'una reserva deberia gastar 1 cupo, gasto %', v_n; end if;

  -- ── miembro ────────────────────────────────────────────────
  -- Entre semana en su propia hora: su plan ya lo cubre.
  select tomar_cupo(v_clase_lun19, 'Alba Camacho', '3009999991', null, 'web', 'miembro') into v_r;
  if (v_r->>'ok')::boolean is not false or (v_r->>'error') <> 'PLAN_YA_CUBRE' then
    raise exception 'entre semana en su hora deberia decir PLAN_YA_CUBRE, dijo: %', v_r;
  end if;

  -- Entre semana en otra hora: eso es clase suelta.
  select tomar_cupo(v_clase_lun18, 'Alba Camacho', '3009999991', null, 'web', 'miembro') into v_r;
  if (v_r->>'ok')::boolean is not false or (v_r->>'error') <> 'OTRO_HORARIO' then
    raise exception 'entre semana en otra hora deberia decir OTRO_HORARIO, dijo: %', v_r;
  end if;

  -- Sabado: reserva sin pagar.
  select tomar_cupo(v_clase_sab, 'Alba Camacho', '3009999991', null, 'web', 'miembro') into v_r;
  if (v_r->>'ok')::boolean is not true then raise exception 'el sabado del miembro no entro: %', v_r; end if;
  if (v_r->>'estado') <> 'confirmada' then
    raise exception 'el miembro deberia quedar confirmada, quedo en %', v_r->>'estado';
  end if;
  raise notice 'miembro sabado: codigo % estado %', v_r->>'codigo', v_r->>'estado';

  -- Quien no tiene mensualidad no entra gratis.
  select tomar_cupo(v_clase_sab, 'Coladito', '3001112233', null, 'web', 'miembro') into v_r;
  if (v_r->>'ok')::boolean is not false or (v_r->>'error') <> 'MEMBRESIA_NO_ENCONTRADA' then
    raise exception 'un no-miembro deberia rebotar, devolvio: %', v_r;
  end if;

  -- La membresia vencida tampoco.
  select tomar_cupo(v_clase_sab, 'Ya No Viene', '3009999992', null, 'web', 'miembro') into v_r;
  if (v_r->>'ok')::boolean is not false then
    raise exception 'una membresia vencida no deberia servir, devolvio: %', v_r;
  end if;

  raise notice 'OK: horario, membresias, cupos, suelta y miembro';
end $$;

-- ── conciliacion por nombre ──────────────────────────────────
do $$
declare
  v_clase uuid;
  v_a jsonb; v_b jsonb;
  v_r jsonb;
  v_estado text;
begin
  select id into v_clase from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') between 1 and 5
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 7
   order by fecha_hora limit 1;

  -- Dos personas esperando el mismo valor: solo el nombre las distingue.
  select tomar_cupo(v_clase, 'Maria Fernanda Gomez', '3005550001', null, 'web', 'suelta') into v_a;
  select tomar_cupo(v_clase, 'Juan Pablo Restrepo',  '3005550002', null, 'web', 'suelta') into v_b;

  -- Las dos dicen "ya pague". Ese paso no vive en SQL: lo hace el nodo
  -- "Supabase: pasa a verificando" con un PATCH de PostgREST. Aqui se
  -- imita, porque la conciliacion solo mira las que ya estan esperando.
  update reservas set estado = 'verificando', updated_at = now()
   where codigo in (v_a->>'codigo', v_b->>'codigo') and estado = 'pendiente_pago';

  select registrar_pago_y_conciliar(
    'Bancolombia', 15000, now(), 'REF-001', 'JUAN PABLO RESTREPO', null, 1.0, null, null) into v_r;

  select estado::text into v_estado from reservas where codigo = v_b->>'codigo';
  if v_estado <> 'confirmada' then
    raise exception 'el pago de Juan Pablo debio confirmar su reserva, quedo en % (%)', v_estado, v_r;
  end if;
  select estado::text into v_estado from reservas where codigo = v_a->>'codigo';
  if v_estado = 'confirmada' then
    raise exception 'se confirmo la reserva equivocada: el nombre no coincidia';
  end if;
  raise notice 'conciliacion por nombre: OK';

  -- El mismo correo dos veces no puede pagar dos reservas.
  select registrar_pago_y_conciliar(
    'Bancolombia', 15000, now(), 'REF-001', 'JUAN PABLO RESTREPO', null, 1.0, null, null) into v_r;
  select estado::text into v_estado from reservas where codigo = v_a->>'codigo';
  if v_estado = 'confirmada' then
    raise exception 'un correo repetido confirmo una segunda reserva';
  end if;
  raise notice 'correo repetido: no confirma de mas';
end $$;

-- ── permisos ─────────────────────────────────────────────────
do $$
declare v_mal text;
begin
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (has_function_privilege('anon', p.oid, 'execute')
       or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_mal is not null then
    raise exception 'estas funciones quedaron abiertas a la llave publica: %', v_mal;
  end if;
  raise notice 'permisos: ninguna funcion ejecutable con la llave anon';
end $$;

select 'TODO EN VERDE' as resultado;
