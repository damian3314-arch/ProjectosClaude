-- Prueba del aviso de pago (0013).
--
-- El caso que de verdad importa: **paga otra persona**. Ahí el nombre del
-- banco no es el de quien reserva, así que si hay dos esperando el mismo
-- monto el nombre no desempata nada. Lo único que las separa es la hora
-- que cada una declaró.
--
--   psql -d tumbao -f pruebas/humo-aviso-pago.sql

\set ON_ERROR_STOP on
set timezone = 'America/Bogota';

do $$
declare
  v_clase uuid;
  v_a jsonb; v_b jsonb; v_r jsonb;
  v_estado text;
  v_t timestamptz;
begin
  delete from reservas where true;
  delete from pagos where true;
  delete from clases where true;
  perform generar_horario(current_date, current_date + 6);

  select id into v_clase from clases where fecha_hora > now() order by fecha_hora limit 1;

  -- ── el aviso guarda lo que declara quien paga ──────────────
  select tomar_cupo(v_clase, 'Camila Rojas', '3001110001', null, 'web', 'suelta') into v_a;
  v_t := now() - interval '3 minutes';
  select registrar_aviso_pago(v_a->>'codigo', v_t, 'M25418019', 'Marta Rojas', 'QR123') into v_r;
  if (v_r->>'ok')::boolean is not true then raise exception 'el aviso fallo: %', v_r; end if;

  select estado::text into v_estado from reservas where codigo = v_a->>'codigo';
  if v_estado <> 'verificando' then raise exception 'quedo en % y no en verificando', v_estado; end if;
  if not exists (select 1 from reservas
                  where codigo = v_a->>'codigo'
                    and pagador_nombre = 'Marta Rojas'
                    and referencia_pago = 'M25418019'
                    and pagado_en = v_t) then
    raise exception 'no guardo lo declarado';
  end if;
  raise notice 'aviso: guarda hora, pagador y referencia';

  -- ── el mismo comprobante no sirve dos veces ────────────────
  select tomar_cupo(v_clase, 'Otro Vivo', '3001110002', null, 'web', 'suelta') into v_b;
  select registrar_aviso_pago(v_b->>'codigo', now(), 'M25418019', null, null) into v_r;
  if (v_r->>'error') <> 'referencia_repetida' then
    raise exception 'dejo reusar el mismo comprobante: %', v_r;
  end if;
  raise notice 'referencia repetida: se rechaza';

  -- ── EL CASO: paga otra persona, y hay dos esperando ────────
  -- Las dos pagaron $15.000. Ninguna transfirio a su propio nombre. Lo
  -- unico distinto es la hora que declararon.
  delete from reservas where true;
  delete from pagos where true;
  update clases set cupo_tomado = 0 where true;

  select tomar_cupo(v_clase, 'Camila Rojas',  '3001110001', null, 'web', 'suelta') into v_a;
  select tomar_cupo(v_clase, 'Daniela Nieto', '3001110002', null, 'web', 'suelta') into v_b;

  perform registrar_aviso_pago(v_a->>'codigo', now() - interval '40 minutes',
                               null, 'Marta Rojas', null);
  perform registrar_aviso_pago(v_b->>'codigo', now() - interval '5 minutes',
                               null, 'Pedro Nieto', null);

  -- Llega el pago de Marta, la mama de Camila, a la hora que Camila dijo.
  select registrar_pago_y_conciliar('Bancolombia', 15000,
    now() - interval '39 minutes', 'REF-A', 'MARTA ROJAS', null, 1.0, null, null) into v_r;

  if (v_r->>'accion') <> 'reserva_confirmada' then
    raise exception 'no confirmo con paga-otro y dos candidatos: %', v_r;
  end if;
  if (v_r->>'codigo') <> (v_a->>'codigo') then
    raise exception 'confirmo la reserva equivocada: % en vez de %',
      v_r->>'codigo', v_a->>'codigo';
  end if;
  select estado::text into v_estado from reservas where codigo = v_b->>'codigo';
  if v_estado = 'confirmada' then raise exception 'confirmo tambien a la otra'; end if;
  raise notice 'paga otra persona con dos esperando: acerto por la hora (%)', v_r->>'metodo';

  -- Y el de Pedro cae en la otra, no en la ya confirmada.
  select registrar_pago_y_conciliar('Bancolombia', 15000,
    now() - interval '4 minutes', 'REF-B', 'PEDRO NIETO', null, 1.0, null, null) into v_r;
  if (v_r->>'codigo') <> (v_b->>'codigo') then
    raise exception 'el segundo pago no cayo donde debia: %', v_r;
  end if;
  raise notice 'el segundo pago cae en la otra reserva';

  -- ── un pago fuera de la ventana no se cuela ────────────────
  delete from reservas where true;
  delete from pagos where true;
  update clases set cupo_tomado = 0 where true;

  select tomar_cupo(v_clase, 'Sola Solita', '3001110003', null, 'web', 'suelta') into v_a;
  perform registrar_aviso_pago(v_a->>'codigo', now() - interval '2 hours', null, null, null);
  select registrar_pago_y_conciliar('Bancolombia', 15000, now(), 'REF-C',
    'SOLA SOLITA', null, 1.0, null, null) into v_r;
  if (v_r->>'accion') <> 'sin_reserva_que_casar' then
    raise exception 'confirmo un pago a 2 horas de la hora declarada: %', v_r;
  end if;
  raise notice 'pago lejos de la hora declarada: no se cuela aunque el nombre calce';

  -- ── sin hora declarada sigue funcionando la ventana vieja ──
  delete from reservas where true;
  delete from pagos where true;
  update clases set cupo_tomado = 0 where true;

  select tomar_cupo(v_clase, 'Sin Hora', '3001110004', null, 'web', 'suelta') into v_a;
  update reservas set estado = 'verificando' where codigo = v_a->>'codigo';
  select registrar_pago_y_conciliar('Bancolombia', 15000, now() + interval '90 minutes',
    'REF-D', 'SIN HORA', null, 1.0, null, null) into v_r;
  if (v_r->>'accion') <> 'reserva_confirmada' then
    raise exception 'sin hora declarada deberia usar la ventana vieja: %', v_r;
  end if;
  raise notice 'sin hora declarada: sigue valiendo la ventana de 3 horas';
