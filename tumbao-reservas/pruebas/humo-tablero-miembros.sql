-- ---------------------------------------------------------------------
-- El tablero no cobra a quien no paga
--
-- LO QUE MIDE
-- El sábado 22 la clase de las 8 tenía 19 confirmadas y el tablero decía
-- COBRADO 285.000. Doce de esas eran miembros: su plan las cubre y no
-- entregan un peso. Lo cobrado eran 105.000.
--
-- Se prueba sobre un sábado a propósito: entre semana el miembro no
-- reserva —su puesto ya sale del aforo— así que el error solo se ve el
-- día en que el afiliado SÍ aparta.
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on
set client_min_messages = notice;

do $$
declare
  v_token text;
  v_clase uuid;
  v_dia   date;
  v_t     jsonb;
  v_c     jsonb;
  i       int;
begin
  delete from admin_tokens;
  v_token := (crear_token_admin('Prueba tablero'))->>'token';

  -- Un sábado futuro, con el aforo partido como el de verdad.
  v_dia := (now() at time zone 'America/Bogota')::date + 7;
  v_dia := v_dia + ((6 - extract(isodow from v_dia)::int + 7) % 7);

  insert into clases (fecha_hora, nombre, profesor, aforo, cupo_total,
                      cupo_tomado, cupo_miembros, cupo_sueltas,
                      precio_cop, activa)
  values ((v_dia + time '08:00') at time zone 'America/Bogota',
          'Clase 8:00 am', 'Kevin', 30, 30, 0, 15, 15, 15000, true)
  returning id into v_clase;

  -- Doce miembros y siete sueltas, como ese sábado.
  for i in 1..12 loop
    insert into reservas (clase_id, codigo, nombre, telefono, tipo, estado,
                          origen, expira_en)
    values (v_clase, 'MI' || lpad(i::text, 4, '0'), 'Miembro ' || i,
            '30011100' || lpad(i::text, 2, '0'), 'miembro', 'confirmada',
            'formulario', now() + interval '1 hour');
  end loop;
  for i in 1..7 loop
    insert into reservas (clase_id, codigo, nombre, telefono, tipo, estado,
                          origen, expira_en)
    values (v_clase, 'SU' || lpad(i::text, 4, '0'), 'Suelta ' || i,
            '30022200' || lpad(i::text, 2, '0'), 'suelta', 'confirmada',
            'formulario', now() + interval '1 hour');
  end loop;
  update clases set cupo_tomado = 19 where id = v_clase;

  v_t := admin_tablero(v_token, v_dia);
  select e into v_c from jsonb_array_elements(v_t->'clases') e
   where e->>'clase_id' = v_clase::text;

  -- ═══ 1. El dinero es solo el de las sueltas ═══
  if (v_c->>'ingreso_cop')::int <> 105000 then
    raise exception 'el tablero dice % y lo cobrado son 105.000', v_c->>'ingreso_cop';
  end if;
  raise notice '  v cobrado = 105.000, no 285.000';

  -- ═══ 2. Se puede saber cuáles son plata y cuáles plan ═══
  -- Sin esto, "19 confirmadas" es un total ciego y la pantalla no puede
  -- decir la verdad aunque quiera.
  if (v_c->>'confirmadas')::int <> 19 then
    raise exception 'las confirmadas dejaron de contarse bien: %', v_c->>'confirmadas';
  end if;
  if (v_c->>'confirmadas_suelta')::int <> 7 then
    raise exception 'las sueltas confirmadas salen mal: %', v_c->>'confirmadas_suelta';
  end if;
  if (v_c->>'confirmadas_miembro')::int <> 12 then
    raise exception 'los miembros confirmados salen mal: %', v_c->>'confirmadas_miembro';
  end if;
  raise notice '  v 19 confirmadas = 7 sueltas + 12 con plan';

  -- ═══ 3. El reparto del sábado dice tomados y libres ═══
  if (v_c->'reparto'->>'miembros_tomados')::int <> 12
     or (v_c->'reparto'->>'miembros_libres')::int <> 3 then
    raise exception 'el lado de afiliados no cuadra: %', v_c->'reparto';
  end if;
  if (v_c->'reparto'->>'sueltas_tomadas')::int <> 7
     or (v_c->'reparto'->>'sueltas_libres')::int <> 8 then
    raise exception 'el lado de sueltas no cuadra: %', v_c->'reparto';
  end if;
  raise notice '  v el reparto: afiliados 12/15 (3 libres), sueltas 7/15 (8 libres)';

  -- ═══ 4. Y el resumen del día suma lo mismo ═══
  -- Es la cifra del mosaico de arriba, la que se mira de un vistazo.
  if (v_t->'resumen'->>'ingreso_cop')::int <> 105000 then
    raise exception 'el resumen del día dice %', v_t->'resumen'->>'ingreso_cop';
  end if;
  if (v_t->'resumen'->>'confirmadas_suelta')::int <> 7
     or (v_t->'resumen'->>'confirmadas_miembro')::int <> 12 then
    raise exception 'el resumen no parte las confirmadas: %', v_t->'resumen';
  end if;
  raise notice '  v el resumen del dia dice lo mismo';

  -- ═══ 5. Entre semana nada cambia ═══
  -- Ahí el miembro no reserva, así que todas las confirmadas son plata.
  -- Si esto se rompiera, el arreglo del sábado habría roto los otros
  -- cinco días.
  insert into clases (fecha_hora, nombre, profesor, aforo, cupo_total,
                      cupo_tomado, precio_cop, activa)
  values ((v_dia + 3 + time '18:00') at time zone 'America/Bogota',
          'Clase 6:00 pm', 'Kevin', 30, 20, 0, 15000, true)
  returning id into v_clase;
  for i in 1..4 loop
    insert into reservas (clase_id, codigo, nombre, telefono, tipo, estado,
                          origen, expira_en)
    values (v_clase, 'EN' || lpad(i::text, 4, '0'), 'Entre semana ' || i,
            '30033300' || lpad(i::text, 2, '0'), 'suelta', 'confirmada',
            'formulario', now() + interval '1 hour');
  end loop;

  v_t := admin_tablero(v_token, v_dia + 3);
  select e into v_c from jsonb_array_elements(v_t->'clases') e
   where e->>'clase_id' = v_clase::text;
  if (v_c->>'ingreso_cop')::int <> 60000 then
    raise exception 'entre semana el cobrado cambió: %', v_c->>'ingreso_cop';
  end if;
  if v_c->>'reparto' is not null and v_c->'reparto' <> 'null'::jsonb then
    raise exception 'entre semana no debería haber reparto: %', v_c->'reparto';
  end if;
  raise notice '  v entre semana sigue igual: 4 sueltas = 60.000, sin reparto';

  raise notice ' ';
  raise notice 'TODO EN VERDE';
end $$;
