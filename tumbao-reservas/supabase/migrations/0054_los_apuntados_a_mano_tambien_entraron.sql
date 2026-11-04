-- ---------------------------------------------------------------------
-- 0054 — Quien se apunta a mano en recepción también entró
--
-- EL PROBLEMA
-- Entradas contaba tres cosas: lo pagado por la página, y lo que
-- recepción cobra en efectivo o por transferencia. Falta una cuarta, y
-- es gente de verdad: cuando alguien llega y en recepción lo apuntan
-- como clase suelta SIN registrar el cobro en Caja, esa persona no
-- aparece por ningún lado.
--
-- No es un caso raro. En el histórico hay 25 reservas de clase suelta
-- con origen 'recepcion' y 23 de ellas no tienen ni movimiento de caja
-- ni pago del banco: 23 personas, $345.000. Nombres reales, clases
-- reales, precio de $15.000, ninguna es de miembro ni está marcada para
-- cobrar en puerta. Entraron y su plata no está en la tirilla.
--
-- Por eso el conteo de Entradas nunca cuadraba con el cuaderno de la
-- puerta: al cuaderno esas personas sí entraron.
--
-- LO QUE HACE
-- Añade la cuarta casilla, `a_mano`. Cuenta las reservas de recepción
-- confirmadas de una clase de HOY que no tienen cobro en caja ni pago
-- del banco.
--
-- POR QUE EXIGE cobro_mov_id NULO
-- Para no contar dos veces. Cuando recepción sí registra el cobro, la
-- reserva queda ligada a su movimiento por `cobro_mov_id`, y ese
-- movimiento ya se cuenta en la casilla de efectivo o de transferencia.
-- Sumar también la reserva duplicaría a la misma persona.
--
-- ESTA CASILLA ES UN AVISO, NO UN INGRESO
-- Su plata no está en el cajón ni en el banco: es plata que debería
-- haberse registrado y no se registró. Cuenta para saber cuánta gente
-- entró y cuánto se debió cobrar, pero por eso mismo va en su propia
-- línea y no mezclada con las otras: si sale distinta de cero, hay algo
-- que corregir en Caja.
-- ---------------------------------------------------------------------
do $$
declare
  v_def text; v_a text; v_b text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if v_def is null then raise exception 'no existe caja_del_dia'; end if;
  if position('0053:' in v_def) = 0 then
    raise exception 'falta 0053';
  end if;
  if position('0054:' in v_def) > 0 then
    raise notice 'ya estaba aplicada'; return;
  end if;

  v_a := '  v_cuando_entro jsonb; v_por_verificar jsonb;';
  v_b := v_a || E'\n' || '  v_a_mano int; v_a_mano_n int;';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro la declaracion de v_cuando_entro exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  v_a := '             and (c3.fecha_hora at time zone ''America/Bogota'')::date = v_dia
           group by 1) t;';
  v_b := v_a || E'\n\n' ||
    '  -- 0054: quien se apunto a mano en recepcion y cuyo cobro no quedo' || E'\n' ||
    '  -- registrado en Caja. Entro igual, asi que cuenta. Se exige' || E'\n' ||
    '  -- cobro_mov_id nulo para no contarlo dos veces: si el cobro si se' || E'\n' ||
    '  -- registro, ese movimiento ya esta en las casillas de arriba.' || E'\n' ||
    '  select coalesce(sum(c4.precio_cop), 0), count(*)' || E'\n' ||
    '    into v_a_mano, v_a_mano_n' || E'\n' ||
    '    from reservas r4 join clases c4 on c4.id = r4.clase_id' || E'\n' ||
    '   where r4.estado = ''confirmada'' and r4.tipo = ''suelta''' || E'\n' ||
    '     and r4.origen = ''recepcion''' || E'\n' ||
    '     and r4.cobro_mov_id is null and r4.pago_id is null' || E'\n' ||
    '     and (c4.fecha_hora at time zone ''America/Bogota'')::date = v_dia;';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro la consulta de por_verificar exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  v_a := '      ''pagina_transferencia_n'',   v_entra_pag_tr_n';
  v_b := v_a || ',' || E'\n' ||
    '      ''a_mano_cop'', v_a_mano, ''a_mano_n'', v_a_mano_n';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro pagina_transferencia_n en la respuesta exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  execute v_def;
end $$;
