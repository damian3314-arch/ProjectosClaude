-- =====================================================================
-- Panel de administración
--
-- Tres cosas que hoy no se pueden hacer:
--
--   1. Armar el horario de una semana a mano. generar_horario() aplica
--      siempre el mismo molde (L-V 7am/6pm/7pm, sáb 8am/9am). Si una
--      semana hay festivo, o se abre una clase extra, no hay por dónde.
--
--   2. Forzar los cupos de una clase. Hoy salen siempre de
--      aforo − afiliados_activos. Si un día caben menos porque hay
--      evento, o se quieren soltar más, no hay perilla.
--
--   3. Darle el check a un pago que no concilió solo. Esto estaba en el
--      flujo desde el principio — "el humano da el check y le envía un
--      mensaje por WhatsApp" — pero no existía la función. Las reservas
--      caían en pendiente_validacion y ahí se quedaban para siempre.
--
-- Todo pasa por un token de admin. Sin token no se ejecuta nada.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Cupo forzado a mano
--
-- null  = automático (aforo − activos), que es el comportamiento normal
-- un nº = se respeta ese, pase lo que pase con las membresías
-- ---------------------------------------------------------------------
alter table clases add column if not exists cupo_manual int
  check (cupo_manual is null or cupo_manual >= 0);

comment on column clases.cupo_manual is
  'Cupos sueltos forzados a mano. null = calculado desde las membresias.';


-- ---------------------------------------------------------------------
-- Tokens de admin
--
-- Se guarda el hash, no el token. Si alguien se lleva la tabla no puede
-- entrar; y si se pierde el token no hay forma de recuperarlo, se emite
-- otro y listo.
-- ---------------------------------------------------------------------
create table if not exists admin_tokens (
  id          uuid primary key default extensions.gen_random_uuid(),
  nombre      text not null,
  token_hash  text not null unique,
  creado_at   timestamptz not null default now(),
  ultimo_uso  timestamptz,
  activo      boolean not null default true
);

alter table admin_tokens enable row level security;


create or replace function hash_token(p_token text)
returns text
language sql
immutable
set search_path = public, extensions, pg_temp
as $$
  select encode(extensions.digest(p_token, 'sha256'), 'hex');
$$;


-- Emite un token nuevo. Lo devuelve UNA sola vez: después ya no se
-- puede volver a leer, solo emitir otro.
create or replace function crear_token_admin(p_nombre text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_token text;
begin
  if coalesce(trim(p_nombre), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'sin_nombre',
      'mensaje', 'Ponle un nombre para saber de quien es el token.');
  end if;

  -- 32 bytes en base64url: suficiente y sin caracteres que se rompan
  -- al pegarlos en una URL.
  v_token := translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_');

  insert into admin_tokens (nombre, token_hash)
  values (trim(p_nombre), hash_token(v_token));

  return jsonb_build_object('ok', true, 'token', v_token,
    'mensaje', 'Guardalo ya. No se puede volver a ver.');
end;
$$;


create or replace function verificar_token_admin(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_id uuid;
begin
  if coalesce(p_token, '') = '' then return null; end if;

  select id into v_id
    from admin_tokens
   where token_hash = hash_token(p_token)
     and activo
   limit 1;

  if v_id is not null then
    update admin_tokens set ultimo_uso = now() where id = v_id;
  end if;
  return v_id;
end;
$$;


-- ---------------------------------------------------------------------
-- recalcular_cupos, ahora respetando el cupo forzado a mano
--
-- Cambia solo eso respecto a 0009: si cupo_manual tiene valor, ese
-- manda. El greatest(cupo_tomado, ...) se mantiene porque el CHECK
-- cupo_tomado <= cupo_total sigue ahi, y preferimos pasarnos un puesto
-- antes que cancelarle a alguien que ya pago.
-- ---------------------------------------------------------------------
create or replace function recalcular_cupos()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_afectadas int;
  v_apretadas int;
  v_manuales  int;
begin
  with calculo as (
    select c.id,
           c.aforo,
           c.cupo_tomado,
           c.cupo_manual,
           (select count(*)
              from membresias m
             where m.hora = (c.fecha_hora at time zone 'America/Bogota')::time
               and (c.fecha_hora at time zone 'America/Bogota')::date
                   between m.inicio and m.fin)::int as activos
      from clases c
     where c.fecha_hora > now()
  ),
  objetivo as (
    select k.*,
           greatest(
             k.cupo_tomado,
             coalesce(k.cupo_manual, greatest(k.aforo - k.activos, 0))
           ) as meta
      from calculo k
  ),
  aplicado as (
    update clases c
       set activos_plan = o.activos,
           cupo_total   = o.meta
      from objetivo o
     where c.id = o.id
       and (c.activos_plan is distinct from o.activos
            or c.cupo_total is distinct from o.meta)
     returning c.id,
               o.cupo_manual,
               coalesce(o.cupo_manual, greatest(o.aforo - o.activos, 0)) as ideal,
               c.cupo_total as real
  )
  select count(*)::int,
         count(*) filter (where real > ideal)::int,
         count(*) filter (where cupo_manual is not null)::int
    into v_afectadas, v_apretadas, v_manuales
    from aplicado;

  return jsonb_build_object(
    'ok', true,
    'clases_actualizadas', v_afectadas,
    'clases_con_cupo_manual', v_manuales,
    'clases_sobrevendidas_por_reservas_previas', v_apretadas);
end;
$$;


-- ---------------------------------------------------------------------
-- La semana, como la ve el panel
--
-- Devuelve siempre los 7 días completos, existan clases o no, para que
-- la cuadrícula se pueda pintar sin adivinar.
-- ---------------------------------------------------------------------
create or replace function admin_semana(p_token text, p_desde date)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_dias  jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select coalesce(jsonb_agg(d order by d->>'fecha'), '[]'::jsonb) into v_dias
  from (
    select jsonb_build_object(
      'fecha', dia,
      'dow',   extract(dow from dia)::int,
      'clases', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'clase_id',    c.id,
                 'nombre',      c.nombre,
                 'hora',        to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'),
                 'profesor',    c.profesor,
                 'activa',      c.activa,
                 'aforo',       c.aforo,
                 'activos_plan', c.activos_plan,
                 'cupo_total',  c.cupo_total,
                 'cupo_tomado', c.cupo_tomado,
                 'cupo_manual', c.cupo_manual,
                 'ya_paso',     c.fecha_hora <= now()
               ) order by c.fecha_hora)
          from clases c
         where (c.fecha_hora at time zone 'America/Bogota')::date = dia
      ), '[]'::jsonb)
    ) as d
    from generate_series(p_desde, p_desde + 6, interval '1 day') g(dia)
  ) s;

  return jsonb_build_object('ok', true, 'desde', p_desde,
    'hasta', p_desde + 6, 'dias', v_dias);
