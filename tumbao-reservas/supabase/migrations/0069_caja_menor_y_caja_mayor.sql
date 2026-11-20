-- ---------------------------------------------------------------------
-- 0069 — De qué caja salió el gasto
--
-- EL PROBLEMA, CONTADO POR QUIEN LO SUFRE
-- La cajera apunta los gastos del día. Pero no todos salen del cajón que
-- ella tiene delante: unas veces Tania paga con la cuenta de la empresa,
-- y otras con efectivo de la empresa que no está en ese cajón. Hasta hoy
-- solo había un sitio donde apuntarlo, así que ese gasto se registraba
-- como si hubiera salido del cajón — y el arqueo de la noche pedía menos
-- billetes de los que de verdad tenía que haber. Un faltante inventado.
--
-- LAS DOS CAJAS
--   · CAJA MENOR  — el cajón del mostrador. Tiene una base, entra el
--                   efectivo de las clases sueltas y las mensualidades, y
--                   de ahí salen los gastos del día. Es la única que se
--                   arquea contando billetes.
--   · CAJA MAYOR  — la plata de la empresa. Puede salir en efectivo o por
--                   transferencia, y NO pasa por el cajón. Se apunta para
--                   que quede reportada, pero no toca el arqueo.
--
-- LA REGLA QUE ESTO HACE CUMPLIR
-- Solo un egreso en efectivo de la CAJA MENOR baja lo que debería haber
-- en el cajón. Todo lo demás se registra, se suma en las salidas del día
-- y se deja fuera del arqueo. Antes esa distinción no existía y por eso
-- no se podía escribir.
--
-- LA CAJA MENOR NO TRANSFIERE
-- Un cajón no hace transferencias: si un egreso sale por transferencia,
-- salió de la caja mayor por definición. Queda como restricción y no como
-- costumbre, porque es la combinación que volvería a descuadrar el arqueo
-- en silencio.
--
-- SE PUEDE APLICAR SIN MIEDO: hoy no hay ni un solo egreso registrado en
-- toda la base (comprobado antes de escribir esto — que es justamente el
-- síntoma del problema: «el 20 de agosto se le pagaron 25.000 al celador
-- y no quedaron en ninguna parte»). Así que ninguna fila existente puede
-- violar la restricción nueva.
-- ---------------------------------------------------------------------

-- ── 1. la columna ─────────────────────────────────────────────────────
alter table caja_movimientos
  add column if not exists origen text not null default 'caja_menor';

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'caja_movimientos_origen_ck') then
    alter table caja_movimientos add constraint caja_movimientos_origen_ck
      check (origen in ('caja_menor', 'caja_mayor'));
  end if;

  -- Un cajón no transfiere. Solo se exige a los egresos: un INGRESO por
  -- transferencia a la caja menor sí existe y es lo más común del día
  -- (recepción cobra por transferencia), así que no se puede prohibir.
  if not exists (select 1 from pg_constraint
                  where conname = 'caja_movimientos_origen_medio_ck') then
    alter table caja_movimientos add constraint caja_movimientos_origen_medio_ck
      check (sentido <> 'egreso'
             or origen = 'caja_mayor'
             or medio = 'efectivo');
  end if;
end $$;

comment on column caja_movimientos.origen is
  'De dónde salió (o entró) la plata. caja_menor = el cajón del '
  'mostrador, el único que se arquea contando billetes. caja_mayor = la '
  'plata de la empresa, en efectivo o por transferencia, que no pasa por '
  'ese cajón. Solo un egreso en efectivo de caja_menor baja el arqueo.';

