-- 0077 · El resumen por concepto dice de qué caja salió cada gasto.
--
-- Damián, mirando la tirilla del 9 de septiembre:
--
--   «Ayúdame a que la tirilla del cierre discrimine los egresos, porque
--    debe mostrar cuándo salió para pagar a un profesor o gasto, y la
--    plata que sí está saliendo de caja para entregar al dueño.»
--
-- En el papel esas dos cosas viven en un solo renglón —«Gastos /
-- retiros $250.000»— y son de naturaleza distinta: $60.000 se le
-- pagaron a un profesor (eso es un costo) y $190.000 se los llevó el
-- dueño (eso no es un costo, es plata que cambia de bolsillo).
--
-- Para partir ese renglón el papel necesita el detalle por concepto de
-- los egresos, y ahí aparece el problema: `resumen_conceptos` agrupa por
-- `sentido`, `concepto` y `medio`, pero NO por `origen`. Un gasto en
-- efectivo de la caja mayor y uno de la caja menor, del mismo concepto,
-- caen en la misma fila.
--
-- Eso rompería el desglose de la forma más fea: la suma de los
-- renglones impresos dejaría de dar el total del cajón —porque la caja
-- mayor no sale de ese cajón, que es justo lo que arregló la 0069— y el
-- papel volvería a no sumar. Es la clase de error que se descubre
-- semanas después y ya no hay a quién preguntarle.
--
-- Así que se añade `origen` al resumen, y con eso la tirilla puede
-- listar SOLO lo que salió del cajón y garantizar que sus renglones den
-- exactamente `egreso_efectivo`.
--
-- No cambia ningún total existente. Los ingresos no se parten: todos
-- llevan `caja_menor` (el valor por defecto de la columna), comprobado
-- contra producción antes de aplicar esto.
--
-- Se parchea EN SITIO sobre la definición viva, no se reescribe:
-- producción trae arreglos que no están en este repo.

do $mig$
declare
  v_src   text;
  v_new   text;
  v_ancla text;
begin
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';

  if v_src is null then
    raise exception '0077: no existe public.caja_del_dia';
  end if;

  if position('0077:' in v_src) > 0 then
    raise notice '0077: ya aplicado, no se toca';
    return;
  end if;

  v_ancla :=
    E'  select coalesce(jsonb_agg(jsonb_build_object(\n' ||
    E'           ''sentido'', s.sentido, ''concepto'', s.concepto, ''medio'', s.medio,\n' ||
    E'           ''n'', s.n, ''valor_cop'', s.total)\n' ||
    E'         order by s.sentido desc, s.total desc), ''[]''::jsonb)\n' ||
    E'    into v_resumen\n' ||
    E'    from (\n' ||
    E'      select sentido, concepto, medio, sum(cantidad) as n,  -- 0065\n' ||
    E'             sum(valor_cop) as total\n' ||
    E'        from caja_movimientos\n' ||
    E'       where dia = v_dia and not anulado\n' ||
    E'       group by sentido, concepto, medio\n' ||
    E'    ) s;';

  if position(v_ancla in v_src) = 0 then
    raise exception '0077: no se encontro el armado de resumen_conceptos';
  end if;

  v_new := replace(v_src, v_ancla,
    E'  select coalesce(jsonb_agg(jsonb_build_object(\n' ||
    E'           ''sentido'', s.sentido, ''concepto'', s.concepto, ''medio'', s.medio,\n' ||
    E'           -- 0077: de que caja salio. Sin esto, un gasto en efectivo\n' ||
    E'           -- de la caja mayor y uno de la menor del mismo concepto\n' ||
    E'           -- caen en la misma fila, y el desglose del cajon en la\n' ||
    E'           -- tirilla dejaria de sumar `egreso_efectivo`.\n' ||
    E'           ''origen'', s.origen,\n' ||
    E'           ''n'', s.n, ''valor_cop'', s.total)\n' ||
    E'         order by s.sentido desc, s.total desc), ''[]''::jsonb)\n' ||
    E'    into v_resumen\n' ||
    E'    from (\n' ||
    E'      select sentido, concepto, medio, origen, sum(cantidad) as n,  -- 0065\n' ||
    E'             sum(valor_cop) as total\n' ||
    E'        from caja_movimientos\n' ||
    E'       where dia = v_dia and not anulado\n' ||
    E'       group by sentido, concepto, medio, origen\n' ||
    E'    ) s;');

  v_new := replace(v_new,
    E'-- 0071: el cuadre cuenta a quien entro, no a quien pago.',
    E'-- 0071: el cuadre cuenta a quien entro, no a quien pago.\n' ||
    E'-- 0077: el resumen por concepto dice de que caja salio cada gasto.');

  execute v_new;
end
$mig$;
