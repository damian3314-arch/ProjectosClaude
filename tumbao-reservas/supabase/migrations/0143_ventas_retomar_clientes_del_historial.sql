-- 0143 · Ventas por WhatsApp: también a quienes compraron antes y se perdieron de vista
--
-- Damián (5 oct): «tienes la data de los clientes que compraron desde diciembre del año pasado.
-- Podemos tener esa gente para la campaña; si fue gente que vino varias veces, quizás les
-- interese retomar».
--
-- La fuente es afiliados_historial (ventas de AdminGym dic-2025 a sep-2026). Entra quien:
--   · vino varias veces: 2 o más meses con plan, o 3 o más clases sueltas;
--   · hoy no tiene mensualidad (ni en gracia), ni tiquetera con clases;
--   · no vino a una clase en los últimos 30 días (si vino, ya la cubre la lista de reservas);
--   · pasa los mismos filtros de siempre: sin bajas ni dueños, sin campaña en 5 días, como mucho
--     2 campañas cada 14 días, una apertura de ventas cada 14 días, 45 días fuera si dijo «no».
--
-- Se ofrece tiquetera (objetivo 'reactivar', origen 'historial') con un mensaje que reconoce que ya
-- bailó con nosotros. Orden de la ronda: 1) mensualidad 6 pm, 2) mensualidad 7 am, 3) tiquetera a
-- quien viene seguido, 4) quien dejó el plan hace poco (últimos 3 meses), 5) quien vino hace 31-90
-- días según las reservas, 6) el resto del historial.
--
-- Sin DROP y sin tocar el CHECK de ventas_chats: se reutiliza el objetivo 'reactivar' y el origen
-- viaja en la columna oferta (jsonb).

create or replace function public.ventas_candidatos_historial(p_limite int default 50)
returns table (tel text, nombre text, meses int, sueltas int, hora_historial text, ultimo_mes date, reciente boolean)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with hoy as (select (now() at time zone 'America/Bogota')::date d),
  vig as (select distinct right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) t
            from membresias, hoy where fin + 3 >= hoy.d),
  tq as (select distinct right(regexp_replace(telefono, '\D', '', 'g'), 10) t
           from tiqueteras, hoy
          where pagado_en is not null and vence_el >= hoy.d and clases_usadas < clases_totales),
  rec as (select distinct right(regexp_replace(x.telefono, '\D', '', 'g'), 10) t
            from reservas x join clases c on c.id = x.clase_id
           where x.estado = 'confirmada' and c.fecha_hora >= now() - interval '30 days'),
  h as (select right(regexp_replace(telefono, '\D', '', 'g'), 10) t,
               initcap(split_part(btrim(nombre), ' ', 1)) n,
               cardinality(meses) m, coalesce(sueltas_n, 0) s, hora,
               (select max((mm || '-01')::date) from unnest(meses) mm) ultimo
          from afiliados_historial)
  select h.t, coalesce(nullif(h.n, ''), 'amigo(a)'), h.m, h.s, h.hora, h.ultimo,
         coalesce(h.ultimo >= (date_trunc('month', (select d from hoy)) - interval '3 months')::date, false)
    from h
   where h.t ~ '^3[0-9]{9}$'
     and (h.m >= 2 or h.s >= 3)
     and h.t not in (select t from vig) and h.t not in (select t from tq) and h.t not in (select t from rec)
     and not wa_es_dueno(h.t)
     and not exists (select 1 from wa_bajas b where b.telefono = h.t)
     and not exists (select 1 from wa_avisos a where a.telefono = h.t and a.tipo = 'campana'
                       and a.estado in ('enviando', 'enviado', 'pendiente') and a.creado_at > now() - interval '5 days')
     and (select count(*) from wa_avisos a where a.telefono = h.t and a.tipo = 'campana'
            and a.estado in ('enviando', 'enviado', 'pendiente') and a.creado_at > now() - interval '14 days') < 2
     and not exists (select 1 from ventas_chats c where c.telefono = h.t and c.abierta_at > now() - interval '14 days')
     and not exists (select 1 from ventas_chats c where c.telefono = h.t and c.resultado = 'no_interesado'
                       and c.cerrada_at > now() - interval '45 days')
   order by 7 desc, h.m desc, h.ultimo desc nulls last, h.s desc
   limit greatest(p_limite, 0)
$$;
revoke all on function public.ventas_candidatos_historial(int) from public, anon, authenticated;

