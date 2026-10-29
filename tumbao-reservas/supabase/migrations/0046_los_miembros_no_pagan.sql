-- ---------------------------------------------------------------------
-- 0046 — Los miembros no pagan la clase, y el tablero decía que sí
--
-- LO QUE PASÓ EL SÁBADO 22
-- La clase de las 8 am tenía 19 reservas confirmadas y el tablero decía
-- COBRADO $285.000. Lo cobrado eran $105.000.
--
-- De esas 19: doce eran de MIEMBROS —su plan las cubre, no pagan nada— y
-- siete eran clases sueltas pagadas a 15.000. El tablero multiplicaba
-- las 19 por el precio:
--
--     'ingreso_cop', n.confirmadas * c.precio_cop
--
-- y `confirmadas` cuenta a todo el mundo. O sea que inventaba $180.000
-- que nadie entregó, justo en la cifra que se mira para saber cuánto
-- entró.
--
-- POR QUÉ SE VE SOBRE TODO EL SÁBADO
-- Entre semana el miembro no reserva: su puesto ya sale del aforo y
-- entra sin pasar por aquí. El sábado el aforo va partido —15 para
-- afiliados y 15 para sueltas— y el afiliado SÍ reserva, para apartar su
-- mitad. Así que el sábado es el día en que el tablero se llena de
-- reservas que no son plata.
--
-- LO QUE HACE
--   · `ingreso_cop` cuenta solo las sueltas confirmadas.
--   · Se parten las confirmadas en `confirmadas_suelta` y
--     `confirmadas_miembro`, para que la pantalla pueda decir cuáles son
--     plata y cuáles son plan, en vez de dar un total ciego.
--
-- Se parchea sobre pg_get_functiondef en vez de reescribir la función:
-- es larga, y reescribir de memoria ya salió mal en este proyecto.
-- ---------------------------------------------------------------------
do $$
declare
  v_def text;
  v_a   text;
  v_b   text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_tablero';
  if v_def is null then
    raise exception 'no existe admin_tablero';
  end if;
  if position('confirmadas_suelta' in v_def) > 0 then
    raise notice 'ya estaba aplicada';
    return;
  end if;

  -- 1. El dinero: solo las sueltas.
  v_a := '''ingreso_cop'', n.confirmadas * c.precio_cop,';
  v_b := '''ingreso_cop'', n.confirmadas_suelta * c.precio_cop,'          || E'\n' ||
         '      -- Partidas a proposito: un total ciego de "19 confirmadas"' || E'\n' ||
         '      -- no deja ver que doce de esas no son plata sino plan.'  || E'\n' ||
         '      ''confirmadas_suelta'',  n.confirmadas_suelta,'           || E'\n' ||
         '      ''confirmadas_miembro'', n.confirmadas_miembro,';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro ingreso_cop exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  -- 2. Las dos cuentas nuevas.
  v_a := 'count(*) filter (where r.estado = ''confirmada'')::int            as confirmadas,';
  v_b := v_a || E'\n' ||
         '        count(*) filter (where r.estado = ''confirmada'''         || E'\n' ||
         '                           and r.tipo = ''suelta'')::int          as confirmadas_suelta,' || E'\n' ||
         '        count(*) filter (where r.estado = ''confirmada'''         || E'\n' ||
         '                           and r.tipo = ''miembro'')::int         as confirmadas_miembro,';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro el contador de confirmadas exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  -- 3. Que el resumen del dia tambien las sume.
  v_a := '''confirmadas'', coalesce((select sum((c->>''confirmadas'')::int) from jsonb_array_elements(v_clases) c), 0),';
  v_b := v_a || E'\n' ||
         '      ''confirmadas_suelta'',  coalesce((select sum((c->>''confirmadas_suelta'')::int)  from jsonb_array_elements(v_clases) c), 0),' || E'\n' ||
         '      ''confirmadas_miembro'', coalesce((select sum((c->>''confirmadas_miembro'')::int) from jsonb_array_elements(v_clases) c), 0),';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro confirmadas en el resumen exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  execute v_def;
end $$;
