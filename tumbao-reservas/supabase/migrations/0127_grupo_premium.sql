-- 0127 · Grupo premium: quién puede seguir teniendo mensualidad
--
-- Decisión de Damián (30 sep): el plan de $125.000 es inviable para el negocio,
-- así que la mensualidad queda para un grupo reducido y único de 20 a 25
-- personas («premium»): quienes pagan su plan mes tras mes y quienes llevan
-- más de 90 días viniendo seguido en clase suelta. Con ellas se sostiene la
-- posibilidad de tener mensualidad hasta el 30 de diciembre. Nadie más entra.
--
-- Qué hay aquí
--   · afiliados_historial  lo que dejó el reporte de ventas de AdminGym
--                          (dic 2025 – sep 2026): por persona, en qué meses pagó
--                          plan o media y cuántas clases sueltas conocidas.
--                          Solo nombre, celular y fechas: nada de cédulas.
--                          Los DATOS no viven en el repo (es público): se
--                          cargan aparte, directo en la base.
--   · premium_grupo        quién está propuesta, aprobada o descartada.
--   · premium_evaluar(t)   «¿Camila aplica?»: busca a la persona por nombre o
--                          celular y dice si cumple la regla y por qué.
--   · premium_estado()     cuántos cupos hay, quiénes están y quiénes se proponen.
--   · premium_decidir(...) aprobar o descartar (solo lo llama el bot del dueño,
--                          con confirmación, y nunca pasa del tope).
--   · renovaciones_proximas(n)  quién vence en los próximos n días y si es premium.
--
-- La regla (ajustable en `ajustes`, sin tocar código):
--   A · PLAN SEGUIDO: pagó plan o media N meses seguidos (premium_min_meses = 4)
--       y pagó este mes o el anterior.
--   B · CLASE SUELTA CONSTANTE: más de 90 días (premium_suelta_dias), al menos
--       8 visitas y 6 semanas distintas, y vino en las últimas 3 semanas.
--   La regla es ayuda para decidir: aprueba el dueño, no la función.
--
-- Los meses se cuentan por fecha de venta; un plan que AdminGym extendió (más de
-- 40 días) cuenta como varios meses seguidos.

-- ── ajustes ───────────────────────────────────────────────────────────
insert into ajustes (clave, valor, nota) values
  ('premium_cupo_max', '25', 'Tope de personas en el grupo premium (mensualidad).'),
  ('premium_vigente_hasta', '2026-12-30', 'Hasta cuándo se sostiene la mensualidad del grupo premium.'),
  ('premium_min_meses', '4', 'Regla A: meses seguidos pagando plan.'),
  ('premium_suelta_dias', '90', 'Regla B: días de historia viniendo en clase suelta.'),
  ('premium_suelta_visitas', '8', 'Regla B: visitas mínimas.'),
  ('premium_suelta_semanas', '6', 'Regla B: semanas distintas con visita.')
on conflict (clave) do nothing;

-- ── tablas (sin políticas: solo las funciones de abajo las tocan) ──────
create table if not exists afiliados_historial (
  telefono         text primary key,
  nombre           text not null,
  meses            text[] not null default '{}',   -- 'AAAA-MM' de cada plan/media pagado
  tipos            text not null default '',       -- p = plan, m = media, en orden
  hora             text,                           -- horario usual ('18:00')
  sueltas_n        int  not null default 0,
  sueltas_primera  date,
  sueltas_ultima   date,
  sueltas_semanas  int  not null default 0,
  fuente           text,
  cargado_at       timestamptz not null default now()
);
alter table afiliados_historial enable row level security;

create table if not exists premium_grupo (
  telefono     text primary key,
  nombre       text not null,
  estado       text not null default 'candidata'
               check (estado in ('candidata', 'aprobada', 'descartada')),
  hora         text,
  nota         text,
  propuesta_por text,
  decidido_por text,
  decidido_at  timestamptz,
  created_at   timestamptz not null default now()
);
alter table premium_grupo enable row level security;