end $$;

-- ── la cola de validacion muestra lo declarado ────────────────
do $$
declare
  v_clase uuid; v_a jsonb; v_r jsonb; v_tok text; v_e jsonb;
begin
  delete from reservas where true;
  delete from pagos where true;
  update clases set cupo_tomado = 0 where true;
  delete from admin_tokens where true;
  select (crear_token_admin('Prueba')->>'token') into v_tok;

  select id into v_clase from clases where fecha_hora > now() order by fecha_hora limit 1;
  select tomar_cupo(v_clase, 'Camila Rojas', '3001110001', null, 'web', 'suelta') into v_a;
  perform registrar_aviso_pago(v_a->>'codigo', now() - interval '10 minutes',
                               'M99', 'Marta Rojas', null);
  update reservas set estado = 'pendiente_validacion' where codigo = v_a->>'codigo';

  perform registrar_pago_y_conciliar('Bancolombia', 15000, now() - interval '9 minutes',
    'REF-X', 'MARTA ROJAS', null, 0.5, null, null);

  select admin_pendientes(v_tok) into v_r;
  v_e := v_r->'reservas'->0;
  if v_e->>'pagador' <> 'Marta Rojas' then raise exception 'no muestra quien pago: %', v_e; end if;
  if v_e->>'referencia' <> 'M99' then raise exception 'no muestra la referencia'; end if;
  if v_e->'pagos_sueltos'->0->>'minutos' is null then
    raise exception 'no calcula los minutos de diferencia';
  end if;
  if (v_e->'pagos_sueltos'->0->>'parecido')::numeric < 0.5 then
    raise exception 'el parecido deberia medirse contra quien paga, dio %',
      v_e->'pagos_sueltos'->0->>'parecido';
  end if;
  raise notice 'cola: muestra pagador, referencia, minutos (%) y parecido (%)',
    v_e->'pagos_sueltos'->0->>'minutos', v_e->'pagos_sueltos'->0->>'parecido';
end $$;

select 'TODO EN VERDE' as resultado;
