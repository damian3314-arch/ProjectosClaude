-- 0205 · «Borrón y cuenta nueva» (Damián, 11 nov). Aplicada en vivo.
-- · wa_en_descanso(tel): true si recibió 3+ mensajes de campaña o de ventas en 30 días, o alguno en los últimos 14 días.
--   La usan campana_publico (reemplaza «3 días / 2 en 14 días») y ventas_seleccion.
-- · ventas_seleccion ya no abre conversaciones con objetivo «reactivar» (en 7 días: 69 aperturas, 1 respuesta, 0 compras).
-- · Pausados con cron.alter_job(active := false), sin borrar nada: tumbao-encuesta-recordatorio, tumbao-encuesta-recordatorio-reenvio,
--   tumbao-tiquetera-constancia, tumbao-frecuentes-nov, tumbao-encuesta-regreso.
-- · No toca confirmaciones de reserva, avisos de renovación, respuestas de Timba ni wa_bajas.
-- · Tiquetera para quien tuvo 2+ clases sueltas en 45 días (pedido de Damián): se encolaron 9 mensajes con tiquetera_frecuentes
--   (clave tiq-2en45:*), solo a quien tenía 2+ en 30 días (para que «viniste N veces en el último mes» sea cierto), sin plan ni
--   tiquetera, sin baja, sin bloqueo de mercadeo y con 2 o menos mensajes de campaña en 30 días. Medir a 7 días.
create or replace function public.wa_en_descanso(p_tel text)
returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $f$
  select (select count(*) from wa_avisos a where right(a.telefono,10) = right(p_tel,10) and a.enviado_at is not null
            and (a.tipo = 'campana' or a.plantilla like 'ventas%') and a.creado_at > now() - interval '30 days') >= 3
      or exists (select 1 from wa_avisos a where right(a.telefono,10) = right(p_tel,10)
            and (a.tipo = 'campana' or a.plantilla like 'ventas%') and a.creado_at > now() - interval '14 days');
$f$;
