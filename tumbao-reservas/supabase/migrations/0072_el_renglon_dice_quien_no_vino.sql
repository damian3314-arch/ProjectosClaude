-- 0072 · El renglón del extracto dice quién de los suyos no vino.
--
-- El 5 de septiembre la hoja 1 decía $300.000 y la hoja 2 decía
-- $315.000, y las dos tenían razón. Damián:
--
--   «Los valores de la hoja uno y la hoja 2 no cuadran. Una dice 300 y
--    la otra 315, esas son las diferencias que causan las confusiones.»
--
-- Los $15.000 salen de un solo depósito. Diana Carreño transfirió
-- $45.000 por tres clases de las 09:00:
--
--   Carolina Carreño       entró
--   Lina Johana Francis    entró
--   María Fernanda Caicedo NO vino  → reprogramada al 08-09
--
-- Desde la 0071 el cierre cuenta a quien entró, así que la hoja 1 dice
-- dos personas · $30.000, que es correcto. Y la hoja 2 tiene que seguir
-- diciendo $45.000 en ese renglón, porque es lo que dice el extracto y
-- es lo que se tacha. Lo que faltaba era la frase que une las dos: el
-- papel enseñaba un renglón de $45.000 con DOS nombres debajo y los
-- $15.000 restantes no se los explicaba a nadie.
--
-- Se añaden dos cosas a `conciliacion`, las dos informativas —ningún
-- total existente cambia de valor:
--
--   `banco[].no_vino`  los nombres de ese depósito que no entraron, para
--                      escribirlos debajo del renglón. Solo en la cabeza
--                      del grupo, igual que `cobros`, para no repetirlos
--                      cuando un pago llegó en dos transferencias.
--   `no_vino_cop`      cuánto de lo listado es de esa gente. Es el
--                      puente entre las dos hojas.
--
-- `no_vino_cop` cuenta SOLO a los que comparten depósito con alguien que
-- sí entró. Quien no vino y tenía su propio depósito no aparece en esta
-- hoja para nada —su depósito no respalda a nadie de hoy—, así que
-- restarlo aquí inventaría un descuadre nuevo.
--
-- Se parchea EN SITIO sobre la definición viva, no se reescribe la
-- función: producción trae arreglos que no están en este repo.

do $mig$
declare
  v_src   text;
  v_new   text;
  v_ancla text;
  v_rep   text;
