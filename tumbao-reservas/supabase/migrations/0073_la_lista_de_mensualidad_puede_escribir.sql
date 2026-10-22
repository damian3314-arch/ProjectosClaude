-- 0073 · La lista de mensualidad tiene que poder escribir.
--
-- SÍNTOMA: la pestaña Mensualidad del panel no enseña nada. El Worker
-- contesta 502 y en sus registros queda:
--
--   supabase 405: {"code":"25006",
--     "message":"cannot execute UPDATE in a read-only transaction"}
--
-- CAUSA: en la 0070 marqué `mensualidad_lista` como STABLE porque «solo
-- lee». Solo lee la lista, sí — pero lo primero que hace es llamar a
-- `verificar_token_admin`, y esa función SÍ escribe: sella
-- `admin_tokens.ultimo_uso` en cada uso. PostgREST corre las funciones
-- STABLE dentro de una transacción de solo lectura, así que ese UPDATE
-- revienta y se lleva por delante la llamada entera.
--
-- Ninguna otra función de admin tenía el problema porque todas son
-- VOLATILE (el valor por defecto): `caja_del_dia`, `mensualidad_solicitar`,
-- `mensualidad_reportar_pago`. La marca STABLE la puse a mano solo aquí.
--
-- `mensualidad_cupos` también es STABLE y esa se queda como está: es
-- pública, no verifica token y por lo tanto no escribe nada. Se comprobó
-- contra producción — el endpoint público responde 200 y la página de
-- mensualidad pinta los cupos bien.
--
-- No cambia ningún dato, ninguna tabla y ningún permiso: solo la
-- volatilidad declarada de una función.

alter function public.mensualidad_lista(text) volatile;

-- Que no se vuelva a colar: cualquier función que verifique un token de
-- admin escribe, y por lo tanto no puede ser STABLE ni IMMUTABLE.
--
-- `prokind = 'f'` deja fuera las agregadas y de ventana: a esas
-- `pg_get_functiondef` no les saca definición, revienta con «array_agg
-- is an aggregate function» y tumbaría la migración entera por un
-- chequeo que ni siquiera les aplica.
do $c$
declare v_mal text;
begin
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', ', ')
    into v_mal
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prokind = 'f'
     and p.provolatile in ('i', 's')
     and pg_get_functiondef(p.oid) like '%verificar_token_admin%';

  if v_mal is not null then
    raise exception
      '0073: estas funciones verifican token (que escribe) y estan marcadas STABLE/IMMUTABLE: %',
      v_mal;
  end if;
end
$c$;