-- ── ayudantes ─────────────────────────────────────────────────────────
-- Meses seguidos que terminan en el último mes pagado.
create or replace function public.premium_racha(p_meses text[])
returns int
language plpgsql
immutable
as $$
declare v_idx int[]; v_max int; n int := 0;
begin
  select array_agg(distinct (substr(x, 1, 4)::int * 12 + substr(x, 6, 2)::int))
    into v_idx from unnest(p_meses) x where x ~ '^\d{4}-\d{2}$';
  if v_idx is null then return 0; end if;
  select max(i) into v_max from unnest(v_idx) i;
  while (v_max - n) = any(v_idx) loop n := n + 1; end loop;
  return n;
end;
$$;

-- Meses con plan pagado: el historial del reporte más las membresías de hoy.
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
    select to_char(inicio + (g || ' months')::interval, 'YYYY-MM')
      from membresias,
           generate_series(0, greatest(1, round((fin - inicio + 1) / 30.0)::int) - 1) g
     where right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) = p_tel
  ) z
$$;

-- Quién es quién: por celular (10 dígitos) o por las palabras del nombre.
create or replace function public.premium_personas(p_buscar text)
returns table (tel text, nombre text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with q as (
    select norm_nombre(coalesce(p_buscar, '')) txt,
           case when length(regexp_replace(coalesce(p_buscar, ''), '\D', '', 'g')) >= 10
                then right(regexp_replace(p_buscar, '\D', '', 'g'), 10) end tel
  ),
  personas as (
    select telefono t, nombre from afiliados_historial
    union all
    select right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10), afiliado from membresias
    union all
    select right(regexp_replace(coalesce(telefono, ''), '\D', '', 'g'), 10), nombre
      from reservas where estado = 'confirmada' and created_at > now() - interval '180 days'
    union all
    select telefono, nombre from premium_grupo
  ),
  agrupadas as (
    select t, (array_agg(nombre order by length(nombre) desc))[1] mejor, array_agg(distinct nombre) nombres
      from personas where t ~ '^3[0-9]{9}$' group by t
  )
  select a.t, initcap(a.mejor)
    from agrupadas a, q
   where (q.tel is not null and a.t = q.tel)
      or (q.tel is null and btrim(q.txt) <> ''
          and not exists (
            select 1 from unnest(string_to_array(btrim(q.txt), ' ')) w
             where w <> '' and not exists (
               select 1 from unnest(a.nombres) n where norm_nombre(n) like '%' || w || '%')))
   order by a.mejor
   limit 8
$$;

-- ── «¿Camila aplica?» ─────────────────────────────────────────────────
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
  v_max       int    := coalesce((select valor from ajustes where clave = 'premium_cupo_max'), '25')::int;
  v_aprobadas int    := (select count(*) from premium_grupo where estado = 'aprobada');
  v_mes_ref   int    := extract(year from hoy)::int * 12 + extract(month from hoy)::int;
  v_lista jsonb := '[]'::jsonb;
  r record;
  v_meses text[]; v_racha int; v_ultimo text; v_ult_idx int;
  v_hist afiliados_historial%rowtype;
  v_on_n int; v_on_pri date; v_on_ult date; v_on_sem int;
  v_n int; v_pri date; v_ult date; v_sem int; v_span int;
  v_g premium_grupo%rowtype; v_vig record;
  v_planes boolean; v_suelta boolean; v_ver text; v_razon text;
