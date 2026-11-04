-- ¿Cuántos de los que ocupan puesto se les acaba el plan ESE día?
--
-- Es un número con el que se toma una decisión de plata: "de los 27 de
-- las 6, 2 vencen hoy, así que me arriesgo a vender 2 sueltas de más".
-- Si miente hacia arriba, se venden puestos que sí estaban ocupados y
-- alguien se queda de pie.
--
-- Las dos cosas que no pueden fallar:
--
--   1. Nunca puede ser mayor que `con_plan`. Es un subconjunto, no otra
--      cuenta: si se calculara con otro criterio podrían contradecirse.
--   2. Tiene que ir contra la fecha DE LA CLASE, no contra hoy. El
--      tablero se mueve día a día.
--
--   psql -d tumbao -f pruebas/humo-vencen.sql

\set ON_ERROR_STOP on
set timezone = 'America/Bogota';

do $$
declare
  v_tok text; v_lun date; v_mar date; v_sab date;
  v_c18 uuid; v_csab uuid;
  v_t jsonb; v_c jsonb; v_l jsonb;
begin
  delete from asistencias where true;
  delete from reservas where true;
  delete from pagos where true;
  delete from membresias where true;
  delete from clases where true;
  delete from admin_tokens where true;
  perform generar_horario(current_date, current_date + 13);

  v_tok := (crear_token_admin('humo de vencimientos'))->>'token';

  select (fecha_hora at time zone 'America/Bogota')::date into v_lun
    from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') between 1 and 5
     and fecha_hora > now()
   order by fecha_hora limit 1;
  -- Otro día entre semana, para comprobar que el número se mueve al
  -- cambiar de día en el tablero.
  select (fecha_hora at time zone 'America/Bogota')::date into v_mar
    from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') between 1 and 5
     and (fecha_hora at time zone 'America/Bogota')::date > v_lun
   order by fecha_hora limit 1;
  select (fecha_hora at time zone 'America/Bogota')::date into v_sab
    from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') = 6
     and fecha_hora > now()
   order by fecha_hora limit 1;

  -- 10 con plan de 6pm: 3 se les acaba el primer día, 2 el segundo,
  -- y 5 siguen vivas todo el mes.
  perform importar_membresias((
    select jsonb_agg(f) from (
      select jsonb_build_object(
        'afiliado', 'Socia ' || g, 'membresia', 'PLAN MENSUALIDAD 6:00PM',
        'hora', '18:00:00', 'tipo', 'plan',
        'documento', (700000 + g)::text, 'celular', '300' || lpad(g::text, 7, '0'),
        'correo', null,
        'inicio', (current_date - 20)::text,
        'fin', case when g <= 3 then v_lun::text
                    when g <= 5 then v_mar::text
                    else (current_date + 25)::text end) as f
      from generate_series(1, 10) g
    ) s));

  select id into v_c18 from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_lun
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 18;

  -- ── 1. el número sale, y es el que se puso ─────────────────
  v_t := admin_tablero(v_tok, v_lun);
  select c into v_c from jsonb_array_elements(v_t->'clases') c where c->>'hora' = '18:00';
  if (v_c->>'con_plan')::int <> 10 then
    raise exception 'deberian ser 10 con plan, son %', v_c->>'con_plan';
  end if;
  if (v_c->>'vencen')::int <> 3 then
    raise exception 'ese dia vencen 3, dice %', v_c->>'vencen';
  end if;
  raise notice '1. primer dia: 10 con plan, 3 vencen';

  -- ── 2. no toca el cupo. Es informacion, no una venta ───────
  -- Si se sumara solo, la sala se llenaria sin que nadie lo decidiera.
  if (v_c->>'a_la_venta')::int <> 20 then
    raise exception 'a la venta deberian ser 30-10=20, son %', v_c->>'a_la_venta';
  end if;
  raise notice '2. no se suma al cupo: sigue en 20 a la venta';

  -- ── 3. al mover el día, cambia el número ───────────────────
  v_t := admin_tablero(v_tok, v_mar);
  select c into v_c from jsonb_array_elements(v_t->'clases') c where c->>'hora' = '18:00';
  -- El segundo dia las 3 primeras ya vencieron: quedan 7 con plan y de
  -- esas 2 se acaban ese dia.
  if (v_c->>'con_plan')::int <> 7 then
    raise exception 'el segundo dia deberian quedar 7 con plan, hay %', v_c->>'con_plan';
  end if;
  if (v_c->>'vencen')::int <> 2 then
    raise exception 'el segundo dia vencen 2, dice %', v_c->>'vencen';
  end if;
  raise notice '3. al cambiar de dia el numero cambia: 7 con plan, 2 vencen';

  -- ── 4. NUNCA mayor que con_plan, en toda la quincena ───────
  -- Esta es la que de verdad protege: si el filtro se desalineara del
  -- de recalcular_cupos, aqui se veria.
  for v_c in
    select c from generate_series(0, 13) g,
         lateral jsonb_array_elements(
           (admin_tablero(v_tok, current_date + g))->'clases') c
  loop
    if (v_c->>'vencen')::int > (v_c->>'con_plan')::int then
      raise exception 'vencen (%) mayor que con_plan (%) en la clase de las %',
        v_c->>'vencen', v_c->>'con_plan', v_c->>'hora';
    end if;
    if (v_c->>'vencen')::int < 0 then
      raise exception 'vencen salio negativo';
    end if;
  end loop;
  raise notice '4. en 14 dias, nunca sale mayor que con_plan';

  -- ── 5. el sabado no tiene planes de esa hora ───────────────
  select id into v_csab from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_sab
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 8;
  v_t := admin_tablero(v_tok, v_sab);
  select c into v_c from jsonb_array_elements(v_t->'clases') c where c->>'hora' = '08:00';
  if (v_c->>'vencen')::int <> 0 then
    raise exception 'el sabado nadie tiene plan de esa hora, dice % vencen',
      v_c->>'vencen';
  end if;
  raise notice '5. sabado: 0 vencen, porque nadie tiene plan de esa hora';

  -- ── 6. el resumen suma lo mismo que las tarjetas ───────────
  v_t := admin_tablero(v_tok, v_lun);
  if (v_t->'resumen'->>'vencen')::int
     <> (select sum((c->>'vencen')::int) from jsonb_array_elements(v_t->'clases') c) then
    raise exception 'el resumen no cuadra con la suma de las tarjetas';
  end if;
  raise notice '6. el resumen cuadra con las tarjetas';

  -- ── 7. y en la puerta, marcada persona por persona ─────────
  v_l := admin_lista_clase(v_tok, v_c18);
  if (v_l->'resumen'->>'vencen')::int <> 3 then
    raise exception 'la lista de la puerta deberia marcar 3 que vencen, marca %',
      v_l->'resumen'->>'vencen';
  end if;
  if (select count(*) from jsonb_array_elements(v_l->'con_plan') e
       where (e->>'vence_hoy')::boolean) <> 3 then
    raise exception 'no marco a las 3 personas que vencen';
  end if;
  raise notice '7. la lista de la puerta marca a las 3, una por una';
end $$;

select 'TODO EN VERDE' as resultado;
