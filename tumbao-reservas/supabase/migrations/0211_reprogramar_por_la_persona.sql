-- 0211 · Reprogramar una clase suelta ya pagada, SIN pasar por recepción (pedido de Damián, 19 nov 2026).
-- La persona entra a la página con el código de su reserva y los últimos 4 números de su celular, y mueve su clase a otra que tenga cupo.
-- Reglas:
--  · Solo clase suelta CONFIRMADA y pagada (pago de la página, cobro en caja, comprobante apuntado o pago de su grupo).
--  · Tiene 3 días: desde el día de la clase (hora de Bogotá) hasta 3 días después. Puede mover antes de la clase o después si no vino.
--  · Las clases con la promoción (2 por $24.000, Aguinaldos) NO se reprograman: son especiales (Damián, 19 nov). Se reconocen porque lo que
--    vale la reserva (valor_reserva, 0207) es menos que el precio de la clase. La página les dice que no aplica.
--  · Si ya entró a esa clase (asistencia marcada) no se puede. Se mueve UNA sola vez: la clase reprogramada ya no se vuelve a mover.
--  · La clase nueva nace confirmada y sin pago propio (la plata ya entró con la vieja), igual que la reprogramación de recepción
--    (origen 'reprogramada', viene_de). Si la vieja todavía no pasaba, su cupo se libera para otra persona.
--  · Queda en caja_auditoria («Cliente (página)»), con el código viejo y el nuevo.
-- Sin DROP ni DELETE. Solo las llama el Worker (service_role).

create or replace function public._reprogramar_estado(p_codigo text, p_celular4 text)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_temp' as $$
declare
  r      reservas%rowtype;
  c      clases%rowtype;
  v_hoy  date := (now() at time zone 'America/Bogota')::date;
  v_dia  date;
  v_vence date;
  v_pago boolean;
  v_c4   text := right(regexp_replace(coalesce(p_celular4, ''), '\D', '', 'g'), 4);
begin
  select * into r from reservas where codigo = upper(btrim(coalesce(p_codigo, '')));
  if not found or length(v_c4) <> 4
     or right(regexp_replace(coalesce(r.telefono, ''), '\D', '', 'g'), 4) <> v_c4 then
    return jsonb_build_object('ok', false, 'error', 'NO_ENCONTRADA',
      'mensaje', 'No encontramos una reserva con ese código y esos números. Revisa el código que te llegó al reservar.');
  end if;
  select * into c from clases where id = r.clase_id;
  v_dia := (c.fecha_hora at time zone 'America/Bogota')::date;
  v_vence := v_dia + 3;

  v_pago := r.pago_id is not null or r.cobro_mov_id is not null or r.referencia_pago is not null
            or exists (select 1 from reservas x where x.grupo_id is not null and x.grupo_id = coalesce(r.grupo_id, r.id)
                          and x.pago_id is not null);

  return jsonb_build_object('ok', true,
    'reserva_id', r.id, 'codigo', r.codigo, 'nombre', r.nombre, 'telefono', r.telefono, 'email', r.email,
    'clase_id', c.id, 'clase', c.nombre, 'fecha_hora', c.fecha_hora, 'dia', v_dia, 'vence', v_vence,
    'clase_paso', c.fecha_hora <= now(),
    'error_elegible',
      case
        when r.estado <> 'confirmada' then 'NO_CONFIRMADA'
        when r.tipo = 'tiquetera' then 'ES_TIQUETERA'
        when r.tipo <> 'suelta' then 'ES_MIEMBRO'
        when r.reprogramada_a is not null then 'YA_REPROGRAMADA'
        when r.origen = 'reprogramada' or r.viene_de is not null then 'YA_ES_REPROGRAMACION'
        when valor_reserva(r.id) < coalesce(c.precio_cop, 0) then 'ES_PROMO'
        when not v_pago then 'SIN_PAGO'
        when exists (select 1 from asistencias a where a.reserva_id = r.id) then 'YA_ASISTIO'
        when v_hoy > v_vence then 'VENCIDA'
        else null end);
