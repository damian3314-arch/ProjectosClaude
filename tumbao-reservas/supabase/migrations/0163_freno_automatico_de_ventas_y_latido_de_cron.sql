-- 0163 · Freno automático de las ventas por WhatsApp y latido del reloj de Cloudflare
--
-- Damián (9 oct): «que yo no tenga que dar tanto permiso para hacer las cosas, que sea automático».
--
-- Hasta hoy, apagar las ventas cuando algo andaba mal dependía de que la rutina diaria (1:17 pm) lo viera o de que
-- alguien leyera la alerta del centinela. Ahora el freno es automático y corre cada hora (centinela, pg_cron) y,
-- si el reloj de Cloudflare funciona, cada 10 minutos:
--
--   ventas_freno_revisar(calidad)  apaga ajustes.wa_ventas ('apagado') SOLO si, hoy:
--       · Meta bajó la calidad del número (algo distinto de GREEN), o
--       · pidieron no recibir más mensajes más del 8 % de las aperturas (con al menos 10 aperturas), o
--       · fallaron más del 25 % de las entregas (con al menos 20 aperturas), o
--       · Meta devolvió el error 131042 (pago pendiente a Meta).
--     Son los mismos límites que ya tenía la rutina diaria. Con wa_ventas apagado se detienen las aperturas, el
--     seguimiento de 24 h y la encuesta del 16 de octubre. No toca renovaciones, reservas ni informes.
--     Volver a encenderlo sigue siendo una decisión de Damián (se revisa el motivo y se pone 'encendido').
--
--   cron_latido(cron)  anota la última vez que Cloudflare disparó un cron del Worker. En agosto esos cron no
--     disparaban en esta cuenta (ver wrangler.jsonc); con esto se sabe, sin mirar el panel, si ya funcionan.
-- Aditivo: dos funciones nuevas y dos ajustes; nada se borra.

insert into ajustes (clave, valor, nota) values
  ('ventas_freno_ultimo', '', 'Último apagado automático de las ventas por WhatsApp: fecha, motivo y cifras. Vacío = nunca. 0163.'),
  ('cf_cron_ultimo', '', 'Última vez que Cloudflare disparó un cron del Worker tumbao-caja (hora y expresión). Vacío = nunca. 0163.'),
  ('cf_cron_total', '0', 'Cuántas veces ha disparado un cron del Worker desde que existe el latido. 0163.')
on conflict (clave) do nothing;

create or replace function public.ventas_freno_revisar(p_calidad text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  hoy date := (now() at time zone 'America/Bogota')::date;
  v_aperturas int; v_fallos int; v_bajas int; v_pago int;
  v_motivo text;
  v_cifras jsonb;
begin
  if coalesce((select valor from ajustes where clave = 'wa_ventas'), 'apagado') <> 'encendido' then
    return jsonb_build_object('accion', 'ninguna', 'motivo', 'ya_apagado');
  end if;

  select count(*) filter (where estado = 'enviado'),
         count(*) filter (where entrega = 'failed' or estado = 'fallido'),
         count(*) filter (where coalesce(entrega_error, '') like '131042%')
    into v_aperturas, v_fallos, v_pago
    from wa_avisos
   where plantilla in ('ventas_apertura', 'ventas_horario', 'encuesta_regreso')
     and (creado_at at time zone 'America/Bogota')::date = hoy;

  select count(*) into v_bajas from wa_bajas where (creado_at at time zone 'America/Bogota')::date = hoy;

  v_cifras := jsonb_build_object('aperturas', v_aperturas, 'fallos', v_fallos, 'bajas', v_bajas,
                                 'calidad', coalesce(p_calidad, 'sin_dato'));

  if coalesce(p_calidad, 'GREEN') <> 'GREEN' then
    v_motivo := 'Meta bajó la calidad del número a ' || p_calidad;
  elsif v_pago > 0 then
    v_motivo := 'Meta devolvió el error 131042 (pago pendiente a Meta)';
  elsif v_aperturas >= 10 and v_bajas * 100.0 / v_aperturas > 8 then
    v_motivo := 'pidieron no recibir mensajes ' || v_bajas || ' de ' || v_aperturas || ' aperturas de hoy (más del 8 %)';
  elsif v_aperturas >= 20 and v_fallos * 100.0 / v_aperturas > 25 then
    v_motivo := 'fallaron ' || v_fallos || ' de ' || v_aperturas || ' entregas de hoy (más del 25 %)';
  end if;

  if v_motivo is null then
    return jsonb_build_object('accion', 'ninguna', 'cifras', v_cifras);
  end if;

  update ajustes set valor = 'apagado', updated_at = now() where clave = 'wa_ventas';
  update ajustes set valor = to_char(now() at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI') || ' · ' || v_motivo || ' · ' || v_cifras::text,
                     updated_at = now()
   where clave = 'ventas_freno_ultimo';
  return jsonb_build_object('accion', 'apagado', 'motivo', v_motivo, 'cifras', v_cifras);
end;
$$;
revoke all on function public.ventas_freno_revisar(text) from public, anon, authenticated;
grant execute on function public.ventas_freno_revisar(text) to service_role;

create or replace function public.cron_latido(p_cron text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update ajustes set valor = to_char(now() at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS') || ' · ' || coalesce(left(p_cron, 40), '?'),
                     updated_at = now()
   where clave = 'cf_cron_ultimo';
  update ajustes set valor = (coalesce(nullif(valor, ''), '0')::int + 1)::text, updated_at = now()
   where clave = 'cf_cron_total';
end;
$$;
revoke all on function public.cron_latido(text) from public, anon, authenticated;
grant execute on function public.cron_latido(text) to service_role;
