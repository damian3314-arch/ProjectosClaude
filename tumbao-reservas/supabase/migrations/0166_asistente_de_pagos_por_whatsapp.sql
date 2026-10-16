-- 0166 · El asistente de pagos: quien recibe el recordatorio de pago puede terminar su reserva POR WHATSAPP
--
-- Damián (9 oct): «aprovechar que a la persona le llegue el mensaje de que tiene pendiente el pago, pero más bien
-- que el bot le ayude: si tuvo algún inconveniente, que le ayude desde esa conversación, que el bot reciba el pago y
-- haga la reserva. Le pide lo que necesita la página, el soporte, todo. Si paga por transferencia le comparte el QR y
-- los datos de la cuenta, y cuando tenga el soporte lo carga al sistema. Si dice que va a pagar en efectivo, le hace
-- la reserva y le dice que llegue antecito y con el dinero suelto, los $15.000».
--
-- CÓMO FUNCIONA
--   1. reserva_recordar_pago() (0165) ahora, además del aviso, abre un «pago_chat» para esa reserva. La plantilla sale
--      de ajustes.wa_recordar_pago_plantilla (hoy reserva_pendiente_pago; pasa a reserva_pago_ayuda cuando Meta la
--      apruebe: invita a responder si tuvo algún inconveniente).
--   2. Si la persona responde, el trigger despierta a /wa/pago (Worker), que conversa dentro de la ventana de 24 h.
--      El pago_chat tiene prioridad sobre opinión y ventas: es lo más urgente que esa persona tiene con Tumbao.
--   3. Lo que NO decide el modelo: la plata, los datos de pago, ni que algo «quedó confirmado». El modelo escoge una
--      acción (datos_de_pago, efectivo, recepcion, cerrar); el Worker la ejecuta con las funciones de abajo y escribe
--      con texto fijo los datos de la cuenta, el valor y las confirmaciones.
--   4. Transferencia: el Worker manda el QR y los datos de ajustes.pago_*; la persona manda la captura; el Worker la
--      lee (la misma lectura de la página) y llama pago_registrar_soporte(), que es exactamente el «ya pagué» de la
--      página (registrar_aviso_pago): la reserva pasa a «verificando» y se confirma sola cuando el correo del banco
--      cuadra. Una captura sola NO confirma nada: cualquiera puede mandar una imagen. Si el banco no la muestra en 6
--      minutos, pasa a revisión de recepción (marcar_pendiente_validacion + nota).
--   5. Efectivo: pago_efectivo() deja la reserva confirmada con cobra_en_puerta (el mismo mecanismo de «paga al
--      llegar» que ya usa recepción: el cobro se registra al marcar la asistencia). Límites: una reserva en efectivo
--      pendiente por persona, y no si en 60 días dejó plantadas 2 reservas en efectivo.
--   6. Si el cupo ya se había soltado (a los 15 minutos), pago_asegurar_reserva() vuelve a apartarlo si todavía hay.
--
-- Se apaga con ajustes.wa_pago_bot = 'apagado'. Aditivo: una tabla, funciones nuevas, tres funciones reemplazadas
-- (wa_guardar_entrante, wa_llamar_agente, reserva_recordar_pago) y ajustes.

create table if not exists public.pago_chats (
  id               bigint generated always as identity primary key,
  telefono         text not null check (telefono ~ '^3[0-9]{9}$'),
  nombre           text,
  reserva_id       uuid not null,
  codigo           text,
  estado           text not null default 'abierta' check (estado in ('abierta', 'conversando', 'cerrada')),
  turnos           int not null default 0,
  intentos_lectura int not null default 0,
  extensiones      int not null default 0,
  resultado        text,
  resumen          text,
  soporte_at       timestamptz,
  seguimiento_at   timestamptz,
  abierta_at       timestamptz not null default now(),
  ultima_at        timestamptz,
  cerrada_at       timestamptz
);
create unique index if not exists pago_chats_por_reserva on public.pago_chats (reserva_id);
create index if not exists pago_chats_por_telefono on public.pago_chats (telefono, abierta_at desc);
alter table public.pago_chats enable row level security;
revoke all on table public.pago_chats from public, anon, authenticated;