end;
$$;

create or replace function public._reprogramar_mensaje(p_error text, p_vence date)
returns text language sql immutable as $$
  select case p_error
    when 'NO_CONFIRMADA' then 'Esa reserva no está confirmada, así que no hay una clase pagada para mover. Escríbenos por WhatsApp y lo revisamos.'
    when 'ES_TIQUETERA' then 'Esa clase salió de tu tiquetera: reserva otra con tu código de tiquetera en la página, sin necesidad de reprogramar.'
    when 'ES_MIEMBRO' then 'Con tu mensualidad no necesitas reprogramar: vienes a tu horario.'
    when 'YA_REPROGRAMADA' then 'Esta clase ya la moviste a otro día. Revisa tu código nuevo.'
    when 'YA_ES_REPROGRAMACION' then 'Esta clase ya es una reprogramación: solo se puede mover una vez. Escríbenos por WhatsApp si te surgió algo.'
    when 'ES_PROMO' then 'Las clases de la promoción (2 personas por $24.000) son especiales y no se pueden reprogramar. Si tienes una duda, escríbenos por WhatsApp.'
    when 'SIN_PAGO' then 'Todavía no vemos el pago de esta reserva. Compártenos el soporte por WhatsApp para validarlo y luego la reprogramas.'
    when 'YA_ASISTIO' then 'Esa clase ya la tomaste, no se puede reprogramar.'
    when 'VENCIDA' then 'El plazo para reprogramar esta clase terminó el ' || to_char(p_vence, 'DD/MM') || ' (son 3 días desde la clase). Escríbenos por WhatsApp y vemos qué se puede hacer.'
    else 'No se puede reprogramar esta reserva.' end;
$$;

create or replace function public.reprogramar_consulta(p_codigo text, p_celular4 text)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_temp' as $$
declare e jsonb; v_clases jsonb;
begin
  e := _reprogramar_estado(p_codigo, p_celular4);
  if (e->>'ok')::boolean is not true then return e; end if;
  if e->>'error_elegible' is not null then
    return jsonb_build_object('ok', true, 'elegible', false, 'error', e->>'error_elegible',
      'mensaje', _reprogramar_mensaje(e->>'error_elegible', (e->>'vence')::date),
      'reserva', jsonb_build_object('codigo', e->>'codigo', 'nombre', e->>'nombre', 'clase', e->>'clase', 'fecha_hora', e->'fecha_hora'));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'clase_id', c.id, 'nombre', c.nombre, 'fecha_hora', c.fecha_hora,
           'libres', greatest(c.cupo_total - c.cupo_tomado, 0)) order by c.fecha_hora), '[]'::jsonb)
    into v_clases
    from clases c
   where c.activa and c.fecha_hora > now() + interval '30 minutes'
     and c.fecha_hora < now() + interval '15 days'
     and c.cupo_tomado < c.cupo_total
     and c.id <> (e->>'clase_id')::uuid;

  return jsonb_build_object('ok', true, 'elegible', true,
    'reserva', jsonb_build_object('codigo', e->>'codigo', 'nombre', e->>'nombre', 'clase', e->>'clase',
                                  'fecha_hora', e->'fecha_hora', 'clase_paso', (e->>'clase_paso')::boolean,
                                  'vence', e->>'vence'),
    'clases', v_clases);
end;
$$;

