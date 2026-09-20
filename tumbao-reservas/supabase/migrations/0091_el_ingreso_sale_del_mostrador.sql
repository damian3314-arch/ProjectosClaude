-- 0091 — El ingreso sale del mostrador
--
-- POR QUÉ
--
-- La tesorería sacaba las entradas de `ventas_entre`, que lee la Caja. Y
-- la Caja no empezó a registrar hasta el 10 de agosto. Con eso, agosto
-- salía así:
--
--   entradas   9.815.000     ← le faltaban los nueve primeros días
--   salidas   11.986.900
--   utilidad  −2.171.900     ← un mes en pérdida
--
-- Con el reporte de AdminGym cargado (0090), agosto entró de verdad
-- 14.170.000. No fue un mes malo: dejó 2.183.100 de utilidad. La pérdida
-- era del dato, no del negocio.
--
-- ── CÓMO SE ELIGE LA FUENTE ─────────────────────────────────────────
--
-- No es «mostrador o Caja», es día por día:
--
--   · hasta donde llega el reporte del mostrador → el mostrador
--   · de ahí en adelante                          → la Caja
--
-- Los dos tramos no se pisan, así que no se cuenta nada dos veces, y el
-- de hoy siempre tiene número aunque el reporte sea de la semana pasada.
-- Cuando Damián suba un export más nuevo, el corte se mueve solo.
--
-- El aviso número 5 cambia de tema. Antes decía «el periodo con el que
-- comparas está incompleto porque la Caja empezó el 10/08»; eso ya no es
-- cierto para nada desde enero. Ahora dice hasta qué día llega el
-- reporte y cuántos días está cubriendo la Caja en su lugar, que es lo
-- único que hoy puede dejar un ingreso corto.
--
-- `entradas` se sigue devolviendo tal cual: es el desglose de lo que pasó
-- por la Caja y la página, y sirve para conciliar. Lo que cambia es de
-- dónde sale la cifra grande.

do $$
declare
  d text := pg_get_functiondef('public.admin_tesoreria(text, date, date)'::regprocedure);

  -- 1 · las variables nuevas
  a_viejo constant text := '  v_txt     text;
begin';
  a_nuevo constant text := '  v_txt     text;
  -- 0091: el ingreso ya no sale solo de la Caja.
  v_mos_hasta date;    -- hasta qué día llega el reporte del mostrador
  v_corte     date;    -- el último día que cubre el mostrador en este rango
  v_ing       bigint;  -- lo que entró, de donde toque
  v_ing_a     bigint;
  v_fuente    text;
  v_dias_caja int;
