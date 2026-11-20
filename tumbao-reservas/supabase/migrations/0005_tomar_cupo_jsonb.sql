-- =====================================================================
-- tomar_cupo() pasa a devolver jsonb en vez del tipo compuesto `reservas`
--
-- POR QUÉ, y no es cosmético:
--
-- Con `returns reservas`, escribir
--     SELECT (tomar_cupo(...)).*
-- hace que Postgres evalúe la función UNA VEZ POR CADA COLUMNA del tipo
-- compuesto. `reservas` tiene 16 columnas.
--
-- Medido sobre el proyecto real: una sola llamada aparente creó
-- 16 reservas y consumió 16 cupos de la clase.
--
-- Es una forma perfectamente natural de escribir la consulta, y el
-- bloqueo FOR UPDATE no protege de esto porque las 16 evaluaciones
-- ocurren dentro de la misma transacción. Una persona dando clic a
-- "reservar" se traga la clase entera.
--
-- Devolver un escalar hace que el error ni siquiera se pueda escribir, y
-- deja la firma igual a la del resto de funciones del proyecto.
-- Los errores de negocio pasan a volver como {ok:false,...} en lugar de
-- excepción, igual que en las funciones de conciliación.
-- =====================================================================

drop function if exists tomar_cupo(uuid, text, text, text, text);

create or replace function tomar_cupo(
  p_clase_id uuid,
  p_nombre   text,
  p_telefono text,
  p_email    text,
  p_origen   text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_clase    clases%rowtype;
  v_reserva  reservas%rowtype;
  v_codigo   text;
  v_intentos int := 0;
begin
  -- FOR UPDATE bloquea la fila: cualquier otra transacción que quiera
  -- esta misma clase espera aquí. Sin esto hay sobreventa.
  select * into v_clase from clases where id = p_clase_id for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'CLASE_NO_EXISTE',
      'mensaje', 'Esa clase ya no está disponible.');
  end if;
  if not v_clase.activa then
    return jsonb_build_object('ok', false, 'error', 'CLASE_INACTIVA',
      'mensaje', 'Esa clase fue cancelada.');
  end if;
  if v_clase.fecha_hora < now() then
    return jsonb_build_object('ok', false, 'error', 'CLASE_YA_PASO',
      'mensaje', 'Esa clase ya empezó. Elige otro horario.');
  end if;
  if v_clase.cupo_tomado >= v_clase.cupo_total then
    return jsonb_build_object('ok', false, 'error', 'SIN_CUPO',
      'mensaje', 'Esa clase se llenó. Elige otro horario.');
  end if;

  update clases set cupo_tomado = cupo_tomado + 1 where id = p_clase_id;

  loop
    v_intentos := v_intentos + 1;
    v_codigo := generar_codigo_reserva();
    begin
      insert into reservas (codigo, clase_id, nombre, telefono, email, origen)
      values (v_codigo, p_clase_id, p_nombre, p_telefono, p_email, p_origen)
      returning * into v_reserva;
      exit;
    exception when unique_violation then
      if v_intentos >= 5 then raise; end if;
    end;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'reserva_id', v_reserva.id,
    'codigo',     v_reserva.codigo,
    'nombre',     v_reserva.nombre,
    'telefono',   v_reserva.telefono,
    'estado',     v_reserva.estado,
    'expira_en',  v_reserva.expira_en,
    'clase',      v_clase.nombre,
    'profesor',   v_clase.profesor,
    'fecha_hora', v_clase.fecha_hora,
    'lugar',      v_clase.lugar,
    'precio_cop', v_clase.precio_cop,
    'cupos_restantes', v_clase.cupo_total - v_clase.cupo_tomado - 1);
end;
$$;

revoke execute on function tomar_cupo(uuid, text, text, text, text) from public;
grant  execute on function tomar_cupo(uuid, text, text, text, text) to service_role;