insert into public.ajustes (clave, valor, nota) values
  ('wa_pago_bot', 'encendido', 'Asistente de pagos por WhatsApp: ayuda a terminar la reserva a quien recibió el recordatorio de pago. encendido / apagado. 0166.'),
  ('wa_pago_url', 'https://tumbao-caja.damian3314.workers.dev/wa/pago', 'Ruta del Worker que conversa con quien responde al recordatorio de pago. 0166.'),
  ('wa_pago_seguimiento_url', 'https://tumbao-caja.damian3314.workers.dev/wa/pago-seguimiento', 'Worker que avisa si el comprobante recibido por WhatsApp ya se confirmó o pasó a revisión. 0166.'),
  ('wa_recordar_pago_plantilla', 'reserva_pendiente_pago', 'Plantilla del recordatorio de pago. Pasa a reserva_pago_ayuda cuando Meta la apruebe. 0166.'),
  ('pago_llave', '1096803067', 'Llave Bre-B que el asistente de pagos comparte (la misma de la página). 0166.'),
  ('pago_banco', 'Bancolombia', 'Banco de la cuenta de Tumbao (la misma de la página). 0166.'),
  ('pago_cuenta', '91289724619', 'Cuenta de Tumbao (la misma de la página). 0166.'),
  ('pago_titular', 'Luz Alejandra Santiago García', 'Titular de la cuenta (el mismo de la página). 0166.'),
  ('pago_qr_url', 'https://tumbaobaila.com/img/qr-breb.png', 'Imagen del QR que el asistente de pagos envía. 0166.')
on conflict (clave) do nothing;

-- La conversación de pago viva de un teléfono: abierta o conversando (12 h), o cerrada hace menos de 6 h (para no
-- contestarle con el «no revisamos mensajes» a quien acaba de pagar y escribe «gracias»).
create or replace function public.pago_viva(p_tel text)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select id from pago_chats
   where telefono = right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 10)
     and coalesce((select valor from ajustes where clave = 'wa_pago_bot'), 'apagado') = 'encendido'
     and ((estado in ('abierta', 'conversando') and greatest(abierta_at, coalesce(ultima_at, abierta_at)) > now() - interval '12 hours')
          or (estado = 'cerrada' and cerrada_at > now() - interval '6 hours'))
   order by abierta_at desc limit 1;
$$;
revoke all on function public.pago_viva(text) from public, anon, authenticated;

-- Todo lo que el asistente puede decir de la reserva, de la base.
create or replace function public.pago_info(p_chat bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare c pago_chats; r reservas; cl clases; v_n int; v_local timestamp;
begin
  select * into c from pago_chats where id = p_chat;
  if c.id is null then return null; end if;
  select * into r from reservas where id = c.reserva_id;
  if r.id is null then return null; end if;
  select * into cl from clases where id = r.clase_id;
  select count(*) into v_n from reservas x where coalesce(x.grupo_id, x.id) = coalesce(r.grupo_id, r.id);
  v_local := cl.fecha_hora at time zone 'America/Bogota';
  return jsonb_build_object(
    'codigo', r.codigo, 'estado', r.estado, 'tipo', r.tipo, 'personas', v_n,
    'clase', cl.nombre, 'lugar', cl.lugar, 'profesor', cl.profesor,
    'fecha_hora', cl.fecha_hora,
    'fecha_texto', wa_fecha_texto(v_local::date), 'hora_texto', wa_hora_texto(v_local::time),
    'precio_cop', cl.precio_cop, 'total_cop', coalesce(cl.precio_cop, 0) * v_n,
    'expira_en', r.expira_en,
    'cupo_libre', greatest(cl.cupo_total - cl.cupo_tomado, 0) >= v_n,
    'clase_activa', cl.activa,
    'clase_paso', cl.fecha_hora < now() - make_interval(mins => minutos_de_gracia()),
    'cobra_en_puerta', r.cobra_en_puerta);
end;
$$;
revoke all on function public.pago_info(bigint) from public, anon, authenticated;

-- Los datos de pago que se comparten (de ajustes, iguales a los de la página).
create or replace function public.pago_datos()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'llave',   coalesce((select valor from ajustes where clave = 'pago_llave'), ''),
    'banco',   coalesce((select valor from ajustes where clave = 'pago_banco'), ''),
    'cuenta',  coalesce((select valor from ajustes where clave = 'pago_cuenta'), ''),
    'titular', coalesce((select valor from ajustes where clave = 'pago_titular'), ''),
    'qr_url',  coalesce((select valor from ajustes where clave = 'pago_qr_url'), ''))
