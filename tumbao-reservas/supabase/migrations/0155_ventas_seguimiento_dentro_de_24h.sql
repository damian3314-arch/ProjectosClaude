-- 0155 · Ventas por WhatsApp: seguimiento dentro de las 24 h a quien mostró interés y se quedó callada
--
-- Damián (7 oct): «lo que importa es que la gente compre». Hoy la conversación termina cuando el bot manda el
-- enlace: de 10 personas con interés alto en una semana, nadie volvía a escribirles. Una persona que escribió
-- hace menos de 24 h tiene la ventana de servicio abierta: un mensaje de texto cuesta $0.
--
-- ventas_seguimientos_tomar(): cada 30 minutos, en horario (L-V 9-19, sábado 9-13, ni domingos ni festivos),
-- devuelve a quien:
--   · está conversando con interés alto o medio y no ha comprado ni cerrado;
--   · recibió la última respuesta nuestra hace entre 3 y 20 horas y escribió hace menos de 22 h (ventana abierta);
--   · no ha tenido ya un seguimiento (oferta.seguimiento_at; UNO por conversación);
--   · no tiene mensualidad vigente, ni tiquetera pagada ni solicitud de mensualidad desde que se abrió el chat;
--   · no pidió salir y no es dueño.
-- y la marca en el mismo paso (no se repite aunque dos corridas se pisen). El texto lo manda el Worker
-- (/wa/ventas-seguimiento): fijo, sin cifras ni promesas. Se apaga con ajustes.wa_ventas_seguimiento = 'apagado'.

insert into ajustes (clave, valor, nota) values
  ('wa_ventas_seguimiento', 'encendido', 'Seguimiento a las 3-20 h a quien mostró interés en una conversación de ventas y se quedó callada, dentro de la ventana de 24 h (gratis). 0155.')
on conflict (clave) do nothing;

insert into ajustes (clave, valor, nota)
select 'wa_ventas_seguimiento_url', replace(valor, '/wa/ventas', '/wa/ventas-seguimiento'), 'Worker que envía el seguimiento de ventas. 0155.'
  from ajustes where clave = 'wa_ventas_url'
on conflict (clave) do nothing;

create or replace function public.ventas_seguimientos_tomar(p_limite int default 5)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  ahora timestamptz := now();
  hoy date := (now() at time zone 'America/Bogota')::date;
  t time := (now() at time zone 'America/Bogota')::time;
  dow int := extract(isodow from (now() at time zone 'America/Bogota')::date);
  v_out jsonb;
begin
  if coalesce((select valor from ajustes where clave = 'wa_ventas_seguimiento'), 'encendido') <> 'encendido' then
    return '[]'::jsonb;
  end if;
  -- Ley 2300: sin mercadeo domingos ni festivos; sábados hasta la 1 pm.
  if dow = 7 or exists (select 1 from festivos where fecha = hoy) then return '[]'::jsonb; end if;
  if t < time '09:00' or t >= (case when dow = 6 then time '13:00' else time '19:00' end) then return '[]'::jsonb; end if;

  with due as (
    select c.id
      from ventas_chats c
     where c.estado = 'conversando'
       and c.interes in ('alto', 'medio')
       and coalesce(c.resultado, '') in ('', 'enlace_enviado')
       and coalesce(c.oferta ->> 'seguimiento_at', '') = ''
       and c.telefono ~ '^3[0-9]{9}$'
       and not wa_es_dueno(c.telefono)
       and not exists (select 1 from wa_bajas b where b.telefono = c.telefono)
       -- la última palabra fue nuestra, y la ventana de 24 h sigue abierta
       and (select m.direccion from wa_mensajes m where right(m.telefono, 10) = c.telefono order by m.id desc limit 1) = 'saliente'
       and (select max(m.creado_at) from wa_mensajes m where right(m.telefono, 10) = c.telefono and m.direccion = 'saliente')
             between ahora - interval '20 hours' and ahora - interval '3 hours'
       and (select max(m.creado_at) from wa_mensajes m where right(m.telefono, 10) = c.telefono and m.direccion = 'entrante')
             >= ahora - interval '22 hours'
       -- si ya compró o está pagando, no se le insiste
       and not exists (select 1 from tiqueteras tq
                        where right(regexp_replace(tq.telefono, '\D', '', 'g'), 10) = c.telefono and tq.pagado_en >= c.abierta_at)
       and not exists (select 1 from membresias m
                        where right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10) = c.telefono and m.fin >= hoy)
       and not exists (select 1 from mensualidad_solicitudes s
                        where right(regexp_replace(coalesce(s.celular, ''), '\D', '', 'g'), 10) = c.telefono
                          and s.estado in ('esperando_pago', 'pagada') and s.creado_at >= c.abierta_at)
     order by c.ultima_at
     limit greatest(p_limite, 0)
  ), marc as (
    update ventas_chats c
       set oferta = coalesce(c.oferta, '{}'::jsonb) || jsonb_build_object('seguimiento_at', ahora)
      from due
     where c.id = due.id
    returning c.id, c.telefono, c.nombre, c.objetivo, c.oferta
  )
  select coalesce(jsonb_agg(jsonb_build_object('chat', id, 'telefono', telefono, 'nombre', nombre,
                                               'objetivo', objetivo, 'hora', oferta ->> 'hora')), '[]'::jsonb)
    into v_out from marc;
  return v_out;
end;
$$;
revoke all on function public.ventas_seguimientos_tomar(int) from public, anon, authenticated;

-- Quien despierta al Worker cada 30 minutos (pg_net, igual que wa_llamar_agente).
create or replace function public.ventas_seguimientos_llamar()
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_url text;
begin
  select valor into v_url from ajustes where clave = 'wa_ventas_seguimiento_url';
  if coalesce(v_url, '') = '' then return; end if;
  perform net.http_post(url := v_url, body := '{}'::jsonb,
                        headers := '{"Content-Type": "application/json"}'::jsonb,
                        timeout_milliseconds := 60000);
exception when others then
  raise warning 'ventas_seguimientos_llamar: %', sqlerrm;
end;
$$;
revoke all on function public.ventas_seguimientos_llamar() from public, anon, authenticated;

do $cron$
begin
  perform cron.unschedule('tumbao-ventas-seguimiento');
exception when others then null;
end
$cron$;
-- cada 30 minutos de 9:00 a 18:30 Bogotá (14:00-23:30 UTC), lunes a sábado; la función filtra festivos y el cierre de 1 pm del sábado
select cron.schedule('tumbao-ventas-seguimiento', '*/30 14-23 * * 1-6', 'select public.ventas_seguimientos_llamar()');
