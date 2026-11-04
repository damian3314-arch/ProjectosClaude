-- ---------------------------------------------------------------------
-- 0042 — Al apuntar a alguien a mano, decir CÓMO pagó
--
-- LO QUE PASÓ EL 19 DE AGOSTO
-- Se apuntaron dos personas a mano a la clase de las 6 pm, 15.000 cada
-- una, y pagaron en efectivo en la puerta. De esos 30.000, solo 15.000
-- llegaron al cajón: alguien se acordó de registrar un movimiento de
-- caja por uno y no por el otro. El cierre esperaba 115.000 y había
-- 295.000 contados.
--
-- POR QUÉ
-- `admin_crear_reserva` no pregunta cómo pagó. Nació suponiendo que
-- apuntar a mano es "ya me llegó el comprobante de la transferencia"
-- —lo dice su propio comentario— y en ese caso la plata está en el
-- banco y no toca el cajón. Pero la realidad de la puerta es que mucha
-- gente paga en efectivo, y entonces esa plata SÍ está en el cajón y el
-- sistema no lo sabe.
--
-- La 0030 ya había visto media película: sacó las reservas a mano de
-- `reservas_cop` para no contarlas dos veces, y las dejó aparte en
-- `reservas_a_mano_cop` "para que si a alguien se le olvida registrarlo
-- en Caja, se note". Se nota, sí — pero solo si alguien lo mira, y a las
-- 7 de la noche con gente en la puerta nadie lo mira. Confiar en que la
-- recepcionista haga un segundo paso en otra pestaña es confiar en la
-- memoria para cuadrar dinero.
--
-- LO QUE HACE ESTA MIGRACIÓN
-- `admin_crear_reserva` recibe `p_medio` y, cuando es 'efectivo',
-- registra el movimiento de caja ella misma, en la misma llamada. Deja
-- de haber un segundo paso que olvidar.
--
-- QUÉ SIGNIFICA CADA MEDIO
--   'efectivo'      la plata está en el cajón  -> se registra en caja
--   'transferencia' la plata está en el banco  -> no toca el cajón
--   null            como antes: se trata como transferencia
--
-- El null existe solo para que el panel viejo siga funcionando entre
-- que se pega este SQL y se despliega el panel nuevo. El panel nuevo
-- siempre manda el medio.
--
-- NO SE PUEDE CONTAR DOS VECES
-- Una reserva apuntada a mano no tiene `pago_id`, y `reservas_cop` solo
-- suma las que lo tienen (0030). Así que el movimiento de caja que crea
-- esta función es el ÚNICO sitio donde esos 15.000 se cuentan.
--
-- SI EL DÍA YA ESTÁ CERRADO
-- La reserva se crea igual —la persona está en la puerta y quiere
-- bailar— pero el efectivo no se puede registrar sobre un día cerrado.
-- En vez de tragárselo, la respuesta trae `efectivo_registrado: false` y
-- un mensaje, para que el panel lo diga en rojo. Plata que no entró y
-- nadie sabe es exactamente lo que esta migración viene a evitar.
-- ---------------------------------------------------------------------

create or replace function admin_crear_reserva(
  p_token    text,
  p_clase_id uuid,
  p_nombre   text,
  p_telefono text,
  p_tipo     text default 'suelta',
  p_nota     text default null,
  p_medio    text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_tel    text;
  v_r      jsonb;
  v_cod    text;
  v_medio  text;
  v_precio int;
  v_caja   jsonb;
  v_ef_ok  boolean := null;
  v_ef_msg text := null;
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

  -- Se valida ANTES de tomar el cupo. Si el medio viene mal escrito, es
  -- mejor no haber movido nada: un cupo tomado con la plata sin
  -- registrar es justo el estado que no queremos.
  v_medio := nullif(btrim(lower(coalesce(p_medio, ''))), '');
  if v_medio is not null and v_medio not in ('efectivo', 'transferencia') then
    return jsonb_build_object('ok', false, 'error', 'MEDIO_INVALIDO',
      'mensaje', 'El pago tiene que ser efectivo o transferencia.');
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
  -- tiene el comprobante delante o la plata en la mano.
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

  -- ── el efectivo, que es lo nuevo ──
  --
  -- Solo para clase suelta: quien tiene plan no paga nada en la puerta,
  -- y meterle un movimiento de caja sería inventar un ingreso.
  v_precio := coalesce((v_r->>'precio_cop')::int, 0);

  if v_medio = 'efectivo' and (v_r->>'tipo') <> 'miembro' and v_precio > 0 then
    -- Se llama a caja_registrar y no se inserta a mano a propósito: ahí
    -- viven las comprobaciones de día cerrado, de valor absurdo y de
    -- medio válido, y duplicarlas aquí sería tener dos verdades.
    v_caja := caja_registrar(
      p_token, 'ingreso', 'clase_suelta', v_precio, 'efectivo',
      'Reserva ' || v_cod || ' — ' || btrim(p_nombre));

    v_ef_ok := coalesce((v_caja->>'ok')::boolean, false);
    if not v_ef_ok then
      v_ef_msg := coalesce(
        v_caja->>'mensaje',
        'No se pudo registrar el efectivo (' || coalesce(v_caja->>'error', 'motivo desconocido') || ').')
        || ' La reserva SÍ quedó: apunta esos '
        || to_char(v_precio, 'FM999G999G999') || ' en la caja a mano.';
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'codigo', v_cod,
    'nombre', btrim(p_nombre),
    'telefono', v_tel,
    'tipo', v_r->>'tipo',
    'clase', v_r->>'clase',
    'fecha_hora', v_r->>'fecha_hora',
    'precio_cop', v_precio,
    'medio', v_medio,
    -- true  = el efectivo entró a la caja
    -- false = se intentó y no se pudo; hay que hacerlo a mano
    -- null  = no había efectivo que registrar (transferencia o miembro)
    'efectivo_registrado', v_ef_ok,
    'aviso_efectivo', v_ef_msg,
    'mensaje', 'Reserva creada y confirmada.');
end;
$$;

comment on function admin_crear_reserva(text, uuid, text, text, text, text, text) is
  'Crea una reserva desde el panel, ya confirmada. Pasa por tomar_cupo: no se salta el aforo. Si el pago es en efectivo, registra el movimiento de caja en la misma llamada.';

revoke execute on function admin_crear_reserva(text, uuid, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function admin_crear_reserva(text, uuid, text, text, text, text, text)
  to service_role;

-- La versión de seis argumentos se va. Si se dejara, PostgREST elegiría
-- una u otra según las claves que le manden, y una llamada a la que se
-- le olvidara el medio entraría por la vieja sin registrar el efectivo
-- y sin decir nada. Es justo el fallo silencioso que se está arreglando.
drop function if exists admin_crear_reserva(text, uuid, text, text, text, text);
