-- 0169 · El asistente general del WhatsApp de Tumbao: informa, manda a la página y, si la persona lo pide, RESERVA por chat
--
-- Damián (10 oct): «ese bot debe ayudar y servir. Si alguien le dice que quiere reservar, puede invitarlo a la página y darle el
-- enlace; si dice que se le ayude desde ese chat, ahí se pone pesada la cosa, pero sé que serías capaz de convertirlo en el
-- solucionador: que tome la información que pide la página (los datos básicos, el día y la hora), le haga la reserva y luego
-- el pago, todo en lenguaje natural. Y si algo sale mal, que diga "escríbenos al de recepción" con un enlace wa.me».
--
-- HOY (antes de esto): quien escribía a este número sin estar en ninguna conversación recibía «este número solo envía avisos y
-- no revisa mensajes». Ahora lo atiende el asistente.
--
-- CÓMO FUNCIONA
--   1. Un mensaje entrante que NO es de un dueño y que no pertenece a una conversación viva de pago, opinión o ventas despierta
--      a /wa/asistente (Worker). Antes de eso, si la persona tiene una reserva de la página con el pago pendiente, se le abre su
--      conversación de PAGO y sigue por ahí (así puede mandar su comprobante al número del bot).
--   2. El asistente responde con datos de la base (clases con cupo, precios, cupos de mensualidad, sus reservas): no inventa.
--      El modelo solo escoge una acción: ninguna | proponer_reserva | recepcion | cerrar.
--   3. Reservar es DETERMINISTA y con consentimiento: el modelo reúne nombre y clase; el CÓDIGO propone («Te aparto X el día Y a
--      la hora Z, $15.000. ¿Autorizas el tratamiento de tus datos (Ley 1581) y confirmas? Responde SÍ»); solo con un «sí» claro
--      de la persona se llama a asistente_reservar(), que usa tomar_cupo (el mismo cupo de la página) y deja abierta la
--      conversación de pago de esa reserva: el QR, los datos, el comprobante y el efectivo los resuelve el asistente de pagos (0166).
--   4. Si algo no se puede resolver, el bot no promete que «te escribimos»: da el enlace wa.me a recepción con el mensaje escrito.
--
-- PILOTO: nace en modo 'piloto' (ajustes.wa_asistente): solo atiende a los números de ajustes.wa_asistente_pilotos. Los demás siguen
-- con el aviso de siempre hasta que se ponga 'encendido'. 'apagado' lo deja todo como antes.
--
-- Aditivo: una tabla, funciones nuevas, tres funciones reemplazadas (wa_guardar_entrante, wa_llamar_agente, reserva_recordar_pago)
-- con anclas exactas, y ajustes. Nada destructivo.

create table if not exists public.asistente_chats (
  id          bigint generated always as identity primary key,
  telefono    text not null check (telefono ~ '^3[0-9]{9}$'),
  nombre      text,
  estado      text not null default 'abierta' check (estado in ('abierta', 'conversando', 'cerrada')),
  turnos      int not null default 0,
  datos       jsonb not null default '{}'::jsonb,
  resultado   text,
  resumen     text,
  reserva_id  uuid,
  codigo      text,
  abierta_at  timestamptz not null default now(),
  ultima_at   timestamptz,
  cerrada_at  timestamptz
);
create index if not exists asistente_chats_por_telefono on public.asistente_chats (telefono, abierta_at desc);
alter table public.asistente_chats enable row level security;
revoke all on table public.asistente_chats from public, anon, authenticated;

