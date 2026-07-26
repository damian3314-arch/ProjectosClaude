-- =====================================================================
-- Conciliación usando el nombre del remitente como desempate
--
-- Reglas, en orden:
--   0 candidatas  -> se registra el pago y nada más
--   1 candidata   -> se confirma, AUNQUE el nombre no calce. Es normal
--                    que pague la mamá, la pareja o un amigo.
--   2 o más       -> gana la única cuyo nombre calce con el remitente.
--                    Si ninguna calza, o calzan varias, va a validación
--                    humana igual que antes.
--
-- Nunca empeora respecto a la versión anterior: los casos que antes
-- iban a un humano siguen yendo, y algunos que antes iban ahora se
-- resuelven solos.
--
-- Verificado sobre el proyecto real:
--   · 2 esperando + paga CAMILA        -> confirma a Camila (metodo: nombre_remitente)
--   · luego paga ANDRES               -> confirma a Andrés
--   · 2 esperando + paga ROSA (ajena)  -> 0 confirmadas, va a humano
--   · 1 esperando + paga la mamá       -> confirma (metodo: monto_unico)
-- =====================================================================

create or replace function registrar_pago_y_conciliar(
  p_banco      text,
  p_valor_cop  int,
  p_fecha_pago timestamptz,
  p_referencia text default null,
  p_remitente  text default null,
  p_ultimos_4  text default null,
  p_confianza  numeric default 1.0,
  p_raw_email  text default null,
  p_hoja_fila  text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_pago       pagos%rowtype;
  v_reserva    reservas%rowtype;
  v_candidatos int;
  v_con_nombre int;
  v_metodo     text := 'monto_unico';
begin
  if p_valor_cop is null or p_valor_cop <= 0 then
    return jsonb_build_object('ok', false, 'error', 'valor_invalido');
  end if;

  insert into pagos (banco, valor_cop, fecha_pago, referencia,
                     remitente, ultimos_4, raw_email, hoja_fila)
  values (p_banco, p_valor_cop, p_fecha_pago, p_referencia,
          p_remitente, p_ultimos_4, p_raw_email, p_hoja_fila)
  on conflict (banco, valor_cop, fecha_pago, coalesce(referencia, ''))
  do nothing
  returning * into v_pago;

  if not found then
    select * into v_pago from pagos
     where banco = p_banco and valor_cop = p_valor_cop
       and fecha_pago = p_fecha_pago
       and coalesce(referencia, '') = coalesce(p_referencia, '');
    return jsonb_build_object('ok', true, 'duplicado', true,
      'pago_id', v_pago.id, 'accion', 'ninguna');
  end if;

  if p_confianza < 0.9 then
    return jsonb_build_object('ok', true, 'duplicado', false,
      'pago_id', v_pago.id, 'accion', 'solo_registrado',
      'motivo', 'confianza_baja');
  end if;

  create temp table if not exists _cand (id uuid, puntaje numeric) on commit drop;
  delete from _cand;

  insert into _cand (id, puntaje)
  select r.id, similitud_nombre(r.nombre, p_remitente)
    from reservas r
    join clases c on c.id = r.clase_id
   where r.estado in ('verificando', 'pendiente_validacion')
     and r.pago_id is null
     and c.precio_cop = p_valor_cop
     and p_fecha_pago between r.created_at - interval '15 minutes'
                          and r.created_at + interval '3 hours';

  select count(*) into v_candidatos from _cand;

  if v_candidatos = 0 then
    return jsonb_build_object('ok', true, 'duplicado', false,
      'pago_id', v_pago.id, 'accion', 'sin_reserva_que_casar');
  end if;

  if v_candidatos = 1 then
    select r.* into v_reserva from reservas r
     where r.id = (select id from _cand limit 1)
       for update skip locked;
  else
    select count(*) into v_con_nombre from _cand where puntaje >= 0.5;

    if v_con_nombre <> 1 then
      return jsonb_build_object('ok', true, 'duplicado', false,
        'pago_id', v_pago.id, 'accion', 'ambiguo',
        'candidatos', v_candidatos,
        'con_nombre_parecido', v_con_nombre,
        'remitente', p_remitente);
    end if;

    v_metodo := 'nombre_remitente';
    select r.* into v_reserva from reservas r
     where r.id = (select id from _cand where puntaje >= 0.5 limit 1)
       for update skip locked;
  end if;

  if not found then
    return jsonb_build_object('ok', true, 'duplicado', false,
      'pago_id', v_pago.id, 'accion', 'sin_reserva_que_casar');
  end if;

  update reservas
     set estado = 'confirmada', pago_id = v_pago.id, updated_at = now()
   where id = v_reserva.id;

  update pagos set consumido = true where id = v_pago.id;

  return jsonb_build_object('ok', true, 'duplicado', false,
    'pago_id', v_pago.id, 'accion', 'reserva_confirmada',
    'metodo', v_metodo, 'candidatos', v_candidatos,
    'reserva_id', v_reserva.id, 'codigo', v_reserva.codigo,
    'nombre', v_reserva.nombre, 'telefono', v_reserva.telefono);
end;
$$;


create or replace function conciliar_reserva(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_reserva reservas%rowtype;
  v_clase   clases%rowtype;
  v_pago    pagos%rowtype;
  v_cand    int;
  v_metodo  text := 'monto_unico';
begin
  select * into v_reserva from reservas
   where upper(btrim(codigo)) = upper(btrim(p_codigo))
     for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_encontrada');
  end if;

  select * into v_clase from clases where id = v_reserva.clase_id;

  if v_reserva.estado <> 'verificando' then
    return jsonb_build_object('ok', true, 'estado', v_reserva.estado,
      'codigo', v_reserva.codigo, 'clase', v_clase.nombre,
      'fecha_hora', v_clase.fecha_hora);
  end if;

  select count(*) into v_cand
    from pagos p
   where not p.consumido
     and p.valor_cop = v_clase.precio_cop
     and p.fecha_pago between v_reserva.created_at - interval '15 minutes'
                          and v_reserva.created_at + interval '3 hours';

  if v_cand = 1 then
    select * into v_pago from pagos p
     where not p.consumido
       and p.valor_cop = v_clase.precio_cop
       and p.fecha_pago between v_reserva.created_at - interval '15 minutes'
                            and v_reserva.created_at + interval '3 hours'
       for update skip locked;
  elsif v_cand > 1 then
    select * into v_pago from pagos p
     where not p.consumido
       and p.valor_cop = v_clase.precio_cop
       and p.fecha_pago between v_reserva.created_at - interval '15 minutes'
                            and v_reserva.created_at + interval '3 hours'
       and similitud_nombre(v_reserva.nombre, p.remitente) >= 0.5
       for update skip locked;
    if found then v_metodo := 'nombre_remitente'; end if;
  end if;

  if v_pago.id is not null then
    update reservas
       set estado = 'confirmada', pago_id = v_pago.id, updated_at = now()
     where id = v_reserva.id;
    update pagos set consumido = true where id = v_pago.id;

    return jsonb_build_object('ok', true, 'estado', 'confirmada',
      'metodo', v_metodo, 'codigo', v_reserva.codigo,
      'clase', v_clase.nombre, 'fecha_hora', v_clase.fecha_hora);
  end if;

  return jsonb_build_object('ok', true, 'estado', 'verificando',
    'codigo', v_reserva.codigo, 'clase', v_clase.nombre,
    'fecha_hora', v_clase.fecha_hora, 'candidatos', v_cand);
end;
$$;

revoke execute on function registrar_pago_y_conciliar(text,int,timestamptz,text,text,text,numeric,text,text) from public, anon, authenticated;
revoke execute on function conciliar_reserva(text) from public, anon, authenticated;
grant execute on function registrar_pago_y_conciliar(text,int,timestamptz,text,text,text,numeric,text,text) to service_role;
grant execute on function conciliar_reserva(text) to service_role;
