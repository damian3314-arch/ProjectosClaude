-- 0185 · Horarios reales de las clases + «¿llegó un mensaje más nuevo de esta persona?»
--
-- Damián (14 oct): lunes a viernes 7 am, 6 pm y 7 pm. Martes y jueves Rumba básica a las 5 pm. Sábados Rumba terapia
-- a las 8 am y 9 am. Timba y el asistente no tenían los horarios y mandaban a recepción a quien preguntaba por ellos
-- (una alumna a punto de volver preguntó por los sábados y por los martes en la mañana).
--
-- Y los mensajes seguidos: cuando alguien escribía dos o tres mensajes en el mismo segundo, cada uno despertaba a Timba por
-- separado y la persona recibía tres respuestas. wa_hay_mensaje_mas_nuevo() deja que el Worker espere unos segundos y
-- conteste solo el último. Solo lee, no cambia nada.
--
-- OJO al aplicarla con la herramienta de Supabase: un punto y coma DENTRO de un texto la deja colgada. Por eso los
-- horarios van separados con puntos.

create or replace function public.wa_hay_mensaje_mas_nuevo(p_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from wa_mensajes a
      join wa_mensajes b on b.telefono = a.telefono
     where a.id = p_id
       and b.direccion = 'entrante'
       and b.id > a.id
       and b.creado_at > now() - interval '2 minutes');
$$;

revoke execute on function public.wa_hay_mensaje_mas_nuevo(bigint) from public, anon, authenticated;
grant execute on function public.wa_hay_mensaje_mas_nuevo(bigint) to service_role;

-- La información que lee el asistente: se le agregan los horarios reales (una sola vez).
update ajustes
   set valor = valor || ' Horarios de clase: de lunes a viernes a las 7:00 am, 6:00 pm y 7:00 pm. Martes y jueves, Rumba básica a las 5:00 pm. Sábados, Rumba terapia a las 8:00 am y a las 9:00 am.'
 where clave = 'asistente_info'
   and valor not like '%Rumba terapia%';
