-- Prueba del histórico de membresías (0012).
--
--   psql -d tumbao -f pruebas/humo-historico.sql
--
-- Lo que importa aquí no es que la tabla exista, sino que la foto se
-- tome sola en cada importación, que reimportar el mismo día no la
-- duplique, y que borrar `membresias` no se lleve el pasado por delante.

\set ON_ERROR_STOP on
set timezone = 'America/Bogota';

do $$
declare
  v_r    jsonb;
  v_n    int;
  v_hoy  date := current_date;
  v_filas jsonb;
begin
  delete from membresias_historico where true;
  delete from membresias where true;

  -- ── una importación normal ─────────────────────────────────
  select jsonb_agg(f) into v_filas from (
    select jsonb_build_object(
      'afiliado', 'Socia ' || g, 'membresia', 'PLAN MENSUALIDAD 6:00PM',
      'hora', '18:00:00', 'tipo', 'plan',
      'documento', (900000 + g)::text, 'celular', '300' || lpad(g::text, 7, '0'),
      'correo', null,
      'inicio', (current_date - 5)::text, 'fin', (current_date + 25)::text) as f
    from generate_series(1, 10) g
    union all
    select jsonb_build_object(
      'afiliado', 'Media Socia', 'membresia', 'MEDIA MENSUALIDAD 7:00AM',
      'hora', '07:00:00', 'tipo', 'media',
      'documento', '999001', 'celular', '3009990001', 'correo', null,
      'inicio', (current_date - 5)::text, 'fin', (current_date + 25)::text) as f
  ) s;

  select importar_membresias(v_filas) into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'la importacion fallo: %', v_r;
  end if;

  select count(*) into v_n from membresias_historico where fecha_foto = v_hoy;
  if v_n <> 11 then raise exception 'la foto deberia tener 11 filas, tiene %', v_n; end if;
  if (v_r->'foto_del_dia'->>'filas')::int <> 11 then
    raise exception 'la respuesta dice % filas de foto', v_r->'foto_del_dia'->>'filas';
  end if;
  raise notice 'foto del dia: 11 filas, y la funcion lo reporta';

  -- ── reimportar el mismo día no duplica ─────────────────────
  select importar_membresias(v_filas) into v_r;
  select count(*) into v_n from membresias_historico where fecha_foto = v_hoy;
  if v_n <> 11 then
    raise exception 'reimportar duplico la foto: quedaron % filas', v_n;
  end if;
  raise notice 'reimportar el mismo dia: sigue habiendo 11, no 22';

  -- ── el pasado no se toca ───────────────────────────────────
  -- Se finge que ayer habia 20 personas a las 6pm.
  insert into membresias_historico
    (fecha_foto, afiliado, membresia, hora, tipo, documento, celular, inicio, fin)
  select v_hoy - 1, 'Socia Vieja ' || g, 'PLAN MENSUALIDAD 6:00PM', '18:00:00',
         'plan', (800000 + g)::text, null, v_hoy - 30, v_hoy - 1
    from generate_series(1, 20) g;

  -- Una importación de hoy con menos gente.
  select jsonb_agg(f) into v_filas from (
    select jsonb_build_object(
      'afiliado', 'Socia ' || g, 'membresia', 'PLAN MENSUALIDAD 6:00PM',
      'hora', '18:00:00', 'tipo', 'plan',
      'documento', (900000 + g)::text, 'celular', null, 'correo', null,
      'inicio', (current_date - 5)::text, 'fin', (current_date + 25)::text) as f
    from generate_series(1, 3) g
  ) s;
  perform importar_membresias(v_filas);

  select count(*) into v_n from membresias_historico where fecha_foto = v_hoy - 1;
  if v_n <> 20 then
    raise exception 'la importacion de hoy se llevo el historico de ayer: quedaron %', v_n;
  end if;
  select count(*) into v_n from membresias where true;
  if v_n <> 3 then raise exception 'membresias deberia tener 3, tiene %', v_n; end if;
  raise notice 'el pasado sigue intacto: ayer 20, hoy 3';

  -- ── un archivo vacío no borra nada, tampoco la foto ────────
  select importar_membresias('[]'::jsonb) into v_r;
  if (v_r->>'error') <> 'archivo_vacio' then
    raise exception 'el archivo vacio no reboto: %', v_r;
  end if;
  select count(*) into v_n from membresias_historico;
  if v_n <> 23 then
    raise exception 'un archivo vacio toco el historico: quedaron % filas', v_n;
  end if;
  raise notice 'archivo vacio: no toca ni membresias ni el historico';

  -- ── el mismo nombre dos veces en el reporte ────────────────
  -- Los nombres vienen escritos a mano; los duplicados pasan.
  select importar_membresias(jsonb_build_array(
    jsonb_build_object('afiliado','Repetida','membresia','PLAN MENSUALIDAD 6:00PM',
      'hora','18:00:00','tipo','plan','documento','1','celular',null,'correo',null,
      'inicio',(current_date-5)::text,'fin',(current_date+25)::text),
    jsonb_build_object('afiliado','Repetida','membresia','PLAN MENSUALIDAD 6:00PM',
      'hora','18:00:00','tipo','plan','documento','1','celular',null,'correo',null,
      'inicio',(current_date-5)::text,'fin',(current_date+25)::text)
  )) into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'un duplicado tumbo la importacion: %', v_r;
  end if;
  select count(*) into v_n from membresias_historico where fecha_foto = v_hoy;
  if v_n <> 1 then raise exception 'el duplicado quedo dos veces en la foto: %', v_n; end if;
  raise notice 'nombre repetido en el reporte: entra una sola vez a la foto';
end $$;

-- ── las vistas ────────────────────────────────────────────────
do $$
declare v_n int;
begin
  delete from membresias where true;
  insert into membresias (afiliado, membresia, hora, tipo, documento, celular, inicio, fin)
  values ('Vence Manana', 'PLAN MENSUALIDAD 6:00PM', '18:00', 'plan', '1', '3001', current_date - 20, current_date + 1),
         ('Vence En 6',   'PLAN MENSUALIDAD 7:00AM', '07:00', 'plan', '2', '3002', current_date - 20, current_date + 6),
         ('Vence En 30',  'PLAN MENSUALIDAD 7:00PM', '19:00', 'plan', '3', '3003', current_date - 20, current_date + 30),
         ('Ya Vencio',    'PLAN MENSUALIDAD 6:00PM', '18:00', 'plan', '4', '3004', current_date - 40, current_date - 2);

  select count(*) into v_n from proximos_vencimientos;
  if v_n <> 2 then
    raise exception 'proximos_vencimientos deberia traer 2 (manana y en 6 dias), trajo %', v_n;
  end if;
  if not exists (select 1 from proximos_vencimientos
                  where afiliado = 'Vence Manana' and dias_restantes = 1) then
    raise exception 'no calculo bien los dias restantes';
  end if;
  raise notice 'proximos_vencimientos: 2 de 4, con los dias bien';

  select count(*) into v_n from activos_por_dia;
  if v_n = 0 then raise exception 'activos_por_dia salio vacia'; end if;
  raise notice 'activos_por_dia: % filas', v_n;
end $$;

select 'TODO EN VERDE' as resultado;
