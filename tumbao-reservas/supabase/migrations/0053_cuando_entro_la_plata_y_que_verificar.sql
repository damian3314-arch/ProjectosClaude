-- ---------------------------------------------------------------------
-- 0053 — Cuándo entró la plata, y qué hay que verificar a mano
--
-- EL PROBLEMA
-- El cuadre diario obliga a revisar todo. Tania cierra, imprime, y
-- después se sienta con el extracto de Bancolombia a buscar una por una
-- las reservas del día. Con quince personas eso son quince búsquedas, y
-- la mayoría sobran.
--
-- LO QUE HACE SOBRAR CASI TODAS
-- Una reserva de la página que se confirmó SOLA ya está cruzada con un
-- depósito: el cruce automático es la prueba de que la plata entró. No
-- hay nada que verificar ahí. Medido sobre la base entera: de las
-- reservas de clase suelta confirmadas, 164 las cruzó el banco solo y 39
-- las confirmó alguien a mano. Solo esas 39 necesitan ojo.
--
-- Y ni siquiera son 39 búsquedas. Un grupo que paga junto comparte la
-- referencia del depósito: el 27 de agosto tres personas distintas eran
-- UN solo deposito de $45.000. En el extracto se busca una línea, no
-- tres. Por eso se agrupa por referencia y no por persona.
--
-- LO QUE AÑADE
--   cuando_entro    De la plata de quienes entraron HOY, qué día la
--                   recibió el banco. Contesta "vino hoy pero pagó el
--                   lunes, ¿sí entró?" sin abrir el sistema, y dice en
--                   qué parte del extracto mirar.
--
--   por_verificar   Lo confirmado a mano, agrupado por referencia de
--                   depósito. Es la lista corta —y muchos días vacía—
--                   de lo único que hay que buscar.
--
-- LAS REPROGRAMADAS VAN MARCADAS, NO SUMADAS
-- Quien reprograma ya pagó otro día: aparece en la lista para que no
-- parezca que se perdió, pero con cero, porque no hay depósito nuevo que
-- buscar. Sumarlas mandaría a Tania a buscar plata que no existe.
--
-- POR QUE 'cuando_entro' SOLO MIRA LA PAGINA
-- Lo que cobra recepción se paga en el momento, así que su plata entró
-- hoy por definición y no hay nada que datar. Datar tiene sentido solo
-- donde el pago pudo ocurrir otro día.
-- ---------------------------------------------------------------------
do $$
declare
  v_def text;
  v_a   text;
  v_b   text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if v_def is null then
    raise exception 'no existe caja_del_dia';
  end if;
  if position('0052:' in v_def) = 0 then
    raise exception 'falta 0052: caja_del_dia todavia lee recepcion desde reservas';
  end if;
  if position('0053:' in v_def) > 0 then
    raise notice 'ya estaba aplicada';
    return;
  end if;

  -- 1. Las variables.
  v_a := '  v_entra_pag_tr    int; v_entra_pag_tr_n    int;';
  v_b := v_a || E'\n' ||
    '  v_cuando_entro jsonb; v_por_verificar jsonb;' || E'\n' ||
    '  v_verificar_cop int; v_verificar_n int;';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro la declaracion de v_entra_pag_tr exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  -- 2. Las consultas, justo despues de las de Entradas.
  v_a := '     and r.origen in (''web'', ''formulario'')
     and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia;';
  v_b := v_a || E'\n\n' ||
    '  -- 0053: de la plata de quienes entran HOY, que dia la recibio el' || E'\n' ||
    '  -- banco. Solo la de la pagina: lo de recepcion se cobra en el' || E'\n' ||
    '  -- momento, asi que no hay nada que datar.' || E'\n' ||
    '  select coalesce(jsonb_agg(jsonb_build_object(' || E'\n' ||
    '           ''dia'', t.d, ''dias_antes'', v_dia - t.d,' || E'\n' ||
    '           ''personas'', t.n, ''cop'', t.cop) order by t.d desc), ''[]''::jsonb)' || E'\n' ||
    '    into v_cuando_entro' || E'\n' ||
    '    from (select (p2.fecha_pago at time zone ''America/Bogota'')::date as d,' || E'\n' ||
    '                 count(*) as n, sum(c2.precio_cop) as cop' || E'\n' ||
    '            from reservas r2' || E'\n' ||
    '            join clases c2 on c2.id = r2.clase_id' || E'\n' ||
    '            join pagos  p2 on p2.id = r2.pago_id' || E'\n' ||
    '           where r2.estado = ''confirmada'' and r2.tipo = ''suelta''' || E'\n' ||
    '             and r2.resuelta_por is null' || E'\n' ||
    '             and r2.origen in (''web'', ''formulario'')' || E'\n' ||
    '             and (c2.fecha_hora at time zone ''America/Bogota'')::date = v_dia' || E'\n' ||
    '           group by 1) t;' || E'\n\n' ||
    '  -- 0053: lo confirmado a mano, agrupado por referencia de deposito.' || E'\n' ||
    '  -- Un grupo que paga junto es UNA linea del extracto, no tres. Las' || E'\n' ||
    '  -- reprogramadas van con cero: ya pagaron otro dia, no hay deposito' || E'\n' ||
    '  -- nuevo que buscar, pero se listan para que no parezcan perdidas.' || E'\n' ||
    '  select coalesce(jsonb_agg(jsonb_build_object(' || E'\n' ||
    '           ''referencia'', t.ref, ''personas'', t.n,' || E'\n' ||
    '           ''cop'', t.cop, ''sin_plata'', t.sin_plata) order by t.cop desc), ''[]''::jsonb),' || E'\n' ||
    '         coalesce(sum(t.cop), 0), coalesce(sum(t.n), 0)' || E'\n' ||
    '    into v_por_verificar, v_verificar_cop, v_verificar_n' || E'\n' ||
    '    from (select coalesce(nullif(btrim(r3.referencia_pago), ''''), ''(sin referencia)'') as ref,' || E'\n' ||
    '                 bool_and(r3.origen = ''reprogramada'') as sin_plata,' || E'\n' ||
    '                 count(*) as n,' || E'\n' ||
    '                 sum(case when r3.origen = ''reprogramada'' then 0' || E'\n' ||
    '                          else c3.precio_cop end) as cop' || E'\n' ||
    '            from reservas r3 join clases c3 on c3.id = r3.clase_id' || E'\n' ||
    '           where r3.estado = ''confirmada'' and r3.tipo = ''suelta''' || E'\n' ||
    '             and r3.resuelta_por is not null' || E'\n' ||
    '             and (c3.fecha_hora at time zone ''America/Bogota'')::date = v_dia' || E'\n' ||
    '           group by 1) t;';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro la consulta de pagina exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  -- 3. Sacarlas en la respuesta.
  v_a := '      ''pagina_transferencia_n'',   v_entra_pag_tr_n
    ),';
  v_b := v_a || E'\n' ||
    '    ''cuando_entro'', v_cuando_entro,' || E'\n' ||
    '    ''por_verificar'', jsonb_build_object(' || E'\n' ||
    '      ''lista'', v_por_verificar,' || E'\n' ||
    '      ''cop'', v_verificar_cop,' || E'\n' ||
    '      ''personas'', v_verificar_n' || E'\n' ||
    '    ),';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro pagina_transferencia_n en la respuesta exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  execute v_def;
end $$;
