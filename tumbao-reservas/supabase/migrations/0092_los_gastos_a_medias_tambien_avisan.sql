-- 0092 — Un periodo con gastos a medias tampoco es real
--
-- Con el ingreso arreglado (0091), junio quedó así:
--
--   entró     12.310.000
--   salió      3.781.200
--   utilidad   8.528.800   ← 69% de margen, y ningún aviso
--
-- Ese 69% es mentira. El chat de gastos empieza el 21 de junio, así que
-- junio tiene el ingreso del mes entero contra los gastos de diez días.
-- El aviso que existía —`sin_gastos`— solo salta cuando no hay NINGÚN
-- gasto; con dieciséis renglones cargados se quedó callado.
--
-- Es el error más caro de esta pantalla y ya lo habíamos escrito en la
-- prueba de la 0087: un número bueno que nadie sabe que es mentira hace
-- más daño que no tener número. Este aviso es el espejo del 5: aquel
-- mira hasta dónde llega el ingreso, éste hasta dónde llegan los gastos.

do $$
declare
  d text := pg_get_functiondef('public.admin_tesoreria(text, date, date)'::regprocedure);

  viejo constant text := '-- 6. Un mes sin gastos cargados no es un mes sin gastos.
  select count(*)::int into v_n from gastos
   where not anulado and dia between v_desde and v_hasta;
  if v_n = 0 then
    v_rev := jsonb_build_object(
      ''clave'', ''sin_gastos'', ''peso'', 0, ''cop'', 0,
      ''titulo'', ''Este periodo no tiene gastos cargados'',
      ''detalle'', ''Solo se ve la caja menor. La utilidad de arriba no es real '' ||
                 ''hasta que se carguen la nómina, el arriendo y los profes.'')
      || v_rev;
  end if;';
  nuevo constant text := '-- 6. Un mes sin gastos cargados no es un mes sin gastos.
  select count(*)::int into v_n from gastos
   where not anulado and dia between v_desde and v_hasta;
  if v_n = 0 then
    v_rev := jsonb_build_object(
      ''clave'', ''sin_gastos'', ''peso'', 0, ''cop'', 0,
      ''titulo'', ''Este periodo no tiene gastos cargados'',
      ''detalle'', ''Solo se ve la caja menor. La utilidad de arriba no es real '' ||
                 ''hasta que se carguen la nómina, el arriendo y los profes.'')
      || v_rev;

  -- 0092: y un periodo con gastos A MEDIAS tampoco es real. El chat de
  -- gastos arranca el 21/6, así que junio tiene el ingreso de todo el mes
  -- contra los gastos de diez días: 69% de margen y ni un aviso. Va con
  -- peso 0, arriba del todo, porque invalida la utilidad entera.
  else
    select min(dia) into v_primer from gastos where not anulado;
    if v_primer is not null and v_desde < v_primer then
      v_rev := jsonb_build_object(
        ''clave'', ''gastos_a_medias'', ''peso'', 0,
        ''cop'', 0,
        ''titulo'', ''Faltan los gastos de los primeros '' ||
                  (v_primer - v_desde) || '' día'' ||
                  case when (v_primer - v_desde) = 1 then '''' else ''s'' end ||
                  '' del periodo'',
        ''detalle'', ''El primer gasto cargado es del '' ||
                   to_char(v_primer, ''DD/MM'') || '', pero aquí se está contando '' ||
                   ''el ingreso desde el '' || to_char(v_desde, ''DD/MM'') || ''. '' ||
                   ''La utilidad y el margen de arriba salen mejores de lo que '' ||
                   ''fueron. Carga los gastos que faltan antes de creértelos.'')
        || v_rev;
    end if;
  end if;';
begin
  if position('0092:' in d) > 0 then
    raise notice '0092 ya estaba puesto';
    return;
  end if;
  if position(viejo in d) = 0 then
    raise exception '0092: no encuentro el aviso de sin_gastos en admin_tesoreria';
  end if;
  execute replace(d, viejo, nuevo);
end $$;
