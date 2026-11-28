-- ¿Deshacer deshace de verdad, y se niega cuando toca?
--
-- Un botón de deshacer que a veces no restaura bien es peor que no
-- tenerlo: da confianza para dar clic sin mirar. Lo que se comprueba
-- aquí es que vuelve EXACTAMENTE al estado anterior, y que los tres
-- candados aguantan.
--
-- El caso que de verdad importa es el último: deshacer un rechazo
-- cuando el cupo ya se vendió. Ahí la respuesta correcta es "no puedo",
-- no "lo meto igual".
--
--   psql -d tumbao -f pruebas/humo-deshacer.sql

\set ON_ERROR_STOP on
set timezone = 'America/Bogota';

do $$
declare
  v_tok text; v_lun date; v_c uuid;
  v_r jsonb; v_res reservas%rowtype;
  v_cod text; v_cod2 text; v_pago uuid;
  v_tomado_antes int; v_tomado int;
begin
  delete from reservas where true;
  delete from pagos where true;
  delete from membresias where true;
  delete from clases where true;
  delete from admin_tokens where true;
  perform generar_horario(current_date, current_date + 13);

  v_tok := (crear_token_admin('humo de deshacer'))->>'token';

  select (fecha_hora at time zone 'America/Bogota')::date into v_lun
    from clases where fecha_hora > now() order by fecha_hora limit 1;
  select id into v_c from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_lun
     and fecha_hora > now() order by fecha_hora limit 1;

  -- ── 1. deshacer un rechazo devuelve el cupo ────────────────
  select tomar_cupo(v_c, 'Yenny Vergara', '3102543733', null, 'web', 'suelta') into v_r;
  v_cod := v_r->>'codigo';
  update reservas set estado = 'pendiente_validacion' where codigo = v_cod;
  select cupo_tomado into v_tomado_antes from clases where id = v_c;

  perform admin_rechazar(v_tok, v_cod);
  select cupo_tomado into v_tomado from clases where id = v_c;
  if v_tomado <> v_tomado_antes - 1 then
    raise exception 'rechazar deberia soltar el cupo: % -> %', v_tomado_antes, v_tomado;
  end if;

  select admin_deshacer(v_tok, v_cod) into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'no dejo deshacer el rechazo: %', v_r;
  end if;
  select * into v_res from reservas where codigo = v_cod;
  if v_res.estado <> 'pendiente_validacion' then
    raise exception 'deberia volver a pendiente_validacion, quedo en %', v_res.estado;
  end if;
  select cupo_tomado into v_tomado from clases where id = v_c;
  if v_tomado <> v_tomado_antes then
    raise exception 'deshacer deberia retomar el cupo: % vs %', v_tomado, v_tomado_antes;
  end if;
  raise notice '1. deshacer un rechazo: vuelve a la cola y retoma el cupo';

  -- ── 2. no se puede deshacer dos veces ──────────────────────
  select admin_deshacer(v_tok, v_cod) into v_r;
  if (v_r->>'error') <> 'NADA_QUE_DESHACER' then
    raise exception 'dejo deshacer algo que ya no estaba resuelto: %', v_r;
  end if;
  select cupo_tomado into v_tomado from clases where id = v_c;
  if v_tomado <> v_tomado_antes then
    raise exception 'el segundo deshacer movio el cupo a %', v_tomado;
  end if;
  raise notice '2. deshacer dos veces: se niega y no toca el cupo';

  -- ── 3. deshacer una confirmacion suelta el pago ────────────
  -- Un pago suelto de $15.000 que el cajero le amarra a mano.
  insert into pagos (banco, valor_cop, fecha_pago, remitente)
  values ('Bancolombia', 15000, now(), 'YENNY VERGARA') returning id into v_pago;

  select admin_confirmar(v_tok, v_cod, v_pago) into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'no confirmo: %', v_r;
  end if;
  if (v_r->>'se_puede_deshacer')::boolean is not true then
    raise exception 'confirmar deberia decir que se puede deshacer: %', v_r;
  end if;
  select * into v_res from reservas where codigo = v_cod;
  if v_res.pago_id <> v_pago then raise exception 'no amarro el pago'; end if;

  select admin_deshacer(v_tok, v_cod) into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'no dejo deshacer la confirmacion: %', v_r;
  end if;
  select * into v_res from reservas where codigo = v_cod;
  if v_res.estado <> 'pendiente_validacion' then
    raise exception 'deberia volver a pendiente_validacion, quedo en %', v_res.estado;
  end if;
  -- El pago tiene que volver al pozo de los que no tienen dueño, o se
  -- queda pegado a una reserva que ya no esta confirmada.
  if v_res.pago_id is not null then
    raise exception 'el pago quedo amarrado a una reserva sin confirmar: %', v_res.pago_id;
  end if;
  raise notice '3. deshacer una confirmacion: suelta el pago y vuelve a la cola';

  -- Y ese pago tiene que reaparecer como candidato en la cola.
  select admin_pendientes(v_tok) into v_r;
  if not exists (
    select 1 from jsonb_array_elements(v_r->'reservas') r
     where r->>'codigo' = v_cod
       and jsonb_array_length(r->'pagos_sueltos') > 0) then
    raise exception 'el pago liberado no volvio a salir como candidato';
  end if;
  raise notice '   y el pago vuelve a aparecer como candidato';

  -- ── 4. deshacer restaura el estado de VERDAD ───────────────
  -- Si venia de "verificando", tiene que volver a "verificando", no a
  -- un pendiente_validacion inventado.
  update reservas set estado = 'verificando' where codigo = v_cod;
  perform admin_confirmar(v_tok, v_cod, null);
  perform admin_deshacer(v_tok, v_cod);
  select * into v_res from reservas where codigo = v_cod;
  if v_res.estado <> 'verificando' then
    raise exception 'deberia volver a verificando, volvio a %', v_res.estado;
  end if;
  raise notice '4. vuelve al estado exacto de antes, no a uno inventado';

  -- ── 5. lo que concilio solo el sistema no se deshace ───────
  update reservas
     set estado = 'confirmada', resuelta_por = null, resuelta_at = null,
         estado_antes = null, pago_id_antes = null
   where codigo = v_cod;
  select admin_deshacer(v_tok, v_cod) into v_r;
  if (v_r->>'error') <> 'NO_FUE_A_MANO' then
    raise exception 'dejo deshacer una conciliacion automatica: %', v_r;
  end if;
  raise notice '5. una conciliacion automatica no se deshace desde el panel';

  -- ── 6. pasados 15 minutos, se acabo ────────────────────────
  update reservas
     set estado_antes = 'pendiente_validacion',
         resuelta_por = (select id from admin_tokens limit 1),
         resuelta_at  = now() - interval '20 minutes'
   where codigo = v_cod;
  select admin_deshacer(v_tok, v_cod) into v_r;
  if (v_r->>'error') <> 'FUERA_DE_TIEMPO' then
    raise exception 'dejo deshacer algo de hace 20 minutos: %', v_r;
  end if;
  if (v_r->>'minutos')::int < 19 then
    raise exception 'los minutos no cuadran: %', v_r->>'minutos';
  end if;
  raise notice '6. fuera de los 15 minutos: se niega y dice cuantos pasaron';

  -- Y justo dentro del plazo, sí.
  update reservas set resuelta_at = now() - interval '14 minutes' where codigo = v_cod;
  select admin_deshacer(v_tok, v_cod) into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'a los 14 minutos deberia dejar: %', v_r;
  end if;
  raise notice '   a los 14 minutos todavia deja';

  -- ── 7. si el cupo ya se vendio, NO sobrevende ──────────────
  -- Se aprieta la clase hasta dejarla llena, se rechaza a alguien y en
  -- ese hueco entra otra persona. Deshacer ya no cabe.
  update clases set cupo_total = cupo_tomado + 1 where id = v_c;
  select tomar_cupo(v_c, 'Paola Riaño', '3194113242', null, 'web', 'suelta') into v_r;
  v_cod2 := v_r->>'codigo';
  update reservas set estado = 'pendiente_validacion' where codigo = v_cod2;

  perform admin_rechazar(v_tok, v_cod2);              -- suelta un cupo
  select tomar_cupo(v_c, 'Se Le Adelanto', '3009998877', null, 'web', 'suelta') into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'la otra persona deberia haber podido entrar: %', v_r;
  end if;

  select cupo_tomado, cupo_total into v_tomado, v_tomado_antes from clases where id = v_c;
  select admin_deshacer(v_tok, v_cod2) into v_r;
  if (v_r->>'error') <> 'SIN_CUPO' then
    raise exception 'sobrevendio al deshacer un rechazo sin cupo: %', v_r;
  end if;
  select cupo_tomado into v_tomado from clases where id = v_c;
  if v_tomado > v_tomado_antes then
    raise exception 'se paso del aforo: % de %', v_tomado, v_tomado_antes;
  end if;
  select * into v_res from reservas where codigo = v_cod2;
  if v_res.estado <> 'rechazada' then
    raise exception 'al negarse deberia dejarla rechazada, quedo en %', v_res.estado;
  end if;
  raise notice '7. rechazo + cupo vendido: se niega, no sobrevende, y no deja nada a medias';

  -- ── 8. sin token no se deshace nada ────────────────────────
  select admin_deshacer('token-inventado', v_cod) into v_r;
  if (v_r->>'error') <> 'NO_AUTORIZADO' then
    raise exception 'un token falso pudo deshacer: %', v_r;
  end if;
  raise notice '8. token falso: NO_AUTORIZADO';
end $$;

-- ── 9. no es ejecutable con la llave publica ─────────────────
do $$
declare v_mal text;
begin
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('admin_deshacer', 'admin_confirmar', 'admin_rechazar')
     and (has_function_privilege('anon', p.oid, 'execute')
       or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_mal is not null then
    raise exception 'abiertas a la llave publica: %', v_mal;
  end if;
  raise notice '9. deshacer no es ejecutable con la llave anon';
end $$;

select 'TODO EN VERDE' as resultado;
