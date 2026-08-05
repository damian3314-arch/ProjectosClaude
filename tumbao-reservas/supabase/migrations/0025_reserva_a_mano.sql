-- ---------------------------------------------------------------------
-- 0025 — Crear una reserva desde el panel
--
-- Mucha gente no autogestiona: escribe por WhatsApp, manda el
-- comprobante, y espera que recepción la anote. Hoy la recepcionista
-- tendría que ir a la página del cliente, llenar el formulario con los
-- datos de otra persona, pasar por la pantalla de pago y después
-- aprobarla en la cola. Toda la vuelta, para algo que ella ya sabe.
--
-- LO QUE NO SE PUEDE SALTAR
-- El aforo. Esta función NO inserta en `reservas` por su cuenta: llama
-- a tomar_cupo, que es quien bloquea la fila de la clase y cuenta. Si
-- se escribiera el insert aquí, el panel podría vender un cupo que no
-- existe — justo lo que todo este sistema existe para impedir.
--
-- Queda confirmada de una porque la recepcionista tiene el comprobante
-- en la mano. Y queda marcada con origen 'recepcion', para que en el
-- cierre se pueda separar lo que entró solo de lo que entró a mano.
-- ---------------------------------------------------------------------
create or replace function admin_crear_reserva(
  p_token    text,
  p_clase_id uuid,
  p_nombre   text,
  p_telefono text,
  p_tipo     text default 'suelta',
  p_nota     text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_tel   text;
  v_r     jsonb;
  v_cod   text;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  if length(btrim(coalesce(p_nombre, ''))) < 2 then
    return jsonb_build_object('ok', false, 'error', 'NOMBRE_CORTO',
      'mensaje', 'Escribe el nombre de la persona.');
  end if;

  -- Mismo trato que en la página: solo dígitos, y se le quita el 57 si
  -- vino pegado. Así el mismo cliente no queda con dos celulares
  -- distintos según por dónde reservó.
  v_tel := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  if length(v_tel) = 12 and left(v_tel, 2) = '57' then
    v_tel := substr(v_tel, 3);
  end if;
  if length(v_tel) <> 10 then
    return jsonb_build_object('ok', false, 'error', 'CELULAR_INVALIDO',
      'mensaje', 'El celular debe tener 10 dígitos.');
  end if;

  -- El cupo lo da tomar_cupo, con su bloqueo de fila. Si no hay, aquí
  -- se acaba: recepción no puede meter a nadie por encima del aforo.
  v_r := tomar_cupo(p_clase_id, btrim(p_nombre), v_tel, null,
                    'recepcion',
                    case when p_tipo = 'miembro' then 'miembro' else 'suelta' end);

  if (v_r->>'ok')::boolean is not true then
    return v_r;   -- SIN_CUPO, CLASE_YA_PASO, MEMBRESIA_NO_ENCONTRADA…
  end if;

  v_cod := v_r->>'codigo';

  -- Un miembro ya sale confirmado de tomar_cupo: no paga. Una suelta
  -- sale esperando pago, y aquí se confirma porque la recepcionista
  -- tiene el comprobante delante.
  if (v_r->>'estado') <> 'confirmada' then
    update reservas
       set estado = 'confirmada',
           resuelta_por = v_admin,
           resuelta_at = now(),
           updated_at = now()
     where codigo = v_cod;
  end if;

  -- La columna se llama pagador_nombre, no pagador. Aquí guarda lo que
  -- recepción quiera dejar anotado —"pagó por Nequi la mamá"— que es
  -- justo el dato que después explica por qué el nombre del banco no
  -- coincide con el de la reserva.
  if p_nota is not null and btrim(p_nota) <> '' then
    update reservas set pagador_nombre = left(btrim(p_nota), 80) where codigo = v_cod;
  end if;

  return jsonb_build_object(
    'ok', true,
    'codigo', v_cod,
    'nombre', btrim(p_nombre),
    'telefono', v_tel,
    'tipo', v_r->>'tipo',
    'clase', v_r->>'clase',
    'fecha_hora', v_r->>'fecha_hora',
    'precio_cop', v_r->>'precio_cop',
    'mensaje', 'Reserva creada y confirmada.');
end;
$$;

comment on function admin_crear_reserva(text, uuid, text, text, text, text) is
  'Crea una reserva desde el panel, ya confirmada. Pasa por tomar_cupo: no se salta el aforo.';

revoke execute on function admin_crear_reserva(text, uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function admin_crear_reserva(text, uuid, text, text, text, text)
  to service_role;
