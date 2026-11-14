-- 0139 · La lista de mensualidad se limpia sola cuando la persona ya está en AdminGym
--
-- Damián (2 oct): «varios de esos ya se activaron en AdminGym y se procesaron, y
-- siguen apareciendo en el listado.» La lista de Caja solo se vaciaba cuando
-- recepción pulsaba «atendida» a mano; si ya la habían registrado en AdminGym y se
-- olvidaban de pulsar, la solicitud se quedaba pendiente.
--
-- mensualidad_cerrar_registradas() cruza las solicitudes pendientes (pagada,
-- esperando_pago, lista_espera) con las membresías que importa AdminGym: si la
-- persona (por celular o por cédula) ya tiene un plan vigente que EMPEZÓ desde un
-- par de días antes de su solicitud, la solicitud pasa a 'atendida' con una nota
-- «Cerrada sola». Cuenta cualquier horario (quien pagó por 6 pm y se registró a
-- las 7 am ya no espera). Corre cada hora (minuto 40); las membresías se importan
-- a las 8 am, así que lo que recepción registre durante el día sale de la lista al
-- día siguiente. No toca dinero ni escribe a nadie.

create or replace function public.mensualidad_cerrar_registradas()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare n int := 0;
begin
  with ya as (
    select distinct on (s.id) s.id, m.hora, m.inicio, m.fin
      from mensualidad_solicitudes s
      join membresias m on (
            (length(regexp_replace(coalesce(s.celular, ''), '\D', '', 'g')) >= 10
             and right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10) = right(regexp_replace(coalesce(s.celular, ''), '\D', '', 'g'), 10))
         or (nullif(btrim(coalesce(m.documento, '')), '') is not null and btrim(m.documento) = btrim(coalesce(s.documento, ''))))
     where s.estado in ('pagada', 'esperando_pago', 'lista_espera')
       and m.fin >= (now() at time zone 'America/Bogota')::date
       and m.inicio >= (s.creado_at at time zone 'America/Bogota')::date - 2
     order by s.id, m.inicio desc),
  cerradas as (
    update mensualidad_solicitudes s
       set estado = 'atendida', atendida_at = now(),
           nota = coalesce(nullif(s.nota, '') || ' · ', '')
                  || 'Cerrada sola: ya aparece en AdminGym (' || to_char(ya.hora, 'HH24:MI') || ', del '
                  || to_char(ya.inicio, 'DD/MM') || ' al ' || to_char(ya.fin, 'DD/MM') || ').'
      from ya where ya.id = s.id
    returning 1)
  select count(*) into n from cerradas;
  return n;
end;
$$;
revoke all on function public.mensualidad_cerrar_registradas() from public, anon, authenticated;

do $cron$
begin
  perform cron.unschedule('tumbao-mensualidad-registradas');
exception when others then null;
end
$cron$;
select cron.schedule('tumbao-mensualidad-registradas', '40 * * * *', 'select public.mensualidad_cerrar_registradas()');
