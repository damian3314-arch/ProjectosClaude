-- ---------------------------------------------------------------------
-- 0060 — Cuándo pagaron los que entraron
--
-- LO QUE SE PIDE
-- Una segunda tirilla, aparte de la del cierre, con el desglose de
-- cuándo hicieron el pago las personas que entraron, para poder cruzarla
-- contra el extracto de Bancolombia.
--
-- POR QUÉ HACE FALTA
-- La tirilla del cierre dice "BANCOLOMBIA REPORTÓ HOY $580.000" y
-- "entraron 11 personas · $150.000". Las dos cifras son ciertas y no se
-- pueden comparar: el banco reporta TODO lo que entró hoy —mensualidades
-- incluidas— y parte de la plata de quien entró hoy pudo llegar al banco
-- hace tres días. Sin saber qué depósito respalda a quién, cuadrar es
-- ir adivinando por el extracto.
--
-- UNA FILA POR LÍNEA DEL EXTRACTO, NO POR PERSONA
-- Es lo único que no puede fallar aquí. El 28 de agosto Isabel Flórez y
-- Lizet Gutiérrez entraron con UN solo depósito de $30.000, y lo mismo
-- Ludys Herazo y Yurley Egea. Listar por persona haría que el papel
-- sumara $60.000 donde el banco tiene una línea de $30.000, y el cuadre
-- no daría nunca. Así que se agrupa por depósito y debajo se dicen los
-- nombres que cubre.
--
-- Es el mismo criterio que ya usa "POR REVISAR" en la tirilla del
-- cierre, que agrupa por referencia por esta misma razón.
--
-- LA MISMA GENTE QUE CUENTA LA 0059
-- El `with suyas` es palabra por palabra el de `v_personas_n`. Tiene que
-- serlo: si las dos tirillas usaran reglas distintas, una diría 11 y la
-- otra listaría 10, y no habría forma de saber cuál miente. Si algún día
-- se cambia una, hay que cambiar la otra.
--
-- TRES GRUPOS, PORQUE SON TRES COSAS DISTINTAS
--   · banco    — lo que hay que buscar en el extracto
--   · efectivo — entró en el cajón y NO va a aparecer en el banco
--   · sin_pago — entró y no hay depósito que lo respalde: es lo que hay
--                que averiguar, no lo que hay que cuadrar
--
-- EL VALOR QUE SE ENSEÑA ES EL DEL DEPÓSITO, NO EL DEL COBRO
-- Un depósito de $30.000 puede haber pagado dos clases de $15.000 desde
-- la Caja (eso lo permite la 0039). En el extracto la línea dice
-- $30.000, así que es lo que tiene que decir el papel.
-- ---------------------------------------------------------------------

