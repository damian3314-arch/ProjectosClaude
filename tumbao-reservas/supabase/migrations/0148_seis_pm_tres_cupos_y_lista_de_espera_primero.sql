-- 0148 · 6 pm: tres cupos en la página, la lista de espera primero; sin aviso de tiquetera por vencer
--
-- Damián (5 oct, noche):
--   · «El aviso de tiquetera por vencer no es necesario»: wa_tiquetera_vence = 'apagado' y el cron
--     tumbao-tiquetera-vence inactivo (la función queda, sin uso).
--   · «En la página solo deja 3 cupos de mensualidad para las 6 pm; a la persona de la lista de espera
--     hay que avisarle primero para que pague; los otros cupos se manejan internamente»:
--       - mensualidad_topes 18:00 = 20 (17 ocupadas hoy + 3 a la venta; el tope interno sigue en 23);
--       - ventas_cupos() usa para las 6 pm lo MENOR entre el tope interno y lo que se vende por la página;
--       - ventas_gancho2 con origen 'lista_espera' («Se liberó un cupo… eres la primera persona…»);
--       - a la primera de la fila de las 6 pm (Aleidys López) se le abrió una conversación de ventas y se
--         encoló la apertura (queda retenida por la guardia de horario hasta las 9:00 am del 6 oct,
--         antes de que arranque la ronda de ventas de las 10:00).
-- (Se aplicó con las instrucciones SQL de esta conversación; este archivo es el registro.)

update public.ajustes set valor = 'apagado' where clave = 'wa_tiquetera_vence';
update public.ajustes set valor = '07:00=35,18:00=20,19:00=0' where clave = 'mensualidad_topes';
-- select cron.alter_job((select jobid from cron.job where jobname = 'tumbao-tiquetera-vence'), active := false);
-- ventas_cupos() y ventas_gancho2(): ver el cuerpo vigente con \sf en la base.
