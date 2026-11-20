-- 0199 · Calendario de campañas de cierre de año, autónomo (2 nov, Damián: «También los mensajes a las clientas que solo vienen los
-- sábados, ofreciendo la tiquetera, y lo que veas conveniente. Tenemos que vender. Aprovechemos las fechas especiales que se vienen y
-- dejemos todo programado y preparado, para que no me tengas que estar pidiendo permiso para todo»). Aplicada en vivo.
--
-- · ajustes.campanas_calendario: la lista de envíos (fecha, plantilla, respaldo, público). Se edita sin tocar código.
-- · campana_publico(p_publico): quién recibe. Siempre con los filtros de siempre: sin bajas, sin dueños, sin plan o tiquetera vigente
--   (salvo el público «con_plan»), sin campaña en 3 días, máx. 2 campañas en 14 días, la misma plantilla nunca dos veces en 30 días,
--   sin conversación de ventas abierta y sin solicitud de mensualidad pendiente.
-- · campanas_del_dia(p_ejecutar): la corre un cron a las 10 am (lunes a sábado). No hace nada en domingo ni festivo. Si la plantilla
--   principal aún no está aprobada por Meta (ajustes.wa_plantillas_aprobadas, que el Worker refresca cada hora) usa la de respaldo.
--   Se detiene si el gasto de estas campañas pasa ajustes.campanas_presupuesto_cop.
-- Sigue siendo ROJO y no lo hace esto: precios, descuentos, ofertas nuevas, horarios. Solo plantillas con lo que ya existe.

insert into ajustes (clave, valor, nota) values
 ('campanas_autonomas', 'encendido',
  '2 nov · Damián autorizó dejar programadas las campañas de fechas especiales (nov-dic) sin pedir permiso para cada una, con las plantillas y ofertas que ya existen (precios de siempre y «premiamos tu constancia»). Apagar: valor=apagado.'),
 ('campanas_presupuesto_cop', '120000', 'Tope de gasto (≈ $46 por mensaje de marketing) de las campañas del calendario, nov-dic 2026.'),
 ('wa_plantillas_aprobadas', '', 'Lista separada por comas de las plantillas APPROVED en Meta. La refresca el Worker cada hora.'),
 ('campanas_calendario', $j$[
  {"fecha":"2026-11-06","clave":"sabados-1","plantilla":"tiquetera_sabados","respaldo":"tiquetera_premio_imagen","publico":"solo_sabados","nota":"Viernes antes del sábado: a quien solo baila los sábados, la tiquetera de 4 (sus 4 sábados del mes)."},
  {"fecha":"2026-11-13","clave":"quincena-nov","plantilla":"tiquetera_premio_imagen","respaldo":"tiquetera_frecuentes","publico":"frecuentes_sin_plan","nota":"Quincena antes del puente: frecuentes sin plan → tiquetera con imagen de premiamos tu constancia."},
  {"fecha":"2026-11-20","clave":"sabados-2","plantilla":"tiquetera_sabados","respaldo":"tiquetera_premio_imagen","publico":"solo_sabados","nota":"Segunda ola de sábados (solo a quien no lo recibió en 30 días)."},
  {"fecha":"2026-11-30","clave":"navidad-fin-nov","plantilla":"navidad_tiquetera","respaldo":"tiquetera_premio_imagen","publico":"frecuentes_sin_plan","nota":"Fin de mes y quincena: arranca diciembre con tiquetera."},
  {"fecha":"2026-12-02","clave":"regala-1","plantilla":"regala_tumbao","respaldo":"regala_tumbao","publico":"con_plan","nota":"Regala Tumbao a quien ya tiene plan o compró tiquetera (90 días)."},
  {"fecha":"2026-12-11","clave":"regala-2","plantilla":"regala_tumbao","respaldo":"regala_tumbao","publico":"frecuentes_sin_plan","nota":"Regala Tumbao a frecuentes sin plan, antes de la prima."},
  {"fecha":"2026-12-16","clave":"prima-2027","plantilla":"rumbo_2027_imagen","respaldo":"rumbo_2027_imagen","publico":"inactivos","nota":"Prima y novenas: a quien no viene hace 1-6 meses, llega a 2027 bailando."},
  {"fecha":"2026-12-28","clave":"cierre-2027","plantilla":"rumbo_2027_imagen","respaldo":"rumbo_2027_imagen","publico":"frecuentes_sin_plan","nota":"Última semana del año: faltan pocos días para 2027."}
 ]$j$, 'Calendario de campañas autónomas (0199). Una entrada por envío: fecha (Bogotá), plantilla, respaldo, público.')
