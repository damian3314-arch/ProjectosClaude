-- Humo de 0060: con qué depósito entró cada quien.
--
-- Es la tirilla que se cruza contra el extracto de Bancolombia, así que
-- lo que no puede fallar es que el papel sume lo MISMO que el banco.
--
-- El caso que lo puede romper es real y del 28 de agosto: Isabel Flórez
-- y Lizet Gutiérrez entraron con un solo depósito de $30.000, y lo mismo
-- Ludys Herazo y Yurley Egea. Si el papel listara por persona, sumaría
-- $60.000 donde el banco tiene una línea de $30.000 y el cuadre no
-- daría nunca.
--
-- Y lo segundo: tiene que listar exactamente a la misma gente que
-- cuenta la tirilla del cierre. Dos papeles del mismo día que no
-- coinciden es peor que un solo papel incompleto.
\set ON_ERROR_STOP on
set timezone = 'America/Bogota';

begin;

create temp table ctx (token text);
insert into ctx select crear_token_admin('cajera de prueba 0060')->>'token';
create or replace function tk() returns text language sql stable as $$ select token from ctx $$;

do $$
declare
  v_tok   text := tk();
  v_hoy   date := (now() at time zone 'America/Bogota')::date;
  v_c     uuid;
  v_d     jsonb;
  v_k     jsonb;
  v_juntas uuid;
  v_ayer   uuid;
  v_puerta2 uuid;
  v_n     int;
  v_lider uuid;
