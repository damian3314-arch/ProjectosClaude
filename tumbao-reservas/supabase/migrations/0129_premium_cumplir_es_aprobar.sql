-- 0129 · Premium: cumplir los requisitos ES la aprobación; identificar bien a la persona
--
-- Damián (30 sep): «yo no soy aprobador. La aprobación es que la persona cumpla
-- con los requisitos; de esa manera se le puede recibir y registrar en el
-- sistema para que asista en mensualidad en el horario que escoja». Y: «un
-- usuario se puede llamar igual a otro, o no tenemos el nombre completo: hace
-- falta el número de cédula o el celular para identificar bien al cliente».
--
-- Qué cambia respecto de 0127/0128
--   · Se acaba la aprobación y el puesto: premium_evaluar() contesta
--       aplica      → cumple los requisitos (plan 4 meses seguidos, o más de 90
--                     días en clase suelta): recepción puede venderle y
--                     registrarla en AdminGym en el horario que elija, si ese
--                     horario tiene cupo;
--       no_aplica   → no cumple: qué le falta;
--       sin_historial.
--   · Identificación: acepta celular, cédula o nombre y dice POR QUÉ la encontró.
--     Por nombre puede haber varias: el asistente pide celular o cédula.
--   · Cupos por horario = planes (y medias) vigentes hoy contra el tope de 25
--     (premium_cupo_max) en 7 am, 6 pm y 7 pm.
--   · premium_vigentes(): quiénes tienen plan hoy y si cumplirían al renovar.
--   · La cédula (afiliados_historial.documento) se carga aparte, como los demás
--     datos: nada de personas en el repositorio.
--   · premium_grupo, premium_ranking() y premium_decidir() de las migraciones
--     anteriores quedan sin uso (el asistente ya no aprueba a nadie).

alter table afiliados_historial add column if not exists documento text;
create index if not exists afiliados_historial_documento_idx on afiliados_historial (documento);

-- Las membresías de una persona: por celular, o por cédula cuando AdminGym no
-- guardó el celular.
create or replace function public.premium_membresias(p_tel text)
returns setof membresias
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select m.* from membresias m
   where right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10) = p_tel
      or (regexp_replace(coalesce(m.documento, ''), '\D', '', 'g') <> ''
          and regexp_replace(coalesce(m.documento, ''), '\D', '', 'g') =
              (select regexp_replace(h.documento, '\D', '', 'g') from afiliados_historial h where h.telefono = p_tel))
$$;

create or replace function public.premium_meses(p_tel text)
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(array_agg(distinct m order by m), '{}'::text[]) from (
    select unnest(meses) m from afiliados_historial where telefono = p_tel
    union
    select to_char(x.inicio + (g || ' months')::interval, 'YYYY-MM')
      from premium_membresias(p_tel) x,
           generate_series(0, greatest(1, round((x.fin - x.inicio + 1) / 30.0)::int) - 1) g
  ) z
$$;

-- Quién es quién: por celular, por cédula o por las palabras del nombre.
create or replace function public.premium_identificar(p_buscar text)
returns table (tel text, nombre text, por text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with q as (
    select norm_nombre(coalesce(p_buscar, '')) txt,
           regexp_replace(coalesce(p_buscar, ''), '\D', '', 'g') dig
  ),
  personas as (
    select telefono t, nombre from afiliados_historial
    union all
    select right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10), afiliado from membresias
    union all
    select right(regexp_replace(coalesce(telefono, ''), '\D', '', 'g'), 10), nombre
      from reservas where estado = 'confirmada' and created_at > now() - interval '180 days'
  ),
  agrupadas as (
    select t, (array_agg(nombre order by length(nombre) desc))[1] mejor, array_agg(distinct nombre) nombres
      from personas where t ~ '^3[0-9]{9}$' group by t
  ),
  por_celular as (
    select a.t, a.mejor, 'celular'::text por from agrupadas a, q
     where length(q.dig) >= 10 and a.t = right(q.dig, 10)
  ),
  por_documento as (
    select a.t, a.mejor, 'documento'::text por from agrupadas a, q
     where length(q.dig) between 5 and 11
       and (exists (select 1 from afiliados_historial h where h.telefono = a.t and regexp_replace(coalesce(h.documento, ''), '\D', '', 'g') = q.dig)
            or exists (select 1 from membresias m
                        where right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10) = a.t
                          and regexp_replace(coalesce(m.documento, ''), '\D', '', 'g') = q.dig))
  ),
  por_nombre as (
    select a.t, a.mejor, 'nombre'::text por from agrupadas a, q
     where q.dig = '' and btrim(q.txt) <> ''
       and not exists (
         select 1 from unnest(string_to_array(btrim(q.txt), ' ')) w
          where w <> '' and not exists (
            select 1 from unnest(a.nombres) n where norm_nombre(n) like '%' || w || '%'))
  )
  select t, initcap(mejor), por from (
    select * from por_celular
    union all select * from por_documento where not exists (select 1 from por_celular)
    union all select * from por_nombre) z
  order by mejor
  limit 8