on conflict (clave) do update set valor = excluded.valor, nota = excluded.nota;

create or replace function public.campana_publico(p_publico text, p_plantilla text default null)
returns table (telefono text, nombre text, dato text)
language plpgsql stable security definer
set search_path to 'public','extensions','pg_temp' as $f$
declare v_gracia int := coalesce(nullif((select valor from ajustes where clave='mensualidad_gracia_dias'),'')::int,5);
begin
  return query
  with v as (
    select right(regexp_replace(r.telefono,'\D','','g'),10) t, initcap(split_part(btrim(r.nombre),' ',1)) n, r.tipo::text tipo,
           extract(isodow from c.fecha_hora at time zone 'America/Bogota') dow, c.fecha_hora f
      from reservas r join clases c on c.id = r.clase_id
     where r.estado = 'confirmada' and r.telefono is not null and c.fecha_hora < now() and c.fecha_hora >= now() - interval '180 days'),
  p as (
    select v.t, mode() within group (order by v.n) n,
           count(*) filter (where v.f >= now()-interval '60 days') v60,
           count(*) filter (where v.f >= now()-interval '60 days' and v.dow = 6) s60,
           max(v.f) ult
      from v group by v.t),
  plan as (  -- tiene mensualidad vigente (o en gracia) o tiquetera vigente
    select right(regexp_replace(m.celular,'\D','','g'),10) t from membresias m
     where m.celular is not null and current_date between m.inicio and m.fin + v_gracia
    union
    select right(regexp_replace(q.telefono,'\D','','g'),10) from tiqueteras q
     where q.telefono is not null and q.vence_el >= current_date and q.estado in ('confirmada','pendiente_pago','pendiente_validacion')),
  compro as (  -- para «con_plan»: plan vigente o tiquetera comprada en 90 días
    select plan.t from plan
    union
    select right(regexp_replace(q.telefono,'\D','','g'),10) from tiqueteras q
     where q.telefono is not null and q.estado = 'confirmada' and q.creada_en >= now() - interval '90 days' and q.premio_de is null),
  base as (
    select p.t, p.n, case when p_publico = 'solo_sabados' then p.s60::text else p.v60::text end d from p
     where (p_publico = 'solo_sabados'        and p.s60 >= 1 and p.s60::numeric / greatest(p.v60,1) >= 0.8 and p.t not in (select plan.t from plan))
        or (p_publico = 'frecuentes_sin_plan' and p.v60 >= 2 and p.t not in (select plan.t from plan))
        or (p_publico = 'inactivos'           and p.ult < now() - interval '30 days' and p.t not in (select plan.t from plan))
    union
    select c.t, coalesce((select p.n from p where p.t = c.t), ''), '' from compro c where p_publico = 'con_plan')
  select b.t, coalesce(nullif(b.n,''),'amigo(a)'), b.d from base b
   where b.t ~ '^3[0-9]{9}$'
     and not wa_es_dueno(b.t)
     and not exists (select 1 from wa_bajas x where right(x.telefono,10) = b.t)
     and not exists (select 1 from wa_avisos a where right(a.telefono,10) = b.t and a.tipo = 'campana' and a.creado_at > now() - interval '3 days')
     and (select count(*) from wa_avisos a where right(a.telefono,10) = b.t and a.tipo = 'campana' and a.creado_at > now() - interval '14 days') < 2
     and (p_plantilla is null or not exists (select 1 from wa_avisos a where right(a.telefono,10) = b.t and a.plantilla = p_plantilla and a.creado_at > now() - interval '30 days'))
     and not exists (select 1 from ventas_chats vc where right(vc.telefono,10) = b.t and vc.estado = 'abierta')
     and not exists (select 1 from mensualidad_solicitudes s where s.celular = b.t and s.estado in ('esperando_pago','pagada'));
