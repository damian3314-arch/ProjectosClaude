-- 0192 · La plata de una mensualidad pagada por la página se une a su solicitud (valor + nombre + ventana de tiempo),
-- se marca consumida y deja de salir como «pago sin asignar / por validar». Corre cada 2 minutos.
-- Entra a caja el día que Luisa la registra en AdminGym; el aviso a recepción sale a los 5 minutos de estar pagada.
-- (Aplicada en vivo; cuerpo vigente: mensualidad_cruzar_pagos() y alertas_recepcion().)
select cron.schedule('tumbao-mensualidad-cruce', '*/2 * * * *', 'select public.mensualidad_cruzar_pagos()');
