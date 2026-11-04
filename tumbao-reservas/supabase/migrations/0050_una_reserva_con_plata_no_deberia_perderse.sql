-- ---------------------------------------------------------------------
-- 0050 — Que una reserva con plata real no se pierda sola, ni al
-- vencer ni al intentar recuperarla
--
-- EL INCIDENTE
-- Ludys Herazo reutilizó por error la referencia de un comprobante
-- viejo. registrar_aviso_pago la rechazó bien (0036), pero su reserva
-- se quedó en pendiente_pago. 0049 ya hacía que eso saliera en la cola
-- de admin_pendientes con su plata al lado — PERO antes de que alguien
-- alcanzara a mirarla, liberar_cupos_de_clase() la venció y le soltó
-- el cupo, sacándola por completo de la cola (0049 solo mira
-- pendiente_pago). Arreglarla a mano requirió tocar reservas, clases y
-- pagos directamente en SQL, con el riesgo de sobrevender si alguien
-- ya había tomado su puesto — no puede ser el camino normal.
--
-- LO QUE HACE, EN CUATRO PIEZAS
--
-- 1. liberar_cupos_de_clase(): ya no vence una reserva si hay plata
--    real sin consumir cerca de cuándo se hizo. Esto es lo que evita
--    que el caso de Ludys vuelva a pasar — con esto puesto, su reserva
--    jamás hubiera vencido, y 0049 ya la hubiera mostrado a tiempo.
--
-- 2. admin_pendientes(): por si ALGO igual expira (un pago que llega
--    fuera de la ventana de -2h/+3h, por ejemplo), las reservas
--    'expirada' con plata cerca también salen en la cola — marcadas
--    'vencida', con 'cupo_libre' para que quien atiende sepa si
--    confirmarla es seguro antes de intentarlo.
--
-- 3. admin_confirmar(): ahora acepta 'expirada' como estado de origen.
--    Si acepta, retoma el cupo que se había soltado — pero solo si de
--    verdad sigue libre (bloqueando la fila de la clase, igual que
--    tomar_cupo). Si alguien más ya lo tomó, responde CUPO_LLENO en
--    vez de sobrevender.
--
-- 4. admin_rechazar(): tenía un bug que esto dejaba alcanzable —
--    soltaba UN cupo por cada reserva tocada sin mirar si esa reserva
--    ya estaba vencida (o sea, sin cupo que soltar). Antes era
--    inofensivo porque 'expirada' nunca llegaba a la cola; ahora que sí
--    llega, rechazar una tarjeta vencida hubiera restado un cupo que no
--    era suyo. Se corrige contando solo las que de verdad lo tenían
--    tomado.
--
-- Se parchea sobre pg_get_functiondef en vez de reescribir las
-- funciones: son largas, y reescribir de memoria ya salió mal antes.
-- ---------------------------------------------------------------------
do $$
declare
  v_def text;
  v_a   text;
  v_b   text;
  v_n   int;