end $f$;
revoke all on function public.campana_publico(text, text) from public, anon, authenticated;

create or replace function public.campanas_del_dia(p_ejecutar boolean default false, p_fecha date default null)
returns jsonb language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $f$
declare
  v_hoy date := coalesce(p_fecha, (now() at time zone 'America/Bogota')::date);
  v_cal jsonb := coalesce(nullif((select valor from ajustes where clave='campanas_calendario'),'')::jsonb, '[]'::jsonb);
  v_aprob text[] := string_to_array(coalesce((select valor from ajustes where clave='wa_plantillas_aprobadas'),''), ',');
  v_tope int := coalesce(nullif((select valor from ajustes where clave='campanas_presupuesto_cop'),'')::int, 0);
  v_gastado int; e jsonb; v_pl text; v_cand int; v_enc int; v_out jsonb := '[]'::jsonb; v_cupo int;
begin
  if coalesce((select valor from ajustes where clave='campanas_autonomas'),'apagado') <> 'encendido' then
    return jsonb_build_object('ok', true, 'nada', 'apagado');
  end if;
  if extract(isodow from v_hoy) = 7 or exists (select 1 from festivos where fecha = v_hoy) then
    return jsonb_build_object('ok', true, 'nada', 'domingo o festivo');
  end if;
  select count(*) * 46 into v_gastado from wa_avisos where clave like 'cal:%' and coalesce(entrega_error,'') = '';
  for e in select * from jsonb_array_elements(v_cal) loop
    continue when (e->>'fecha')::date <> v_hoy;
    v_pl := case when (e->>'plantilla') = any(v_aprob) then e->>'plantilla' else e->>'respaldo' end;
    v_cupo := greatest((v_tope - v_gastado) / 46, 0);
    select count(*) into v_cand from campana_publico(e->>'publico', v_pl);
    v_enc := 0;
    if p_ejecutar and v_cupo > 0 and v_pl = any(v_aprob) then
      with ins as (
        insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
        select 'cal:' || (e->>'clave') || ':' || c.telefono, 'campana', c.telefono, v_pl,
               case when v_pl in ('tiquetera_sabados','tiquetera_frecuentes') then jsonb_build_array(c.nombre, c.dato)
                    else jsonb_build_array(c.nombre) end,
               now() + interval '3 days'
          from (select * from campana_publico(e->>'publico', v_pl) limit v_cupo) c
        on conflict (clave) do nothing returning 1)
      select count(*) into v_enc from ins;
      v_gastado := v_gastado + v_enc * 46;
    end if;
    v_out := v_out || jsonb_build_object('clave', e->>'clave', 'plantilla', v_pl, 'aprobada', v_pl = any(v_aprob),
                                         'publico', e->>'publico', 'candidatos', v_cand, 'encolados', v_enc);
  end loop;
  if p_ejecutar and jsonb_array_length(v_out) > 0 then
    insert into ajustes (clave, valor, nota) values ('campanas_ultimo', to_char(now() at time zone 'America/Bogota','YYYY-MM-DD HH24:MI') || ' · ' || v_out::text, 'Último resultado de campanas_del_dia (0199).')
    on conflict (clave) do update set valor = excluded.valor;
  end if;
  return jsonb_build_object('ok', true, 'dia', v_hoy, 'gastado_cop', v_gastado, 'tope_cop', v_tope, 'envios', v_out);
end $f$;
revoke all on function public.campanas_del_dia(boolean, date) from public, anon, authenticated;

-- El Worker anota cada hora qué plantillas están aprobadas (para elegir la principal o la de respaldo).
create or replace function public.wa_plantillas_anotar(p_aprobadas text)
returns void language sql security definer set search_path to 'public','pg_temp' as $f$
  update ajustes set valor = coalesce(p_aprobadas,'') where clave = 'wa_plantillas_aprobadas';
$f$;
revoke all on function public.wa_plantillas_anotar(text) from public, anon, authenticated;
grant execute on function public.wa_plantillas_anotar(text) to service_role;

select cron.schedule('tumbao-campanas-calendario', '0 15 * * 1-6', 'select public.campanas_del_dia(true)');
