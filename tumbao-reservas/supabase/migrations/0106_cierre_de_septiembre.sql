-- 0106 · Cierre de septiembre 2026: renovaciones, tiquetera y regreso.
--
-- LO QUE PIDIÓ DAMIÁN (27 sep, 9 pm)
-- «Tenemos 3 días para el cierre de mes… tenemos que cerrar con unos 16
--  millones y a lo mucho estamos en 14… sin nada de descuento, solo
--  usando lo que ya tenemos. Lancémonos.»
--
-- ── LOS TRES GRUPOS (medidos el 27 sep contra la base) ──────────────
--   renovacion   26 mensualidades que vencen del 25 sep al 2 oct.
--                Hasta $3.250.000: es la palanca grande. Plantilla
--                UTILITY (es la fecha de SU cuenta, no una promoción).
--   tiquetera    45 que vinieron 3 o más veces como clase suelta en 30
--                días, sin mensualidad vigente. La tiquetera de 8 les
--                sale a $12.000 la clase: precio de lista, sin descuento.
--   regreso      90 cuya última clase fue hace 14 a 35 días y no tienen
--                nada reservado. Dos lotes (mar y mié) para cuidar el
--                número, que es nuevo.
--
-- ── CUÁNDO (Bogotá; nunca domingo, Ley 2300) ────────────────────────
--   lun 28  9:00   renovación          10:30  tiquetera
--   mar 29 10:00   regreso lote 1
--   mié 30  9:00   renovación, último día (solo quien siga sin renovar)
--   mié 30 10:00   regreso lote 2
-- Cada trabajo de pg_cron se borra solo después de correr.
--
-- ── LOS FRENOS ──────────────────────────────────────────────────────
--   · Clave única por persona y campaña: nadie recibe dos veces lo mismo
--     (la renovación del miércoles tiene su propia clave y solo va a
--     quien la membresía siga vencida sin renovar).
--   · Nadie de wa_bajas (lo omite wa_tomar_avisos), ni los dueños.
--   · Tope por persona de 3 mensajes en 24 h y tope diario de 200 (0101).
--   · Antes de cada lanzamiento, una revisión (Claude) confirma que Meta
--     aprobó la plantilla y que la calidad del número sigue en verde; si
--     no, desprograma el trabajo.
--   · El despacho sale de a 10 por minuto (pg_cron cada minuto), no de
--     golpe.

create or replace function public.wa_fecha_texto(p_fecha date)
returns text
language sql
immutable
as $$
  select (array['domingo','lunes','martes','miércoles','jueves','viernes','sábado'])[extract(dow from p_fecha)::int + 1]
         || ' ' || extract(day from p_fecha)::int || ' de ' ||
         (array['enero','febrero','marzo','abril','mayo','junio','julio','agosto',
                'septiembre','octubre','noviembre','diciembre'])[extract(month from p_fecha)::int];
$$;

create or replace function public.wa_hora_texto(p_hora time)
returns text
language sql
immutable
as $$
  select to_char(p_hora, 'FMHH12:MI') || case when extract(hour from p_hora) < 12 then ' am' else ' pm' end;
$$;

create or replace function public.campana_cierre_sep(p_grupo text)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  hoy date := (now() at time zone 'America/Bogota')::date;
  fin_campana timestamptz := (date '2026-10-01')::timestamp at time zone 'America/Bogota';
  n int := 0;