begin
  for r in select * from premium_personas(p_buscar) loop
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

    select * into v_g from premium_grupo where telefono = r.tel;
    select hora, fin into v_vig from membresias
     where right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) = r.tel and fin >= hoy
     order by fin desc limit 1;

    v_planes := v_racha >= v_min_meses and v_ult_idx is not null and v_ult_idx >= v_mes_ref - 1;
    v_suelta := v_n >= v_visitas and v_sem >= v_semanas and v_span >= v_dias
                and v_ult is not null and v_ult >= hoy - 21;

    if v_g.estado = 'aprobada' then
      v_ver := 'ya_es_premium'; v_razon := 'Ya está aprobada en el grupo premium.';
    elsif v_g.estado = 'descartada' then
      v_ver := 'descartada'; v_razon := 'Se descartó del grupo' || coalesce(': ' || v_g.nota, '.');
    elsif v_planes then
      v_ver := 'cumple'; v_razon := v_racha || ' meses seguidos pagando plan (el mínimo es ' || v_min_meses || ').';
    elsif v_suelta then
      v_ver := 'cumple'; v_razon := 'Clase suelta constante: ' || v_n || ' visitas en ' || v_sem || ' semanas durante ' || v_span || ' días.';
    elsif cardinality(v_meses) > 0 and v_racha >= v_min_meses then
      v_ver := 'no_cumple'; v_razon := 'Tuvo ' || v_racha || ' meses seguidos, pero hace más de un mes que no paga plan.';
    elsif cardinality(v_meses) > 0 then
      v_ver := 'no_cumple'; v_razon := 'Lleva ' || v_racha || ' mes(es) seguidos de plan; el mínimo es ' || v_min_meses
                || ' (en total ha pagado ' || cardinality(v_meses) || ' mes(es)).';
    elsif v_n > 0 then
      v_ver := 'no_cumple'; v_razon := 'Solo se conocen ' || v_n || ' clases sueltas en ' || v_sem || ' semanas y ' || v_span
                || ' días de historia; se piden al menos ' || v_visitas || ' visitas, ' || v_semanas || ' semanas y ' || v_dias || ' días.';
    else
      v_ver := 'sin_historial'; v_razon := 'No aparece historial de pagos ni de clases.';
    end if;

    v_lista := v_lista || jsonb_build_object(
      'nombre', r.nombre,
      'celular_termina_en', right(r.tel, 4),
      'veredicto', v_ver,
      'razon', v_razon,
      'grupo', case when v_g.telefono is null then null
                    else jsonb_build_object('estado', v_g.estado, 'nota', v_g.nota, 'decidido_at', v_g.decidido_at) end,
      'plan_vigente', case when v_vig.fin is null then null
                           else jsonb_build_object('hora', to_char(v_vig.hora, 'HH24:MI'), 'hasta', v_vig.fin) end,
      'horario_usual', coalesce(to_char(v_vig.hora, 'HH24:MI'), v_hist.hora, v_g.hora),
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
    'cupo_premium', jsonb_build_object('tope', v_max, 'aprobadas', v_aprobadas, 'libres', greatest(v_max - v_aprobadas, 0),
                                       'vigente_hasta', (select valor from ajustes where clave = 'premium_vigente_hasta')),
    'regla', jsonb_build_object('meses_seguidos_plan', v_min_meses, 'suelta_dias', v_dias,
                                'suelta_visitas', v_visitas, 'suelta_semanas', v_semanas),
    'personas', v_lista);
end;
$$;

-- ── el grupo completo ─────────────────────────────────────────────────
create or replace function public.premium_estado()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  hoy date := (now() at time zone 'America/Bogota')::date;
  v_max int := coalesce((select valor from ajustes where clave = 'premium_cupo_max'), '25')::int;
  v_apr int := (select count(*) from premium_grupo where estado = 'aprobada');
begin
  return jsonb_build_object(
    'ok', true,
    'tope', v_max, 'aprobadas', v_apr, 'libres', greatest(v_max - v_apr, 0),
    'candidatas', (select count(*) from premium_grupo where estado = 'candidata'),
    'descartadas', (select count(*) from premium_grupo where estado = 'descartada'),
    'vigente_hasta', (select valor from ajustes where clave = 'premium_vigente_hasta'),
    'por_horario_aprobadas', coalesce((
      select jsonb_object_agg(coalesce(hora, 'sin horario'), n) from (
        select hora, count(*) n from premium_grupo where estado = 'aprobada' group by hora) z), '{}'::jsonb),
    'planes_vigentes_por_horario', coalesce((
      select jsonb_object_agg(h, n) from (
        select to_char(hora, 'HH24:MI') h, count(*) n from membresias where fin >= hoy group by 1) z), '{}'::jsonb),
    'personas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'nombre', g.nombre, 'celular_termina_en', right(g.telefono, 4), 'estado', g.estado,
               'horario', g.hora, 'meses_seguidos', premium_racha(premium_meses(g.telefono)), 'nota', g.nota)
             order by case g.estado when 'aprobada' then 0 when 'candidata' then 1 else 2 end,
                      premium_racha(premium_meses(g.telefono)) desc, g.nombre)
        from premium_grupo g), '[]'::jsonb));
end;
$$;