do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if v_def is null then raise exception 'no existe caja_del_dia'; end if;

  if position('0060:' in v_def) > 0 then
    raise notice '0060: ya estaba aplicada';
    return;
  end if;

  v_def := replace(v_def,
    '  v_personas_n int;   -- 0059: la cuenta de gente, aparte de la de plata',
    '  v_personas_n int;   -- 0059: la cuenta de gente, aparte de la de plata' || E'\n' ||
    '  v_concilia jsonb;   -- 0060: con que deposito entro cada quien');

  v_def := replace(v_def,
    '    into v_personas_n;',
    '    into v_personas_n;' || E'\n\n' ||
    '  -- 0060: de la gente que entro hoy, con que linea del extracto se' || E'\n' ||
    '  -- respalda cada una. `suyas` es el mismo de arriba a proposito: si' || E'\n' ||
    '  -- las dos tirillas usaran reglas distintas, una diria 11 y la otra' || E'\n' ||
    '  -- listaria 10 y no habria como saber cual miente.' || E'\n' ||
    '  with suyas as (' || E'\n' ||
    '    select r.id, r.nombre, r.pago_id, r.origen::text as origen' || E'\n' ||
    '      from reservas r join clases c on c.id = r.clase_id' || E'\n' ||
    '     where r.estado = ''confirmada'' and r.tipo = ''suelta''' || E'\n' ||
    '       and r.reprogramada_a is null' || E'\n' ||
    '       and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia),' || E'\n' ||
    '  -- Una fila por DEPOSITO, no por persona: dos que pagan juntas son' || E'\n' ||
    '  -- una sola linea del extracto. El valor es el del deposito, que es' || E'\n' ||
    '  -- lo que dice el banco, aunque en caja se haya repartido.' || E'\n' ||
    '  del_banco as (' || E'\n' ||
    '    select p.id, p.fecha_pago, p.valor_cop, p.remitente, p.referencia' || E'\n' ||
    '      from pagos p' || E'\n' ||
    '     where p.id in (select pago_id from suyas where pago_id is not null)' || E'\n' ||
    '    union' || E'\n' ||
    '    select p.id, p.fecha_pago, p.valor_cop, p.remitente, p.referencia' || E'\n' ||
    '      from caja_movimientos m join pagos p on p.id = m.pago_id' || E'\n' ||
    '     where m.dia = v_dia and not m.anulado and m.sentido = ''ingreso''' || E'\n' ||
    '       and m.concepto = ''clase_suelta''' || E'\n' ||
    '       and not exists (select 1 from suyas s where s.pago_id = p.id))' || E'\n' ||
    '  select jsonb_build_object(' || E'\n' ||
    '    ''banco'', coalesce((' || E'\n' ||
    '      select jsonb_agg(jsonb_build_object(' || E'\n' ||
    '               ''dia'',      (b.fecha_pago at time zone ''America/Bogota'')::date,' || E'\n' ||
    '               ''dias_antes'', v_dia - (b.fecha_pago at time zone ''America/Bogota'')::date,' || E'\n' ||
    '               ''hora'',     to_char(b.fecha_pago at time zone ''America/Bogota'', ''HH24:MI''),' || E'\n' ||
    '               ''valor_cop'', b.valor_cop,' || E'\n' ||
    '               ''remitente'', b.remitente,' || E'\n' ||
    '               ''referencia'', nullif(btrim(coalesce(b.referencia, '''')), ''''),' || E'\n' ||
    '               -- Vacio = se cobro en la puerta, sin reserva a nombre' || E'\n' ||
    '               -- de nadie. No es un error: es como entro esa persona.' || E'\n' ||
    '               ''para'', coalesce((select jsonb_agg(s.nombre order by s.nombre)' || E'\n' ||
    '                                    from suyas s where s.pago_id = b.id), ''[]''::jsonb))' || E'\n' ||
    '             order by b.fecha_pago)' || E'\n' ||
    '        from del_banco b), ''[]''::jsonb),' || E'\n' ||
    '    ''banco_cop'', coalesce((select sum(b.valor_cop) from del_banco b), 0),' || E'\n' ||
    '    -- Entro al cajon: no va a aparecer en el extracto nunca.' || E'\n' ||
    '    ''efectivo'', coalesce((' || E'\n' ||
    '      select jsonb_agg(jsonb_build_object(' || E'\n' ||
    '               ''hora'', to_char(m.created_at at time zone ''America/Bogota'', ''HH24:MI''),' || E'\n' ||
    '               ''valor_cop'', m.valor_cop) order by m.created_at)' || E'\n' ||
    '        from caja_movimientos m' || E'\n' ||
    '       where m.dia = v_dia and not m.anulado and m.sentido = ''ingreso''' || E'\n' ||
    '         and m.concepto = ''clase_suelta'' and m.medio = ''efectivo''), ''[]''::jsonb),' || E'\n' ||
    '    ''efectivo_cop'', coalesce((select sum(m.valor_cop) from caja_movimientos m' || E'\n' ||
    '       where m.dia = v_dia and not m.anulado and m.sentido = ''ingreso''' || E'\n' ||
    '         and m.concepto = ''clase_suelta'' and m.medio = ''efectivo''), 0),' || E'\n' ||
    '    -- Entro y no hay deposito que lo respalde. Esto no se cuadra: se' || E'\n' ||
    '    -- averigua.' || E'\n' ||
    '    ''sin_pago'', coalesce((' || E'\n' ||
    '      select jsonb_agg(jsonb_build_object(' || E'\n' ||
    '               ''nombre'', s.nombre,' || E'\n' ||
    '               ''motivo'', case when s.origen = ''reprogramada''' || E'\n' ||
    '                             then ''reprogramada, pago otro dia''' || E'\n' ||
    '                             else ''sin deposito enlazado'' end)' || E'\n' ||
    '             order by s.nombre)' || E'\n' ||
    '        from suyas s where s.pago_id is null), ''[]''::jsonb))' || E'\n' ||
    '  into v_concilia;');

  v_def := replace(v_def,
    '      ''personas_n'', v_personas_n' || E'\n' ||
    '    ),',
    '      ''personas_n'', v_personas_n' || E'\n' ||
    '    ),' || E'\n' ||
    '    -- 0060: para la tirilla de conciliacion con el banco.' || E'\n' ||
    '    ''conciliacion'', v_concilia,');

  if position('0060:' in v_def) = 0 then
    raise exception '0060: los anclajes no encajaron';
  end if;
  execute v_def;
  raise notice '0060: caja_del_dia parcheada';
end $$;
