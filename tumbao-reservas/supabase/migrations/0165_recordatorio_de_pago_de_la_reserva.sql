-- 0165 · Recordatorio de pago a quien reservó una clase suelta y no ha pagado
--
-- Damián (9 oct, «sí»): en 30 días, 64 reservas de clase suelta se vencieron sin pago (18 % de las de gente nueva,
-- unos $960.000). Un WhatsApp a los ~8 minutos —«tu cupo sigue guardado, completa el pago»— cuesta unos $3
-- (plantilla de UTILIDAD) y se paga solo con que recupere una de cada diez.
--
-- reserva_recordar_pago() la corre pg_cron cada 2 minutos de 6 am a 10 pm (Bogotá). Encola un aviso a quien:
--   · tiene una reserva suelta en pendiente_pago creada hace entre 7 y 12 minutos, con el cupo todavía guardado
--     (expira_en a más de un minuto) y la clase por venir;
--   · tiene celular válido, no pidió SALIR (wa_bajas) y no es dueño;
--   · no tiene ya esa clase confirmada, ni otro recordatorio hoy (uno por persona y por día) ni uno por esa reserva.
-- El aviso vence cuando vence el cupo: si no alcanzó a salir, no sale. Es transaccional (tipo 'recordatorio_pago'),
-- no entra en las reglas de mercadeo, y no lleva oferta ni descuento.
--
-- Nace APAGADO (ajustes.wa_recordar_pago = 'apagado'): se enciende cuando Meta apruebe la plantilla
-- reserva_pendiente_pago (el Worker la crea en /wa/plantillas). Se apaga poniendo 'apagado'.

insert into ajustes (clave, valor, nota) values
  ('wa_recordar_pago', 'apagado', 'Recordatorio por WhatsApp a quien reservó y no ha pagado (a los ~8 min, una vez). encendido / apagado. 0165.')
on conflict (clave) do nothing;

create or replace function public.reserva_recordar_pago()
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare n int := 0;
begin
  if coalesce((select valor from ajustes where clave = 'wa_recordar_pago'), 'apagado') <> 'encendido' then
    return 0;
  end if;

  with c as (
    select r.id, r.clase_id,
           right(regexp_replace(coalesce(r.telefono, ''), '\D', '', 'g'), 10) tel,
           initcap(split_part(btrim(r.nombre), ' ', 1)) nombre,
           cl.fecha_hora, r.expira_en
      from reservas r
      join clases cl on cl.id = r.clase_id
     where r.estado = 'pendiente_pago' and r.tipo = 'suelta'
       and r.created_at between now() - interval '12 minutes' and now() - interval '7 minutes'
       and (r.expira_en is null or r.expira_en > now() + interval '1 minute')
       and cl.fecha_hora > now()
  ), elegibles as (
    select distinct on (c.tel) c.*
      from c
     where c.tel ~ '^3[0-9]{9}$'
       and not wa_es_dueno(c.tel)
       and not exists (select 1 from wa_bajas b where b.telefono = c.tel)
       and not exists (select 1 from reservas h
                        where h.clase_id = c.clase_id and h.estado = 'confirmada'
                          and right(regexp_replace(coalesce(h.telefono, ''), '\D', '', 'g'), 10) = c.tel)
       and not exists (select 1 from wa_avisos a
                        where a.telefono = c.tel and a.tipo = 'recordatorio_pago'
                          and (a.creado_at at time zone 'America/Bogota')::date = (now() at time zone 'America/Bogota')::date)
     order by c.tel, c.fecha_hora
  ), ins as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'recordatorio_pago:' || e.id, 'recordatorio_pago', e.tel, 'reserva_pendiente_pago',
           jsonb_build_array(coalesce(nullif(e.nombre, ''), 'amigo(a)'),
             'el ' || wa_fecha_texto((e.fecha_hora at time zone 'America/Bogota')::date) || ' a las '
                   || wa_hora_texto((e.fecha_hora at time zone 'America/Bogota')::time)),
           coalesce(e.expira_en, now() + interval '10 minutes')
      from elegibles e
    on conflict (clave) do nothing
    returning 1)
  select count(*) into n from ins;
  return n;
end;
$$;
revoke all on function public.reserva_recordar_pago() from public, anon, authenticated;
grant execute on function public.reserva_recordar_pago() to service_role;

-- Cada 2 minutos de 6:00 a 21:58 Bogotá (11:00-02:58 UTC); con el ajuste apagado no hace nada.
do $cron$
begin
  perform cron.unschedule('tumbao-recordar-pago');
exception when others then null;
end
$cron$;
select cron.schedule('tumbao-recordar-pago', '*/2 11-23,0-2 * * *', 'select public.reserva_recordar_pago()');
