-- ---------------------------------------------------------------------
-- 0052 — "Transferencia, recepción" se lee de caja, no de reservas
--
-- EL PROBLEMA
-- 0051 partió de una premisa que los datos desmienten. Decía: "una
-- transferencia SIEMPRE deja fila en reservas —es lo único que la cruza
-- con el depósito—, así que ahí sí hay de dónde leer el origen". Por eso
-- buscaba las de recepción en `reservas` con origen='recepcion' y
-- pago_id no nulo.
--
-- Esa fila no existe. Comprobado sobre la base entera:
--
--   · reservas confirmadas, suelta, origen='recepcion': 25, y las 25
--     con pago_id NULO. Ni una sola con pago_id, nunca.
--   · movimientos de caja concepto='clase_suelta' medio='transferencia':
--     19, $285.000, y NINGUNO tiene reserva que le corresponda por
--     pago_id (se cruzó uno a uno).
--
-- O sea que la casilla "Transferencia, recepción" no daba cero por
-- casualidad: no podía dar otra cosa. La consulta miraba un sitio donde
-- esa plata nunca estuvo, mientras los $285.000 reales vivían en
-- caja_movimientos sin que la tirilla los mostrara. Entraban al total
-- de transferencias del día, pero no a Entradas — y Entradas es
-- justamente lo que se cruza contra el cuaderno de la puerta.
--
-- POR QUÉ PASA
-- Cuando alguien llega y paga en el momento por transferencia, recepción
-- lo registra como movimiento de caja. No crea reserva: la persona ya
-- está adentro, no hay cupo que apartar. Es el mismo camino del efectivo,
-- solo que con otro medio.
--
-- LO QUE HACE
-- Deja las tres casillas simétricas, cada una en la fuente donde su plata
-- realmente vive:
--
--   Efectivo (clase suelta)     -> caja_movimientos, clase_suelta,
--                                   efectivo, del día.   [sin cambio]
--   Transferencia, recepción    -> caja_movimientos, clase_suelta,
--                                   transferencia, del día.  [CORREGIDO]
--   Transferencia, página       -> reservas confirmadas, suelta, con
--                                   pago_id, de una clase de HOY, y con
--                                   origen de la página.     [acotado]
--
-- NO HAY DOBLE CONTEO
-- Es la condición que hace válido sumar las tres. Se verificó cruzando
-- por pago_id: ningún movimiento de caja de clase suelta corresponde a
-- una reserva, y ninguna reserva de recepción tiene pago_id. Los dos
-- conjuntos son ajenos, así que el total de Entradas no repite un peso.
--
-- POR QUÉ 'web','formulario' Y NO "todo lo que no sea recepción"
-- 0051 mandaba a página todo origen distinto de 'recepcion'. Hoy hay un
-- cuarto origen, 'reprogramada' (4 filas), que ahí caería como página
-- siendo que no es plata que entró hoy: es alguien que ya pagó antes y
-- movió su clase. Hoy no estorba porque ninguna tiene pago_id, pero
-- basta que una lo tenga para inflar la casilla. Nombrar los dos
-- orígenes que sí son la página cierra esa puerta.
-- ---------------------------------------------------------------------
do $$
declare
  v_def text;
  v_a   text;
  v_b   text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if v_def is null then
    raise exception 'no existe caja_del_dia';
  end if;
  if position('v_entra_recep_tr' in v_def) = 0 then
    raise exception 'falta 0051: caja_del_dia no tiene las casillas de Entradas';
  end if;
  if position('0052:' in v_def) > 0 then
    raise notice 'ya estaba aplicada';
    return;
  end if;

  v_a := '  -- Una transferencia siempre queda cruzada con una fila en
  -- reservas (es lo que la liga al deposito), asi que aqui si hay
  -- de donde leer si vino de recepcion o de la pagina.
  select
    coalesce(sum(c.precio_cop) filter (where r.origen = ''recepcion''), 0),
    count(*) filter (where r.origen = ''recepcion''),
    coalesce(sum(c.precio_cop) filter (where r.origen <> ''recepcion''), 0),
    count(*) filter (where r.origen <> ''recepcion'')
    into v_entra_recep_tr, v_entra_recep_tr_n, v_entra_pag_tr, v_entra_pag_tr_n
    from reservas r join clases c on c.id = r.clase_id
   where r.estado = ''confirmada'' and r.tipo = ''suelta'' and r.pago_id is not null
     and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia;';

  v_b :=
    '  -- 0052: la transferencia que cobra recepcion NO deja fila en' || E'\n' ||
    '  -- reservas. La persona ya esta adentro, no hay cupo que apartar,' || E'\n' ||
    '  -- asi que se registra como movimiento de caja igual que el' || E'\n' ||
    '  -- efectivo. Se lee de ahi, que es donde esa plata vive.' || E'\n' ||
    '  select coalesce(sum(valor_cop), 0), count(*)' || E'\n' ||
    '    into v_entra_recep_tr, v_entra_recep_tr_n' || E'\n' ||
    '    from caja_movimientos' || E'\n' ||
    '   where dia = v_dia and not anulado' || E'\n' ||
    '     and sentido = ''ingreso'' and medio = ''transferencia''' || E'\n' ||
    '     and concepto = ''clase_suelta'';' || E'\n\n' ||
    '  -- La pagina si deja reserva: es la fila que cruza el deposito con' || E'\n' ||
    '  -- la clase. Se nombran los dos origenes de la pagina en vez de' || E'\n' ||
    '  -- "todo lo que no sea recepcion", para que ''reprogramada'' —que no' || E'\n' ||
    '  -- es plata que entro hoy— no se cuele aqui el dia que traiga pago.' || E'\n' ||
    '  select coalesce(sum(c.precio_cop), 0), count(*)' || E'\n' ||
    '    into v_entra_pag_tr, v_entra_pag_tr_n' || E'\n' ||
    '    from reservas r join clases c on c.id = r.clase_id' || E'\n' ||
    '   where r.estado = ''confirmada'' and r.tipo = ''suelta''' || E'\n' ||
    '     and r.pago_id is not null' || E'\n' ||
    '     and r.origen in (''web'', ''formulario'')' || E'\n' ||
    '     and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia;';

  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro la consulta de entradas por transferencia exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  execute v_def;
end $$;
