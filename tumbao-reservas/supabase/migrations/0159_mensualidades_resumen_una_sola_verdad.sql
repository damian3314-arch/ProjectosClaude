-- 0159 · Mensualidades: UNA sola fuente de cifras para el asistente, el informe y la página
--
-- Damián (8 oct): le preguntó al bot por WhatsApp «¿cuántos activos en mensualidad hay?» y respondió «58 personas»;
-- «¿en cada horario?» → 26 / 20 / 23 con «Total: 58» (la suma real es 69); y en la página decía otra cosa.
-- Había tres cuentas distintas en circulación y el modelo las mezcló:
--   · el informe diario cuenta FILAS de membresías (una renovación vigente deja dos filas de la misma persona): 58;
--   · la página cuenta PERSONAS que ocupan cupo, incluidos los días de gracia (hoy 5): 26 / 20 / 23 = 69;
--   · el modelo sumó a mano y puso un total que no era.
--
-- mensualidades_resumen(dia) deja todo calculado y rotulado, por persona (no por fila):
--   vigentes   personas con plan al día (inicio <= dia <= fin);
--   en_gracia  vencieron hace días <= mensualidad_gracia_dias y se les guarda el cupo;
--   ocupan_cupo lo que cuenta la página (vigentes + en gracia, más lo apartado o por procesar de hoy);
--   tope, libres (solo hoy): lo que la página puede vender.
-- y los totales sumados en SQL (nadie suma a mano). El informe diario (tablero_tumbao) usa personas y trae este resumen.

create or replace function public.mensualidades_resumen(p_dia date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  d date := coalesce(p_dia, (now() at time zone 'America/Bogota')::date);
  hoy date := (now() at time zone 'America/Bogota')::date;
  v_gracia int := coalesce(nullif((select valor from ajustes where clave = 'mensualidad_gracia_dias'), '')::int, 3);
  v_horas jsonb; v_pagina jsonb := mensualidad_cupos() -> 'horas';
begin
  select coalesce(jsonb_agg(x order by x ->> 'hora'), '[]'::jsonb) into v_horas
  from (
    select jsonb_build_object(
      'hora', to_char(h.hora, 'HH24:MI'),
      'etiqueta', ltrim(to_char(h.hora, 'HH12:MI am'), '0'),
      'vigentes', v.n,
      'en_gracia', o.n - v.n,
      'ocupan_cupo', case when d = hoy then coalesce((select (e ->> 'ocupadas')::int from jsonb_array_elements(v_pagina) e where e ->> 'hora' = to_char(h.hora, 'HH24:MI')), o.n) else o.n end,
      'tope_pagina', case when d = hoy then (select (e ->> 'tope')::int from jsonb_array_elements(v_pagina) e where e ->> 'hora' = to_char(h.hora, 'HH24:MI')) end,
      'libres_pagina', case when d = hoy then (select (e ->> 'libres')::int from jsonb_array_elements(v_pagina) e where e ->> 'hora' = to_char(h.hora, 'HH24:MI')) end,
      'en_lista_de_espera', case when d = hoy then (select (e ->> 'en_espera')::int from jsonb_array_elements(v_pagina) e where e ->> 'hora' = to_char(h.hora, 'HH24:MI')) end
    ) x
    from (select btrim(z)::time hora from unnest(string_to_array(coalesce((select valor from ajustes where clave = 'mensualidad_horas'), '07:00,18:00,19:00'), ',')) z) h
    cross join lateral (select count(distinct coalesce(nullif(right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10), ''), m.id::text)) n
                          from membresias m where m.hora = h.hora and d between m.inicio and m.fin) v
    cross join lateral (select count(distinct coalesce(nullif(right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10), ''), m.id::text)) n
                          from membresias m where m.hora = h.hora and d between m.inicio and m.fin + v_gracia) o
  ) q;

  return jsonb_build_object(
    'dia', d,
    'dias_de_gracia', v_gracia,
    'por_horario', v_horas,
    'total_vigentes', (select coalesce(sum((x ->> 'vigentes')::int), 0) from jsonb_array_elements(v_horas) x),
    'total_en_gracia', (select coalesce(sum((x ->> 'en_gracia')::int), 0) from jsonb_array_elements(v_horas) x),
    'total_ocupan_cupo', (select coalesce(sum((x ->> 'ocupan_cupo')::int), 0) from jsonb_array_elements(v_horas) x),
    'que_significa', jsonb_build_object(
      'vigentes', 'Personas con la mensualidad al día hoy (una persona cuenta una vez por horario, aunque tenga dos filas por una renovación).',
      'en_gracia', 'Personas cuya mensualidad venció hace ' || v_gracia || ' días o menos y a quienes se les guarda el cupo mientras renuevan.',
      'ocupan_cupo', 'Vigentes + en gracia (+ lo apartado o por procesar hoy): es el número que cuenta la página contra el tope.',
      'libres_pagina', 'Cupos que la página puede vender hoy: tope de la página menos los que ocupan cupo.'));
end;
$$;
revoke all on function public.mensualidades_resumen(date) from public, anon, authenticated;

-- El informe diario deja de contar filas: personas, y trae el resumen completo.
do $mig$
declare v_def text; v_nuevo text;
begin
  v_def := pg_get_functiondef('public.tablero_tumbao(text)'::regprocedure);
  if position('mensualidades_resumen' in v_def) > 0 then return; end if;
  if position('''vigentes'', (select count(*) from membresias where fin >= d and inicio <= d),' in v_def) = 0 then
    raise exception 'tablero_tumbao: no encuentro el conteo de vigentes';
  end if;
  v_nuevo := replace(v_def, '''vigentes'', (select count(*) from membresias where fin >= d and inicio <= d),',
    $r$'vigentes', (select count(distinct coalesce(nullif(right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10), ''), id::text)) from membresias where fin >= d and inicio <= d),
    'resumen_exacto', mensualidades_resumen(d),$r$);
  v_nuevo := regexp_replace(v_nuevo,
    'count\(\*\) n from membresias(\s+)where fin >= d and inicio <= d group by 1',
    $r$count(distinct coalesce(nullif(right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10), ''), id::text)) n from membresias\1where fin >= d and inicio <= d group by 1$r$);
  if v_nuevo = v_def or position('count(distinct' in substr(v_nuevo, position('vigentes_por_hora' in v_nuevo), 400)) = 0 then
    raise exception 'tablero_tumbao: no pude cambiar vigentes_por_hora';
  end if;
  execute v_nuevo;
end
$mig$;
