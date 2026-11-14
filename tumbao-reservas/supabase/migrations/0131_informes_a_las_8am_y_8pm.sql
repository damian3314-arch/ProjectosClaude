-- 0131 · Los informes diarios pasan a las 8:00 am y las 8:00 pm
--
-- Damián (1 oct): el debrief de la mañana y el cierre de la noche, que salían a
-- las 6:00 am y 10:00 pm (0105), ahora a las 8:00 am y 8:00 pm de Bogotá.
-- (Primero se pasó el cierre a las 9 pm y enseguida se corrigió a las 8 pm.)
-- pg_cron trabaja en UTC y Bogotá es UTC-5 todo el año (sin horario de verano):
--   8:00 am Bogotá = 13:00 UTC      8:00 pm Bogotá = 01:00 UTC (del día siguiente)
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'tumbao-informe-manana'), schedule := '0 13 * * *');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'tumbao-informe-noche'),  schedule := '0 1 * * *');
update public.ajustes
   set nota = 'A dónde toca pg_cron para los informes de las 8 am y las 8 pm. 0105; horas cambiadas en 0131.'
 where clave = 'wa_informe_url';
