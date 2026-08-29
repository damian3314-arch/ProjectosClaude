-- Humo de 0059: cuanta GENTE entro a clase suelta.
--
-- El caso del 28 de agosto: el cierre decia 10 y en la puerta habian
-- entrado 11. Faltaba una persona que entro con el credito de una clase
-- que habia reprogramado. Sumar las cuatro casillas de dinero no sirve
-- para contar gente: hay al menos tres formas de entrar que no dejan
-- plata en ninguna casilla de ese dia.
--
-- Lo que se comprueba, una por una, es cada forma de colarse por un
-- hueco; y sobre todo que nadie se cuente DOS veces, que seria peor que
-- quedarse corto: haria vender puestos que no existen.
\set ON_ERROR_STOP on
set timezone = 'America/Bogota';

begin;

create temp table ctx (token text);
insert into ctx select crear_token_admin('cajera de prueba 0059')->>'token';
create or replace function tk() returns text language sql stable as $$ select token from ctx $$;

do $$
declare
  v_tok  text := tk();
  v_hoy  date := (now() at time zone 'America/Bogota')::date;
  v_c    uuid;
  v_d    jsonb;
  v_n    int;
  v_pago uuid;
  v_mov  uuid;
  v_vieja uuid;
  v_id   uuid;
  v_quien uuid;
begin
  select id into v_quien from admin_tokens order by creado_at desc limit 1;

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

  -- ── 1. la de siempre: reserva de la pagina con su deposito ────────
  insert into pagos (id, banco, valor_cop, fecha_pago, remitente, consumido)
  values (gen_random_uuid(), 'bancolombia', 15000, now(), 'PAGINA UNO', true)
  returning id into v_pago;
  insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo, origen, pago_id)
  values ('PAG001', v_c, 'De la pagina', '3000000001', 'confirmada', 'suelta', 'web', v_pago);

  v_d := caja_del_dia(v_tok, v_hoy);
  if (v_d->'entradas'->>'personas_n')::int <> 1 then
    raise exception 'la de la pagina deberia contar 1, cuenta %',
      v_d->'entradas'->>'personas_n';
  end if;
  raise notice '  v la reserva normal de la pagina cuenta 1';

  -- ── 2. la reprogramada: entra hoy, pero pago otro dia ─────────────
  -- Es la que faltaba el 28 de agosto. No tiene pago_id: su plata entro
  -- el dia de la reserva vieja.
  insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen)
  values (gen_random_uuid(), 'VIEJA1', v_c, 'Julieth', '3000000002',
          'confirmada', 'suelta', 'web')
  returning id into v_vieja;
  insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen)
  values (gen_random_uuid(), 'REPRO1', v_c, 'Julieth', '3000000002',
          'confirmada', 'suelta', 'reprogramada')
  returning id into v_id;
  update reservas set reprogramada_a = v_id where id = v_vieja;

  v_d := caja_del_dia(v_tok, v_hoy);
  if (v_d->'entradas'->>'personas_n')::int <> 2 then
    raise exception 'la reprogramada deberia contar (2 en total), cuenta %',
      v_d->'entradas'->>'personas_n';
  end if;
  raise notice '  v la que entra con una clase reprogramada SI cuenta';
  raise notice '  v y su reserva vieja, ya movida, no cuenta dos veces';

  -- ── 3. y no aporta plata: solo persona ────────────────────────────
  if (v_d->'entradas'->>'pagina_transferencia_cop')::int <> 15000 then
    raise exception 'la reprogramada metio plata que no era: %',
      v_d->'entradas'->>'pagina_transferencia_cop';
  end if;
  raise notice '  v la reprogramada suma persona pero cero pesos';

  -- ── 4. confirmada a mano, sin deposito enlazado ───────────────────
  -- No es de recepcion y no tiene pago_id: no cabia en ninguna casilla.
  insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo,
                        origen, resuelta_por)
  values ('AMANO1', v_c, 'Confirmada a dedo', '3000000003', 'confirmada',
          'suelta', 'formulario', v_quien);

  v_d := caja_del_dia(v_tok, v_hoy);
  if (v_d->'entradas'->>'personas_n')::int <> 3 then
    raise exception 'la confirmada a mano deberia contar (3), cuenta %',
      v_d->'entradas'->>'personas_n';
  end if;
  raise notice '  v la confirmada a mano sin deposito tambien cuenta';

  -- ── 5. el que llega y paga en la puerta, sin reserva ──────────────
  perform caja_registrar(v_tok, 'ingreso', 'clase_suelta', 15000, 'efectivo', null, null);
  v_d := caja_del_dia(v_tok, v_hoy);
  if (v_d->'entradas'->>'personas_n')::int <> 4 then
    raise exception 'el de la puerta deberia contar (4), cuenta %',
      v_d->'entradas'->>'personas_n';
  end if;
  raise notice '  v el que paga en la puerta sin reserva cuenta';

  -- ── 6. cobro anulado y vuelto a hacer: cuenta UNA vez ─────────────
  -- El caso de JENNY PAOLA del 20/08: se le anulo el cobro y se rehizo,
  -- y se caia por el hueco entre "a mano" y las casillas de caja.
  select id into v_mov from caja_movimientos
   where concepto = 'clase_suelta' and not anulado order by created_at desc limit 1;
  perform caja_anular(v_tok, v_mov);
  perform caja_registrar(v_tok, 'ingreso', 'clase_suelta', 15000, 'efectivo', null, null);

  v_d := caja_del_dia(v_tok, v_hoy);
  if (v_d->'entradas'->>'personas_n')::int <> 4 then
    raise exception 'anular y rehacer deberia dejarlo en 4, dejo %',
      v_d->'entradas'->>'personas_n';
  end if;
  raise notice '  v anular un cobro y rehacerlo no duplica ni pierde a nadie';

  -- ── 7. el cobro en puerta enlazado al deposito de una reserva ─────
  -- Es la MISMA persona: no puede contarse dos veces.
  perform caja_registrar(v_tok, 'ingreso', 'clase_suelta', 15000, 'transferencia',
                         null, v_pago);
  v_d := caja_del_dia(v_tok, v_hoy);
  if (v_d->'entradas'->>'personas_n')::int <> 4 then
    raise exception 'el cobro ligado a una reserva se conto aparte: %',
      v_d->'entradas'->>'personas_n';
  end if;
  raise notice '  v un cobro ligado al deposito de una reserva no se cuenta aparte';

  -- ── 8. una rechazada no entra ─────────────────────────────────────
  insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo, origen)
  values ('NOPE01', v_c, 'No vino', '3000000009', 'rechazada', 'suelta', 'web');
  v_d := caja_del_dia(v_tok, v_hoy);
  if (v_d->'entradas'->>'personas_n')::int <> 4 then
    raise exception 'una rechazada se colo: %', v_d->'entradas'->>'personas_n';
  end if;
  raise notice '  v una rechazada no cuenta';

  raise notice ' ';
  raise notice 'TODO EN VERDE';
end $$;

rollback;
