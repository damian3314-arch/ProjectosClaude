-- 0128 · El grupo premium son 20 a 25 personas POR HORARIO, no 25 en total
--
-- Aclaración de Damián (30 sep): «son 20 a 25 por cada clase, por los horarios
-- que manejamos». Los horarios con mensualidad son 7 am, 6 pm y 7 pm
-- (ajustes.mensualidad_horas), así que el grupo puede llegar a 25 + 25 + 25.
--
-- Qué cambia respecto de 0127
--   · El tope (premium_cupo_max = 25) y el mínimo buscado (premium_cupo_min = 20)
--     valen POR HORARIO.
--   · premium_ranking(): ordena a quienes pagaron plan en el último mes dentro de
--     su horario (más meses seguidos primero). «4 meses seguidos» sola dejaba
--     8, 10 y 3 personas: muy por debajo de 20 a 25; el puesto en el horario sí
--     llena los cupos con quienes más constantes han sido.
--   · premium_evaluar(): además de cumple / no_cumple, dice 'cabe_por_cupo' cuando
--     no llega a la regla de 4 meses pero su puesto cabe en los cupos de su horario.
--   · premium_estado(): cupos, candidatas y planes vigentes por horario.
--   · premium_decidir(): el tope se cuenta en el horario de la persona.
--
-- Sigue siendo una ayuda: aprueba Damián.

insert into ajustes (clave, valor, nota) values
  ('premium_cupo_min', '20', 'Lo mínimo que se busca tener en el grupo premium POR HORARIO.')
on conflict (clave) do nothing;
update ajustes set nota = 'Tope del grupo premium POR HORARIO (7 am, 6 pm y 7 pm). 0128.'
 where clave = 'premium_cupo_max';

-- ── el orden dentro de cada horario ───────────────────────────────────
create or replace function public.premium_ranking()
returns table (tel text, nombre text, hora text, racha int, total int, ultimo text, puesto int)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with fuentes as (
    select telefono t, nombre n, hora hr from afiliados_historial where cardinality(meses) > 0
    union all
    select right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10), initcap(afiliado), to_char(hora, 'HH24:MI')
      from membresias where coalesce(celular, '') <> ''
  ),
  personas as (
    select t, (array_agg(n order by length(n) desc))[1] n,
           coalesce((select to_char(m.hora, 'HH24:MI') from membresias m
                      where right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10) = f.t
                      order by m.fin desc limit 1),
                    max(hr)) hr
      from fuentes f where t ~ '^3[0-9]{9}$' group by t
  ),
  base as (
    select t, n, hr, premium_racha(premium_meses(t)) rc, cardinality(premium_meses(t)) tt,
           (select max(m) from unnest(premium_meses(t)) m) ul
      from personas
  )
  select t, n, hr, rc, tt, ul,
         (row_number() over (partition by hr order by rc desc, tt desc, ul desc, n))::int
    from base
   where hr is not null and ul is not null
     and ul >= to_char((now() at time zone 'America/Bogota')::date - interval '1 month', 'YYYY-MM')
$$;

-- ── cupos por horario ─────────────────────────────────────────────────
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
           'tope', c.tope, 'minimo_buscado', c.minimo,
           'aprobadas', (select count(*) from premium_grupo g where g.estado = 'aprobada' and g.hora = hr),
           'libres', greatest(c.tope - (select count(*) from premium_grupo g where g.estado = 'aprobada' and g.hora = hr), 0),
           'candidatas', (select count(*) from premium_grupo g where g.estado = 'candidata' and g.hora = hr),
           'planes_vigentes_hoy', (select count(*) from membresias m where m.fin >= c.hoy and to_char(m.hora, 'HH24:MI') = hr))),
         '{}'::jsonb)
    from horas, cfg c
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
  v_mes_ref   int    := extract(year from hoy)::int * 12 + extract(month from hoy)::int;
  v_cupos jsonb := premium_cupos_horario();
  v_lista jsonb := '[]'::jsonb;
  r record;
  v_meses text[]; v_racha int; v_ultimo text; v_ult_idx int;
  v_hist afiliados_historial%rowtype;
  v_on_n int; v_on_pri date; v_on_ult date; v_on_sem int;
  v_n int; v_pri date; v_ult date; v_sem int; v_span int;
  v_g premium_grupo%rowtype; v_vig record; v_rk record;
  v_hora text; v_apr_h int; v_libres_h int;
  v_planes boolean; v_suelta boolean; v_cabe boolean; v_ver text; v_razon text;
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
    select * into v_rk from premium_ranking() k where k.tel = r.tel;

    v_hora := coalesce(to_char(v_vig.hora, 'HH24:MI'), v_rk.hora, v_hist.hora, v_g.hora);
    v_apr_h := case when v_hora is null then 0
                    else (select count(*) from premium_grupo where estado = 'aprobada' and hora = v_hora) end;
    v_libres_h := greatest(v_max - v_apr_h, 0);

    v_planes := v_racha >= v_min_meses and v_ult_idx is not null and v_ult_idx >= v_mes_ref - 1;
    v_suelta := v_n >= v_visitas and v_sem >= v_semanas and v_span >= v_dias
                and v_ult is not null and v_ult >= hoy - 21;
    v_cabe   := v_rk.puesto is not null and v_rk.puesto <= v_max and v_libres_h > 0;

    if v_g.estado = 'aprobada' then
      v_ver := 'ya_es_premium'; v_razon := 'Ya está aprobada en el grupo premium.';
    elsif v_g.estado = 'descartada' then
      v_ver := 'descartada'; v_razon := 'Se descartó del grupo' || coalesce(': ' || v_g.nota, '.');
    elsif v_planes then
      v_ver := 'cumple'; v_razon := v_racha || ' meses seguidos pagando plan (el ideal es ' || v_min_meses || ' o más).';
    elsif v_suelta then
      v_ver := 'cumple'; v_razon := 'Clase suelta constante: ' || v_n || ' visitas en ' || v_sem || ' semanas durante ' || v_span || ' días.';
    elsif v_cabe then
      v_ver := 'cabe_por_cupo';
      v_razon := 'Lleva ' || v_racha || ' mes(es) seguidos de plan (el ideal es ' || v_min_meses || '), pero está en el puesto '
                 || v_rk.puesto || ' de su horario de ' || v_hora || ' y ese horario tiene ' || v_libres_h || ' cupo(s) libre(s) de ' || v_max || '.';
    elsif cardinality(v_meses) > 0 and v_racha >= v_min_meses then
      v_ver := 'no_cumple'; v_razon := 'Tuvo ' || v_racha || ' meses seguidos, pero hace más de un mes que no paga plan.';
    elsif cardinality(v_meses) > 0 then
      v_ver := 'no_cumple'; v_razon := 'Lleva ' || v_racha || ' mes(es) seguidos de plan (en total ' || cardinality(v_meses) || ')'
                || case when v_rk.puesto is not null then ' y está en el puesto ' || v_rk.puesto || ' de su horario (caben ' || v_max || ')'
                        else ' y no pagó plan en el último mes' end || '.';
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
      'horario', v_hora,
      'puesto_en_su_horario', v_rk.puesto,
      'cupos_de_su_horario', case when v_hora is null then null else v_cupos -> v_hora end,
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
    'cupos_por_horario', v_cupos,
    'vigente_hasta', (select valor from ajustes where clave = 'premium_vigente_hasta'),
    'regla', jsonb_build_object('meses_seguidos_plan', v_min_meses, 'suelta_dias', v_dias,
                                'suelta_visitas', v_visitas, 'suelta_semanas', v_semanas,
                                'tope_por_horario', v_max),
    'personas', v_lista);