begin
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';

  if v_src is null then
    raise exception '0072: no existe public.caja_del_dia';
  end if;

  if position('0072:' in v_src) > 0 then
    raise notice '0072: ya aplicado, no se toca';
    return;
  end if;

  if position('0071:' in v_src) = 0 then
    raise exception '0072: falta la 0071, que es la que separa a quien entro';
  end if;

  v_new := v_src;

  -- ── 1. el conjunto complementario de `suyas` ──────────────────────
  v_ancla :=
    E'       and r.no_vino_at is null and r.reprogramada_a is null\n' ||
    E'       and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia),\n' ||
    E'  -- Todo lo que se registro en la Caja hoy, no solo la clase suelta: la';
  if position(v_ancla in v_new) = 0 then
    raise exception '0072: no se encontro el suyas de v_concilia';
  end if;
  v_rep :=
    E'       and r.no_vino_at is null and r.reprogramada_a is null\n' ||
    E'       and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia),\n' ||
    E'  -- 0072: el complemento exacto de `suyas`. Los del dia que NO\n' ||
    E'  -- entraron pero cuyo deposito si respalda a alguien que si. Tres\n' ||
    E'  -- amigas transfieren 45.000 juntas y una no viene: el renglon del\n' ||
    E'  -- extracto sigue diciendo 45.000 —eso es lo que se tacha— pero\n' ||
    E'  -- solo entraron dos. Sin nombrar a la tercera, en el papel quedan\n' ||
    E'  -- 15.000 colgando y las dos hojas del mismo dia se contradicen.\n' ||
    E'  no_vinieron as (\n' ||
    E'    select r.id, r.nombre, r.pago_id, c.precio_cop\n' ||
    E'      from reservas r join clases c on c.id = r.clase_id\n' ||
    E'     where r.estado = ''confirmada'' and r.tipo = ''suelta''\n' ||
    E'       and (r.no_vino_at is not null or r.reprogramada_a is not null)\n' ||
    E'       and r.pago_id is not null\n' ||
    E'       and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia),\n' ||
    E'  -- Todo lo que se registro en la Caja hoy, no solo la clase suelta: la';
  v_new := replace(v_new, v_ancla, v_rep);

  -- ── 2. los nombres, debajo de su renglon del extracto ─────────────
  v_ancla :=
    E'                     and not exists (select 1 from suyas s2 where s2.pago_id = l.grupo)) end)\n' ||
    E'             order by l.fecha_pago)';
  if position(v_ancla in v_new) = 0 then
    raise exception '0072: no se encontro el cierre de la fila del banco';
  end if;
  v_rep :=
    E'                     and not exists (select 1 from suyas s2 where s2.pago_id = l.grupo)) end,\n' ||
    E'               -- 0072: quien pago dentro de este deposito y no\n' ||
    E'               -- entro. Solo en la cabeza del grupo, igual que\n' ||
    E'               -- `cobros`: un pago que llego en dos transferencias\n' ||
    E'               -- no puede nombrarla dos veces.\n' ||
    E'               ''no_vino'', case when l.es_parte then ''[]''::jsonb else\n' ||
    E'                 coalesce((select jsonb_agg(nv.nombre order by nv.nombre)\n' ||
    E'                             from no_vinieron nv where nv.pago_id = l.grupo),\n' ||
    E'                          ''[]''::jsonb) end)\n' ||
    E'             order by l.fecha_pago)';
  v_new := replace(v_new, v_ancla, v_rep);

  -- ── 3. el puente entre las dos hojas ──────────────────────────────
  v_ancla :=
    E'    ''banco_hoy_cop'', coalesce((select sum(l.valor_cop) from lineas l\n' ||
    E'       where (l.fecha_pago at time zone ''America/Bogota'')::date = v_dia), 0),';
  if position(v_ancla in v_new) = 0 then
    raise exception '0072: no se encontro banco_hoy_cop';
  end if;
  v_rep :=
    E'    ''banco_hoy_cop'', coalesce((select sum(l.valor_cop) from lineas l\n' ||
    E'       where (l.fecha_pago at time zone ''America/Bogota'')::date = v_dia), 0),\n' ||
    E'    -- 0072: cuanto de lo listado arriba es de gente que no entro.\n' ||
    E'    -- El extracto trae 45.000 y el cierre cuenta 30.000 porque una\n' ||
    E'    -- de las tres no vino: esta es esa diferencia, con nombre.\n' ||
    E'    -- Solo los que comparten deposito con alguien que si entro: el\n' ||
    E'    -- que no vino y tenia su propio deposito no sale en esta hoja\n' ||
    E'    -- para nada, y restarlo aqui inventaria un descuadre nuevo.\n' ||
    E'    ''no_vino_cop'', coalesce((select sum(nv.precio_cop) from no_vinieron nv\n' ||
    E'       where nv.pago_id in (select l.grupo from lineas l)), 0),';
  v_new := replace(v_new, v_ancla, v_rep);

  -- La marca de idempotencia, junto a la de la 0071.
  v_ancla := E'-- 0071: el cuadre cuenta a quien entro, no a quien pago.';
  if position(v_ancla in v_new) = 0 then
    raise exception '0072: no se encontro la marca de la 0071';
  end if;
  v_new := replace(v_new, v_ancla,
    E'-- 0071: el cuadre cuenta a quien entro, no a quien pago.\n' ||
    E'-- 0072: y el renglon del extracto dice quien de los suyos no vino.');

  execute v_new;
end
$mig$;