$$;
revoke all on function public.pago_datos() from public, anon, authenticated;

-- El Worker toma el mensaje entrante y la conversación completa del pago.
create or replace function public.wa_tomar_pago(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare m wa_mensajes; c pago_chats; v_his jsonb;
begin
  update wa_mensajes set estado = 'procesando'
   where id = p_id and estado = 'recibido' and direccion = 'entrante'
  returning * into m;
  if m.id is null or wa_es_dueno(m.telefono) then return null; end if;
  if exists (select 1 from wa_bajas b where b.telefono = right(m.telefono, 10)) then
    update wa_mensajes set estado = 'ignorado' where id = m.id;
    return null;
  end if;
  select * into c from pago_chats where id = pago_viva(m.telefono);
  if c.id is null then
    update wa_mensajes set estado = 'ignorado' where id = m.id;
    return null;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('direccion', h.direccion, 'texto', h.texto) order by h.id), '[]'::jsonb)
    into v_his
    from (select id, direccion, texto from wa_mensajes
           where right(telefono, 10) = c.telefono and id < m.id and texto is not null
             and creado_at >= c.abierta_at - interval '10 minutes'
           order by id desc limit 20) h;
  return jsonb_build_object('id', m.id, 'telefono', m.telefono, 'wa_msg_id', m.wa_msg_id,
    'tipo', m.tipo, 'texto', m.texto, 'historial', v_his,
    'chat', jsonb_build_object('id', c.id, 'nombre', c.nombre, 'estado', c.estado, 'turnos', c.turnos,
                               'intentos_lectura', c.intentos_lectura, 'resultado', c.resultado),
    'reserva', pago_info(c.id),
    'pago', pago_datos());
end;
$$;
revoke all on function public.wa_tomar_pago(bigint) from public, anon, authenticated;
grant execute on function public.wa_tomar_pago(bigint) to service_role;

-- El Worker anota el resultado de cada turno.
create or replace function public.pago_turno(p_chat bigint, p_mensaje bigint, p_texto_entrante text,
                                             p_cerrar boolean, p_resultado text, p_resumen text)
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
  update pago_chats
     set turnos = turnos + 1,
         ultima_at = now(),
         estado = case when p_cerrar then 'cerrada' else 'conversando' end,
         cerrada_at = case when p_cerrar then coalesce(cerrada_at, now()) else null end,
         resumen = coalesce(nullif(btrim(coalesce(p_resumen, '')), ''), resumen),
         resultado = coalesce(nullif(btrim(coalesce(p_resultado, '')), ''), resultado)
   where id = p_chat;
end;
$$;
revoke all on function public.pago_turno(bigint, bigint, text, boolean, text, text) from public, anon, authenticated;
grant execute on function public.pago_turno(bigint, bigint, text, boolean, text, text) to service_role;

-- Cuenta una captura que no se pudo leer (a la segunda se pasa a recepción).
create or replace function public.pago_marcar_lectura(p_chat bigint)
returns int
language sql
security definer
set search_path = public, pg_temp
as $$
  update pago_chats set intentos_lectura = intentos_lectura + 1 where id = p_chat returning intentos_lectura;
$$;
revoke all on function public.pago_marcar_lectura(bigint) from public, anon, authenticated;
grant execute on function public.pago_marcar_lectura(bigint) to service_role;