begin
  delete from asistencias where true;
  delete from caja_movimientos where true;
  delete from reservas where true;
  delete from pagos where true;
  delete from clases where true;

  insert into clases (id, nombre, profesor, fecha_hora, duracion_min,
                      cupo_total, precio_cop, lugar, activa, aforo)
  values (gen_random_uuid(), 'Clase 6:00 pm', 'Kevin',
          (v_hoy + time '18:00') at time zone 'America/Bogota',
          60, 30, 15000, 'Sede Tumbao', true, 30)
  returning id into v_c;

  -- ── EL CASO PELIGROSO: dos personas, un solo depósito ─────────────
  insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
  values (gen_random_uuid(), 'bancolombia', 30000,
          (v_hoy + time '11:29') at time zone 'America/Bogota',
          'ISABEL FLOREZ MARTINEZ', 'M07471046', true)
  returning id into v_juntas;

  insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, pago_id)
  values (gen_random_uuid(), 'JUN001', v_c, 'Isabel Florez', '3000000001',
          'confirmada', 'suelta', 'web', v_juntas)
  returning id into v_lider;
  insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo, origen, pago_id, grupo_id)
  values ('JUN002', v_c, 'Lizet Gutierrez', '3000000002',
          'confirmada', 'suelta', 'web', v_juntas, v_lider);

  -- ── Alguien que pagó ANTES de hoy: es el motivo de la tirilla ─────
  insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
  values (gen_random_uuid(), 'bancolombia', 15000,
          (v_hoy - 2 + time '09:10') at time zone 'America/Bogota',
          'CAMILA LOPEZ', 'M11112222', true)
  returning id into v_ayer;
  insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo, origen, pago_id)
  values ('ANT001', v_c, 'Camila Lopez', '3000000003',
          'confirmada', 'suelta', 'web', v_ayer);

  -- ── Efectivo en la puerta: no va a aparecer en el extracto ────────
  perform caja_registrar(v_tok, 'ingreso', 'clase_suelta', 15000, 'efectivo', null, null);

  -- ── DOS cobros en la puerta con UN solo depósito ──────────────────
  -- Lo permite la 0039: uno de $30.000 paga dos clases de $15.000. La
  -- línea del extracto es una y cubre a dos personas, ninguna con
  -- reserva a su nombre. Es el caso que hacía que contar cabezas sobre
  -- el papel diera distinto que la tirilla del cierre.
  insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
  values (gen_random_uuid(), 'bancolombia', 30000,
          (v_hoy + time '19:40') at time zone 'America/Bogota',
          'DOS AMIGAS JUNTAS', 'M99998888', false)
  returning id into v_puerta2;
  perform caja_registrar(v_tok, 'ingreso', 'clase_suelta', 15000, 'transferencia', null, v_puerta2);
  perform caja_registrar(v_tok, 'ingreso', 'clase_suelta', 15000, 'transferencia', null, v_puerta2);

  -- ── Una reprogramada: entró y no hay depósito que buscar ──────────
  insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo, origen)
  values ('REP001', v_c, 'Julieth Herrera', '3000000004',
          'confirmada', 'suelta', 'reprogramada');

  v_d := caja_del_dia(v_tok, v_hoy);
  v_k := v_d->'conciliacion';

  -- ── 1. una línea por depósito, no por persona ─────────────────────
  select count(*) into v_n from jsonb_array_elements(v_k->'banco');
  if v_n <> 3 then
    raise exception 'deberian ser 3 lineas de banco (compartido + viejo + puerta), son %', v_n;
  end if;
  raise notice '  v dos personas con un solo deposito son UNA linea, no dos';

  -- ── 2. y esa línea nombra a las dos ───────────────────────────────
  select count(*) into v_n
    from jsonb_array_elements(v_k->'banco') b,
         jsonb_array_elements_text(b->'para') q
   where (b->>'valor_cop')::int = 30000;
  if v_n <> 2 then
    raise exception 'la linea de 30.000 deberia nombrar a las dos, nombra %', v_n;
  end if;
  raise notice '  v y debajo dice a quienes cubre';

  -- ── 3. EL QUE IMPORTA: el papel suma lo mismo que el banco ────────
  if (v_k->>'banco_cop')::int <> 75000 then
    raise exception 'el papel deberia sumar 75.000 como el extracto, suma %',
      v_k->>'banco_cop';
  end if;
  raise notice '  v el total a buscar en el extracto es 75.000: una linea por deposito';

  -- ── 3b. la linea de la puerta dice que cubre a DOS ────────────────
  select (b->>'cobros')::int into v_n
    from jsonb_array_elements(v_k->'banco') b
   where b->>'remitente' = 'DOS AMIGAS JUNTAS';
  if v_n <> 2 then
    raise exception 'el deposito de la puerta deberia cubrir 2 cobros, dice %', v_n;
  end if;
  raise notice '  v un deposito que paga dos clases en la puerta dice que son dos';

  -- ── 4. el que pagó antes sale con cuántos días antes ──────────────
  select b->>'dias_antes' into v_n
    from jsonb_array_elements(v_k->'banco') b where (b->>'valor_cop')::int = 15000;
  if v_n <> 2 then
    raise exception 'el pago viejo deberia decir 2 dias antes, dice %', v_n;
  end if;
  raise notice '  v el que pago hace dos dias lo dice, para saber que pagina mirar';

  -- ── 5. el efectivo va aparte: nunca va a estar en el banco ────────
  if (v_k->>'efectivo_cop')::int <> 15000 then
    raise exception 'el efectivo deberia ir aparte por 15.000, va por %',
      v_k->>'efectivo_cop';
  end if;
  select count(*) into v_n from jsonb_array_elements(v_k->'banco') b
   where (b->>'valor_cop')::int = 15000 and (b->>'dias_antes')::int = 0;
  if v_n <> 0 then
    raise exception 'el efectivo se colo en lo que hay que buscar en el banco';
  end if;
  raise notice '  v el efectivo va aparte y NO se busca en el extracto';

  -- ── 6. la reprogramada sale como lo que hay que averiguar ─────────
  select count(*) into v_n from jsonb_array_elements(v_k->'sin_pago');
  if v_n <> 1 then
    raise exception 'deberia haber 1 sin deposito, hay %', v_n;
  end if;
  select count(*) into v_n from jsonb_array_elements(v_k->'sin_pago') x
   where x->>'nombre' = 'Julieth Herrera' and x->>'motivo' like 'reprogramada%';
  if v_n <> 1 then
    raise exception 'la reprogramada no dice por que no tiene deposito';
  end if;
  raise notice '  v quien entro sin deposito sale, y dice por que';

  -- ── 7. LAS DOS TIRILLAS HABLAN DE LA MISMA GENTE ──────────────────
  -- 7 personas: Isabel, Lizet, Camila, el del efectivo, las dos de la
  -- puerta que comparten deposito, y Julieth.
  -- Cada linea del banco cubre a los que nombra MAS los cobros en
  -- puerta que salieron de ese deposito. Sumado al efectivo y a los que
  -- entraron sin deposito tiene que dar exactamente personas_n.
  -- Del efectivo solo cuentan las clases sueltas: desde la 0062 esa
  -- seccion tambien trae mensualidades, y una mensualidad no es alguien
  -- entrando a una clase. Contarlas daba 12 contra 11.
  select (select coalesce(sum(jsonb_array_length(b->'para') + (b->>'cobros')::int), 0)
            from jsonb_array_elements(v_k->'banco') b)
       + (select count(*) from jsonb_array_elements(v_k->'efectivo') e
           where e->>'concepto' = 'clase_suelta')
       + (select count(*) from jsonb_array_elements(v_k->'sin_pago'))
    into v_n;
  if v_n <> (v_d->'entradas'->>'personas_n')::int then
    raise exception 'la tirilla del banco lista % y la del cierre cuenta %',
      v_n, v_d->'entradas'->>'personas_n';
  end if;
  raise notice '  v lista la misma gente que cuenta la tirilla del cierre (%)', v_n;

  -- ── 8. y el dinero tambien cuadra entre las dos ───────────────────
  if (v_k->>'banco_cop')::int + (v_k->>'efectivo_cop')::int <> 90000 then
    raise exception 'banco + efectivo deberian dar 90.000, dan %',
      (v_k->>'banco_cop')::int + (v_k->>'efectivo_cop')::int;
  end if;
  raise notice '  v banco + efectivo = lo que entro de clase suelta';

  raise notice ' ';
  raise notice 'clase suelta: todo en verde';
