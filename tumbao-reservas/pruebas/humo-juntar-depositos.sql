-- Humo de 0057: dos depositos que son un solo pago.
--
-- El caso de Genny, tal cual paso: consigno 85.000 por una "media
-- mensualidad" que no existe, recepcion le explico, y consigno 40.000
-- mas para completar los 125.000 de la mensualidad de verdad.
--
-- Lo que mas se cuida aqui es que juntar NO toque lo que reporto el
-- banco: el extracto dice dos transferencias y tiene que seguir
-- diciendo dos, aunque la caja las cobre como una.
\set ON_ERROR_STOP on
begin;

-- El token se guarda en plano en una temporal: en admin_tokens solo
-- queda el hash, y psql no interpola variables dentro de un bloque DO.
create temp table ctx (token text);
insert into ctx select crear_token_admin('cajera de prueba 0057')->>'token';
create or replace function tk() returns text language sql stable as $$ select token from ctx $$;

insert into pagos (id, banco, valor_cop, fecha_pago, referencia, remitente, ultimos_4, consumido)
values ('aaaa0057-0000-4000-8000-000000000001', 'bancolombia', 85000,
        now() - interval '3 hours', '1096803067', 'GENNY PAOLA GONZALEZ VEGA', '4619', false),
       ('aaaa0057-0000-4000-8000-000000000002', 'bancolombia', 40000,
        now() - interval '1 hour',  '1096803067', 'GENNY PAOLA GONZALEZ VEGA', '4619', false),
       -- Un tercero que va solo: tiene que seguir comportandose igual
       -- que siempre. Es la regresion que mas importa.
       ('aaaa0057-0000-4000-8000-000000000003', 'bancolombia', 15000,
        now() - interval '2 hours', '1096803067', 'OTRA PERSONA', '4619', false);

do $$
declare
  v_tok  text;
  v_r    jsonb;
  v_caja jsonb;
  v_n    int;
  v_cop  int;
  A constant uuid := 'aaaa0057-0000-4000-8000-000000000001';
  B constant uuid := 'aaaa0057-0000-4000-8000-000000000002';
  C constant uuid := 'aaaa0057-0000-4000-8000-000000000003';