-- La lista completa y en orden: reservas (6 pm, 7 am, tiquetera) → historial reciente →
-- reservas dormidas → resto del historial. Sin repetir a nadie.
create or replace function public.ventas_seleccion(p_limite int default 50)
returns table (tel text, nombre text, objetivo text, visitas_30d int, hora_habitual text,
               prioridad int, origen text, meses int)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with a as (
    select c.tel, c.nombre, c.objetivo, c.visitas_30d, c.hora_habitual, c.prioridad, 'reservas'::text origen, null::int meses, c.n
      from ventas_candidatos(500) with ordinality as c(tel, nombre, objetivo, visitas_30d, hora_habitual, prioridad, n)
     where c.objetivo <> 'reactivar'),
  b as (
    select h.tel, h.nombre, 'reactivar'::text objetivo, 0 visitas_30d, h.hora_historial hora_habitual,
           case when h.reciente then 4 else 6 end prioridad, 'historial'::text origen, h.meses, h.n
      from ventas_candidatos_historial(500) with ordinality as h(tel, nombre, meses, sueltas, hora_historial, ultimo_mes, reciente, n)
     where h.tel not in (select tel from a)),
  c as (
    select x.tel, x.nombre, x.objetivo, x.visitas_30d, x.hora_habitual, 5 prioridad, 'reservas'::text origen, null::int meses, x.n
      from ventas_candidatos(500) with ordinality as x(tel, nombre, objetivo, visitas_30d, hora_habitual, prioridad, n)
     where x.objetivo = 'reactivar' and x.tel not in (select tel from a) and x.tel not in (select tel from b))
  select u.tel, u.nombre, u.objetivo, u.visitas_30d, u.hora_habitual, u.prioridad, u.origen, u.meses
    from (select * from a union all select * from b union all select * from c) u
   order by u.prioridad, u.n
   limit greatest(p_limite, 0)
$$;
revoke all on function public.ventas_seleccion(int) from public, anon, authenticated;

-- La frase de la apertura según el origen: quien ya bailó con nosotros lo lee en el mensaje.
create or replace function public.ventas_gancho2(p_objetivo text, p_visitas int, p_origen text, p_meses int)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_por int;
begin
  if coalesce(p_origen, '') <> 'historial' then
    return ventas_gancho(p_objetivo, p_visitas);
  end if;
  select min(round((p ->> 'precio_cop')::numeric / nullif((p ->> 'clases')::numeric, 0)))::int into v_por
    from jsonb_array_elements(tiquetera_paquetes()) p;
  v_por := coalesce(v_por, 12000);
  return 'Hace un tiempo no te vemos por Tumbao y nos acordamos de ti 🧡 Bailaste con nosotros '
         || case when coalesce(p_meses, 0) >= 2 then p_meses || ' meses' else 'varias veces' end
         || ' y nos encantaría que vuelvas: esta semana hay clases todos los días y con una tiquetera cada clase te sale desde $'
         || replace(to_char(v_por, 'FM999,999,999'), ',', '.');
end;
$$;
revoke all on function public.ventas_gancho2(text, int, text, int) from public, anon, authenticated;

-- ventas_ronda: elige con ventas_seleccion y guarda el origen; ventas_perfil: suma el historial.
do $mig$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.ventas_ronda(boolean, timestamptz)'::regprocedure);
  if position('from ventas_candidatos(50) c;' in v_def) = 0
     or position('select * from ventas_candidatos(least(v_por, v_tope - v_hoy))' in v_def) = 0
     or position('''hora_habitual'', s.hora_habitual), p_ahora' in v_def) = 0
     or position('ventas_gancho(c.objetivo, (c.oferta ->> ''visitas_30d'')::int)' in v_def) = 0 then
    raise exception 'ventas_ronda: no encuentro el texto a cambiar (¿ya se aplicó 0143?)';
  end if;
  v_def := replace(v_def, 'from ventas_candidatos(50) c;', 'from ventas_seleccion(50) c;');
  v_def := replace(v_def, 'select * from ventas_candidatos(least(v_por, v_tope - v_hoy))', 'select * from ventas_seleccion(least(v_por, v_tope - v_hoy))');
  v_def := replace(v_def, '''hora_habitual'', s.hora_habitual), p_ahora', '''hora_habitual'', s.hora_habitual, ''origen'', s.origen, ''meses'', s.meses), p_ahora');
  v_def := replace(v_def, 'ventas_gancho(c.objetivo, (c.oferta ->> ''visitas_30d'')::int)',
                   'ventas_gancho2(c.objetivo, (c.oferta ->> ''visitas_30d'')::int, c.oferta ->> ''origen'', (c.oferta ->> ''meses'')::int)');
  v_def := replace(v_def, '''visitas_30d'', c.visitas_30d, ''hora_habitual'', c.hora_habitual)), ''[]''::jsonb)',
                   '''visitas_30d'', c.visitas_30d, ''hora_habitual'', c.hora_habitual, ''origen'', c.origen)), ''[]''::jsonb)');
  execute v_def;

  v_def := pg_get_functiondef('public.ventas_perfil(text)'::regprocedure);
  if position('''precio_suelta'', 15000,' in v_def) = 0 then
    raise exception 'ventas_perfil: no encuentro el texto a cambiar';
  end if;
  v_def := replace(v_def, '''precio_suelta'', 15000,',
    '''precio_suelta'', 15000,
    ''historial'', (select jsonb_build_object(''meses_con_plan'', cardinality(h.meses), ''clases_sueltas'', h.sueltas_n, ''horario'', h.hora)
                     from afiliados_historial h where right(regexp_replace(h.telefono, ''\D'', '''', ''g''), 10) = t limit 1),');
  execute v_def;
end
$mig$;