begin
  if p_grupo in ('renovacion', 'renovacion_ultimo') then
    with m as (
      select distinct on (right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10))
             right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) as tel,
             initcap(split_part(trim(afiliado), ' ', 1)) as nombre, hora, fin
        from membresias
       order by right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10), fin desc)
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'cierre_sep:' || p_grupo || ':' || m.tel, 'campana', m.tel, 'mensualidad_vencimiento',
           jsonb_build_array(coalesce(nullif(m.nombre, ''), 'amigo(a)'), wa_hora_texto(m.hora), wa_fecha_texto(m.fin)),
           now() + interval '10 hours'
      from m
     where m.tel ~ '^3[0-9]{9}$'
       and not wa_es_dueno(m.tel)
       and case when p_grupo = 'renovacion'
                then m.fin between date '2026-09-25' and date '2026-10-02'
                else m.fin between date '2026-09-25' and date '2026-09-30'   -- último día: solo quien sigue sin renovar
           end
    on conflict (clave) do nothing;
    get diagnostics n = row_count;

  elsif p_grupo = 'tiquetera' then
    with vig as (
      -- Vigentes y los del grupo de renovación: a ellos ya les llega su aviso.
      select right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) tel from membresias where fin >= date '2026-09-25'),
    r as (
      select right(regexp_replace(x.telefono, '\D', '', 'g'), 10) tel,
             (array_agg(initcap(split_part(trim(x.nombre), ' ', 1)) order by x.created_at desc))[1] nombre,
             count(*) filter (where x.tipo = 'suelta' and c.fecha_hora >= now() - interval '30 days' and c.fecha_hora < now()) veces
        from reservas x join clases c on c.id = x.clase_id
       where x.estado = 'confirmada' group by 1)
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'cierre_sep:tiquetera:' || r.tel, 'campana', r.tel, 'tiquetera_frecuentes',
           jsonb_build_array(coalesce(nullif(r.nombre, ''), 'amigo(a)'), r.veces::text), fin_campana
      from r
     where r.veces >= 3 and r.tel ~ '^3[0-9]{9}$'
       and r.tel not in (select tel from vig)
       and not wa_es_dueno(r.tel)
       and not exists (select 1 from tiqueteras t where right(regexp_replace(t.telefono, '\D', '', 'g'), 10) = r.tel
                         and t.pagado_en is not null and t.vence_el >= hoy)
    on conflict (clave) do nothing;
    get diagnostics n = row_count;

  elsif p_grupo in ('regreso_1', 'regreso_2') then
    with vig as (
      -- Vigentes y los del grupo de renovación: a ellos ya les llega su aviso.
      select right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) tel from membresias where fin >= date '2026-09-25'),
    r as (
      select right(regexp_replace(x.telefono, '\D', '', 'g'), 10) tel,
             (array_agg(initcap(split_part(trim(x.nombre), ' ', 1)) order by x.created_at desc))[1] nombre,
             max(c.fecha_hora) ultima, bool_or(c.fecha_hora > now()) tiene_futura
        from reservas x join clases c on c.id = x.clase_id
       where x.estado = 'confirmada' group by 1),
    candidatos as (
      select r.* from r
       where r.ultima < now() - interval '14 days' and r.ultima >= now() - interval '35 days'
         and not r.tiene_futura and r.tel ~ '^3[0-9]{9}$'
         and r.tel not in (select tel from vig)
         and not wa_es_dueno(r.tel)
         and not exists (select 1 from wa_avisos a where a.telefono = r.tel and a.clave like 'cierre_sep:%'
                           and a.clave not like 'cierre_sep:renovacion%')
       order by r.ultima desc
       limit case when p_grupo = 'regreso_1' then 45 else 60 end)
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'cierre_sep:regreso:' || tel, 'campana', tel, 'te_extranamos',
           jsonb_build_array(coalesce(nullif(nombre, ''), 'amigo(a)')), now() + interval '10 hours'
      from candidatos
    on conflict (clave) do nothing;
    get diagnostics n = row_count;
  else
    raise exception 'grupo desconocido: %', p_grupo;
  end if;

  insert into ajustes (clave, valor, nota)
  values ('cierre_sep_' || p_grupo, n::text || ' encolados el ' || to_char(now() at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI'),
          'Registro de la campaña de cierre de septiembre 2026. 0106.')
  on conflict (clave) do update set valor = excluded.valor, updated_at = now();
  return n;
end;
$$;
revoke all on function public.campana_cierre_sep(text) from public, anon, authenticated;

-- ── el despacho, cada minuto ────────────────────────────────────────
-- El disparador de 0101 toca al Worker una vez por INSERT, y el Worker
-- manda 10 por vuelta: una campaña de 45 dejaría 35 esperando. Cada
-- minuto se vacía de a 10. Si la cola está vacía, cuesta una consulta.
create or replace function public.wa_disparar_despacho()
returns void
language sql
security definer
set search_path = public, extensions, pg_temp
as $$
  select net.http_post(
    url := (select valor from ajustes where clave = 'wa_despachar_url'),
    body := '{}'::jsonb,
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 60000)
  where exists (select 1 from wa_avisos where estado = 'pendiente');
$$;
revoke all on function public.wa_disparar_despacho() from public, anon, authenticated;
select cron.schedule('tumbao-despachar', '* * * * *', $$select public.wa_disparar_despacho()$$);

-- ── los lanzamientos (UTC = Bogotá + 5) ─────────────────────────────
select cron.schedule('cierre-renovacion-lun', '0 14 28 9 *',
  $$select public.campana_cierre_sep('renovacion'); select cron.unschedule('cierre-renovacion-lun')$$);
select cron.schedule('cierre-tiquetera-lun', '30 15 28 9 *',
  $$select public.campana_cierre_sep('tiquetera'); select cron.unschedule('cierre-tiquetera-lun')$$);
select cron.schedule('cierre-regreso1-mar', '0 15 29 9 *',
  $$select public.campana_cierre_sep('regreso_1'); select cron.unschedule('cierre-regreso1-mar')$$);
select cron.schedule('cierre-renovacion-mie', '0 14 30 9 *',
  $$select public.campana_cierre_sep('renovacion_ultimo'); select cron.unschedule('cierre-renovacion-mie')$$);
select cron.schedule('cierre-regreso2-mie', '0 15 30 9 *',
  $$select public.campana_cierre_sep('regreso_2'); select cron.unschedule('cierre-regreso2-mie')$$);
