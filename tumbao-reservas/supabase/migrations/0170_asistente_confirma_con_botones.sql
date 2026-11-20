-- 0170 · La reserva por chat se confirma con BOTONES, no con la palabra «sí»
--
-- Damián (10 oct): «eso de esperar el sí no me gusta: usa botones, que la persona marque Sí o No. Si se deja abierto, la gente va a
-- contestar cualquier cosa y no la palabra sí».
--
-- Qué cambia respecto de la 0169:
--   · asistente_proponer() ahora guarda con la propuesta una CLAVE de un solo uso («token»). Los botones del mensaje la llevan
--     en su id (asist:si:<token> / asist:no:<token>).
--   · asistente_confirmar(chat, token) es lo ÚNICO que marca la propuesta como confirmada, y solo si el token coincide y la
--     propuesta tiene menos de 20 minutos. Un botón de un resumen anterior no confirma nada.
--   · asistente_reservar(chat) —misma firma— exige esa confirmación: sin ella no reserva, aunque alguien lo llame.
--   · El consentimiento queda anotado con su vía: datos.consentimiento = {at, via: 'boton'}.
--
-- Esto cierra por la base lo que el Worker ya hace: el texto «sí» escrito a mano deja de reservar. Solo el toque en el botón
-- (un mensaje de tipo «interactive» que WhatsApp entrega, y que nadie puede fabricar escribiendo) llega a asistente_confirmar.

create or replace function public.asistente_proponer(p_chat bigint, p_clase_id uuid, p_nombre text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare c asistente_chats; cl clases; v_nom text; v_lib int; v_cod text; v_token text;
begin
  select * into c from asistente_chats where id = p_chat for update;
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'sin_chat'); end if;

  v_nom := left(regexp_replace(btrim(coalesce(p_nombre, '')), '\s+', ' ', 'g'), 60);
  if length(v_nom) < 2 or v_nom !~ '^[[:alpha:]][[:alpha:] ''.-]*$' then
    return jsonb_build_object('ok', false, 'error', 'NOMBRE_INVALIDO');
  end if;

  select * into cl from clases where id = p_clase_id;
  if cl.id is null or not cl.activa or cl.fecha_hora <= now() then
    return jsonb_build_object('ok', false, 'error', 'CLASE_NO_DISPONIBLE');
  end if;
  v_lib := asistente_libres(p_clase_id);
  if v_lib <= 0 then return jsonb_build_object('ok', false, 'error', 'SIN_CUPO'); end if;

  select r.codigo into v_cod from reservas r
   where r.clase_id = p_clase_id and right(regexp_replace(coalesce(r.telefono, ''), '\D', '', 'g'), 10) = c.telefono
     and r.estado not in ('rechazada', 'expirada') limit 1;
  if v_cod is not null then return jsonb_build_object('ok', false, 'error', 'YA_RESERVADA', 'codigo', v_cod); end if;

  v_token := substr(md5(random()::text || clock_timestamp()::text || p_chat::text), 1, 10);
  update asistente_chats
     set datos = jsonb_set(datos, '{pendiente}',
                           jsonb_build_object('clase_id', p_clase_id, 'nombre', v_nom, 'pedido_at', now(), 'token', v_token), true),
         nombre = initcap(split_part(v_nom, ' ', 1)), ultima_at = now()
   where id = p_chat;

  return jsonb_build_object('ok', true, 'nombre', v_nom, 'clase', cl.nombre, 'precio_cop', cl.precio_cop, 'libres', v_lib,
    'token', v_token,
    'fecha_texto', wa_fecha_texto((cl.fecha_hora at time zone 'America/Bogota')::date),
    'hora_texto', wa_hora_texto((cl.fecha_hora at time zone 'America/Bogota')::time));
end;
$$;
revoke all on function public.asistente_proponer(bigint, uuid, text) from public, anon, authenticated;
grant execute on function public.asistente_proponer(bigint, uuid, text) to service_role;

-- El toque en «Sí, reservar»: marca la propuesta como confirmada si el botón es el de ESTE resumen.
create or replace function public.asistente_confirmar(p_chat bigint, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare c asistente_chats; pend jsonb;
begin
  select * into c from asistente_chats where id = p_chat for update;
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'sin_chat'); end if;
  pend := c.datos -> 'pendiente';
  if pend is null or (pend ->> 'pedido_at')::timestamptz < now() - interval '20 minutes' then
    return jsonb_build_object('ok', false, 'error', 'sin_propuesta');
  end if;
  if coalesce(p_token, '') = '' or (pend ->> 'token') is distinct from p_token then
    return jsonb_build_object('ok', false, 'error', 'token');
  end if;
  update asistente_chats
     set datos = jsonb_set(datos, '{pendiente,confirmado_at}', to_jsonb(now()), true)
   where id = p_chat;
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.asistente_confirmar(bigint, text) from public, anon, authenticated;
grant execute on function public.asistente_confirmar(bigint, text) to service_role;

-- Reservar: exige la confirmación del botón.
create or replace function public.asistente_reservar(p_chat bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare c asistente_chats; pend jsonb; v jsonb; v_n int; v_pago bigint; v_res uuid;
begin
  select * into c from asistente_chats where id = p_chat for update;
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'sin_chat'); end if;
  pend := c.datos -> 'pendiente';
  if pend is null or (pend ->> 'pedido_at')::timestamptz < now() - interval '20 minutes' then
    return jsonb_build_object('ok', false, 'error', 'sin_propuesta');
  end if;
  if (pend ->> 'confirmado_at') is null then
    return jsonb_build_object('ok', false, 'error', 'sin_confirmar');
  end if;

  select count(*) into v_n from reservas
   where origen = 'whatsapp' and right(regexp_replace(coalesce(telefono, ''), '\D', '', 'g'), 10) = c.telefono
     and created_at > now() - interval '24 hours';
  if v_n >= 3 then return jsonb_build_object('ok', false, 'error', 'LIMITE_DIARIO'); end if;
  select count(*) into v_n from reservas
   where estado = 'pendiente_pago' and (expira_en is null or expira_en > now())
     and right(regexp_replace(coalesce(telefono, ''), '\D', '', 'g'), 10) = c.telefono;
  if v_n >= 2 then return jsonb_build_object('ok', false, 'error', 'PENDIENTES'); end if;

  v := tomar_cupo((pend ->> 'clase_id')::uuid, pend ->> 'nombre', c.telefono, null, 'whatsapp', 'suelta', null);
  if coalesce((v ->> 'ok')::boolean, false) is not true then return v; end if;
  v_res := (v ->> 'reserva_id')::uuid;

  insert into pago_chats (telefono, nombre, reserva_id, codigo, estado, turnos, ultima_at)
  values (c.telefono, initcap(split_part(pend ->> 'nombre', ' ', 1)), v_res, v ->> 'codigo', 'conversando', 1, now())
  on conflict (reserva_id) do nothing;
  select id into v_pago from pago_chats where reserva_id = v_res;

  update asistente_chats
     set datos = (datos - 'pendiente') || jsonb_build_object('consentimiento', jsonb_build_object('at', now(), 'via', 'boton')),
         reserva_id = v_res, codigo = v ->> 'codigo', resultado = 'reservo',
         estado = 'cerrada', cerrada_at = now(), ultima_at = now()
   where id = p_chat;

  return v || jsonb_build_object('info', pago_info(v_pago));
end;
$$;
revoke all on function public.asistente_reservar(bigint) from public, anon, authenticated;
grant execute on function public.asistente_reservar(bigint) to service_role;
