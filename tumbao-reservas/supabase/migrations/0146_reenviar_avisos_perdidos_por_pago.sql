-- 0146 · Reenviar los avisos que fallaron por el pago de Meta (error 131042)
--
-- Del 4 al 5 de octubre Meta rechazó todos los envíos («Business eligibility payment issue»: un saldo
-- pendiente de ~$10.000 en la cuenta de WhatsApp). El Worker los dio por «enviados» y nada se reintenta
-- solo, así que se perdieron avisos que a los clientes sí les importan: renovaciones, la tiquetera
-- comprada, el seguimiento y el «¿cómo te fue?».
--
-- Esta función los vuelve a encolar UNA vez (clave original + ':r1'), pero solo si:
--   · hoy es hora de escribir (lun–vie 9:00–19:00, sábado hasta la 1 pm; nunca domingo ni festivo),
--   · WhatsApp ya está entregando (el último entregado es posterior al último fallo 131042),
--   · el aviso es de los últimos 4 días y de un tipo que sigue sirviendo,
--   · la persona no pidió salir y, si era una renovación, todavía no renovó.
-- No toca reservas ya pasadas, informes ni campañas de mercadeo (esas se reabren por su lado).
-- Corre de lunes a sábado a las 9:35 am de Bogotá; si no hay nada por reenviar no hace nada.

create or replace function public.wa_reenviar_fallidos_de_pago()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  ahora timestamp := now() at time zone 'America/Bogota';
  hoy date := ahora::date;
  v_dow int := extract(isodow from ahora)::int;
  v_fin time := case when v_dow = 6 then time '13:00' else time '19:00' end;
  v_n int := 0;
begin
  if v_dow = 7 or exists (select 1 from festivos where fecha = hoy)
     or ahora::time < time '09:00' or ahora::time >= v_fin then
    return jsonb_build_object('ok', true, 'motivo', 'fuera_de_hora');
  end if;
  -- ¿Ya entrega WhatsApp otra vez?
  if not coalesce((select max(enviado_at) from wa_avisos where entrega in ('delivered', 'read'))
                  > (select coalesce(max(enviado_at), '-infinity'::timestamptz) from wa_avisos
                      where entrega = 'failed' and entrega_error like '131042%'), false) then
    return jsonb_build_object('ok', true, 'motivo', 'whatsapp_aun_no_entrega');
  end if;

  with src as (
    select a.* from wa_avisos a
     where a.entrega = 'failed' and a.entrega_error like '131042%'
       and a.creado_at > now() - interval '4 days'
       and a.plantilla in ('mensualidad_vencimiento', 'mensualidad_recordatorio', 'tiquetera_lista',
                           'seguimiento_encanto', 'como_te_fue')
       and not exists (select 1 from wa_bajas b where b.telefono = a.telefono)
       and not exists (select 1 from wa_avisos r where r.clave = a.clave || ':r1')
       and (a.plantilla not in ('mensualidad_vencimiento', 'mensualidad_recordatorio')
            or not exists (select 1 from membresias m
                            where right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10) = a.telefono
                              and m.fin >= hoy + 10))
  ), ins as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, idioma, datos, variables, vence_at)
    select s.clave || ':r1', s.tipo, s.telefono, s.plantilla, s.idioma, s.datos, s.variables, now() + interval '8 hours'
      from src s
    on conflict (clave) do nothing
    returning 1
  )
  select count(*) into v_n from ins;
  return jsonb_build_object('ok', true, 'reencolados', v_n);
exception when others then
  raise warning 'wa_reenviar_fallidos_de_pago: %', sqlerrm;
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;
revoke all on function public.wa_reenviar_fallidos_de_pago() from public, anon, authenticated;

select cron.schedule('tumbao-reenvio-fallidos-pago', '35 14 * * 1-6', 'select public.wa_reenviar_fallidos_de_pago()');