-- ── aprobar o descartar (lo llama el bot del dueño, con confirmación) ──
create or replace function public.premium_decidir(p_buscar text, p_estado text, p_nota text, p_por text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_max int := coalesce((select valor from ajustes where clave = 'premium_cupo_max'), '25')::int;
  v_apr int;
  v_n int;
  v_tel text; v_nom text;
  v_hora text;
  v_ya text;
begin
  if p_estado not in ('aprobada', 'descartada', 'candidata') then
    return jsonb_build_object('ok', false, 'error', 'ESTADO_INVALIDO');
  end if;
  -- Decidir es de Damián (wa_notas_para), no de los otros dos números del
  -- equipo: ellos consultan, él aprueba.
  if not exists (
       select 1 from unnest(string_to_array(coalesce((select valor from ajustes where clave = 'wa_notas_para'), ''), ',')) t
        where right(regexp_replace(t, '\D', '', 'g'), 10) = right(regexp_replace(coalesce(p_por, ''), '\D', '', 'g'), 10)
          and length(regexp_replace(t, '\D', '', 'g')) >= 10) then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select count(*) into v_n from premium_personas(p_buscar);
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'error', 'NO_ENCONTRADA');
  elsif v_n > 1 then
    return jsonb_build_object('ok', false, 'error', 'AMBIGUA',
      'opciones', (select jsonb_agg(jsonb_build_object('nombre', nombre, 'celular_termina_en', right(tel, 4)))
                     from premium_personas(p_buscar)));
  end if;
  select tel, nombre into v_tel, v_nom from premium_personas(p_buscar);

  select estado into v_ya from premium_grupo where telefono = v_tel;
  select count(*) into v_apr from premium_grupo where estado = 'aprobada';
  if p_estado = 'aprobada' and v_ya is distinct from 'aprobada' and v_apr >= v_max then
    return jsonb_build_object('ok', false, 'error', 'SIN_CUPO', 'tope', v_max, 'aprobadas', v_apr);
  end if;

  select coalesce(to_char((select hora from membresias
                            where right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) = v_tel
                            order by fin desc limit 1), 'HH24:MI'),
                  (select hora from afiliados_historial where telefono = v_tel)) into v_hora;

  insert into premium_grupo (telefono, nombre, estado, hora, nota, decidido_por, decidido_at)
  values (v_tel, v_nom, p_estado, v_hora, nullif(btrim(coalesce(p_nota, '')), ''),
          right(regexp_replace(p_por, '\D', '', 'g'), 10), now())
  on conflict (telefono) do update
     set estado = excluded.estado,
         nota = coalesce(excluded.nota, premium_grupo.nota),
         hora = coalesce(premium_grupo.hora, excluded.hora),
         decidido_por = excluded.decidido_por,
         decidido_at = excluded.decidido_at;

  select count(*) into v_apr from premium_grupo where estado = 'aprobada';
  return jsonb_build_object('ok', true, 'nombre', v_nom, 'celular_termina_en', right(v_tel, 4),
                            'estado', p_estado, 'aprobadas', v_apr, 'libres', greatest(v_max - v_apr, 0));
end;
$$;

-- ── quién vence pronto ────────────────────────────────────────────────
create or replace function public.renovaciones_proximas(p_dias int default 7)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with hoy as (select (now() at time zone 'America/Bogota')::date d),
  ultima as (
    select distinct on (right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10))
           right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) tel, afiliado, tipo, hora, fin
      from membresias
     where coalesce(celular, '') <> ''
     order by right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10), fin desc)
  select coalesce(jsonb_agg(jsonb_build_object(
           'nombre', initcap(u.afiliado), 'celular', u.tel, 'tipo', u.tipo,
           'horario', to_char(u.hora, 'HH24:MI'), 'vence', u.fin, 'dias', u.fin - h.d,
           'grupo_premium', (select g.estado from premium_grupo g where g.telefono = u.tel),
           'meses_seguidos', premium_racha(premium_meses(u.tel))) order by u.fin, u.afiliado), '[]'::jsonb)
    from ultima u, hoy h
   where u.fin between h.d - 5 and h.d + greatest(coalesce(p_dias, 7), 0)
$$;

revoke all on function public.premium_racha(text[]), public.premium_meses(text), public.premium_personas(text),
  public.premium_evaluar(text), public.premium_estado(), public.premium_decidir(text, text, text, text),
  public.renovaciones_proximas(int) from public, anon, authenticated;