begin';

  -- 2 · de dónde sale cada tramo
  b_viejo constant text := 'v_ent   := ventas_entre(v_desde,  v_hasta);
  v_ent_a := ventas_entre(v_adesde, v_ahasta);';
  b_nuevo constant text := 'v_ent   := ventas_entre(v_desde,  v_hasta);
  v_ent_a := ventas_entre(v_adesde, v_ahasta);

  -- 0091: el ingreso se arma por tramos. Hasta donde llega el reporte
  -- del mostrador manda el mostrador; de ahí en adelante, la Caja. Los
  -- dos tramos son días distintos, así que nada se cuenta dos veces.
  select max(dia) into v_mos_hasta from ventas_mostrador;
  v_corte := coalesce(v_mos_hasta, v_desde - 1);

  select coalesce(sum(cobrado_cop), 0) into v_ing from ventas_mostrador
   where dia between v_desde and least(v_hasta, v_corte);
  if v_hasta > v_corte then
    v_ing := v_ing + coalesce((ventas_entre(greatest(v_desde, v_corte + 1),
                                            v_hasta)->>''ingreso_cop'')::bigint, 0);
  end if;

  select coalesce(sum(cobrado_cop), 0) into v_ing_a from ventas_mostrador
   where dia between v_adesde and least(v_ahasta, v_corte);
  if v_ahasta > v_corte then
    v_ing_a := v_ing_a + coalesce((ventas_entre(greatest(v_adesde, v_corte + 1),
                                                v_ahasta)->>''ingreso_cop'')::bigint, 0);
  end if;

  v_dias_caja := greatest(v_hasta - greatest(v_desde - 1, v_corte), 0);
  v_fuente := case when v_mos_hasta is null then ''caja''
                   when v_dias_caja = 0    then ''mostrador''
                   else ''mixto'' end;';

  -- 3 · la utilidad, sobre el ingreso nuevo
  c_viejo constant text := 'v_util   := coalesce((v_ent->>''ingreso_cop'')::bigint, 0)   - v_sal;
  v_util_a := coalesce((v_ent_a->>''ingreso_cop'')::bigint, 0) - v_sal_a;';
  c_nuevo constant text := 'v_util   := v_ing   - v_sal;
  v_util_a := v_ing_a - v_sal_a;';

  -- 4 · el aviso 5 ya no es sobre la Caja vieja
  e_viejo constant text := '-- 5. La Caja no existía al principio: comparar contra un mes en el que
  --    no se registraba todo da un porcentaje que miente.
  select min(dia) into v_primer from caja_movimientos where not anulado;
  if v_primer is not null and v_adesde < v_primer then
    v_rev := v_rev || jsonb_build_object(
      ''clave'', ''antes_incompleto'', ''peso'', 5, ''cop'', 0,
      ''titulo'', ''El periodo con el que se compara está incompleto'',
      ''detalle'', ''La Caja empezó a registrar el '' ||
                 to_char(v_primer, ''DD/MM'') || '', así que lo de antes de esa '' ||
                 ''fecha tiene menos ingresos de los que hubo. La comparación '' ||
                 ''se ve mejor de lo que fue.'');
  end if;';
  e_nuevo constant text := '-- 5. 0091: hasta dónde llega el reporte del mostrador.
  --    Es lo único que hoy puede dejar el ingreso corto: los días que el
  --    reporte todavía no vio los cubre la Caja, que solo ve lo que pasó
  --    por la página y el banco y se pierde el efectivo del mostrador.
  if v_mos_hasta is null then
    select min(dia) into v_primer from caja_movimientos where not anulado;
    v_rev := v_rev || jsonb_build_object(
      ''clave'', ''sin_mostrador'', ''peso'', 5, ''cop'', 0,
      ''titulo'', ''No hay reporte de ventas cargado'',
      ''detalle'', ''Las entradas salen de la Caja, que empezó el '' ||
                 to_char(coalesce(v_primer, v_hoy), ''DD/MM'') || '' y solo ve lo '' ||
                 ''que pasó por la página y el banco. Sube el reporte de '' ||
                 ''ventas de AdminGym para que el ingreso sea el de verdad.'');
  elsif v_dias_caja > 0 then
    v_rev := v_rev || jsonb_build_object(
      ''clave'', ''mostrador_viejo'', ''peso'', 5, ''cop'', 0,
      ''titulo'', ''El reporte de ventas llega hasta el '' ||
                to_char(v_mos_hasta, ''DD/MM''),
      ''detalle'', v_dias_caja || '' día'' ||
                 case when v_dias_caja = 1 then '''' else ''s'' end ||
                 '' de este periodo salen de la Caja, que no ve el efectivo '' ||
                 ''cobrado en el mostrador. Sube el reporte nuevo de AdminGym '' ||
                 ''y esa parte se completa sola.'');
  end if;';

  -- 5 · el margen y las cifras nuevas en la respuesta
  f_viejo constant text := '''salidas_cop'', v_sal,';
  f_nuevo constant text := '-- 0091: la cifra grande de «entró». `entradas` sigue siendo el
    -- desglose de la Caja, que es lo que sirve para conciliar.
    ''ingreso_cop'', v_ing,
    ''ingreso_antes_cop'', v_ing_a,
    ''fuente_ingreso'', v_fuente,
    ''mostrador_hasta'', v_mos_hasta,
    ''salidas_cop'', v_sal,';

  g_viejo constant text := '''margen_pct'', case when coalesce((v_ent->>''ingreso_cop'')::bigint, 0) = 0 then null
                       else round(v_util * 100.0 /
                                  (v_ent->>''ingreso_cop'')::bigint) end,';
  g_nuevo constant text := '''margen_pct'', case when v_ing = 0 then null
                       else round(v_util * 100.0 / v_ing) end,';
begin
  if position('0091:' in d) > 0 then
    raise notice '0091 ya estaba puesto en admin_tesoreria';
    return;
  end if;
  if position(a_viejo in d) = 0 then raise exception '0091: no encuentro el declare'; end if;
  if position(b_viejo in d) = 0 then raise exception '0091: no encuentro ventas_entre'; end if;
  if position(c_viejo in d) = 0 then raise exception '0091: no encuentro la utilidad'; end if;
  if position(e_viejo in d) = 0 then raise exception '0091: no encuentro el aviso 5'; end if;
  if position(f_viejo in d) = 0 then raise exception '0091: no encuentro salidas_cop'; end if;
  if position(g_viejo in d) = 0 then raise exception '0091: no encuentro el margen'; end if;

  d := replace(d, a_viejo, a_nuevo);
  d := replace(d, b_viejo, b_nuevo);
  d := replace(d, c_viejo, c_nuevo);
  d := replace(d, e_viejo, e_nuevo);
  d := replace(d, f_viejo, f_nuevo);
  d := replace(d, g_viejo, g_nuevo);
  execute d;
end $$;
