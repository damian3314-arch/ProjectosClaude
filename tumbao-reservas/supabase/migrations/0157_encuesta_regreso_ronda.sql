-- 0157 · Encuesta «¿Qué te ha impedido volver?» (16 oct): quien responde sigue en conversación con el asistente
--
-- Plan Tumbao (autorizado por Damián el 27 sep, sin descuento): la plantilla encuesta_regreso (MARKETING, botones
-- Horario / Precio / Tiempo / Otra razón) sale el viernes 16 de octubre a quienes se fueron y no han vuelto.
--
-- Cómo queda cableado, sin tablas nuevas:
--   · encuesta_regreso_ronda(): el 16 de octubre (ajustes.encuesta_regreso_fecha), entre 10:00 am y 1:00 pm, 10 por
--     corrida hasta ajustes.encuesta_regreso_total (60). Elige con ventas_seleccion (mismos filtros de siempre:
--     sin plan ni tiquetera, sin bajas ni dueños, sin campaña en 5 días, máx. 2 en 14, una apertura de ventas cada
--     14 días, 45 días fuera tras un «no») solo a los de objetivo 'reactivar'.
--   · abre su conversación de ventas con origen 'encuesta' ANTES de enviar: así el toque de un botón, y todo lo
--     que escriba después, lo contesta el asistente (que sabe qué hacer con «Horario», «Precio», «Tiempo» y
--     «Otra razón») en vez de la respuesta automática general.
--   · la respuesta queda guardada en wa_mensajes (es el texto del botón): no hace falta otra tabla.
--   · cron cada 10 minutos de 10 a 12 Bogotá, que solo hace algo el día fijado.
--   · wa_tomar_ventas: la «apertura» que lee el bot puede venir también de esta plantilla.

insert into ajustes (clave, valor, nota) values
  ('encuesta_regreso_fecha', '2026-10-16', 'Día en que sale la encuesta de regreso (plan Tumbao). Vacío = no sale. 0157.'),
  ('encuesta_regreso_total', '60', 'Máximo de personas a las que sale la encuesta ese día. 0157.')
on conflict (clave) do nothing;

create or replace function public.encuesta_regreso_ronda(p_ahora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  ahora timestamp := p_ahora at time zone 'America/Bogota';
  hoy date := ahora::date;
  v_dow int := extract(isodow from ahora)::int;
  v_fecha date := nullif(ventas_ajuste('encuesta_regreso_fecha', ''), '')::date;
  v_total int := ventas_ajuste('encuesta_regreso_total', '60')::int;
  v_fin time := time '13:00';
  v_hechas int; v_n int := 0;
begin
  if v_fecha is distinct from hoy then return jsonb_build_object('ok', true, 'motivo', 'no_es_el_dia'); end if;
  if ventas_ajuste('wa_ventas', 'apagado') <> 'encendido' then return jsonb_build_object('ok', true, 'motivo', 'ventas_apagadas'); end if;
  if v_dow = 7 or exists (select 1 from festivos where fecha = hoy) then return jsonb_build_object('ok', true, 'motivo', 'dia_sin_envio'); end if;
  if ahora::time < time '10:00' or ahora::time >= v_fin then return jsonb_build_object('ok', true, 'motivo', 'fuera_de_ventana'); end if;

  select count(*) into v_hechas from ventas_chats
   where oferta ->> 'origen' = 'encuesta' and (abierta_at at time zone 'America/Bogota')::date = hoy;
  if v_hechas >= v_total then return jsonb_build_object('ok', true, 'motivo', 'tope', 'hoy', v_hechas); end if;

  with sel as (
    select s.* from ventas_seleccion(500) s where s.objetivo = 'reactivar'
     order by s.prioridad limit least(10, v_total - v_hechas)
  ), chat as (
    insert into ventas_chats (telefono, nombre, objetivo, oferta, abierta_at)
    select s.tel, s.nombre, 'reactivar',
           jsonb_build_object('origen', 'encuesta', 'visitas_30d', s.visitas_30d, 'hora_habitual', s.hora_habitual), p_ahora
      from sel s
    returning telefono, nombre
  ), enc as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'encuesta:' || c.telefono || ':' || to_char(hoy, 'YYYYMMDD'), 'campana', c.telefono, 'encuesta_regreso',
           jsonb_build_array(c.nombre), now() + interval '2 hours'
      from chat c
    on conflict (clave) do nothing
    returning 1
  )
  select count(*) into v_n from enc;
  return jsonb_build_object('ok', true, 'encolados', v_n, 'hoy', v_hechas + v_n);
exception when others then
  raise warning 'encuesta_regreso_ronda: %', sqlerrm;
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;
revoke all on function public.encuesta_regreso_ronda(timestamptz) from public, anon, authenticated;

do $mig$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.wa_tomar_ventas(bigint)'::regprocedure);
  if position('encuesta_regreso' in v_def) = 0 then
    if position('a.plantilla in (''ventas_apertura'', ''ventas_horario'')' in v_def) = 0 then raise exception 'wa_tomar_ventas: no encuentro el texto a cambiar'; end if;
    v_def := replace(v_def, 'a.plantilla in (''ventas_apertura'', ''ventas_horario'')', 'a.plantilla in (''ventas_apertura'', ''ventas_horario'', ''encuesta_regreso'')');
    execute v_def;
  end if;
end
$mig$;

do $cron$
begin
  perform cron.unschedule('tumbao-encuesta-regreso');
exception when others then null;
end
$cron$;
-- cada 10 minutos de 10:00 a 12:50 Bogotá (15:00-17:50 UTC), lunes a sábado; la función solo actúa el día fijado
select cron.schedule('tumbao-encuesta-regreso', '*/10 15-17 * * 1-6', 'select public.encuesta_regreso_ronda()');
