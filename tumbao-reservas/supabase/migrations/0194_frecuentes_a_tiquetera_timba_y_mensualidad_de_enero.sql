-- 0194 · Cierre de año (2 nov, Damián aprobó 2, 3 y 5 del plan «Rumbo a 2027»). Aplicada en vivo.
--
-- 2 · Campaña a frecuentes sin plan → tiquetera (plantilla tiquetera_frecuentes, marketing ≈ $46). Quien bailó 2 o más veces en 30 días,
--     sin plan ni tiquetera vigente, sin bajas, sin campañas en 3 días (máx. 2 en 14), sin conversación de ventas abierta o cerrada en 45 días.
--     Un cron diario (10 am, lunes a sábado) la corre hasta el 20 de noviembre: a medida que se liberan los filtros entran más. Es idempotente.
-- 5 · Timba: la selección de ventas ponía a «tiquetera» (frecuentes sin plan) en el último lugar (prioridad 7); ahora va en 3, justo después de los
--     cupos de mensualidad.
-- 3 · «Asegura tu enero»: la solicitud de mensualidad guarda `inicio_deseado` (la página la manda entre el 15 dic y el 3 ene) y el panel lo muestra
--     para que recepción registre a la persona con esa fecha. «Regala Tumbao» es solo de la página (la tiquetera ya tiene código transferible).

create or replace function public.campana_frecuentes_nov(p_ejecutar boolean default false)
returns jsonb language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $f$
declare v_gracia int := coalesce(nullif((select valor from ajustes where clave='mensualidad_gracia_dias'),'')::int,3); v_tot int; v_enc int := 0;
begin
  with base as (
    select right(regexp_replace(r.telefono,'\D','','g'),10) t,
           mode() within group (order by initcap(split_part(btrim(r.nombre),' ',1))) n,
           count(*) filter (where r.tipo='suelta' and r.estado='confirmada' and c.fecha_hora >= now()-interval '30 days' and c.fecha_hora < now()) v30
      from reservas r join clases c on c.id=r.clase_id where r.telefono is not null group by 1),
  cand as (
    select b.t, coalesce(nullif(b.n,''),'amigo(a)') n, b.v30::int v30 from base b
     where b.v30 >= 2 and b.t ~ '^3[0-9]{9}$'
       and not wa_es_dueno(b.t)
       and not exists (select 1 from wa_bajas x where right(x.telefono,10)=b.t)
       and not exists (select 1 from membresias m where m.celular is not null and right(regexp_replace(m.celular,'\D','','g'),10)=b.t and current_date between m.inicio and m.fin+v_gracia)
       and not exists (select 1 from tiqueteras q where q.telefono is not null and right(regexp_replace(q.telefono,'\D','','g'),10)=b.t and q.vence_el >= current_date and q.estado in ('confirmada','pendiente_pago','pendiente_validacion'))
       and not exists (select 1 from wa_avisos a where right(a.telefono,10)=b.t and a.tipo='campana' and a.creado_at > now()-interval '3 days')
       and (select count(*) from wa_avisos a where right(a.telefono,10)=b.t and a.tipo='campana' and a.creado_at > now()-interval '14 days') < 2
       and not exists (select 1 from wa_avisos a where right(a.telefono,10)=b.t and a.plantilla='tiquetera_frecuentes' and a.creado_at > now()-interval '30 days')
       and not exists (select 1 from ventas_chats c where right(c.telefono,10)=b.t and (c.estado='abierta' or c.cerrada_at > now()-interval '45 days'))
       and not exists (select 1 from mensualidad_solicitudes s where s.celular=b.t and s.estado in ('esperando_pago','pagada'))),
  ins as (
    insert into wa_avisos (clave,tipo,telefono,plantilla,variables,vence_at)
    select 'frecuentes-nov:'||t,'campana',t,'tiquetera_frecuentes',jsonb_build_array(n,v30::text),now()+interval '4 days' from cand
     where p_ejecutar
    on conflict (clave) do nothing returning 1)
  select (select count(*) from cand), (select count(*) from ins) into v_tot, v_enc;
  return jsonb_build_object('ejecutado',p_ejecutar,'candidatos',v_tot,'encolados',v_enc,'costo_aprox_cop',v_tot*46);
end $f$;
revoke all on function public.campana_frecuentes_nov(boolean) from public, anon, authenticated;

select cron.schedule('tumbao-frecuentes-nov','0 15 * * 1-6','select case when current_date <= date ''2026-11-20'' then public.campana_frecuentes_nov(true) end');

-- Timba: la tiquetera para frecuentes pasa de prioridad 7 a 3.
do $b$ declare d text; begin
 d := pg_get_functiondef('public.ventas_seleccion(integer)'::regprocedure);
 d := replace(d, 'case when c.objetivo = ''tiquetera'' then 7 else', 'case when c.objetivo = ''tiquetera'' then 3 else');
 execute d; end $b$;

-- Mensualidad de enero.
alter table public.mensualidad_solicitudes add column if not exists inicio_deseado date;
create or replace function public.mensualidad_fijar_inicio(p_id uuid, p_inicio date)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $f$
begin
  if p_inicio is null or p_inicio < date '2026-12-15' or p_inicio > date '2027-02-28' then
    return jsonb_build_object('ok', false, 'error', 'FECHA_INVALIDA');
  end if;
  update mensualidad_solicitudes set inicio_deseado = p_inicio
   where id = p_id and estado in ('esperando_pago','pagada','lista_espera') and creado_at > now() - interval '2 days';
  return jsonb_build_object('ok', found);
end $f$;
revoke all on function public.mensualidad_fijar_inicio(uuid, date) from public, anon, authenticated;
do $b$ declare d text; begin
 d := pg_get_functiondef('public.mensualidad_lista(text)'::regprocedure);
 d := replace(d, '''primera_vez'', s.primera_vez,', '''primera_vez'', s.primera_vez, ''inicio_deseado'', s.inicio_deseado,');
 execute d; end $b$;
