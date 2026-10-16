-- ---------------------------------------------------------------------
-- 0068 — El contador es del día; la lista para escoger, no
--
-- CORRIGE UN EXCESO DE LA 0067
-- La 0067 hizo bien en dejar de arrastrar lo no identificado: el cuadre
-- es del día y una lista de pendientes que solo crece se deja de mirar.
-- Pero estrechó a un día DOS cosas que salen del mismo dato y contestan
-- preguntas distintas:
--
--   1. EL CONTADOR — «de hoy quedan $X sin identificar». Es un aviso, y
--      su sitio es el día: mañana se arranca limpio. Aquí la 0067 tiene
--      razón y se queda como está.
--
--   2. LA LISTA — la que sale en «¿cuál de estos depósitos es?» cuando
--      la cajera registra un cobro por transferencia, y en la pantalla
--      de confirmar una reserva. Eso no es un pendiente: es la
--      herramienta con la que se ADJUDICA la plata.
--
-- POR QUÉ LA LISTA NO PUEDE SER DE UN DÍA
-- Quien transfiere a las once de la noche y aparece a las siete de la
-- mañana tiene su depósito fechado ayer. Con la ventana en un día su
-- pago no saldría en el selector, y la cajera —que lo tiene delante
-- enseñando el comprobante— no tendría con qué cruzarlo. Se registraría
-- suelto, y eso es justo el descuadre que todo esto vino a arreglar.
--
-- TRES DÍAS, NO VEINTE
-- Veinte hacían un muro de decenas de depósitos donde se escoge el
-- primero que cuadre por valor. Tres cubren el caso real —anoche, ayer,
-- el fin de semana— y dejan la lista corta.
--
-- Y PARA EL QUE LLEGA MÁS TARDE, lo que pidió quien lleva la caja: se le
-- registra el ingreso en la Caja y se apunta en la nota la referencia
-- del comprobante. Esa nota es la que amarra el cobro con el renglón
-- del extracto cuando se concilie el mes; no hace falta que su depósito
-- siga saliendo en ninguna lista.
-- ---------------------------------------------------------------------

do $$
declare
  v_def text;
  v_ini int;

  -- La declaración de la ventana de la lista, al lado de la del contador.
  c_dec_viejo constant text := '  c_dias constant int := 1;';
  c_dec_nuevo constant text :=
    '  c_dias constant int := 1;' || E'\n' ||
    '  -- 0068: la lista para ESCOGER depósito mira tres días, no uno.' || E'\n' ||
    '  -- El contador de arriba sí es del día; esto es otra cosa: es la' || E'\n' ||
    '  -- herramienta con la que se adjudica la plata, y quien transfiere' || E'\n' ||
    '  -- a las once de la noche y llega a las siete de la mañana tiene su' || E'\n' ||
    '  -- depósito fechado ayer.' || E'\n' ||
    '  c_dias_lista constant int := 3;' || E'\n' ||
    '  v_corte_lista timestamptz;';

  c_corte_viejo constant text :=
    '  v_corte := greatest(v_desde,' || E'\n' ||
    '                      inicio_produccion()::timestamp at time zone ''America/Bogota'');';
  c_corte_nuevo constant text :=
    '  v_corte := greatest(v_desde,' || E'\n' ||
    '                      inicio_produccion()::timestamp at time zone ''America/Bogota'');' || E'\n' ||
    '  v_corte_lista := greatest(v_hasta - make_interval(days => c_dias_lista),' || E'\n' ||
    '                      inicio_produccion()::timestamp at time zone ''America/Bogota'');';

  -- Solo la lista cambia de corte. El total de arriba (v_libre) se queda
  -- con v_corte, que es el día: ese es el número del aviso.
  c_lis_viejo constant text :=
    '       where p.fecha_pago >= v_corte and p.fecha_pago < v_hasta';
  c_lis_nuevo constant text :=
    '       where p.fecha_pago >= v_corte_lista and p.fecha_pago < v_hasta';
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if v_def is null then raise exception '0068: no existe caja_del_dia'; end if;

  if position('0068:' in v_def) > 0 then
    raise notice '0068 ya estaba puesta, no se toca';
    return;
  end if;
  if position('0067:' in v_def) = 0 then
    raise exception '0068: falta la 0067, que es lo que esta corrige';
  end if;

  v_ini := position(c_dec_viejo in v_def);
  if v_ini = 0 then raise exception '0068: no se encontró la declaración de c_dias'; end if;
  v_def := left(v_def, v_ini - 1) || c_dec_nuevo
           || substr(v_def, v_ini + length(c_dec_viejo));

  v_ini := position(c_corte_viejo in v_def);
  if v_ini = 0 then raise exception '0068: no se encontró el cálculo de v_corte'; end if;
  v_def := left(v_def, v_ini - 1) || c_corte_nuevo
           || substr(v_def, v_ini + length(c_corte_viejo));

  v_ini := position(c_lis_viejo in v_def);
  if v_ini = 0 then raise exception '0068: no se encontró la lista de libres'; end if;
  v_def := left(v_def, v_ini - 1) || c_lis_nuevo
           || substr(v_def, v_ini + length(c_lis_viejo));

  if position('0068:' in v_def) = 0 then
    raise exception '0068: el empalme no dejó la marca';
  end if;
  execute v_def;
  raise notice '0068: el contador sigue siendo del día; la lista mira 3 días';
end $$;