-- La reserva viva de la conversación. Si el cupo ya se soltó (15 minutos sin pago), se vuelve a apartar si todavía
-- hay; si la persona ya tiene otra reserva viva para la misma clase (por ejemplo la hizo de nuevo en la página), se
-- usa esa.
create or replace function public.pago_asegurar_reserva(p_chat bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare c pago_chats; r reservas; r2 reservas; v jsonb; v_n int;
begin
  select * into c from pago_chats where id = p_chat for update;
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'sin_chat'); end if;
  select * into r from reservas where id = c.reserva_id;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'sin_reserva'); end if;

  if r.estado in ('pendiente_pago', 'verificando', 'pendiente_validacion', 'confirmada') then
    return jsonb_build_object('ok', true, 'codigo', r.codigo, 'estado', r.estado, 'nueva', false);
  end if;
  if r.estado <> 'expirada' then
    return jsonb_build_object('ok', false, 'error', 'estado_' || r.estado);
  end if;

  select * into r2 from reservas x
   where x.clase_id = r.clase_id and right(solo_digitos(x.telefono), 10) = c.telefono
     and x.estado in ('pendiente_pago', 'verificando', 'pendiente_validacion', 'confirmada')
   order by x.created_at desc limit 1;
  if r2.id is not null then
    begin
      update pago_chats set reserva_id = r2.id, codigo = r2.codigo where id = c.id;
    exception when unique_violation then
      -- esa reserva ya tiene su propia conversación de pago: no se mezclan
      return jsonb_build_object('ok', false, 'error', 'reserva_duplicada');
    end;
    return jsonb_build_object('ok', true, 'codigo', r2.codigo, 'estado', r2.estado, 'nueva', false);
  end if;

  select count(*) into v_n from reservas x where coalesce(x.grupo_id, x.id) = coalesce(r.grupo_id, r.id);
  if v_n > 1 then
    return jsonb_build_object('ok', false, 'error', 'grupo_expirado');
  end if;

  v := tomar_cupo(r.clase_id, r.nombre, r.telefono, r.email, 'whatsapp', 'suelta');
  if coalesce((v ->> 'ok')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'error', coalesce(v ->> 'error', 'SIN_CUPO'), 'mensaje', v ->> 'mensaje');
  end if;
  update pago_chats set reserva_id = (v ->> 'reserva_id')::uuid, codigo = v ->> 'codigo' where id = c.id;
  return jsonb_build_object('ok', true, 'codigo', v ->> 'codigo', 'estado', v ->> 'estado', 'nueva', true);
end;
$$;
revoke all on function public.pago_asegurar_reserva(bigint) from public, anon, authenticated;
grant execute on function public.pago_asegurar_reserva(bigint) to service_role;

