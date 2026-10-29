-- 0122 · Aviso automático de renovación de mensualidad (octubre en adelante)
--
-- La campaña de cierre (0106/0107) cubrió a quienes vencían del 25 sep al
-- 2 oct con 'mensualidad_vencimiento' (lun 28) y 'mensualidad_recordatorio'
-- (mié 30). Esto la deja andando sola para todos los vencimientos desde el
-- 3 de octubre, con las MISMAS plantillas (ya aprobadas):
--
--   · 3 días antes del vencimiento  → mensualidad_vencimiento
--   · el día que vence              → mensualidad_recordatorio
--
-- Cómo se cuida a la gente:
--   · Solo se avisa por la mensualidad MÁS RECIENTE de cada persona: quien
--     ya renovó (su fin es posterior) no recibe nada por la vieja.
--   · Un aviso por (celular, vencimiento, momento): la clave
--     'renovacion:<cel>:<fin>:<3|0>' hace que el sistema se niegue a repetirlo.
--   · Ley 2300: ni domingos ni festivos. Lo que caiga en un día sin envío
--     se pone al día en la siguiente corrida (ventanas de 1 a 3 días antes y
--     de 0 a 2 días después), sin duplicar nada por la clave.
--   · Solo celulares válidos, sin el dueño y sin quienes pidieron SALIR.
--   · Solo planes de verdad mensuales (>= 20 días): una mensualidad recién
--     comprada no recibe un «se te vence» al día siguiente.
--
-- Corre a las 9:15 am de Bogotá (14:15 UTC), después de la importación de
-- membresías de las 8 am. Apagable con ajustes.wa_renovacion_auto.

insert into ajustes (clave, valor, nota)
values ('wa_renovacion_auto', 'encendido',
        'Aviso automático de renovación de mensualidad: 3 días antes y el día que vence (0122). Poner apagado para detenerlo.')
on conflict (clave) do nothing;

create or replace function public.renovacion_automatica()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  -- `tumbao.dia` solo lo usan las pruebas para simular otro día.
  hoy date := coalesce(nullif(current_setting('tumbao.dia', true), '')::date,
                       (now() at time zone 'America/Bogota')::date);
  desde_oct3 constant date := date '2026-10-03';
  n_venc int := 0;
  n_rec  int := 0;
begin
  if coalesce((select valor from ajustes where clave = 'wa_renovacion_auto'), 'encendido')
     <> 'encendido' then
    return jsonb_build_object('ok', true, 'activo', false);
  end if;
  -- Ley 2300: nada de mensajes de mercadeo domingos ni festivos.
  if extract(isodow from hoy) = 7 or exists (select 1 from festivos where fecha = hoy) then
    return jsonb_build_object('ok', true, 'activo', true, 'motivo', 'domingo_o_festivo');
  end if;

  with ultima as (
    select distinct on (right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10))
           right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) as tel,
           initcap(split_part(btrim(afiliado), ' ', 1)) as nombre, hora, inicio, fin
      from membresias
     order by right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10), fin desc),
  elegibles as (
    select u.*
      from ultima u
     where u.tel ~ '^3[0-9]{9}$'
       and u.fin >= desde_oct3
       and (u.fin - u.inicio) >= 20
       and not wa_es_dueno(u.tel)
       and not exists (select 1 from wa_bajas b where b.telefono = u.tel)),
  venc as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'renovacion:' || e.tel || ':' || e.fin || ':3', 'renovacion', e.tel,
           coalesce((select valor::jsonb->>'renovacion' from ajustes where clave = 'cierre_sep_plantillas'),
                    'mensualidad_vencimiento'),
           jsonb_build_array(coalesce(nullif(e.nombre, ''), 'amigo(a)'), wa_hora_texto(e.hora),
                             wa_fecha_texto(e.fin)),
           now() + interval '10 hours'
      from elegibles e
     where e.fin between hoy + 1 and hoy + 3
    on conflict (clave) do nothing
    returning 1),
  rec as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'renovacion:' || e.tel || ':' || e.fin || ':0', 'renovacion', e.tel,
           coalesce((select valor::jsonb->>'renovacion_ultimo' from ajustes where clave = 'cierre_sep_plantillas'),
                    'mensualidad_recordatorio'),
           jsonb_build_array(coalesce(nullif(e.nombre, ''), 'amigo(a)'), wa_hora_texto(e.hora),
                             wa_fecha_texto(e.fin)),
           now() + interval '10 hours'
      from elegibles e
     where e.fin between hoy - 2 and hoy
    on conflict (clave) do nothing
    returning 1)
  select (select count(*) from venc), (select count(*) from rec) into n_venc, n_rec;

  if current_setting('tumbao.dia', true) is null or current_setting('tumbao.dia', true) = '' then
    insert into ajustes (clave, valor, nota)
    values ('renovacion_auto_ultimo',
            n_venc || ' avisos de 3 días y ' || n_rec || ' del día, el '
              || to_char(now() at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI'),
            'Última corrida del aviso automático de renovación (0122).')
    on conflict (clave) do update set valor = excluded.valor, updated_at = now();
  end if;
  return jsonb_build_object('ok', true, 'activo', true, 'tres_dias', n_venc, 'del_dia', n_rec);
exception when others then
  raise warning 'renovacion_automatica: %', sqlerrm;
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;
revoke all on function public.renovacion_automatica() from public, anon, authenticated;

-- 9:15 am de Bogotá = 14:15 UTC, todos los días (la función se salta
-- domingos y festivos por su cuenta).
do $cron$
begin
  perform cron.unschedule('tumbao-renovacion-auto');
exception when others then null;
end
$cron$;
select cron.schedule('tumbao-renovacion-auto', '15 14 * * *',
                     'select public.renovacion_automatica()');