-- ── 2. caja_registrar acepta el origen ────────────────────────────────
do $$
declare
  v_def text;
  v_ini int;

  c_firma_viejo constant text := 'p_cantidad integer DEFAULT 1)';
  c_firma_nuevo constant text :=
    'p_cantidad integer DEFAULT 1, p_origen text DEFAULT ''caja_menor'')';

  c_decl_viejo constant text := '  v_cantidad int;   -- 0065: cuánta gente cubre este cobro';
  c_decl_nuevo constant text :=
    '  v_cantidad int;   -- 0065: cuánta gente cubre este cobro' || E'\n' ||
    '  v_origen text;    -- 0069: de qué caja salió';

  c_val_viejo constant text :=
    '  if p_medio not in (''efectivo'', ''transferencia'') then' || E'\n' ||
    '    return jsonb_build_object(''ok'', false, ''error'', ''MEDIO_INVALIDO'');' || E'\n' ||
    '  end if;';
  c_val_nuevo constant text :=
    '  if p_medio not in (''efectivo'', ''transferencia'') then' || E'\n' ||
    '    return jsonb_build_object(''ok'', false, ''error'', ''MEDIO_INVALIDO'');' || E'\n' ||
    '  end if;' || E'\n' || E'\n' ||
    '  -- 0069: de qué caja salió. Null es caja_menor: una llamada vieja' || E'\n' ||
    '  -- que no manda origen significa exactamente lo de siempre — el' || E'\n' ||
    '  -- cajón del mostrador.' || E'\n' ||
    '  v_origen := coalesce(nullif(btrim(coalesce(p_origen, '''')), ''''), ''caja_menor'');' || E'\n' ||
    '  if v_origen not in (''caja_menor'', ''caja_mayor'') then' || E'\n' ||
    '    return jsonb_build_object(''ok'', false, ''error'', ''ORIGEN_INVALIDO'');' || E'\n' ||
    '  end if;' || E'\n' ||
    '  -- Un cajón no transfiere. Se atrapa aquí para devolver un mensaje' || E'\n' ||
    '  -- que se entienda, en vez de dejar que reviente la restricción.' || E'\n' ||
    '  if p_sentido = ''egreso'' and v_origen = ''caja_menor''' || E'\n' ||
    '     and p_medio <> ''efectivo'' then' || E'\n' ||
    '    return jsonb_build_object(''ok'', false, ''error'', ''ORIGEN_NO_APLICA'',' || E'\n' ||
    '      ''mensaje'', ''De la caja menor solo sale efectivo. Si fue una ''' || E'\n' ||
    '                  ''transferencia, salió de la caja mayor.'');' || E'\n' ||
    '  end if;';

  c_ins_viejo constant text :=
    '                                nota, registrado_por, pago_id, cantidad)';
  c_ins_nuevo constant text :=
    '                                nota, registrado_por, pago_id, cantidad,' || E'\n' ||
    '                                origen)';

  c_val2_viejo constant text := '          v_cantidad)';
  c_val2_nuevo constant text := '          v_cantidad, v_origen)';
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_registrar'
     and pg_get_function_arguments(p.oid) not like '%p_origen%';
  if v_def is null then
    raise notice '0069: caja_registrar ya tenía p_origen';
    return;
  end if;

  v_ini := position(c_firma_viejo in v_def);
  if v_ini = 0 then raise exception '0069: no se encontró la firma'; end if;
  v_def := left(v_def, v_ini - 1) || c_firma_nuevo
           || substr(v_def, v_ini + length(c_firma_viejo));

  v_ini := position(c_decl_viejo in v_def);
  if v_ini = 0 then raise exception '0069: no se encontró dónde declarar v_origen'; end if;
  v_def := left(v_def, v_ini - 1) || c_decl_nuevo
           || substr(v_def, v_ini + length(c_decl_viejo));

  v_ini := position(c_val_viejo in v_def);
  if v_ini = 0 then raise exception '0069: no se encontró la validación del medio'; end if;
  v_def := left(v_def, v_ini - 1) || c_val_nuevo
           || substr(v_def, v_ini + length(c_val_viejo));

  v_ini := position(c_ins_viejo in v_def);
  if v_ini = 0 then raise exception '0069: no se encontró el insert'; end if;
  v_def := left(v_def, v_ini - 1) || c_ins_nuevo
           || substr(v_def, v_ini + length(c_ins_viejo));

  v_ini := position(c_val2_viejo in v_def);
  if v_ini = 0 then raise exception '0069: no se encontró el values'; end if;
  v_def := left(v_def, v_ini - 1) || c_val2_nuevo
           || substr(v_def, v_ini + length(c_val2_viejo));

  execute v_def;

  -- La firma de 8 argumentos se suelta en el MISMO bloque: con las dos
  -- vivas, una llamada de 8 argumentos es ambigua y Postgres la rechaza.
  -- Es la ventana que la 0065 dejó abierta unos segundos; aquí no se
  -- abre.
  drop function if exists public.caja_registrar(
    text, text, text, integer, text, text, uuid, integer);

  revoke all on function public.caja_registrar(
    text, text, text, integer, text, text, uuid, integer, text) from public;
  grant execute on function public.caja_registrar(
    text, text, text, integer, text, text, uuid, integer, text) to service_role;

  raise notice '0069: caja_registrar acepta p_origen';
end $$;

