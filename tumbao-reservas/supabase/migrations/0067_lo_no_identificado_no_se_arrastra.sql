-- ---------------------------------------------------------------------
-- 0067 — Lo que no se identificó no se arrastra al día siguiente
--
-- LA REGLA, DICHA POR QUIEN LLEVA LA CAJA
-- «Si un día hay dineros registrados que no se logran identificar, no se
--  puede impedir el cierre: puede pasar que un cliente pagó y no nos
--  reportó. Pero al día siguiente no es necesario que vuelva a aparecer,
--  porque para eso es el cuadre del día. Si llega alguien y dice que
--  pagó hace tres días, se genera el ingreso en caja y se apunta la
--  referencia del comprobante. Tenemos que avanzar.»
--
-- LO QUE HACÍA ANTES
-- La lista de depósitos sin dueño arrastraba una ventana de 20 días. Un
-- pago que nadie reclamó el lunes seguía apareciendo el martes, el
-- miércoles y tres semanas después. La lista solo crecía, y una lista
-- que solo crece se deja de mirar — que es exactamente lo contrario de
-- lo que hace falta el día que aparece uno de verdad.
--
-- LO QUE HACE AHORA
-- La ventana es el día que se está mirando. Lo de hoy sale hoy; mañana
-- la lista arranca limpia. Al mirar un día pasado se ve lo que quedó
-- sin identificar ESE día, que es lo que hace falta para conciliar el
-- mes.
--
-- NO SE PIERDE NADA, Y ESTO ES LO IMPORTANTE
-- El depósito sigue entero en `pagos`, con su valor, su fecha, su
-- remitente y su referencia. Sigue contando en el extracto de su día.
-- Y `caja_cierres.banco_sin_ident_cop` ya guarda, cierre por cierre,
-- cuánto quedó sin identificar ese día: la conciliación del mes se hace
-- contra eso, no contra una lista que se acumula en pantalla.
--
-- EL CIERRE NUNCA SE BLOQUEÓ POR ESTO, Y SIGUE SIN BLOQUEARSE.
-- Se comprobó antes de tocar nada: las salidas de error de `caja_cerrar`
-- son de autorización y de conteo (NO_AUTORIZADO, CONTADO_INVALIDO,
-- DEJADO_INVALIDO, DEJADO_MAYOR_QUE_CONTADO, DIA_YA_CERRADO,
-- MOTIVO_REQUERIDO). Ninguna mira el dinero sin identificar. Que siga
-- así: un cierre que no se puede hacer a las nueve de la noche es peor
-- que un descuadre documentado.
--
-- EL QUE LLEGA TARDE
-- Quien aparece a los tres días diciendo que pagó no necesita que su
-- depósito siga en la lista: se le registra el ingreso en la Caja y se
-- apunta la referencia del comprobante en la nota del movimiento. Esa
-- nota es la que amarra el cobro con el renglón del extracto cuando se
-- concilie el mes.
-- ---------------------------------------------------------------------

do $$
declare
  v_def text;
  v_ini int;
  v_nuevo text;

  c_dias_viejo constant text := '  c_dias constant int := 20;';
  c_dias_nuevo constant text :=
    '  -- 0067: era 20. La ventana de lo que sigue sin dueño es EL DÍA,' || E'\n' ||
    '  -- no las tres semanas de atrás: lo que no se identificó ya quedó' || E'\n' ||
    '  -- contado en el cierre de su día y no vuelve a pedir turno.' || E'\n' ||
    '  c_dias constant int := 1;';

  c_corte_viejo constant text :=
    '  v_corte := greatest(v_hasta - make_interval(days => c_dias),' || E'\n' ||
    '                      inicio_produccion()::timestamp at time zone ''America/Bogota'');';
  c_corte_nuevo constant text :=
    '  v_corte := greatest(v_desde,' || E'\n' ||
    '                      inicio_produccion()::timestamp at time zone ''America/Bogota'');';

  c_tot_viejo constant text := '   where fecha_pago >= v_corte;';
  c_tot_nuevo constant text := '   where fecha_pago >= v_corte and fecha_pago < v_hasta;';

  c_lis_viejo constant text := '       where p.fecha_pago >= v_corte';
  c_lis_nuevo constant text := '       where p.fecha_pago >= v_corte and p.fecha_pago < v_hasta';
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if v_def is null then raise exception '0067: no existe caja_del_dia'; end if;

  if position('0067:' in v_def) > 0 then
    raise notice '0067 ya estaba puesta, no se toca';
    return;
  end if;

  -- Se empalma por marcadores sobre la definición VIVA: producción tiene
  -- arreglos que no están en el repo y reescribir la función entera los
  -- borraría. Si un anclaje no aparece se falla — parchear a ciegas la
  -- función de la caja es peor que no parchearla.

  -- ── 1. la ventana ─────────────────────────────────────────────────
  v_ini := position(c_dias_viejo in v_def);
  if v_ini = 0 then raise exception '0067: no se encontró c_dias'; end if;
  v_def := left(v_def, v_ini - 1) || c_dias_nuevo
           || substr(v_def, v_ini + length(c_dias_viejo));

  -- ── 2. el corte pasa a ser el arranque del día ────────────────────
  -- Se conserva el `greatest` contra inicio_produccion(): es la fecha
  -- desde la que estos datos son de fiar, y mirar un día anterior a ella
  -- no debe sacar nada.
  v_ini := position(c_corte_viejo in v_def);
  if v_ini = 0 then raise exception '0067: no se encontró el cálculo de v_corte'; end if;
  v_def := left(v_def, v_ini - 1) || c_corte_nuevo
           || substr(v_def, v_ini + length(c_corte_viejo));

  -- ── 3 y 4. el techo del día ───────────────────────────────────────
  -- Sin el `< v_hasta`, mirar un día pasado arrastraría todo lo que vino
  -- DESPUÉS, que es el mismo problema al revés y rompería la
  -- conciliación del mes.
  v_ini := position(c_tot_viejo in v_def);
  if v_ini = 0 then raise exception '0067: no se encontró el total de libres'; end if;
  v_def := left(v_def, v_ini - 1) || c_tot_nuevo
           || substr(v_def, v_ini + length(c_tot_viejo));

  v_ini := position(c_lis_viejo in v_def);
  if v_ini = 0 then raise exception '0067: no se encontró la lista de libres'; end if;
  v_def := left(v_def, v_ini - 1) || c_lis_nuevo
           || substr(v_def, v_ini + length(c_lis_viejo));

  if position('0067:' in v_def) = 0 then
    raise exception '0067: el empalme no dejó la marca';
  end if;
  execute v_def;
  raise notice '0067: caja_del_dia parcheada — lo sin dueño ya no se arrastra';
end $$;