end;
$$;


-- ---------------------------------------------------------------------
-- Guardar la semana de un golpe
--
-- p_celdas = [{fecha, hora, activa, cupo_manual, aforo, profesor}, ...]
--   fecha 'YYYY-MM-DD', hora 'HH:MM'
--   activa false      -> la clase se apaga (no se borra: si alguien ya
--                        reservó, borrarla se llevaría la reserva por
--                        delante)
--   cupo_manual null  -> vuelve al cálculo automático
--
-- Se hace todo en una transacción: o entra la semana entera o no entra
-- nada. Así no queda media semana guardada si algo falla.
-- ---------------------------------------------------------------------
create or replace function admin_guardar_semana(p_token text, p_celdas jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin    uuid;
  v_celda    jsonb;
  v_fecha    date;
  v_hora     time;
  v_momento  timestamptz;
  v_clase    clases%rowtype;
  v_creadas  int := 0;
  v_editadas int := 0;
  v_apagadas int := 0;
  v_avisos   jsonb := '[]'::jsonb;
  v_cupo_manual int;
  v_aforo    int;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  if p_celdas is null or jsonb_typeof(p_celdas) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'SIN_DATOS',
      'mensaje', 'No llego ninguna celda que guardar.');
  end if;

  for v_celda in select * from jsonb_array_elements(p_celdas) loop
    v_fecha := (v_celda->>'fecha')::date;
    v_hora  := (v_celda->>'hora')::time;
    v_momento := (v_fecha + v_hora) at time zone 'America/Bogota';

    v_cupo_manual := case
      when v_celda->>'cupo_manual' is null then null
      else (v_celda->>'cupo_manual')::int end;
    v_aforo := coalesce((v_celda->>'aforo')::int, 30);

    select * into v_clase from clases where fecha_hora = v_momento;

    if not found then
      -- No se crean clases en el pasado: no sirven para nada y ensucian.
      if v_momento <= now() then
        v_avisos := v_avisos || jsonb_build_object(
          'fecha', v_fecha, 'hora', to_char(v_hora, 'HH24:MI'),
          'aviso', 'no se creo, esa hora ya paso');
        continue;
      end if;
      if coalesce((v_celda->>'activa')::boolean, true) then
        insert into clases (nombre, profesor, fecha_hora, duracion_min,
                            cupo_total, precio_cop, lugar, aforo, activa, cupo_manual)
        values (
          coalesce(nullif(trim(v_celda->>'nombre'), ''),
                   'Clase ' || trim(to_char(v_fecha + v_hora, 'HH12:MI am'))),
          coalesce(nullif(trim(v_celda->>'profesor'), ''), 'Por asignar'),
          v_momento, 60,
          coalesce(v_cupo_manual, v_aforo),
          coalesce((v_celda->>'precio_cop')::int, 15000),
          'Sede Tumbao', v_aforo, true, v_cupo_manual);
        v_creadas := v_creadas + 1;
      end if;
      continue;
    end if;

    -- Apagar una clase que ya tiene gente adentro es peor que dejarla.
    if coalesce((v_celda->>'activa')::boolean, true) = false
       and v_clase.cupo_tomado > 0 then
      v_avisos := v_avisos || jsonb_build_object(
        'fecha', v_fecha, 'hora', to_char(v_hora, 'HH24:MI'),
        'aviso', 'no se apago: ya tiene ' || v_clase.cupo_tomado || ' reserva(s)');
      continue;
    end if;

    -- Un cupo manual por debajo de lo ya reservado dejaria la tabla en
    -- un estado invalido; se sube a lo minimo posible y se avisa.
    if v_cupo_manual is not null and v_cupo_manual < v_clase.cupo_tomado then
      v_avisos := v_avisos || jsonb_build_object(
        'fecha', v_fecha, 'hora', to_char(v_hora, 'HH24:MI'),
        'aviso', 'se dejo en ' || v_clase.cupo_tomado ||
                 ': ya hay esas reservas, no se puede bajar mas');
      v_cupo_manual := v_clase.cupo_tomado;
    end if;

    update clases
       set activa      = coalesce((v_celda->>'activa')::boolean, activa),
           aforo       = v_aforo,
           cupo_manual = v_cupo_manual,
           cupo_total  = greatest(cupo_tomado,
                                  coalesce(v_cupo_manual,
                                           greatest(v_aforo - activos_plan, 0))),
           profesor    = coalesce(nullif(trim(v_celda->>'profesor'), ''), profesor)
     where id = v_clase.id;

    if coalesce((v_celda->>'activa')::boolean, true) = false then
      v_apagadas := v_apagadas + 1;
    else
      v_editadas := v_editadas + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true,
    'creadas', v_creadas, 'editadas', v_editadas, 'apagadas', v_apagadas,
    'avisos', v_avisos);