end $$;

-- =====================================================================
-- 0062: lo que se registra a mano en la Caja también hay que tacharlo
--
-- De los $580.000 que reportó el banco el 28 de agosto, $445.000 eran
-- mensualidades apuntadas a mano. La tirilla los dejaba fuera y lo
-- decía al pie, o sea que dejaba fuera la mayor parte del trabajo.
-- =====================================================================
do $$
declare
  v_tok  text := tk();
  v_hoy  date := (now() at time zone 'America/Bogota')::date;
  v_c    uuid;
  v_d    jsonb;
  v_k    jsonb;
  v_cab  uuid;
  v_part uuid;
  v_solo uuid;
  v_n    int;
begin
  delete from asistencias where true;
  delete from caja_movimientos where true;
  delete from reservas where true;
  delete from pagos where true;
  delete from clases where true;

  insert into clases (id, nombre, profesor, fecha_hora, duracion_min,
                      cupo_total, precio_cop, lugar, activa, aforo)
  values (gen_random_uuid(), 'Clase 6:00 pm', 'Kevin',
          (v_hoy + time '18:00') at time zone 'America/Bogota',
          60, 30, 15000, 'Sede Tumbao', true, 30)
  returning id into v_c;

  -- ── Una mensualidad normal, por transferencia ─────────────────────
  insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
  values (gen_random_uuid(), 'bancolombia', 125000,
          (v_hoy + time '17:12') at time zone 'America/Bogota',
          'MARTHA LUCIA NUNEZ MARIN', 'M55554444', false)
  returning id into v_solo;
  perform caja_registrar(v_tok, 'ingreso', 'mensualidad', 125000, 'transferencia', null, v_solo);

  -- ── EL CASO DIFÍCIL: una mensualidad pagada en DOS transferencias ─
  -- $85.000 y $40.000 juntados con la 0057. En la caja es UN ingreso de
  -- $125.000; en el extracto son DOS renglones. Si el papel enseñara
  -- solo la cabeza diria 85.000 donde la caja dice 125.000, y los
  -- 40.000 pareceria que nadie los reclamo.
  insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
  values (gen_random_uuid(), 'bancolombia', 85000,
          (v_hoy + time '09:39') at time zone 'America/Bogota',
          'GENNY PAOLA GONZALEZ VEGA', 'M11110000', false)
  returning id into v_cab;
  insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
  values (gen_random_uuid(), 'bancolombia', 40000,
          (v_hoy + time '17:45') at time zone 'America/Bogota',
          'GENNY PAOLA GONZALEZ VEGA', 'M11110001', false)
  returning id into v_part;
  perform caja_fusionar_pagos(v_tok, array[v_cab, v_part]);
  perform caja_registrar(v_tok, 'ingreso', 'mensualidad', 125000, 'transferencia', null, v_cab);

  -- ── Una mensualidad en efectivo: no va al banco ───────────────────
  perform caja_registrar(v_tok, 'ingreso', 'mensualidad', 125000, 'efectivo', null, null);

  -- ── Una camiseta por transferencia SIN enlazar depósito ───────────
  -- Hay que buscarla a mano en el extracto: no se sabe qué renglón es.
  perform caja_registrar(v_tok, 'ingreso', 'camiseta', 50000, 'transferencia', null, null);

  v_d := caja_del_dia(v_tok, v_hoy);
  v_k := v_d->'conciliacion';

  -- ── 1. las mensualidades ya salen ─────────────────────────────────
  select count(*) into v_n
    from jsonb_array_elements(v_k->'banco') b,
         jsonb_array_elements_text(b->'conceptos') q
   where q = 'mensualidad';
  if v_n < 1 then
    raise exception 'las mensualidades registradas a mano no salen en la tirilla';
  end if;
  raise notice '  v lo que se registra a mano en la Caja tambien sale';

  -- ── 2. EL QUE IMPORTA: el pago en dos partes son DOS renglones ────
  select count(*) into v_n from jsonb_array_elements(v_k->'banco') b
   where b->>'remitente' = 'GENNY PAOLA GONZALEZ VEGA';
  if v_n <> 2 then
    raise exception 'el pago en dos transferencias deberia dar 2 renglones, da %', v_n;
  end if;
  raise notice '  v un pago que llego en dos transferencias son DOS renglones';

  -- ── 3. y suman lo que de verdad dice el banco ─────────────────────
  select sum((b->>'valor_cop')::int) into v_n
    from jsonb_array_elements(v_k->'banco') b
   where b->>'remitente' = 'GENNY PAOLA GONZALEZ VEGA';
  if v_n <> 125000 then
    raise exception 'los dos renglones deberian sumar 125.000, suman %', v_n;
  end if;
  raise notice '  v y los dos juntos suman los 125.000 del ingreso';

  -- ── 4. la parte se marca, para que no parezca plata de mas ────────
  select count(*) into v_n from jsonb_array_elements(v_k->'banco') b
   where b->>'remitente' = 'GENNY PAOLA GONZALEZ VEGA' and (b->>'es_parte')::boolean;
  if v_n <> 1 then
    raise exception 'deberia haber 1 renglon marcado como parte, hay %', v_n;
  end if;
  raise notice '  v el segundo renglon se marca como parte del mismo pago';

  -- ── 5. el total a buscar es el del extracto ───────────────────────
  -- 125.000 (Martha) + 85.000 + 40.000 (Genny) = 250.000.
  if (v_k->>'banco_cop')::int <> 250000 then
    raise exception 'a buscar en el banco deberian ser 250.000, son %',
      v_k->>'banco_cop';
  end if;
  raise notice '  v el total a buscar en el extracto es 250.000';

  -- ── 6. el efectivo va aparte, con su concepto ─────────────────────
  if (v_k->>'efectivo_cop')::int <> 125000 then
    raise exception 'el efectivo deberia ser 125.000, es %', v_k->>'efectivo_cop';
  end if;
  select count(*) into v_n from jsonb_array_elements(v_k->'efectivo') x
   where x->>'concepto' = 'mensualidad';
  if v_n <> 1 then raise exception 'el efectivo no dice de que fue'; end if;
  raise notice '  v la mensualidad en efectivo va aparte y dice que es';

  -- ── 7. lo registrado sin enlazar se nombra ────────────────────────
  if (v_k->>'sin_enlazar_cop')::int <> 50000 then
    raise exception 'la camiseta sin enlazar deberia salir por 50.000, sale por %',
      v_k->>'sin_enlazar_cop';
  end if;
  raise notice '  v una transferencia sin deposito enlazado se nombra, para buscarla';

  -- ── 8. y NO se cuela en lo que se puede tachar ────────────────────
  select count(*) into v_n from jsonb_array_elements(v_k->'banco') b
   where (b->>'valor_cop')::int = 50000;
  if v_n <> 0 then
    raise exception 'la camiseta sin enlazar se colo en los renglones del banco';
  end if;
  raise notice '  v y no se cuela entre los renglones que si se pueden tachar';

  -- ── 9. una mensualidad NO cuenta como alguien que entro ───────────
  -- Aqui no entro nadie a clase: solo mensualidades y una camiseta. Si
  -- la conciliacion contara cada fila de efectivo como una persona,
  -- diria 1 donde el cierre dice 0.
  select (select coalesce(sum(jsonb_array_length(b->'para') + (b->>'cobros')::int), 0)
            from jsonb_array_elements(v_k->'banco') b)
       + (select count(*) from jsonb_array_elements(v_k->'efectivo') e
           where e->>'concepto' = 'clase_suelta')
       + (select count(*) from jsonb_array_elements(v_k->'sin_pago'))
    into v_n;
  if v_n <> (v_d->'entradas'->>'personas_n')::int then
    raise exception 'la conciliacion lista % personas y el cierre cuenta %',
      v_n, v_d->'entradas'->>'personas_n';
  end if;
  raise notice '  v una mensualidad no se cuenta como alguien que entro (%)', v_n;

  raise notice ' ';
  raise notice 'TODO EN VERDE';
end $$;

rollback;