insert into public.ajustes (clave, valor, nota) values
  ('wa_asistente', 'piloto', 'Asistente general del WhatsApp: encendido (todos) / piloto (solo wa_asistente_pilotos) / apagado (el aviso de siempre). 0169.'),
  ('wa_asistente_pilotos', '3202284121', 'Celulares (10 dígitos, separados por coma) que atiende el asistente mientras wa_asistente = piloto. 0169.'),
  ('wa_asistente_url', 'https://tumbao-caja.damian3314.workers.dev/wa/asistente', 'Ruta del Worker que conversa con quien escribe al número del bot. 0169.'),
  ('asistente_info', 'Tumbao · Baila pa'' sanar es una academia de baile en Barrancabermeja. Las clases son de lunes a sábado (sin domingos ni festivos). La clase suelta cuesta $15.000 y se reserva en tumbaobaila.com; se paga por transferencia o en efectivo en la puerta. Conviene llegar unos 10 minutos antes. Instagram: @tumbao.bca. La dirección, el nivel de las clases y cualquier detalle que no esté aquí los resuelve recepción.',
   'Lo que el asistente puede decir del negocio además de los horarios y precios de la base. Edítalo para agregar la dirección, qué llevar, etc. 0169.')
on conflict (clave) do nothing;

-- ¿Este teléfono lo atiende el asistente? (no dueño, sin baja, y el interruptor lo permite)
create or replace function public.asistente_activo(p_tel text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select not wa_es_dueno(p_tel)
     and not exists (select 1 from wa_bajas b where b.telefono = right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 10))
     and case coalesce((select valor from ajustes where clave = 'wa_asistente'), 'apagado')
           when 'encendido' then true
           when 'piloto' then right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 10)
                              = any (string_to_array(regexp_replace(coalesce((select valor from ajustes where clave = 'wa_asistente_pilotos'), ''), '\s', '', 'g'), ','))
           else false end
$$;
revoke all on function public.asistente_activo(text) from public, anon, authenticated;

-- Cupos libres de una clase para una persona que paga clase suelta (el mismo cálculo de tomar_cupo: aforo y, los sábados, el
-- cupo de sueltas).
create or replace function public.asistente_libres(p_clase_id uuid)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select greatest(least(
           c.cupo_total - c.cupo_tomado,
           coalesce(c.cupo_sueltas - (select count(*) from reservas r
                                       where r.clase_id = c.id and r.tipo in ('suelta', 'tiquetera')
                                         and r.estado not in ('rechazada', 'expirada')),
                    c.cupo_total - c.cupo_tomado)), 0)::int
    from clases c where c.id = p_clase_id
$$;
revoke all on function public.asistente_libres(uuid) from public, anon, authenticated;

