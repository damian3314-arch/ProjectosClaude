-- 0173 · El freno de ventas no se activa con la calidad «UNKNOWN»
--
-- El domingo 11 oct a las 5 am el freno (0163) apagó las ventas porque Meta reportó la calidad del número como «UNKNOWN».
-- UNKNOWN no es una baja de calidad: es lo que Meta muestra cuando no tiene datos suficientes (fin de semana con poco
-- movimiento). El lunes el número estaba en GREEN otra vez. Damián (12 oct) aprobó que el freno solo se active cuando Meta
-- marque el número en YELLOW o RED (o cualquier valor que no sea GREEN ni UNKNOWN), y volver a encender las ventas.
--
-- Cambia solo la condición de la calidad dentro de ventas_freno_revisar; las demás (bajas > 8 %, fallos > 25 %, error
-- 131042) siguen igual. Nada destructivo.

do $$
declare
  v_def text := pg_get_functiondef('public.ventas_freno_revisar(text)'::regprocedure);
  v_viejo text := $v$if coalesce(p_calidad, 'GREEN') <> 'GREEN' then$v$;
  v_nuevo text := $v$if upper(coalesce(p_calidad, 'GREEN')) not in ('GREEN', 'UNKNOWN') then$v$;
begin
  if position(v_nuevo in v_def) > 0 then
    raise notice '0173 ya aplicada';
    return;
  end if;
  if position(v_viejo in v_def) = 0 then
    raise exception '0173: no encontré la condición de calidad en ventas_freno_revisar';
  end if;
  execute replace(v_def, v_viejo, v_nuevo);
end $$;

-- Las ventas se vuelven a encender (decisión de Damián, 12 oct).
update ajustes set valor = 'encendido' where clave = 'wa_ventas';
