-- 0131 · Los informes diarios pasan a las 8:00 am y las 9:00 pm
--
-- Damián (1 oct): el debrief de la mañana y el cierre de la noche, que salían a
-- las 6:00 am y 10:00 pm (0105), ahora a las 8:00 am y 9:00 pm de Bogotá.
-- pg_cron trabaja en UTC y Bogotá es UTC-5 todo el año (sin horario de verano):
--   8:00 am Bogotá = 13:00 UTC      9:00 pm Bogotá = 02:00 UTC (del día siguiente)
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'tumbao-informe-manana'), schedule := '0 13 * * *');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'tumbao-informe-noche'),  schedule := '0 2 * * *');
update public.ajustes
   set nota = 'A dónde toca pg_cron para los informes de las 8 am y las 9 pm. 0105; horas cambiadas en 0131.'
 where clave = 'wa_informe_url';