-- El Worker toma el mensaje entrante y todo lo que el asistente necesita saber.
create or replace function public.wa_tomar_asistente(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  m wa_mensajes; c asistente_chats; v_tel text; v_his jsonb; v_hor jsonb; v_viv jsonb; v_hoy int; v_pend reservas;
begin
  select * into m from wa_mensajes where id = p_id and estado = 'recibido' and direccion = 'entrante';
  if m.id is null then return null; end if;
  v_tel := right(regexp_replace(coalesce(m.telefono, ''), '\D', '', 'g'), 10);
  -- No es para el asistente (apagado, dueño, baja, o ya hay una conversación de pago viva): se deja como está.
  if v_tel !~ '^3[0-9]{9}$' or not asistente_activo(m.telefono) or pago_viva(m.telefono) is not null then return null; end if;

  -- Una reserva de la página con el pago pendiente: la conversación sigue por el asistente de pagos (así puede mandar su
  -- comprobante a este número). El mensaje queda 'recibido' para que lo tome /wa/pago.
  select * into v_pend from reservas r
   where right(regexp_replace(coalesce(r.telefono, ''), '\D', '', 'g'), 10) = v_tel
     and r.tipo = 'suelta' and r.created_at > now() - interval '24 hours'
     and ((r.estado = 'pendiente_pago' and (r.expira_en is null or r.expira_en > now()))
          or r.estado in ('verificando', 'pendiente_validacion'))
     and not exists (select 1 from pago_chats x where x.reserva_id = r.id)
   order by r.created_at desc limit 1;
  if v_pend.id is not null then
    insert into pago_chats (telefono, nombre, reserva_id, codigo)
    values (v_tel, nullif(initcap(split_part(btrim(coalesce(v_pend.nombre, '')), ' ', 1)), ''), v_pend.id, v_pend.codigo)
    on conflict (reserva_id) do nothing;
    return jsonb_build_object('adoptado', true, 'id', m.id);
  end if;

  -- Tope por persona y por día (evita que alguien gaste el modelo): pasado eso no se le contesta.
  select count(*) into v_hoy from wa_mensajes
   where direccion = 'saliente' and right(regexp_replace(coalesce(telefono, ''), '\D', '', 'g'), 10) = v_tel
     and creado_at > now() - interval '24 hours';
  if v_hoy >= 60 then
    update wa_mensajes set estado = 'ignorado' where id = m.id;
    return null;
  end if;

  update wa_mensajes set estado = 'procesando' where id = m.id;

  select * into c from asistente_chats
   where telefono = v_tel and estado <> 'cerrada' and coalesce(ultima_at, abierta_at) > now() - interval '12 hours'
   order by id desc limit 1;
  if c.id is null then
    insert into asistente_chats (telefono) values (v_tel) returning * into c;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('direccion', h.direccion, 'texto', h.texto) order by h.id), '[]'::jsonb)
    into v_his
    from (select id, direccion, texto from wa_mensajes
           where right(regexp_replace(coalesce(telefono, ''), '\D', '', 'g'), 10) = v_tel and id < m.id and texto is not null
             and creado_at > now() - interval '12 hours'
           order by id desc limit 20) h;

  -- Las clases que de verdad se pueden reservar en los próximos 8 días (la `n` es solo para esta respuesta).
  select coalesce(jsonb_agg(jsonb_build_object('n', f.n, 'clase_id', f.id, 'clase', f.nombre, 'fecha_texto', f.fecha_texto,
                                               'hora_texto', f.hora_texto, 'precio_cop', f.precio_cop, 'libres', f.libres) order by f.n), '[]'::jsonb)
    into v_hor
    from (select (row_number() over (order by b.fecha_hora))::int n, b.*
            from (select cl.id, cl.nombre, cl.fecha_hora, cl.precio_cop, asistente_libres(cl.id) libres,
                         wa_fecha_texto((cl.fecha_hora at time zone 'America/Bogota')::date) fecha_texto,
                         wa_hora_texto((cl.fecha_hora at time zone 'America/Bogota')::time) hora_texto
                    from clases cl
                   where cl.activa and cl.fecha_hora > now() and cl.fecha_hora < now() + interval '8 days') b
           where b.libres > 0
           order by b.fecha_hora limit 16) f;

  -- Lo que la persona ya tiene reservado.
  select coalesce(jsonb_agg(jsonb_build_object('codigo', r.codigo, 'estado', r.estado, 'clase', cl.nombre,
                                               'fecha_texto', wa_fecha_texto((cl.fecha_hora at time zone 'America/Bogota')::date),
                                               'hora_texto', wa_hora_texto((cl.fecha_hora at time zone 'America/Bogota')::time),
                                               'cobra_en_puerta', r.cobra_en_puerta) order by cl.fecha_hora), '[]'::jsonb)
    into v_viv
    from reservas r join clases cl on cl.id = r.clase_id
   where right(regexp_replace(coalesce(r.telefono, ''), '\D', '', 'g'), 10) = v_tel
     and r.estado not in ('rechazada', 'expirada')
     and cl.fecha_hora > now() - interval '3 hours' and cl.fecha_hora < now() + interval '30 days';

  return jsonb_build_object('id', m.id, 'telefono', m.telefono, 'wa_msg_id', m.wa_msg_id,
    'tipo', m.tipo, 'texto', m.texto, 'nombre_perfil', m.nombre, 'historial', v_his,
    'chat', jsonb_build_object('id', c.id, 'nombre', c.nombre, 'estado', c.estado, 'turnos', c.turnos, 'datos', c.datos),
    'contexto', jsonb_build_object('horarios', v_hor, 'reservas', v_viv, 'perfil', ventas_perfil(v_tel),
                                   'info', coalesce((select valor from ajustes where clave = 'asistente_info'), '')),
    'pago', pago_datos());