create or replace function public.reprogramar_propia(p_codigo text, p_celular4 text, p_clase_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public','extensions','pg_temp' as $$
declare
  e       jsonb;
  v_res   reservas%rowtype;
  v_nueva jsonb;
  v_id    uuid;
  v_antes boolean;
begin
  e := _reprogramar_estado(p_codigo, p_celular4);
  if (e->>'ok')::boolean is not true then return e; end if;
  if e->>'error_elegible' is not null then
    return jsonb_build_object('ok', false, 'error', e->>'error_elegible',
      'mensaje', _reprogramar_mensaje(e->>'error_elegible', (e->>'vence')::date));
  end if;

  -- Se bloquea la reserva vieja y se vuelve a mirar con el bloqueo puesto: dos toques seguidos no la mueven dos veces.
  select * into v_res from reservas where id = (e->>'reserva_id')::uuid for update;
  if v_res.reprogramada_a is not null then
    return jsonb_build_object('ok', false, 'error', 'YA_REPROGRAMADA', 'mensaje', _reprogramar_mensaje('YA_REPROGRAMADA', null));
  end if;
  if p_clase_id is null or p_clase_id = v_res.clase_id then
    return jsonb_build_object('ok', false, 'error', 'MISMA_CLASE', 'mensaje', 'Escoge una clase distinta a la que reservaste.');
  end if;
  if not exists (select 1 from clases c where c.id = p_clase_id and c.activa
                    and c.fecha_hora > now() + interval '30 minutes' and c.fecha_hora < now() + interval '15 days') then
    return jsonb_build_object('ok', false, 'error', 'CLASE_NO_DISPONIBLE',
      'mensaje', 'Esa clase ya no está disponible. Escoge otra de la lista.');
  end if;

  -- El cupo lo da tomar_cupo con su bloqueo de fila: si la clase nueva se llenó, aquí se acaba. No puede sobrevender.
  v_nueva := tomar_cupo(p_clase_id, v_res.nombre, v_res.telefono, v_res.email, 'reprogramada', 'suelta');
  if (v_nueva->>'ok')::boolean is not true then
    return jsonb_build_object('ok', false, 'error', coalesce(v_nueva->>'error', 'SIN_CUPO'),
      'mensaje', 'Se llenó esa clase mientras escogías. Escoge otra de la lista.');
  end if;
  v_id := (v_nueva->>'reserva_id')::uuid;

  update reservas
     set estado = 'confirmada', viene_de = v_res.id, resuelta_at = now(), updated_at = now()
   where id = v_id;

  v_antes := (e->>'clase_paso')::boolean is not true;
  if v_antes then
    -- La clase vieja todavía no pasaba: su cupo queda libre para otra persona.
    update reservas set reprogramada_a = v_id, updated_at = now() where id = v_res.id;
    update clases set cupo_tomado = greatest(cupo_tomado - 1, 0) where id = v_res.clase_id;
  else
    -- No vino: queda como el crédito de siempre (3 días) y se usa.
    update reservas
       set reprogramada_a = v_id, no_vino_at = coalesce(no_vino_at, now()),
           credito_vence = coalesce(credito_vence, (e->>'vence')::date), updated_at = now()
     where id = v_res.id;
  end if;

  insert into caja_auditoria (admin_id, quien, accion, codigo, clase_id, nombre, motivo, detalle)
  values (null, 'Cliente (página)', 'reprogramar_autogestion', v_res.codigo, v_res.clase_id, v_res.nombre,
          'Reprogramó su propia clase ' || case when v_antes then 'antes de que pasara' else 'después de no venir' end,
          jsonb_build_object('codigo_nuevo', v_nueva->>'codigo', 'clase_nueva', p_clase_id, 'fecha_nueva', v_nueva->>'fecha_hora'));

  return jsonb_build_object('ok', true,
    'codigo', v_nueva->>'codigo', 'codigo_viejo', v_res.codigo, 'nombre', v_res.nombre,
    'clase', v_nueva->>'clase', 'fecha_hora', v_nueva->>'fecha_hora',
    'mensaje', 'Listo, tu clase quedó reprogramada. Tu código nuevo es ' || (v_nueva->>'codigo') || '.');
end;
$$;

revoke all on function public._reprogramar_estado(text, text) from public, anon, authenticated;
revoke all on function public._reprogramar_mensaje(text, date) from public, anon, authenticated;
revoke all on function public.reprogramar_consulta(text, text) from public, anon, authenticated;
revoke all on function public.reprogramar_propia(text, text, uuid) from public, anon, authenticated;
grant execute on function public._reprogramar_estado(text, text), public._reprogramar_mensaje(text, date),
      public.reprogramar_consulta(text, text), public.reprogramar_propia(text, text, uuid) to service_role;
