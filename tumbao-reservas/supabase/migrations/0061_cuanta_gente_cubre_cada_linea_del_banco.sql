-- ---------------------------------------------------------------------
-- 0061 — Cuánta gente cubre cada línea del banco
--
-- QUÉ FALTABA EN LA 0060
-- La tirilla de conciliación dice, debajo de cada depósito, a quién
-- cubre. Cuando el depósito viene de una reserva eso son nombres; cuando
-- se cobró en la puerta no hay reserva y la lista va vacía, así que el
-- papel decía «cobrado en la puerta» y punto.
--
-- Eso es correcto mientras cada cobro en puerta sea un depósito, que es
-- lo que pasa hoy. Pero la 0039 permite justo lo contrario: un depósito
-- de $30.000 puede pagar dos clases de $15.000 desde la Caja. Ese día la
-- línea diría «cobrado en la puerta» una sola vez para dos personas, y
-- quien cuente cabezas sobre el papel llegaría a un número distinto del
-- que dice la tirilla del cierre.
--
-- Dos papeles del mismo día que no coinciden es peor que uno incompleto:
-- no hay forma de saber cuál miente.
--
-- LO QUE HACE
-- Añade `cobros` a cada línea: cuántos cobros de clase suelta de ese día
-- se pagaron con ese depósito sin pasar por una reserva. Con eso, la
-- gente que cubre una línea es `para` + `cobros`, y la suma de todas las
-- líneas más el efectivo más los que entraron sin depósito da
-- exactamente `personas_n`. Es una igualdad que se puede comprobar, y
-- hay una prueba que la comprueba.
-- ---------------------------------------------------------------------

do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if v_def is null then raise exception 'no existe caja_del_dia'; end if;

  if position('0061:' in v_def) > 0 then
    raise notice '0061: ya estaba aplicada';
    return;
  end if;

  v_def := replace(v_def,
    '               ''para'', coalesce((select jsonb_agg(s.nombre order by s.nombre)' || E'\n' ||
    '                                    from suyas s where s.pago_id = b.id), ''[]''::jsonb))',
    '               ''para'', coalesce((select jsonb_agg(s.nombre order by s.nombre)' || E'\n' ||
    '                                    from suyas s where s.pago_id = b.id), ''[]''::jsonb),' || E'\n' ||
    '               -- 0061: cuantos cobros en puerta salieron de este' || E'\n' ||
    '               -- deposito. Casi siempre 1, pero uno de 30.000 puede' || E'\n' ||
    '               -- pagar dos clases de 15.000 (eso lo permite la 0039)' || E'\n' ||
    '               -- y entonces la linea cubre a dos personas sin nombre.' || E'\n' ||
    '               -- Sin este numero, contar cabezas sobre el papel daba' || E'\n' ||
    '               -- distinto que la tirilla del cierre.' || E'\n' ||
    '               ''cobros'', (select count(*) from caja_movimientos m2' || E'\n' ||
    '                             where m2.pago_id = b.id and m2.dia = v_dia' || E'\n' ||
    '                               and not m2.anulado and m2.sentido = ''ingreso''' || E'\n' ||
    '                               and m2.concepto = ''clase_suelta''' || E'\n' ||
    '                               and not exists (select 1 from suyas s2' || E'\n' ||
    '                                                where s2.pago_id = b.id)))');

  if position('0061:' in v_def) = 0 then
    raise exception '0061: los anclajes no encajaron';
  end if;
  execute v_def;
  raise notice '0061: caja_del_dia parcheada';
end $$;