end;
$$;
revoke all on function public.wa_tomar_asistente(bigint) from public, anon, authenticated;
grant execute on function public.wa_tomar_asistente(bigint) to service_role;

-- Anota el turno (y el nombre y el resumen, si los hay). `p_limpiar` borra la propuesta pendiente de confirmar.
create or replace function public.asistente_turno(p_chat bigint, p_mensaje bigint, p_texto_entrante text, p_cerrar boolean,
                                                  p_resultado text, p_resumen text, p_nombre text default null,
                                                  p_limpiar boolean default false)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_texto_entrante is not null then
    update wa_mensajes set texto = left(p_texto_entrante, 4000) where id = p_mensaje;
  end if;
  update wa_mensajes set estado = 'respondido' where id = p_mensaje and estado = 'procesando';
  update asistente_chats
     set turnos = turnos + 1,
         ultima_at = now(),
         estado = case when p_cerrar then 'cerrada' else 'conversando' end,
         cerrada_at = case when p_cerrar then coalesce(cerrada_at, now()) else null end,
         nombre = coalesce(nullif(btrim(coalesce(p_nombre, '')), ''), nombre),
         resumen = coalesce(nullif(btrim(coalesce(p_resumen, '')), ''), resumen),
         resultado = coalesce(nullif(btrim(coalesce(p_resultado, '')), ''), resultado),
         datos = case when p_limpiar then datos - 'pendiente' else datos end
   where id = p_chat;