-- Antes de mandar los datos de pago: la reserva queda viva y, si sigue sin pagar, el cupo se guarda otros 15 minutos
-- (hasta dos veces por conversación y nunca más allá del inicio de la clase).
create or replace function public.pago_preparar(p_chat bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v jsonb; r reservas; c pago_chats; v_ini timestamptz;
begin
  v := pago_asegurar_reserva(p_chat);
  if coalesce((v ->> 'ok')::boolean, false) is not true then return v; end if;
  if v ->> 'estado' = 'pendiente_pago' and not coalesce((v ->> 'nueva')::boolean, false) then
    update pago_chats set extensiones = extensiones + 1 where id = p_chat and extensiones < 2 returning * into c;
    if c.id is not null then
      select * into r from reservas where id = c.reserva_id;
      select fecha_hora into v_ini from clases where id = r.clase_id;
      update reservas
         set expira_en = greatest(expira_en, least(now() + make_interval(mins => minutos_cupo_sin_pago()), v_ini)),
             updated_at = now()
       where coalesce(grupo_id, id) = coalesce(r.grupo_id, r.id) and estado = 'pendiente_pago';
    end if;
  end if;
  return v || jsonb_build_object('info', pago_info(p_chat));
end;
$$;
revoke all on function public.pago_preparar(bigint) from public, anon, authenticated;
grant execute on function public.pago_preparar(bigint) to service_role;

-- «Ya pagué» con captura: lo mismo que el botón de la página. Una imagen sola no confirma: la reserva queda en
-- «verificando» y se confirma cuando el correo del banco cuadra (o la valida recepción).
create or replace function public.pago_registrar_soporte(p_chat bigint, p_pagado_en timestamptz, p_referencia text,
                                                         p_pagador text, p_media text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v jsonb; r jsonb; v_estado text;
begin
  v := pago_asegurar_reserva(p_chat);
  if coalesce((v ->> 'ok')::boolean, false) is not true then return v; end if;

  v_estado := v ->> 'estado';
  if v_estado in ('verificando', 'pendiente_validacion') then
    -- Ya hay un comprobante en revisión: no se vuelve a registrar.
    r := jsonb_build_object('ok', true, 'estado', v_estado, 'codigo', v ->> 'codigo', 'repetido', true);
  else
    r := registrar_aviso_pago(v ->> 'codigo', p_pagado_en, p_referencia, p_pagador,
                              left('whatsapp:' || coalesce(p_media, ''), 500));
  end if;
  if coalesce((r ->> 'ok')::boolean, false) is not true then return r; end if;

  update pago_chats
     set resultado = case when r ->> 'estado' = 'confirmada' then 'pagado' else 'soporte_recibido' end,
         soporte_at = coalesce(soporte_at, now()),
         estado = case when r ->> 'estado' = 'confirmada' then 'cerrada' else estado end,
         cerrada_at = case when r ->> 'estado' = 'confirmada' then coalesce(cerrada_at, now()) else cerrada_at end
   where id = p_chat;
  return r || jsonb_build_object('nueva', coalesce((v ->> 'nueva')::boolean, false), 'info', pago_info(p_chat));
end;
$$;
revoke all on function public.pago_registrar_soporte(bigint, timestamptz, text, text, text) from public, anon, authenticated;
grant execute on function public.pago_registrar_soporte(bigint, timestamptz, text, text, text) to service_role;

-- Efectivo: la reserva queda confirmada y el cobro se hace en la puerta (cobra_en_puerta), el mismo mecanismo que usa
-- recepción. El aviso automático de «cupo confirmado» no sale: el asistente ya le dio el código en el chat.
create or replace function public.pago_efectivo(p_chat bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare c pago_chats; r reservas; v jsonb; v_info jsonb;
begin
  select * into c from pago_chats where id = p_chat;
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'sin_chat'); end if;
  v_info := pago_info(c.id);
  if v_info is null then return jsonb_build_object('ok', false, 'error', 'sin_reserva'); end if;
  if (v_info ->> 'clase_paso')::boolean or not (v_info ->> 'clase_activa')::boolean then
    return jsonb_build_object('ok', false, 'error', 'clase_no_disponible');
  end if;
  if v_info ->> 'tipo' <> 'suelta' then
    return jsonb_build_object('ok', false, 'error', 'no_aplica');
  end if;

  -- Quien dejó plantadas dos reservas en efectivo en 60 días paga por transferencia.
  if (select count(*) from reservas x
       where right(solo_digitos(x.telefono), 10) = c.telefono and x.cobra_en_puerta and x.no_vino_at is not null
         and x.created_at > now() - interval '60 days') >= 2 then
    return jsonb_build_object('ok', false, 'error', 'efectivo_no_disponible');
  end if;

  v := pago_asegurar_reserva(c.id);
  if coalesce((v ->> 'ok')::boolean, false) is not true then return v; end if;
  select * into r from reservas where codigo = v ->> 'codigo';

  if r.estado = 'confirmada' then
    return jsonb_build_object('ok', true, 'estado', 'confirmada', 'codigo', r.codigo, 'ya_estaba', true,
                              'cobra_en_puerta', r.cobra_en_puerta, 'info', pago_info(c.id));
  end if;
  if r.estado <> 'pendiente_pago' then
    return jsonb_build_object('ok', false, 'error', 'pago_en_revision', 'estado', r.estado);
  end if;

  -- Una sola reserva en efectivo pendiente por persona.
  if exists (select 1 from reservas x join clases cl on cl.id = x.clase_id
              where right(solo_digitos(x.telefono), 10) = c.telefono and x.cobra_en_puerta
                and x.estado = 'confirmada' and x.cobrado_en_puerta_at is null and cl.fecha_hora > now()
                and coalesce(x.grupo_id, x.id) <> coalesce(r.grupo_id, r.id)) then
    return jsonb_build_object('ok', false, 'error', 'ya_tiene_efectivo');
  end if;

  insert into wa_avisos (clave, tipo, telefono, plantilla, estado, motivo)
  values ('reserva_confirmada:' || r.clase_id || ':' || c.telefono, 'reserva_confirmada', c.telefono,
          'reserva_confirmada', 'omitido', 'confirmada_por_chat_en_efectivo')
  on conflict (clave) do nothing;

  update reservas
     set estado = 'confirmada', cobra_en_puerta = true, resuelta_at = now(), updated_at = now()
   where coalesce(grupo_id, id) = coalesce(r.grupo_id, r.id) and estado = 'pendiente_pago';

  update pago_chats set resultado = 'efectivo' where id = c.id;
  return jsonb_build_object('ok', true, 'estado', 'confirmada', 'codigo', r.codigo, 'nueva', coalesce((v ->> 'nueva')::boolean, false),
                            'cobra_en_puerta', true, 'info', pago_info(c.id));
end;
$$;
revoke all on function public.pago_efectivo(bigint) from public, anon, authenticated;
grant execute on function public.pago_efectivo(bigint) to service_role;

-- Seguimiento del comprobante recibido por WhatsApp: ¿el banco ya lo mostró? Lo llama el Worker (/wa/pago-seguimiento).
--   confirmada  → se le avisa que quedó lista;
--   en_revision → pasaron 6 minutos sin que el banco cuadre: queda pendiente_validacion y se le avisa a recepción;
--   rechazada / expirada → se le dice que el equipo lo revisa.
create or replace function public.pago_seguimientos_tomar(p_limite int default 5)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare c record; v jsonb; v_tipo text; v_out jsonb := '[]'::jsonb;
begin
  for c in
    select * from pago_chats
     where resultado = 'soporte_recibido' and seguimiento_at is null
       and soporte_at <= now() - interval '75 seconds' and soporte_at > now() - interval '20 hours'
     order by soporte_at limit greatest(p_limite, 0) for update skip locked
  loop
    v := conciliar_reserva(c.codigo);
    v_tipo := null;
    if v ->> 'estado' = 'confirmada' then
      v_tipo := 'confirmada';
    elsif v ->> 'estado' in ('rechazada', 'expirada') then
      v_tipo := 'rechazada';
    elsif v ->> 'estado' = 'pendiente_validacion'
          or (v ->> 'estado' = 'verificando' and c.soporte_at <= now() - interval '6 minutes') then
      if v ->> 'estado' = 'verificando' then perform marcar_pendiente_validacion(c.codigo); end if;
      v_tipo := 'en_revision';
    end if;
    if v_tipo is not null then
      update pago_chats
         set seguimiento_at = now(), estado = 'cerrada', cerrada_at = now(),
             resultado = case v_tipo when 'confirmada' then 'pagado' else 'recepcion' end
       where id = c.id;
      v_out := v_out || jsonb_build_object('chat', c.id, 'telefono', c.telefono, 'nombre', c.nombre, 'tipo', v_tipo,
                                           'codigo', c.codigo, 'info', pago_info(c.id));
    end if;
  end loop;
  return v_out;
end;
$$;
revoke all on function public.pago_seguimientos_tomar(int) from public, anon, authenticated;
grant execute on function public.pago_seguimientos_tomar(int) to service_role;

-- Quien despierta al Worker cada 2 minutos, SOLO si hay un comprobante esperando.
create or replace function public.pago_seguimientos_llamar()
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_url text;
begin
  if coalesce((select valor from ajustes where clave = 'wa_pago_bot'), 'apagado') <> 'encendido' then return; end if;
  if not exists (select 1 from pago_chats
                  where resultado = 'soporte_recibido' and seguimiento_at is null
                    and soporte_at <= now() - interval '75 seconds' and soporte_at > now() - interval '20 hours') then
    return;
  end if;
  select valor into v_url from ajustes where clave = 'wa_pago_seguimiento_url';
  if coalesce(v_url, '') = '' then return; end if;
  perform net.http_post(url := v_url, body := '{}'::jsonb,
                        headers := '{"Content-Type": "application/json"}'::jsonb,
                        timeout_milliseconds := 60000);
exception when others then
  raise warning 'pago_seguimientos_llamar: %', sqlerrm;
end;
$$;
revoke all on function public.pago_seguimientos_llamar() from public, anon, authenticated;

do $cron$
begin
  perform cron.unschedule('tumbao-pago-seguimiento');
exception when others then null;
end
$cron$;
select cron.schedule('tumbao-pago-seguimiento', '*/2 * * * *', 'select public.pago_seguimientos_llamar()');

-- El recordatorio (0165) ahora abre el pago_chat y usa la plantilla de ajustes.wa_recordar_pago_plantilla.
create or replace function public.reserva_recordar_pago()
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare n int := 0; v_plantilla text;
begin
  if coalesce((select valor from ajustes where clave = 'wa_recordar_pago'), 'apagado') <> 'encendido' then
    return 0;
  end if;
  v_plantilla := coalesce(nullif((select valor from ajustes where clave = 'wa_recordar_pago_plantilla'), ''), 'reserva_pendiente_pago');

  with c as (
    select r.id, r.clase_id, r.codigo,
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
    select 'recordatorio_pago:' || e.id, 'recordatorio_pago', e.tel, v_plantilla,
           jsonb_build_array(coalesce(nullif(e.nombre, ''), 'amigo(a)'),
             'el ' || wa_fecha_texto((e.fecha_hora at time zone 'America/Bogota')::date) || ' a las '
                   || wa_hora_texto((e.fecha_hora at time zone 'America/Bogota')::time)),
           coalesce(e.expira_en, now() + interval '10 minutes')
      from elegibles e
    on conflict (clave) do nothing
    returning clave),
  chats as (
    insert into pago_chats (telefono, nombre, reserva_id, codigo)
    select e.tel, nullif(e.nombre, ''), e.id, e.codigo
      from elegibles e
     where 'recordatorio_pago:' || e.id in (select clave from ins)
    on conflict (reserva_id) do nothing
    returning 1)
  select count(*) into n from ins;
  return n;
end;
$$;
revoke all on function public.reserva_recordar_pago() from public, anon, authenticated;
grant execute on function public.reserva_recordar_pago() to service_role;

-- Entrante: bandera «pago» (prioridad sobre opinión y ventas) y la imagen se guarda como [imagen:<id>] solo si hay una
-- conversación de pago viva (para el resto, sigue como antes: sin texto).
create or replace function public.wa_guardar_entrante(p_wa_msg_id text, p_tel text,
                                                      p_nombre text, p_tipo text, p_texto text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id bigint; v_dueno boolean := wa_es_dueno(p_tel); v_pago bigint; v_texto text := p_texto;
begin
  v_pago := case when v_dueno then null else pago_viva(p_tel) end;
  if v_texto like '[imagen:%' and v_pago is null then v_texto := null; end if;
  insert into wa_mensajes (wa_msg_id, telefono, nombre, direccion, tipo, texto)
  values (p_wa_msg_id, regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'),
          left(p_nombre, 120), 'entrante', coalesce(p_tipo, 'text'), left(v_texto, 4000))
  on conflict (wa_msg_id) do nothing
  returning id into v_id;
  if v_id is null then return jsonb_build_object('nuevo', false); end if;
  return jsonb_build_object('nuevo', true, 'id', v_id, 'dueno', v_dueno,
    'pago', v_pago is not null,
    'opinion', (not v_dueno) and v_pago is null and wa_opinion_viva(p_tel) is not null,
    'ventas', (not v_dueno) and v_pago is null and wa_opinion_viva(p_tel) is null and ventas_viva(p_tel) is not null,
    'responder', coalesce((select valor from ajustes where clave = 'wa_respuesta_auto'), 'apagado') = 'encendido');
end;
$$;

create or replace function public.wa_llamar_agente()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_url text;
begin
  if new.direccion <> 'entrante' then return null; end if;
  if wa_es_dueno(new.telefono) then
    select valor into v_url from ajustes where clave = 'wa_agente_url';
  elsif pago_viva(new.telefono) is not null then
    select valor into v_url from ajustes where clave = 'wa_pago_url';
  elsif wa_opinion_viva(new.telefono) is not null then
    select valor into v_url from ajustes where clave = 'wa_opinion_url';
  elsif ventas_viva(new.telefono) is not null then
    select valor into v_url from ajustes where clave = 'wa_ventas_url';
  end if;
  if coalesce(v_url, '') <> '' then
    perform net.http_post(url := v_url, body := jsonb_build_object('id', new.id),
                          headers := '{"Content-Type": "application/json"}'::jsonb,
                          timeout_milliseconds := 120000);
  end if;
  return null;
exception when others then
  raise warning 'wa_llamar_agente: %', sqlerrm;
  return null;
end;
$$;