-- ── 3. el arqueo solo mira la caja menor ──────────────────────────────
do $$
declare
  v_def text;
  v_ini int;

  c_sel_viejo constant text :=
    '    coalesce(sum(valor_cop) filter (where sentido=''egreso''  and medio=''efectivo''), 0),' || E'\n' ||
    '    coalesce(sum(valor_cop) filter (where sentido=''egreso''  and medio=''transferencia''), 0),';
  c_sel_nuevo constant text :=
    '    -- 0069: SOLO la caja menor. Es lo único que baja lo que debería' || E'\n' ||
    '    -- haber en el cajón; un gasto que Tania pagó con plata de la' || E'\n' ||
    '    -- empresa se registra igual pero no puede pedir menos billetes.' || E'\n' ||
    '    coalesce(sum(valor_cop) filter (where sentido=''egreso''  and medio=''efectivo''' || E'\n' ||
    '                                      and origen=''caja_menor''), 0),' || E'\n' ||
    '    coalesce(sum(valor_cop) filter (where sentido=''egreso''  and medio=''transferencia''), 0),' || E'\n' ||
    '    -- El efectivo que salió de la caja mayor: se reporta, no se arquea.' || E'\n' ||
    '    coalesce(sum(valor_cop) filter (where sentido=''egreso''  and medio=''efectivo''' || E'\n' ||
    '                                      and origen=''caja_mayor''), 0),';

  c_into_viejo constant text :=
    '  into v_ing_ef, v_ing_tr, v_egr_ef, v_egr_tr, v_sin_resp, v_sin_resp_n';
  c_into_nuevo constant text :=
    '  into v_ing_ef, v_ing_tr, v_egr_ef, v_egr_tr, v_egr_may_ef,' || E'\n' ||
    '       v_sin_resp, v_sin_resp_n';

  c_dec_viejo constant text := '  v_ing_ef int; v_ing_tr int; v_egr_ef int; v_egr_tr int;';
  c_dec_nuevo constant text :=
    '  v_ing_ef int; v_ing_tr int; v_egr_ef int; v_egr_tr int;' || E'\n' ||
    '  v_egr_may_ef int;   -- 0069: efectivo que salió de la caja mayor';

  c_json_viejo constant text := '    ''egreso_efectivo'',  v_egr_ef,';
  c_json_nuevo constant text :=
    '    -- 0069: `egreso_efectivo` es SOLO el de la caja menor, porque es' || E'\n' ||
    '    -- el que entra en `esperado_efectivo` de la línea de abajo. Lo de' || E'\n' ||
    '    -- la caja mayor va aparte y no toca el arqueo.' || E'\n' ||
    '    ''egreso_efectivo'',  v_egr_ef,' || E'\n' ||
    '    ''egreso_caja_mayor_efectivo'', v_egr_may_ef,';

  -- `total_egresos` tiene que seguir siendo TODO lo que salió: es lo que
  -- se imprime en las salidas del día. Solo el arqueo distingue de dónde.
  c_tot_viejo constant text := '    ''total_egresos'',  v_egr_ef + v_egr_tr,';
  c_tot_nuevo constant text := '    ''total_egresos'',  v_egr_ef + v_egr_tr + v_egr_may_ef,';
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if v_def is null then raise exception '0069: no existe caja_del_dia'; end if;

  if position('0069:' in v_def) > 0 then
    raise notice '0069 ya estaba en caja_del_dia';
    return;
  end if;

  v_ini := position(c_dec_viejo in v_def);
  if v_ini = 0 then raise exception '0069: no se encontró la declaración de egresos'; end if;
  v_def := left(v_def, v_ini - 1) || c_dec_nuevo
           || substr(v_def, v_ini + length(c_dec_viejo));

  v_ini := position(c_sel_viejo in v_def);
  if v_ini = 0 then raise exception '0069: no se encontró el select de egresos'; end if;
  v_def := left(v_def, v_ini - 1) || c_sel_nuevo
           || substr(v_def, v_ini + length(c_sel_viejo));

  v_ini := position(c_into_viejo in v_def);
  if v_ini = 0 then raise exception '0069: no se encontró el into'; end if;
  v_def := left(v_def, v_ini - 1) || c_into_nuevo
           || substr(v_def, v_ini + length(c_into_viejo));

  v_ini := position(c_json_viejo in v_def);
  if v_ini = 0 then raise exception '0069: no se encontró egreso_efectivo en el json'; end if;
  v_def := left(v_def, v_ini - 1) || c_json_nuevo
           || substr(v_def, v_ini + length(c_json_viejo));

  v_ini := position(c_tot_viejo in v_def);
  if v_ini = 0 then raise exception '0069: no se encontró total_egresos'; end if;
  v_def := left(v_def, v_ini - 1) || c_tot_nuevo
           || substr(v_def, v_ini + length(c_tot_viejo));

  if position('0069:' in v_def) = 0 then
    raise exception '0069: el empalme no dejó la marca';
  end if;
  execute v_def;
  raise notice '0069: caja_del_dia separa caja menor de caja mayor';
end $$;

-- ── 4. el cierre guarda el arqueo con la misma regla ──────────────────
do $$
declare
  v_def text;
  v_ini int;
  c_viejo constant text :=
    '    coalesce(sum(valor_cop) filter (where sentido=''egreso''  and medio=''efectivo''), 0)';
  c_nuevo constant text :=
    '    -- 0069: solo la caja menor baja el arqueo del cajón.' || E'\n' ||
    '    coalesce(sum(valor_cop) filter (where sentido=''egreso''  and medio=''efectivo''' || E'\n' ||
    '                                      and origen=''caja_menor''), 0)';
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_cerrar';
  if v_def is null then raise exception '0069: no existe caja_cerrar'; end if;

  if position('0069:' in v_def) > 0 then
    raise notice '0069 ya estaba en caja_cerrar';
    return;
  end if;

  v_ini := position(c_viejo in v_def);
  if v_ini = 0 then raise exception '0069: no se encontró el egreso en caja_cerrar'; end if;
  v_def := left(v_def, v_ini - 1) || c_nuevo
           || substr(v_def, v_ini + length(c_viejo));

  if position('0069:' in v_def) = 0 then
    raise exception '0069: el empalme no dejó la marca en caja_cerrar';
  end if;
  execute v_def;
  raise notice '0069: caja_cerrar arquea solo la caja menor';
end $$;