$$;

-- Cupos de mensualidad por horario: lo que hay vigente hoy contra el tope.
create or replace function public.premium_cupos_horario()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with cfg as (
    select coalesce((select valor from ajustes where clave = 'premium_cupo_max'), '25')::int tope,
           coalesce((select valor from ajustes where clave = 'premium_cupo_min'), '20')::int minimo,
           (select (now() at time zone 'America/Bogota')::date) hoy),
  horas as (
    select btrim(h) hr
      from unnest(string_to_array(coalesce((select valor from ajustes where clave = 'mensualidad_horas'), '07:00,18:00,19:00'), ',')) h
  )
  select coalesce(jsonb_object_agg(hr, jsonb_build_object(
           'tope', c.tope,
           'ocupados_hoy', (select count(*) from membresias m where m.fin >= c.hoy and to_char(m.hora, 'HH24:MI') = hr),
           'libres', greatest(c.tope - (select count(*) from membresias m where m.fin >= c.hoy and to_char(m.hora, 'HH24:MI') = hr), 0),
           'minimo_buscado', c.minimo)),
         '{}'::jsonb)
    from horas, cfg c
$$;

-- «¿Camila aplica para mensualidad?»
create or replace function public.premium_evaluar(p_buscar text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  hoy date := (now() at time zone 'America/Bogota')::date;
  v_min_meses int    := coalesce((select valor from ajustes where clave = 'premium_min_meses'), '4')::int;
  v_dias      int    := coalesce((select valor from ajustes where clave = 'premium_suelta_dias'), '90')::int;
  v_visitas   int    := coalesce((select valor from ajustes where clave = 'premium_suelta_visitas'), '8')::int;
  v_semanas   int    := coalesce((select valor from ajustes where clave = 'premium_suelta_semanas'), '6')::int;
  v_mes_ref   int    := extract(year from hoy)::int * 12 + extract(month from hoy)::int;
  v_lista jsonb := '[]'::jsonb;
  v_por text;
  r record;
  v_meses text[]; v_racha int; v_ultimo text; v_ult_idx int;
  v_hist afiliados_historial%rowtype;
  v_on_n int; v_on_pri date; v_on_ult date; v_on_sem int;
  v_n int; v_pri date; v_ult date; v_sem int; v_span int;
  v_vig record;
  v_planes boolean; v_suelta boolean; v_ver text; v_razon text;
begin
  for r in select * from premium_identificar(p_buscar) loop
    v_por := r.por;
    v_meses := premium_meses(r.tel);
    v_racha := premium_racha(v_meses);
    select max(m) into v_ultimo from unnest(v_meses) m;
    v_ult_idx := case when v_ultimo is null then null
                      else substr(v_ultimo, 1, 4)::int * 12 + substr(v_ultimo, 6, 2)::int end;

    select * into v_hist from afiliados_historial where telefono = r.tel;

    select count(*), min((c.fecha_hora at time zone 'America/Bogota')::date),
           max((c.fecha_hora at time zone 'America/Bogota')::date),
           count(distinct date_trunc('week', c.fecha_hora at time zone 'America/Bogota'))
      into v_on_n, v_on_pri, v_on_ult, v_on_sem
      from reservas x join clases c on c.id = x.clase_id
     where x.estado = 'confirmada' and x.tipo in ('suelta', 'tiquetera') and c.fecha_hora < now()
       and right(regexp_replace(coalesce(x.telefono, ''), '\D', '', 'g'), 10) = r.tel;

    v_n   := coalesce(v_hist.sueltas_n, 0) + coalesce(v_on_n, 0);
    v_pri := least(v_hist.sueltas_primera, v_on_pri);
    v_ult := greatest(v_hist.sueltas_ultima, v_on_ult);
    v_sem := coalesce(v_hist.sueltas_semanas, 0) + coalesce(v_on_sem, 0);
    v_span := case when v_pri is null then 0 else hoy - v_pri end;

    select hora, fin into v_vig from premium_membresias(r.tel) where fin >= hoy order by fin desc limit 1;

    v_planes := v_racha >= v_min_meses and v_ult_idx is not null and v_ult_idx >= v_mes_ref - 1;
    v_suelta := v_n >= v_visitas and v_sem >= v_semanas and v_span >= v_dias
                and v_ult is not null and v_ult >= hoy - 21;

    if v_planes then
      v_ver := 'aplica';
      v_razon := v_racha || ' meses seguidos pagando plan (se piden ' || v_min_meses || ').';
    elsif v_suelta then
      v_ver := 'aplica';
      v_razon := 'Clase suelta constante: ' || v_n || ' visitas en ' || v_sem || ' semanas durante ' || v_span || ' días.';
    elsif cardinality(v_meses) > 0 and v_racha >= v_min_meses then
      v_ver := 'no_aplica'; v_razon := 'Tuvo ' || v_racha || ' meses seguidos, pero hace más de un mes que no paga plan.';
    elsif cardinality(v_meses) > 0 then
      v_ver := 'no_aplica';
      v_razon := 'Lleva ' || v_racha || ' mes(es) seguidos pagando plan y se piden ' || v_min_meses
                 || ' (en total ha pagado ' || cardinality(v_meses) || ' mes(es)).'
                 || case when v_ult_idx < v_mes_ref - 1 then ' Además no pagó plan en el último mes.' else '' end;
    elsif v_n > 0 then
      v_ver := 'no_aplica';
      v_razon := 'Solo se conocen ' || v_n || ' clases sueltas en ' || v_sem || ' semanas y ' || v_span
                 || ' días de historia; se piden al menos ' || v_visitas || ' visitas, ' || v_semanas || ' semanas y más de ' || v_dias || ' días.';
    else
      v_ver := 'sin_historial'; v_razon := 'No aparece historial de pagos ni de clases con ese dato.';
    end if;

    v_lista := v_lista || jsonb_build_object(
      'nombre', r.nombre,
      'celular_termina_en', right(r.tel, 4),
      'encontrada_por', r.por,
      'veredicto', v_ver,
      'razon', v_razon,
      'plan_vigente', case when v_vig.fin is null then null
                           else jsonb_build_object('horario', to_char(v_vig.hora, 'HH24:MI'), 'hasta', v_vig.fin) end,
      'horario_habitual', coalesce(to_char(v_vig.hora, 'HH24:MI'), v_hist.hora),
      'meses_seguidos_pagando_plan', v_racha,
      'meses_con_plan_en_total', cardinality(v_meses),
      'ultimo_mes_con_plan', v_ultimo,
      'clases_sueltas', jsonb_build_object('visitas', v_n, 'semanas', v_sem,
                                           'primera', v_pri, 'ultima', v_ult, 'dias_de_historia', v_span));
  end loop;

  return jsonb_build_object(
    'ok', true,
    'buscado', p_buscar,
    'encontradas', jsonb_array_length(v_lista),
    -- por nombre hay que confirmar que es la persona correcta (nombres repetidos o incompletos)
    'confirmar_identidad', coalesce(v_por = 'nombre', false),
    'cupos_por_horario', premium_cupos_horario(),
    'vigente_hasta', (select valor from ajustes where clave = 'premium_vigente_hasta'),
    'regla', jsonb_build_object('meses_seguidos_plan', v_min_meses, 'suelta_dias', v_dias,
                                'suelta_visitas', v_visitas, 'suelta_semanas', v_semanas),
    'personas', v_lista);
end;
$$;

-- Quiénes tienen plan hoy y si cumplirían los requisitos al renovar.
create or replace function public.premium_vigentes()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  hoy date := (now() at time zone 'America/Bogota')::date;
  v_lista jsonb := '[]'::jsonb;
  r record;
  v_ev jsonb; v_p jsonb;
begin
  for r in
    select distinct on (coalesce(nullif(right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10), ''),
                                 regexp_replace(coalesce(m.documento, ''), '\D', '', 'g')))
           initcap(m.afiliado) nombre, m.hora, m.fin, m.tipo,
           coalesce(nullif(right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10), ''),
                    (select h.telefono from afiliados_historial h
                      where regexp_replace(coalesce(h.documento, ''), '\D', '', 'g') = regexp_replace(coalesce(m.documento, ''), '\D', '', 'g')
                        and regexp_replace(coalesce(m.documento, ''), '\D', '', 'g') <> '' limit 1)) tel
      from membresias m
     where m.fin >= hoy
     order by coalesce(nullif(right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10), ''),
                       regexp_replace(coalesce(m.documento, ''), '\D', '', 'g')), m.fin desc
  loop
    if r.tel is null then
      v_lista := v_lista || jsonb_build_object('nombre', r.nombre, 'horario', to_char(r.hora, 'HH24:MI'), 'vence', r.fin,
                                               'cumple', null, 'razon', 'Sin celular en AdminGym: no se puede cruzar con su historial.');
    else
      v_ev := premium_evaluar(r.tel);
      v_p := v_ev -> 'personas' -> 0;
      v_lista := v_lista || jsonb_build_object(
        'nombre', r.nombre, 'celular_termina_en', right(r.tel, 4),
        'horario', to_char(r.hora, 'HH24:MI'), 'vence', r.fin, 'tipo', r.tipo,
        'cumple', coalesce(v_p ->> 'veredicto' = 'aplica', false),
        'meses_seguidos', (v_p ->> 'meses_seguidos_pagando_plan')::int,
        'razon', v_p ->> 'razon');
    end if;
  end loop;
  return jsonb_build_object(
    'ok', true,
    'total', jsonb_array_length(v_lista),
    'cumplen', (select count(*) from jsonb_array_elements(v_lista) x where (x ->> 'cumple') = 'true'),
    'no_cumplen', (select count(*) from jsonb_array_elements(v_lista) x where (x ->> 'cumple') = 'false'),
    'sin_celular', (select count(*) from jsonb_array_elements(v_lista) x where (x ->> 'cumple') is null),
    'personas', (select coalesce(jsonb_agg(x order by x ->> 'vence', x ->> 'nombre'), '[]'::jsonb) from jsonb_array_elements(v_lista) x));
end;
$$;

-- Resumen: cupos por horario y cuántos de los vigentes cumplirían.
create or replace function public.premium_estado()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with v as (select premium_vigentes() j)
  select jsonb_build_object(
    'ok', true,
    'vigente_hasta', (select valor from ajustes where clave = 'premium_vigente_hasta'),
    'cupos_por_horario', premium_cupos_horario(),
    'planes_vigentes_hoy', (v.j ->> 'total')::int,
    'vigentes_que_cumplen', (v.j ->> 'cumplen')::int,
    'vigentes_que_no_cumplen', (v.j ->> 'no_cumplen')::int,
    'vigentes_sin_celular', (v.j ->> 'sin_celular')::int)
    from v
$$;

revoke all on function public.premium_membresias(text), public.premium_identificar(text),
  public.premium_cupos_horario(), public.premium_evaluar(text), public.premium_vigentes(),
  public.premium_estado(), public.premium_meses(text)
  from public, anon, authenticated;
