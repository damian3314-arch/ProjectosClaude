-- 0162 · La alerta «dijeron que pagaron y el pago no aparece» espera 30 minutos, no 15
--
-- Damián (9 oct): «están llegando mensajes de que no se completa la validación, la reserva y el pago».
--
-- QUÉ PASABA (medido el 9 oct contra la base y el correo de Bancolombia)
--   · El sistema estaba sano: tumbaobaila.com y Supabase respondían, y cada pago se registró a los pocos segundos
--     de llegar el correo del banco (la ingesta de n8n no falló).
--   · Lo que falló fue el banco: los correos de «recibiste una transferencia» llegaron 15, 22, 25 y 45 minutos
--     después de la transferencia (p. ej. Danna: pagó 12:32, el correo llegó 12:57). Mientras tanto el cliente ya
--     había marcado «ya pagué» y a los 15 minutos alertas_recepcion() le avisaba a recepción que el pago no aparecía.
--     En cuanto llegaba el correo, la reserva se confirmaba sola (las 4 de ese día quedaron confirmadas).
--
-- CÓMO QUEDA
--   · La alerta de «ya pagué» sin pago espera 30 minutos (antes 15) y dice que el banco a veces tarda.
--   · Lo demás no cambia: pagos que llegaron sin dueño (10 min), tiqueteras (15 min) y mensualidades (1 h).

do $mig$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.alertas_recepcion()'::regprocedure);
  if position('Si pagaron hace poco, el banco a veces tarda en avisar' in v_def) > 0 then return; end if;  -- ya aplicada
  if position('x.created_at between now() - interval ''48 hours'' and now() - interval ''15 minutes''' in v_def) = 0
     or position('Pídeles el comprobante o revisa «Por validar».' in v_def) = 0 then
    raise exception 'alertas_recepcion: no encuentro el texto a cambiar';
  end if;
  v_def := replace(v_def, 'x.created_at between now() - interval ''48 hours'' and now() - interval ''15 minutes''',
                          'x.created_at between now() - interval ''48 hours'' and now() - interval ''30 minutes''');
  v_def := replace(v_def, 'Pídeles el comprobante o revisa «Por validar».',
                          'Pídeles el comprobante o revisa «Por validar». Si pagaron hace poco, el banco a veces tarda en avisar: cuando llegue, la reserva se confirma sola.');
  execute v_def;
end
$mig$;