begin
  v_tok := tk();

  -- ── antes de juntar: tres depositos sueltos ──────────────────────
  v_caja := caja_del_dia(v_tok, null);
  select count(*) into v_n from jsonb_array_elements(v_caja->'pagos_libres');
  if v_n <> 3 then raise exception 'esperaba 3 depositos sueltos, hay %', v_n; end if;
  raise notice '  v los tres depositos salen sueltos';

  -- ── juntar los dos de Genny ──────────────────────────────────────
  v_r := caja_fusionar_pagos(v_tok, array[A, B]);
  if not (v_r->>'ok')::bool then raise exception 'no dejo juntar: %', v_r; end if;
  if (v_r->>'pago_id')::uuid <> A then
    raise exception 'la cabeza deberia ser el mas viejo (85.000), fue %', v_r->>'pago_id';
  end if;
  if (v_r->>'total_cop')::int <> 125000 then
    raise exception 'el grupo deberia valer 125.000, vale %', v_r->>'total_cop';
  end if;
  raise notice '  v se juntan y el grupo vale 125.000, con el mas viejo de cabeza';

  -- ── EL ASSERT QUE IMPORTA: el banco no se toca ───────────────────
  v_caja := caja_del_dia(v_tok, null);
  if (v_caja->'banco'->>'recibido_cop')::int <> 140000 then
    raise exception 'juntar movio lo que reporto el banco: % (deberian ser 140.000)',
      v_caja->'banco'->>'recibido_cop';
  end if;
  raise notice '  v lo que reporto el banco sigue igual: 140.000 en tres transferencias';

  -- ── la lista ahora muestra el grupo como UNA cosa ────────────────
  select count(*) into v_n from jsonb_array_elements(v_caja->'pagos_libres');
  if v_n <> 2 then raise exception 'esperaba 2 filas (el grupo + el suelto), hay %', v_n; end if;
  raise notice '  v la lista pasa de tres filas a dos: el grupo cuenta como uno';

  select x->>'saldo_cop' into v_cop
    from jsonb_array_elements(v_caja->'pagos_libres') x
   where (x->>'id')::uuid = A;
  if v_cop <> 125000 then raise exception 'el grupo deberia mostrar 125.000, muestra %', v_cop; end if;

  select count(*) into v_n
    from jsonb_array_elements(v_caja->'pagos_libres') x,
         jsonb_array_elements(x->'partes') pt
   where (x->>'id')::uuid = A;
  if v_n <> 2 then raise exception 'el grupo deberia decir de que 2 partes se compone, dice %', v_n; end if;
  raise notice '  v y dice cuales son las dos transferencias que lo forman';

  -- El suelto no se contagio.
  select x->>'saldo_cop' into v_cop
    from jsonb_array_elements(v_caja->'pagos_libres') x
   where (x->>'id')::uuid = C;
  if v_cop <> 15000 then raise exception 'el deposito suelto cambio: %', v_cop; end if;
  raise notice '  v el deposito que va solo no se entero de nada';

  if (v_caja->'banco'->>'libre_cop')::int <> 140000 then
    raise exception 'sin dueno deberian seguir 140.000, dice %', v_caja->'banco'->>'libre_cop';
  end if;

  -- ── cobrarlo: UNA mensualidad de 125.000 ─────────────────────────
  v_r := caja_registrar(v_tok, 'ingreso', 'mensualidad', 125000, 'transferencia', null, A);
  if not (v_r->>'ok')::bool then raise exception 'no dejo cobrar el grupo: %', v_r; end if;
  raise notice '  v se cobra de una: 125.000 como mensualidad';

  -- Las dos partes quedan gastadas, cada una por lo suyo.
  select usado_cop into v_cop from pagos where id = A;
  if v_cop <> 85000 then raise exception 'a la cabeza deberian gastarle 85.000, le gastaron %', v_cop; end if;
  select usado_cop into v_cop from pagos where id = B;
  if v_cop <> 40000 then raise exception 'a la parte deberian gastarle 40.000, le gastaron %', v_cop; end if;
  raise notice '  v cada transferencia queda gastada por su propio valor: 85.000 y 40.000';

  -- Una sola linea en la caja, y con respaldo del banco.
  v_caja := caja_del_dia(v_tok, null);
  select count(*), coalesce(sum((x->>'valor_cop')::int), 0) into v_n, v_cop
    from jsonb_array_elements(v_caja->'movimientos') x
   where x->>'concepto' = 'mensualidad';
  if v_n <> 1 or v_cop <> 125000 then
    raise exception 'esperaba UNA linea de 125.000, hay % por %', v_n, v_cop;
  end if;
  raise notice '  v la tirilla ve una sola linea de 125.000, no dos';

  if (v_caja->'banco'->>'sin_respaldo_cop')::int <> 0 then
    raise exception 'el ingreso quedo sin respaldo del banco: %',
      v_caja->'banco'->>'sin_respaldo_cop';
  end if;
  raise notice '  v y queda enlazada al banco, no como ingreso suelto';

  -- Ya no queda nada del grupo por reclamar.
  select count(*) into v_n
    from jsonb_array_elements(v_caja->'pagos_libres') x
   where (x->>'id')::uuid in (A, B);
  if v_n <> 0 then raise exception 'el grupo cobrado sigue saliendo sin dueno'; end if;
  raise notice '  v el grupo cobrado desaparece de la lista de sin dueno';

  -- ── no se puede separar algo ya cobrado ──────────────────────────
  v_r := caja_separar_pago(v_tok, B);
  if (v_r->>'ok')::bool or v_r->>'error' <> 'GRUPO_YA_COBRADO' then
    raise exception 'dejo separar un grupo ya cobrado: %', v_r;
  end if;
  raise notice '  v no deja separar un grupo al que ya se le registro el ingreso';

  -- ── anular devuelve la plata a las dos partes ────────────────────
  perform caja_anular(v_tok, (select id from caja_movimientos
                               where concepto = 'mensualidad' and not anulado limit 1));
  select usado_cop into v_cop from pagos where id = A;
  if v_cop <> 0 then raise exception 'anular no le devolvio a la cabeza: %', v_cop; end if;
  select usado_cop into v_cop from pagos where id = B;
  if v_cop <> 0 then raise exception 'anular no le devolvio a la parte: %', v_cop; end if;
  raise notice '  v anular le devuelve a cada transferencia lo suyo';

  -- Pero siguen juntos: anular el cobro no deshace el grupo.
  if (select fusionado_en from pagos where id = B) is null then
    raise exception 'anular deshizo el grupo, y no deberia';
  end if;
  if not (select consumido from pagos where id = A) then
    raise exception 'la cabeza volvio a quedar libre para el cruce automatico';
  end if;
  raise notice '  v siguen juntos, y fuera del cruce automatico';

  -- ── ahora si se separan ──────────────────────────────────────────
  v_r := caja_separar_pago(v_tok, A);
  if not (v_r->>'ok')::bool then raise exception 'no dejo separar: %', v_r; end if;
  if (select count(*) from pagos where id in (A, B) and (fusionado_en is not null or consumido)) <> 0 then
    raise exception 'separar no los dejo libres del todo';
  end if;
  raise notice '  v separar los devuelve a estar solos y libres';

  -- ── los topes ────────────────────────────────────────────────────
  v_r := caja_fusionar_pagos(v_tok, array[A]);
  if (v_r->>'ok')::bool or v_r->>'error' <> 'FALTAN_DEPOSITOS' then
    raise exception 'dejo juntar uno solo: %', v_r;
  end if;

  v_r := caja_fusionar_pagos(v_tok, array[A, B]);
  v_r := caja_registrar(v_tok, 'ingreso', 'mensualidad', 126000, 'transferencia', null, A);
  if (v_r->>'ok')::bool or v_r->>'error' <> 'VALOR_NO_COINCIDE' then
    raise exception 'dejo cobrar mas de lo que tiene el grupo: %', v_r;
  end if;
  raise notice '  v no deja cobrarle al grupo mas de lo que tiene';

  -- Y un deposito ya adjudicado no se puede meter a un grupo.
  perform caja_registrar(v_tok, 'ingreso', 'clase_suelta', 15000, 'transferencia', null, C);
  v_r := caja_fusionar_pagos(v_tok, array[C, A]);
  if (v_r->>'ok')::bool then raise exception 'dejo juntar un deposito ya adjudicado: %', v_r; end if;
  raise notice '  v no deja juntar un deposito que ya tiene dueno';

  raise notice ' ';
  raise notice 'TODO EN VERDE';
end $$;

rollback;
