-- ---------------------------------------------------------------------
-- 0044 — Liberar una reserva apuntada a mano
--
-- EL AGUJERO
-- Una reserva apuntada desde el panel no se podía deshacer por ninguna
-- vía. `Liberar` solo sale en las que están sin confirmar, y las de
-- mostrador nacen confirmadas. `Deshacer` las rechaza con NO_FUE_A_MANO
-- porque exige `estado_antes`, que solo escriben las decisiones tomadas
-- desde la cola de pagos.
--
-- O sea: recepción apunta a la persona equivocada, o a la clase
-- equivocada, y ese cupo queda tomado para siempre.
--
-- POR QUÉ AHORA PESA MÁS
-- Desde la 0042 y la 0043 una reserva de mostrador puede haber movido
-- plata: si se cobró en efectivo hay un movimiento de caja detrás. Un
-- error que no se puede corregir dejó de ser un cupo perdido y pasó a
-- ser una caja que no cuadra — que es justo lo que el módulo existe para
-- evitar.
--
-- LO QUE HACE
-- `admin_rechazar` acepta ahora una confirmada SI se apuntó a mano
-- (`origen = 'recepcion'`). Al liberarla:
--   · suelta el cupo
--   · anula el movimiento de caja, si lo hubo
--   · le quita la marca de entrada, si la tenía
--
-- POR QUÉ SOLO LAS DE MOSTRADOR
-- Una reserva que cruzó la página sola está confirmada porque llegó un
-- depósito de verdad al banco. Soltar esa con un clic dejaría el dinero
-- huérfano y el cupo a la venta sin que nadie se entere. Para esas sigue
-- estando `Deshacer`, que devuelve el depósito a la cola. Aquí se abre
-- exactamente una puerta, no la pared.
--
-- NO SE BLOQUEA AUNQUE LA CLASE YA HAYA PASADO
-- Sería fácil exigir que la clase esté por venir, y sería un error: el
-- caso que más importa es darse cuenta media hora después de haberle
-- cobrado a la persona equivocada. Poder devolver esa plata vale más que
-- proteger un cupo de una clase que ya se dictó.
--
-- SE REUSA EL BOTÓN QUE YA HAY
-- No se inventa un verbo nuevo. En la puerta ya dice "Liberar" y ya
-- pregunta antes de hacerlo; lo único que cambia es que ahora también
-- aparece en las de mostrador.
-- ---------------------------------------------------------------------
create or replace function admin_rechazar(p_token text, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin    uuid;
  v_reserva  reservas%rowtype;
  v_grupo    uuid;
  v_n        int;
  v_caja     jsonb;
  v_devuelto int  := null;
  v_aviso    text := null;
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

  -- Una confirmada solo se libera si se apuntó a mano.
  if v_reserva.estado = 'confirmada' and v_reserva.origen is distinct from 'recepcion' then
    return jsonb_build_object('ok', false, 'error', 'YA_CONFIRMADA',
      'mensaje', 'Esa reserva ya esta confirmada y entro por la pagina. Para '
              || 'deshacerla usa Deshacer en la cola de pagos, que ademas '
              || 'devuelve el deposito.');
  end if;

  -- ── la plata, antes de tocar la reserva ──
  -- Si se cobró en efectivo, ese ingreso tiene que salir de la caja.
  if v_reserva.cobro_mov_id is not null then
    v_caja := caja_anular(p_token, v_reserva.cobro_mov_id);
    if coalesce((v_caja->>'ok')::boolean, false) then
      v_devuelto := (v_caja->>'valor_cop')::int;
      update reservas
         set cobro_mov_id = null, cobrado_en_puerta_at = null
       where id = v_reserva.id;
    else
      -- Los dos casos reales: el día ya se cerró, o el cobro fue otro
      -- día. No se bloquea la liberación —el cupo hay que soltarlo
      -- igual— pero se dice, porque queda en la caja un ingreso de un
      -- cobro que ya no existe.
      v_aviso := coalesce(v_caja->>'mensaje',
        'No se pudo quitar el cobro de la caja (' || coalesce(v_caja->>'error','?') || ').')
        || ' El cupo SI quedo libre: quita ese ingreso a mano.';
    end if;
  end if;

  -- Si ya le habían marcado la entrada, deja de haber entrada que marcar.
  delete from asistencias
   where reserva_id = v_reserva.id and clase_id = v_reserva.clase_id;

  v_grupo := grupo_de(v_reserva.id);

  with tocadas as (
    update reservas
       set estado        = 'rechazada',
           estado_antes  = estado,
           pago_id_antes = pago_id,
           resuelta_por  = v_admin,
           resuelta_at   = now(),
           updated_at    = now()
     where coalesce(grupo_id, id) = v_grupo
       -- Misma regla que arriba: en un grupo mixto no se puede soltar la
       -- que trae depósito.
       and (estado not in ('rechazada', 'confirmada')
            or (estado = 'confirmada' and origen = 'recepcion'))
    returning 1
  )
  select count(*)::int into v_n from tocadas;

  -- Un cupo por persona soltada, no uno por grupo.
  update clases set cupo_tomado = greatest(cupo_tomado - v_n, 0)
   where id = v_reserva.clase_id;

  return jsonb_build_object('ok', true, 'estado', 'rechazada',
    'codigo', v_reserva.codigo, 'nombre', v_reserva.nombre,
    'telefono', v_reserva.telefono, 'cupos', v_n,
    'se_puede_deshacer', true,
    -- Cuánto salió de la caja al liberar, si es que había entrado algo.
    'devuelto_cop', v_devuelto,
    'aviso_caja', v_aviso,
    'mensaje', case when v_n > 1
                 then 'Rechazadas, quedaron libres ' || v_n || ' cupos.'
                 else 'Rechazada, el cupo quedo libre.' end);
end;
$$;

revoke execute on function admin_rechazar(text, text) from public, anon, authenticated;
grant execute on function admin_rechazar(text, text) to service_role;


-- ---------------------------------------------------------------------
-- La lista de la puerta dice cuáles se pueden liberar y cuánto devuelven
--
-- Sin esto el panel tendría que adivinar en qué se puede clicar, y así
-- es como se enseña un botón que después falla.
--
-- Se parchea sobre lo que hay en vez de reescribir la función entera:
-- es larga, y reescribirla de memoria ya salió mal una vez en este
-- proyecto —la rama de las membresías de admin_marcar_asistencia—. Si el
-- trozo a reemplazar no aparece exactamente una vez, la migración se
-- para en vez de dejar la función a medias.
-- ---------------------------------------------------------------------
do $$
declare
  v_def   text;
  v_viejo text;
  v_nuevo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_lista_clase';

  v_viejo := '      ''credito_vence'', r.credito_vence' || E'\n' ||
             '    ) as x';

  v_nuevo := '      ''credito_vence'', r.credito_vence,' || E'\n' ||
             '      -- Se apunto desde el panel. Solo estas se pueden liberar' || E'\n' ||
             '      -- estando ya confirmadas: las que cruzo la pagina traen un' || E'\n' ||
             '      -- deposito detras y se deshacen desde la cola de pagos.' || E'\n' ||
             '      ''a_mano'',     r.origen = ''recepcion'',' || E'\n' ||
             '      -- Si se cobro en efectivo, liberar devuelve esta plata a la' || E'\n' ||
             '      -- caja. La pantalla lo dice ANTES de preguntar, que es' || E'\n' ||
             '      -- cuando sirve saberlo.' || E'\n' ||
             '      ''cobrado_cop'', (select m.valor_cop from caja_movimientos m' || E'\n' ||
             '                       where m.id = r.cobro_mov_id and not m.anulado)' || E'\n' ||
             '    ) as x';

  if v_def is null then
    raise exception 'no existe admin_lista_clase';
  end if;
  if (length(v_def) - length(replace(v_def, v_viejo, ''))) / length(v_viejo) <> 1 then
    raise exception 'el trozo a parchear no aparece exactamente una vez en admin_lista_clase';
  end if;

  execute replace(v_def, v_viejo, v_nuevo);
end $$;