end;
$$;


-- ---------------------------------------------------------------------
-- La cola de validación humana
--
-- Lo que quedó esperando el check de alguien: o porque el correo del
-- banco no llegó en 5 minutos, o porque llegaron dos pagos iguales y no
-- se pudo saber cuál era cuál.
-- ---------------------------------------------------------------------
create or replace function admin_pendientes(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_out   jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select coalesce(jsonb_agg(x order by x->>'creada_at'), '[]'::jsonb) into v_out
  from (
    select jsonb_build_object(
      'codigo',     r.codigo,
      'nombre',     r.nombre,
      'telefono',   r.telefono,
      'estado',     r.estado,
      'creada_at',  r.created_at,
      'clase',      c.nombre,
      'fecha_hora', c.fecha_hora,
      'precio_cop', c.precio_cop,
      -- Pagos sin dueño de ese valor, para que quien valida tenga algo
      -- con que comparar en vez de adivinar.
      'pagos_sueltos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'pago_id',   p.id,
                 'valor_cop', p.valor_cop,
                 'fecha',     p.fecha_pago,
                 'remitente', p.remitente,
                 'parecido',  round(similitud_nombre(r.nombre, p.remitente), 2))
               order by p.fecha_pago desc)
          from pagos p
         where p.valor_cop = c.precio_cop
           and p.fecha_pago between r.created_at - interval '30 minutes'
                               and r.created_at + interval '3 hours'
           and not exists (select 1 from reservas r2 where r2.pago_id = p.id)
      ), '[]'::jsonb)
    ) as x
    from reservas r
    join clases c on c.id = r.clase_id
   where r.estado in ('pendiente_validacion', 'verificando')
  ) s;

  return jsonb_build_object('ok', true, 'reservas', v_out);
end;
$$;


