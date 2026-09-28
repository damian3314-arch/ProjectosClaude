-- 0110 · En el debrief de la mañana, hoy también es un día para vender.
--
-- "dias_con_clase_que_quedan" contaba desde mañana. A las 10 pm está bien
-- (el día ya se vendió); a las 6 am no: el lunes 28 decía 2 días y
-- $2.025.000 por día, cuando quedaban lunes, martes y miércoles.

do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.tablero_tumbao(text)'::regprocedure) into v_src;
  v_new := replace(v_src,
    'from generate_series(d + 1, fin_mes, interval ''1 day'') g',
    'from generate_series(case when p_tipo = ''manana'' then d else d + 1 end, fin_mes, interval ''1 day'') g');
  if v_new = v_src then
    raise exception '0110: no se aplicó el cambio';
  end if;
  execute v_new;
end
$mig$;