end;
$$;
revoke all on function public.asistente_turno(bigint, bigint, text, boolean, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.asistente_turno(bigint, bigint, text, boolean, text, text, text, boolean) to service_role;

-- PASO 1 de reservar: el modelo reunió nombre y clase. Se valida contra la base y se guarda la propuesta; la persona todavía
-- no tiene nada reservado.
create or replace function public.asistente_proponer(p_chat bigint, p_clase_id uuid, p_nombre text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare c asistente_chats; cl clases; v_nom text; v_lib int; v_cod text;
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

  update asistente_chats
     set datos = jsonb_set(datos, '{pendiente}', jsonb_build_object('clase_id', p_clase_id, 'nombre', v_nom, 'pedido_at', now()), true),
         nombre = initcap(split_part(v_nom, ' ', 1)), ultima_at = now()
   where id = p_chat;

  return jsonb_build_object('ok', true, 'nombre', v_nom, 'clase', cl.nombre, 'precio_cop', cl.precio_cop, 'libres', v_lib,
    'fecha_texto', wa_fecha_texto((cl.fecha_hora at time zone 'America/Bogota')::date),
    'hora_texto', wa_hora_texto((cl.fecha_hora at time zone 'America/Bogota')::time));
end;
$$;
revoke all on function public.asistente_proponer(bigint, uuid, text) from public, anon, authenticated;
grant execute on function public.asistente_proponer(bigint, uuid, text) to service_role;

-- PASO 2: la persona dijo «sí» a la propuesta (y con eso, autorizó el tratamiento de sus datos). Se aparta el cupo con
-- tomar_cupo —el mismo de la página— y se abre la conversación de pago de esa reserva.
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

  -- Límites contra el abuso: 3 reservas por chat en 24 h y 2 pendientes de pago a la vez.
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

  -- El QR, los datos, el comprobante y el efectivo siguen por el asistente de pagos (0166), con turnos = 1 para que no
  -- trate el siguiente mensaje como el primero de una conversación que ya empezó.
  insert into pago_chats (telefono, nombre, reserva_id, codigo, estado, turnos, ultima_at)
  values (c.telefono, initcap(split_part(pend ->> 'nombre', ' ', 1)), v_res, v ->> 'codigo', 'conversando', 1, now())
  on conflict (reserva_id) do nothing;
  select id into v_pago from pago_chats where reserva_id = v_res;

  update asistente_chats
     set datos = (datos - 'pendiente') || jsonb_build_object('consentimiento_at', now()),
         reserva_id = v_res, codigo = v ->> 'codigo', resultado = 'reservo',
         estado = 'cerrada', cerrada_at = now(), ultima_at = now()
   where id = p_chat;

  return v || jsonb_build_object('info', pago_info(v_pago));
end;
$$;
revoke all on function public.asistente_reservar(bigint) from public, anon, authenticated;
grant execute on function public.asistente_reservar(bigint) to service_role;

-- ── Parches a funciones vivas (anclas exactas; si falta una, se detiene sin tocar nada) ─────────────────────────────
do $m$
declare d text; n text;
begin
  -- wa_guardar_entrante: bandera «asistente» y la captura se conserva también para el asistente (puede ser un comprobante).
  d := pg_get_functiondef('public.wa_guardar_entrante(text,text,text,text,text)'::regprocedure);
  if position('asistente_activo' in d) = 0 then
    n := d;
    if position($a$  if v_texto like '[imagen:%' and v_pago is null then v_texto := null; end if;$a$ in n) = 0 then raise exception '0169: falta el ancla 1 de wa_guardar_entrante'; end if;
    n := replace(n, $a$  if v_texto like '[imagen:%' and v_pago is null then v_texto := null; end if;$a$,
                    $a$  if v_texto like '[imagen:%' and v_pago is null and not ((not v_dueno) and asistente_activo(p_tel)) then v_texto := null; end if;$a$);
    if position($a$    'ventas', (not v_dueno) and v_pago is null and wa_opinion_viva(p_tel) is null and ventas_viva(p_tel) is not null,$a$ in n) = 0 then raise exception '0169: falta el ancla 2 de wa_guardar_entrante'; end if;
    n := replace(n, $a$    'ventas', (not v_dueno) and v_pago is null and wa_opinion_viva(p_tel) is null and ventas_viva(p_tel) is not null,$a$,
                    $a$    'ventas', (not v_dueno) and v_pago is null and wa_opinion_viva(p_tel) is null and ventas_viva(p_tel) is not null,
    'asistente', (not v_dueno) and v_pago is null and wa_opinion_viva(p_tel) is null and ventas_viva(p_tel) is null and asistente_activo(p_tel),$a$);
    execute n;
  end if;

  -- wa_llamar_agente: lo que no es de ninguna otra conversación lo atiende el asistente.
  d := pg_get_functiondef('public.wa_llamar_agente()'::regprocedure);
  if position('wa_asistente_url' in d) = 0 then
    n := d;
    if position($a$    select valor into v_url from ajustes where clave = 'wa_ventas_url';
  end if;$a$ in n) = 0 then raise exception '0169: falta el ancla 1 de wa_llamar_agente'; end if;
    n := replace(n, $a$    select valor into v_url from ajustes where clave = 'wa_ventas_url';
  end if;$a$,
                    $a$    select valor into v_url from ajustes where clave = 'wa_ventas_url';
  elsif asistente_activo(new.telefono) then
    select valor into v_url from ajustes where clave = 'wa_asistente_url';
  end if;$a$);
    execute n;
  end if;

  -- reserva_recordar_pago: a quien reservó POR WHATSAPP no se le manda la plantilla (ya está conversando con el bot).
  d := pg_get_functiondef('public.reserva_recordar_pago()'::regprocedure);
  if position($a$r.origen is distinct from 'whatsapp'$a$ in d) = 0 then
    n := d;
    if position($a$     where r.estado = 'pendiente_pago' and r.tipo = 'suelta'$a$ in n) = 0 then raise exception '0169: falta el ancla 1 de reserva_recordar_pago'; end if;
    n := replace(n, $a$     where r.estado = 'pendiente_pago' and r.tipo = 'suelta'$a$,
                    $a$     where r.estado = 'pendiente_pago' and r.tipo = 'suelta' and r.origen is distinct from 'whatsapp'$a$);
    execute n;
  end if;
end
$m$;
