-- 0137 · Recordatorio por WhatsApp el mismo día de la clase, ~3 horas antes
--
-- Hito del Plan Tumbao (2 oct): medir quién reserva y no llega.
-- Resultado de las últimas 4 semanas (clases ya terminadas, reservas confirmadas
-- cruzadas con asistencias por reserva_id): 411 reservas, 59 no llegaron (14,4 %).
-- Las SUELTAS: 348 reservas, 38 no llegaron = 10,9 % (más del 10 % que se había
-- fijado como umbral). Por horario (sueltas): 7 am 20 %, 8 am 16 %, 9 am 10,5 %,
-- 6 pm 11 %, 7 pm 6 %. Por eso se construye el recordatorio.
--
-- Cómo funciona
--   · Cada hora (minuto 5) recordatorios_de_clase() mira las reservas CONFIRMADAS
--     de clases que empiezan en las próximas ~3 horas y todavía no tienen aviso.
--   · Hora del recordatorio = 3 horas antes de la clase, pero nunca antes de las
--     6:30 am de Bogotá (a una clase de las 8 am se le avisa a las 6:30).
--   · UN aviso por persona y clase: clave 'recordatorio:<clase>:<celular>' (la cola
--     se niega a repetir). Un aviso por celular aunque haya reservado varios cupos.
--   · Se salta: a quien pidió SALIR, a los dueños (se prueban a mano), a quien
--     confirmó su reserva hace menos de 2 horas (ya recibió su confirmación) y a
--     las clases que ya empezaron.
--   · Plantilla 'recordatorio_clase' (UTILITY): nombre, hora y clase. Dice que si
--     no puede venir avise al 301 783 3550 para liberar el cupo.
--   · Interruptor: ajustes.wa_recordatorio_clase. NACE APAGADO: se prende cuando
--     Meta apruebe la plantilla (si se mandara antes, Meta la rechaza y quema un
--     envío). Apagarlo detiene todo.

insert into ajustes (clave, valor, nota) values
  ('wa_recordatorio_clase', 'apagado',
   'encendido = recordatorio por WhatsApp ~3 h antes de cada clase reservada (0137). Prender solo cuando la plantilla recordatorio_clase esté APROBADA en Meta.')
on conflict (clave) do nothing;

create or replace function public.recordatorios_de_clase()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_n int := 0;
begin
  if coalesce((select valor from ajustes where clave = 'wa_recordatorio_clase'), 'apagado') <> 'encendido' then
    return jsonb_build_object('ok', true, 'activo', false);
  end if;

  with base as (
    select distinct on (v.tel)
           v.tel, v.nombre, c.id as clase_id, c.nombre as clase, c.fecha_hora,
           v.confirmada_at
      from (
        select right(regexp_replace(coalesce(r.telefono, ''), '\D', '', 'g'), 10) as tel,
               initcap(split_part(btrim(r.nombre), ' ', 1)) as nombre,
               r.clase_id, r.updated_at as confirmada_at, r.created_at
          from reservas r
         where r.estado = 'confirmada'
      ) v
      join clases c on c.id = v.clase_id
     where c.fecha_hora > now() + interval '30 minutes'
       and c.fecha_hora <= now() + interval '3 hours 30 minutes'
       -- hora de aviso = 3 h antes, pero nunca antes de las 6:30 am de Bogotá
       and now() >= greatest(
             c.fecha_hora - interval '3 hours',
             (date_trunc('day', c.fecha_hora at time zone 'America/Bogota') + interval '6 hours 30 minutes')
               at time zone 'America/Bogota')
       and v.confirmada_at < now() - interval '2 hours'
       and v.tel ~ '^3[0-9]{9}$'
     order by v.tel, c.fecha_hora, v.created_at
  ), enc as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'recordatorio:' || b.clase_id || ':' || b.tel, 'recordatorio', b.tel, 'recordatorio_clase',
           jsonb_build_array(coalesce(nullif(b.nombre, ''), 'amigo(a)'),
                             lower(to_char(b.fecha_hora at time zone 'America/Bogota', 'FMHH12:MI am')),
                             coalesce(nullif(btrim(b.clase), ''), 'Tu clase')),
           b.fecha_hora - interval '20 minutes'
      from base b
     where not wa_es_dueno(b.tel)
       and not exists (select 1 from wa_bajas x where x.telefono = b.tel)
    on conflict (clave) do nothing
    returning 1
  )
  select count(*) into v_n from enc;

  return jsonb_build_object('ok', true, 'activo', true, 'encolados', v_n);
exception when others then
  raise warning 'recordatorios_de_clase: %', sqlerrm;
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;
revoke all on function public.recordatorios_de_clase() from public, anon, authenticated;

do $cron$
begin
  perform cron.unschedule('tumbao-recordatorio-clase');
exception when others then null;
end
$cron$;
select cron.schedule('tumbao-recordatorio-clase', '5 * * * *', 'select public.recordatorios_de_clase()');