end;
$$;

-- ── el grupo completo, por horario ────────────────────────────────────
create or replace function public.premium_estado()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'ok', true,
    'vigente_hasta', (select valor from ajustes where clave = 'premium_vigente_hasta'),
    'por_horario', premium_cupos_horario(),
    'aprobadas_en_total', (select count(*) from premium_grupo where estado = 'aprobada'),
    'candidatas_en_total', (select count(*) from premium_grupo where estado = 'candidata'),
    'descartadas_en_total', (select count(*) from premium_grupo where estado = 'descartada'),
    'personas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'nombre', g.nombre, 'celular_termina_en', right(g.telefono, 4), 'estado', g.estado,
               'horario', g.hora, 'meses_seguidos', premium_racha(premium_meses(g.telefono)), 'nota', g.nota)
             order by g.hora nulls last,
                      case g.estado when 'aprobada' then 0 when 'candidata' then 1 else 2 end,
                      premium_racha(premium_meses(g.telefono)) desc, g.nombre)
        from premium_grupo g), '[]'::jsonb))
$$;

-- ── aprobar o descartar: el tope se cuenta en el horario de la persona ─
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
  v_ya text; v_hora_ya text;
begin
  if p_estado not in ('aprobada', 'descartada', 'candidata') then
    return jsonb_build_object('ok', false, 'error', 'ESTADO_INVALIDO');
  end if;
  -- Decidir es de Damián (wa_notas_para), no de los otros dos números.
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

  select estado, hora into v_ya, v_hora_ya from premium_grupo where telefono = v_tel;
  v_hora := coalesce(
    (select to_char(hora, 'HH24:MI') from membresias
      where right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) = v_tel
      order by fin desc limit 1),
    v_hora_ya,
    (select hora from afiliados_historial where telefono = v_tel));

  if p_estado = 'aprobada' then
    if v_hora is null then
      return jsonb_build_object('ok', false, 'error', 'SIN_HORARIO', 'nombre', v_nom);
    end if;
    select count(*) into v_apr from premium_grupo where estado = 'aprobada' and hora = v_hora;
    if v_ya is distinct from 'aprobada' and v_apr >= v_max then
      return jsonb_build_object('ok', false, 'error', 'SIN_CUPO', 'horario', v_hora, 'tope', v_max, 'aprobadas_en_ese_horario', v_apr);
    end if;
  end if;

  insert into premium_grupo (telefono, nombre, estado, hora, nota, decidido_por, decidido_at)
  values (v_tel, v_nom, p_estado, v_hora, nullif(btrim(coalesce(p_nota, '')), ''),
          right(regexp_replace(p_por, '\D', '', 'g'), 10), now())
  on conflict (telefono) do update
     set estado = excluded.estado,
         nota = coalesce(excluded.nota, premium_grupo.nota),
         hora = coalesce(premium_grupo.hora, excluded.hora),
         decidido_por = excluded.decidido_por,
         decidido_at = excluded.decidido_at;

  select count(*) into v_apr from premium_grupo where estado = 'aprobada' and hora = v_hora;
  return jsonb_build_object('ok', true, 'nombre', v_nom, 'celular_termina_en', right(v_tel, 4),
                            'estado', p_estado, 'horario', v_hora,
                            'aprobadas_en_ese_horario', v_apr, 'libres_en_ese_horario', greatest(v_max - v_apr, 0));
end;
$$;

revoke all on function public.premium_ranking(), public.premium_cupos_horario(),
  public.premium_evaluar(text), public.premium_estado(), public.premium_decidir(text, text, text, text)
  from public, anon, authenticated;