begin

  -- ═══ 1. liberar_cupos_de_clase: no vencer si hay plata cerca ═══
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'liberar_cupos_de_clase';
  if v_def is null then
    raise exception 'no existe liberar_cupos_de_clase';
  end if;

  if position('r.expira_en' in v_def) > 0 then
    raise notice 'liberar_cupos_de_clase: ya estaba aplicada';
  else
    v_a := 'update reservas set estado = ''expirada'', updated_at = now()' || E'\n' ||
      '     where clase_id = p_clase_id' || E'\n' ||
      '       and estado = ''pendiente_pago''' || E'\n' ||
      '       and expira_en < now()' || E'\n' ||
      '    returning 1';
    v_b := 'update reservas r set estado = ''expirada'', updated_at = now()' || E'\n' ||
      '     where r.clase_id = p_clase_id' || E'\n' ||
      '       and r.estado = ''pendiente_pago''' || E'\n' ||
      '       and r.expira_en < now()' || E'\n' ||
      '       -- Si hay una plata real sin consumir cerca de cuando se' || E'\n' ||
      '       -- hizo la reserva, no se vence: es justo el caso de que el' || E'\n' ||
      '       -- aviso nunca se registro pero el dinero si llego. Vencerla' || E'\n' ||
      '       -- le soltaria el cupo a otro mientras el dinero de esta' || E'\n' ||
      '       -- persona sigue ahi, sin dueno.' || E'\n' ||
      '       and not exists (' || E'\n' ||
      '         select 1 from pagos p' || E'\n' ||
      '          where not p.consumido' || E'\n' ||
      '            and p.fecha_pago between r.created_at - interval ''2 hours''' || E'\n' ||
      '                                and r.created_at + interval ''3 hours''' || E'\n' ||
      '       )' || E'\n' ||
      '    returning 1';
    if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
      raise exception 'liberar_cupos_de_clase: no se encontro el update esperado exactamente una vez';
    end if;
    v_def := replace(v_def, v_a, v_b);
    execute v_def;
    raise notice 'liberar_cupos_de_clase: parchada';
  end if;

  -- ═══ 2. admin_pendientes: tambien 'expirada' con plata cerca ═══
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_pendientes';
  if v_def is null then
    raise exception 'no existe admin_pendientes';
  end if;

  if position('cupo_libre' in v_def) > 0 then
    raise notice 'admin_pendientes: ya estaba aplicada';
  else
    -- 2a. En los dos sitios donde 0049 dejo 'pendiente_pago' solo, ahora
    -- tambien cuenta 'expirada': una vez en el campo sin_aviso de la
    -- respuesta, otra vez en el filtro de la cola. Es el mismo cambio
    -- en los dos lugares, por eso se pide que aparezca EXACTAMENTE dos
    -- veces antes de tocarlo.
    v_a := 'r.estado = ''pendiente_pago''';
    v_b := 'r.estado in (''pendiente_pago'', ''expirada'')';
    if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 2 then
      raise exception 'admin_pendientes: esperaba encontrar r.estado = pendiente_pago dos veces (sin_aviso y el filtro)';
    end if;
    v_def := replace(v_def, v_a, v_b);

    -- 2b. Marcar cuando la tarjeta salio por estar vencida, y si la
    -- clase todavia tiene donde retomarla.
    v_a := '''sin_aviso'',   r.estado in (''pendiente_pago'', ''expirada''),';
    v_b := v_a || E'\n' ||
      '      -- true si esta tarjeta perdio el cupo por vencimiento.' || E'\n' ||
      '      -- Confirmarla puede necesitar retomar un puesto que quiza' || E'\n' ||
      '      -- ya no este libre: por eso viene con cupo_libre al lado.' || E'\n' ||
      '      ''vencida'',    r.estado = ''expirada'',' || E'\n' ||
      '      ''cupo_libre'', c.cupo_tomado < c.cupo_total,';
    if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
      raise exception 'admin_pendientes: no se encontro la linea de sin_aviso exactamente una vez';
    end if;
    v_def := replace(v_def, v_a, v_b);

    execute v_def;
    raise notice 'admin_pendientes: parchada';
  end if;

  -- ═══ 3. admin_confirmar: aceptar 'expirada', retomando el cupo ═══
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_confirmar';
  if v_def is null then
    raise exception 'no existe admin_confirmar';
  end if;

  if position('CUPO_LLENO' in v_def) > 0 then
    raise notice 'admin_confirmar: ya estaba aplicada';
  else
    v_a := E'declare\n  v_admin   uuid;\n  v_reserva reservas%rowtype;\n  v_grupo   uuid;\n  v_n       int;\nbegin';
    v_b := E'declare\n  v_admin       uuid;\n  v_reserva     reservas%rowtype;\n  v_grupo       uuid;\n  v_n           int;\n  v_expiradas   int;\n  v_cupo_total  int;\n  v_cupo_tomado int;\nbegin';
    if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
      raise exception 'admin_confirmar: no se encontro el declare esperado exactamente una vez';
    end if;
    v_def := replace(v_def, v_a, v_b);

    v_a := 'if v_reserva.estado not in (''pendiente_validacion'', ''verificando'', ''pendiente_pago'') then';
    v_b := 'if v_reserva.estado not in (''pendiente_validacion'', ''verificando'', ''pendiente_pago'', ''expirada'') then';
    if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
      raise exception 'admin_confirmar: no se encontro el chequeo de estado esperado exactamente una vez';
    end if;
    v_def := replace(v_def, v_a, v_b);

    v_a := '  v_grupo := grupo_de(v_reserva.id);';
    v_b := v_a || E'\n\n' ||
      '  -- Si alguna del grupo ya vencio, liberar_cupos_de_clase ya le' || E'\n' ||
      '  -- solto el cupo. Confirmarla ahora es retomar ese puesto, y eso' || E'\n' ||
      '  -- solo se puede si de verdad sigue libre: sin este chequeo, se' || E'\n' ||
      '  -- confirmaria por encima de quien ya lo haya tomado mientras' || E'\n' ||
      '  -- esta reserva estaba vencida.' || E'\n' ||
      '  select count(*) into v_expiradas' || E'\n' ||
      '    from reservas' || E'\n' ||
      '   where coalesce(grupo_id, id) = v_grupo' || E'\n' ||
      '     and estado = ''expirada'';' || E'\n\n' ||
      '  if v_expiradas > 0 then' || E'\n' ||
      '    select cupo_total, cupo_tomado into v_cupo_total, v_cupo_tomado' || E'\n' ||
      '      from clases where id = v_reserva.clase_id' || E'\n' ||
      '      for update;' || E'\n' ||
      '    if v_cupo_tomado + v_expiradas > v_cupo_total then' || E'\n' ||
      '      return jsonb_build_object(''ok'', false, ''error'', ''CUPO_LLENO'',' || E'\n' ||
      '        ''libres'', greatest(v_cupo_total - v_cupo_tomado, 0),' || E'\n' ||
      '        ''mensaje'', ''Esa clase ya no tiene cupo: alguien mas lo tomo '' ||' || E'\n' ||
      '                   ''mientras esta reserva estaba vencida. Hay que '' ||' || E'\n' ||
      '                   ''ofrecerle otro horario o resolverlo por WhatsApp.'');' || E'\n' ||
      '    end if;' || E'\n' ||
      '    update clases set cupo_tomado = cupo_tomado + v_expiradas' || E'\n' ||
      '     where id = v_reserva.clase_id;' || E'\n' ||
      '  end if;';
    if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
      raise exception 'admin_confirmar: no se encontro la linea de v_grupo esperada exactamente una vez';
    end if;
    v_def := replace(v_def, v_a, v_b);

    v_a := 'and estado in (''pendiente_validacion'', ''verificando'', ''pendiente_pago'')' || E'\n' || '    returning 1';
    v_b := 'and estado in (''pendiente_validacion'', ''verificando'', ''pendiente_pago'', ''expirada'')' || E'\n' || '    returning 1';
    if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
      raise exception 'admin_confirmar: no se encontro el update final esperado exactamente una vez';
    end if;
    v_def := replace(v_def, v_a, v_b);

    execute v_def;
    raise notice 'admin_confirmar: parchada';
  end if;

  -- ═══ 4. admin_rechazar: no soltar un cupo que ya estaba suelto ═══
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_rechazar';
  if v_def is null then
    raise exception 'no existe admin_rechazar';
  end if;

  if position('tenia_cupo' in v_def) > 0 then
    raise notice 'admin_rechazar: ya estaba aplicada';
  else
    -- Declarar v_liberar (0043 ya le agrego v_caja/v_devuelto/v_aviso
    -- para "paga al llegar"; esto solo agrega una variable mas).
    v_a := E'declare\n  v_admin    uuid;\n  v_reserva  reservas%rowtype;\n  v_grupo    uuid;\n  v_n        int;\n  v_caja     jsonb;\n  v_devuelto int  := null;\n  v_aviso    text := null;\nbegin';
    v_b := E'declare\n  v_admin    uuid;\n  v_reserva  reservas%rowtype;\n  v_grupo    uuid;\n  v_n        int;\n  v_liberar  int;\n  v_caja     jsonb;\n  v_devuelto int  := null;\n  v_aviso    text := null;\nbegin';
    if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
      raise exception 'admin_rechazar: no se encontro el declare esperado exactamente una vez';
    end if;
    v_def := replace(v_def, v_a, v_b);

    v_a := E'    returning 1\n  )\n  select count(*)::int into v_n from tocadas;\n\n  -- Un cupo por persona soltada, no uno por grupo.\n  update clases set cupo_tomado = greatest(cupo_tomado - v_n, 0)\n   where id = v_reserva.clase_id;';
    v_b := E'    returning (estado_antes <> ''expirada'') as tenia_cupo\n  )\n  select count(*)::int, count(*) filter (where tenia_cupo)::int\n    into v_n, v_liberar\n    from tocadas;\n\n  -- Un cupo por persona soltada QUE DE VERDAD LO TENIA. Las que ya\n  -- habian vencido no tienen nada que soltar: liberar_cupos_de_clase ya\n  -- les habia soltado el suyo. Soltarlo de nuevo aqui restaria un cupo\n  -- que no era de esta reserva.\n  if v_liberar > 0 then\n    update clases set cupo_tomado = greatest(cupo_tomado - v_liberar, 0)\n     where id = v_reserva.clase_id;\n  end if;';
    if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
      raise exception 'admin_rechazar: no se encontro el bloque esperado exactamente una vez';
    end if;
    v_def := replace(v_def, v_a, v_b);

    execute v_def;
    raise notice 'admin_rechazar: parchada';
  end if;

end $$;