-- ---------------------------------------------------------------------
-- El check
--
-- p_pago_id opcional: si se pasa, la reserva queda amarrada a ese pago
-- concreto (y ese pago ya no puede usarse para otra). Si no se pasa, se
-- confirma sin amarrar — para el caso de "me consta que pagó, lo vi".
-- ---------------------------------------------------------------------
create or replace function admin_confirmar(
  p_token text, p_codigo text, p_pago_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin   uuid;
  v_reserva reservas%rowtype;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_reserva from reservas
   where codigo = upper(trim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  if v_reserva.estado = 'confirmada' then
    return jsonb_build_object('ok', true, 'estado', 'confirmada',
      'codigo', v_reserva.codigo, 'mensaje', 'Ya estaba confirmada.');
  end if;

  if v_reserva.estado not in ('pendiente_validacion', 'verificando', 'pendiente_pago') then
    return jsonb_build_object('ok', false, 'error', 'ESTADO_INVALIDO',
      'estado', v_reserva.estado,
      'mensaje', 'Esa reserva esta en ' || v_reserva.estado || ', no se puede confirmar.');
  end if;

  if p_pago_id is not null then
    if exists (select 1 from reservas where pago_id = p_pago_id and id <> v_reserva.id) then
      return jsonb_build_object('ok', false, 'error', 'PAGO_YA_USADO',
        'mensaje', 'Ese pago ya esta amarrado a otra reserva.');
    end if;
    if not exists (select 1 from pagos where id = p_pago_id) then
      return jsonb_build_object('ok', false, 'error', 'PAGO_NO_EXISTE');
    end if;
  end if;

  update reservas
     set estado = 'confirmada',
         pago_id = coalesce(p_pago_id, pago_id),
         updated_at = now()
   where id = v_reserva.id;

  return jsonb_build_object('ok', true, 'estado', 'confirmada',
    'codigo', v_reserva.codigo, 'nombre', v_reserva.nombre,
    'telefono', v_reserva.telefono,
    'mensaje', 'Confirmada a mano.');
end;
$$;


-- ---------------------------------------------------------------------
-- Rechazar: suelta el cupo para que lo pueda tomar alguien más
-- ---------------------------------------------------------------------
create or replace function admin_rechazar(p_token text, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin   uuid;
  v_reserva reservas%rowtype;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_reserva from reservas
   where codigo = upper(trim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  if v_reserva.estado = 'rechazada' then
    return jsonb_build_object('ok', true, 'estado', 'rechazada',
      'codigo', v_reserva.codigo, 'mensaje', 'Ya estaba rechazada.');
  end if;
  if v_reserva.estado = 'confirmada' then
    return jsonb_build_object('ok', false, 'error', 'YA_CONFIRMADA',
      'mensaje', 'Esa reserva ya esta confirmada. Si hay que deshacerla, con cuidado y a mano.');
  end if;

  update reservas set estado = 'rechazada', updated_at = now()
   where id = v_reserva.id;

  update clases set cupo_tomado = greatest(cupo_tomado - 1, 0)
   where id = v_reserva.clase_id;

  return jsonb_build_object('ok', true, 'estado', 'rechazada',
    'codigo', v_reserva.codigo, 'nombre', v_reserva.nombre,
    'telefono', v_reserva.telefono,
    'mensaje', 'Rechazada, el cupo quedo libre.');
end;
$$;


-- ---------------------------------------------------------------------
-- Quién viene a una clase
-- ---------------------------------------------------------------------
create or replace function admin_reservas_de_clase(p_token text, p_clase_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_out   jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo',   r.codigo,
           'nombre',   r.nombre,
           'telefono', r.telefono,
           'tipo',     r.tipo,
           'estado',   r.estado,
           'creada_at', r.created_at)
         order by r.created_at), '[]'::jsonb)
    into v_out
    from reservas r
   where r.clase_id = p_clase_id
     and r.estado not in ('expirada', 'rechazada');

  return jsonb_build_object('ok', true, 'reservas', v_out);
end;
$$;


-- ---------------------------------------------------------------------
-- Permisos: nada de esto se toca con la llave publica
-- ---------------------------------------------------------------------
revoke execute on function hash_token(text)                        from public, anon, authenticated;
revoke execute on function crear_token_admin(text)                 from public, anon, authenticated;
revoke execute on function verificar_token_admin(text)             from public, anon, authenticated;
revoke execute on function admin_semana(text, date)                from public, anon, authenticated;
revoke execute on function admin_guardar_semana(text, jsonb)       from public, anon, authenticated;
revoke execute on function admin_pendientes(text)                  from public, anon, authenticated;
revoke execute on function admin_confirmar(text, text, uuid)       from public, anon, authenticated;
revoke execute on function admin_rechazar(text, text)              from public, anon, authenticated;
revoke execute on function admin_reservas_de_clase(text, uuid)     from public, anon, authenticated;
revoke execute on function recalcular_cupos()                      from public, anon, authenticated;

grant execute on function admin_semana(text, date)            to service_role;
grant execute on function admin_guardar_semana(text, jsonb)   to service_role;
grant execute on function admin_pendientes(text)              to service_role;
grant execute on function admin_confirmar(text, text, uuid)   to service_role;
grant execute on function admin_rechazar(text, text)          to service_role;
grant execute on function admin_reservas_de_clase(text, uuid) to service_role;
grant execute on function crear_token_admin(text)             to service_role;
grant execute on function recalcular_cupos()                  to service_role;
