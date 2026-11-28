-- ---------------------------------------------------------------------
-- Apuntar a mano diciendo cómo pagó
--
-- LO QUE MIDE
-- Que la plata que se recibe en la puerta llegue al cajón sin depender
-- de que alguien se acuerde de un segundo paso. El 19 de agosto se
-- apuntaron dos personas en efectivo y solo una de las dos apareció en
-- la caja.
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on
set client_min_messages = notice;

do $$
declare
  v_token   text;
  v_clase   uuid;
  v_r       jsonb;
  v_dia     jsonb;
  v_ef0     int;
  v_ef1     int;
  v_esp0    int;
  v_esp1    int;
  v_movs    int;
  v_mano_n  int;
begin
  -- Un admin y una clase con cupo, en el futuro.
  delete from admin_tokens;
  v_token := (crear_token_admin('Prueba caja'))->>'token';

  insert into clases (fecha_hora, nombre, profesor, aforo, cupo_total,
                     cupo_tomado, precio_cop, activa)
  values (now() + interval '3 hours', 'Clase de prueba', 'Kevin',
          30, 30, 0, 15000, true)
  returning id into v_clase;

  -- ── de dónde partimos ──
  v_dia  := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  v_ef0  := (v_dia->>'ingreso_efectivo')::int;
  v_esp0 := (v_dia->>'esperado_efectivo')::int;

  -- ═══ 1. En efectivo: la plata TIENE que llegar al cajón ═══
  v_r := admin_crear_reserva(v_token, v_clase, 'Ana Efectivo', '3001112233',
                             'suelta', null, 'efectivo');
  if (v_r->>'ok')::boolean is not true then
    raise exception 'la reserva en efectivo no se creó: %', v_r;
  end if;
  if (v_r->>'efectivo_registrado') <> 'true' then
    raise exception 'el efectivo no quedó registrado: %', v_r;
  end if;

  v_dia  := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  v_ef1  := (v_dia->>'ingreso_efectivo')::int;
  v_esp1 := (v_dia->>'esperado_efectivo')::int;

  if v_ef1 - v_ef0 <> 15000 then
    raise exception 'el cajón no subió 15.000: antes % ahora %', v_ef0, v_ef1;
  end if;
  -- Esto es lo que de verdad importa: lo que el cierre va a decir que
  -- DEBERÍA haber en el cajón. Si no sube, el arqueo sale con
  -- diferencia y nadie sabe por qué.
  if v_esp1 - v_esp0 <> 15000 then
    raise exception 'lo esperado en el cajón no subió 15.000: antes % ahora %',
      v_esp0, v_esp1;
  end if;
  raise notice '  v en efectivo, el cajón sube 15.000 y lo esperado también';

  -- El movimiento tiene que poder rastrearse hasta la reserva: sin eso,
  -- al cuadrar aparece un ingreso suelto que nadie sabe de dónde salió.
  select count(*) into v_movs
    from caja_movimientos
   where dia = (now() at time zone 'America/Bogota')::date
     and medio = 'efectivo' and concepto = 'clase_suelta'
     and nota like '%' || (v_r->>'codigo') || '%';
  if v_movs <> 1 then
    raise exception 'el movimiento no menciona el código de la reserva (encontrados %)', v_movs;
  end if;
  raise notice '  v el movimiento dice de qué reserva es';

  -- ═══ 2. Por transferencia: NO toca el cajón ═══
  v_ef0 := v_ef1;
  v_r := admin_crear_reserva(v_token, v_clase, 'Beto Transfer', '3002223344',
                             'suelta', null, 'transferencia');
  if (v_r->>'ok')::boolean is not true then
    raise exception 'la reserva por transferencia no se creó: %', v_r;
  end if;
  if v_r->>'efectivo_registrado' is not null then
    raise exception 'una transferencia no debería tocar el efectivo: %', v_r;
  end if;

  v_dia := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  if (v_dia->>'ingreso_efectivo')::int <> v_ef0 then
    raise exception 'una transferencia movió el cajón: antes % ahora %',
      v_ef0, (v_dia->>'ingreso_efectivo')::int;
  end if;
  raise notice '  v por transferencia el cajón no se mueve';

  -- ═══ 3. Sin decir el medio: como antes, no toca el cajón ═══
  -- Es el hueco de compatibilidad mientras se despliega el panel. Tiene
  -- que comportarse como el día anterior, ni mejor ni peor.
  v_r := admin_crear_reserva(v_token, v_clase, 'Caro Sinmedio', '3003334455',
                             'suelta', null, null);
  if (v_r->>'ok')::boolean is not true then
    raise exception 'sin medio no se creó: %', v_r;
  end if;
  v_dia := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  if (v_dia->>'ingreso_efectivo')::int <> v_ef0 then
    raise exception 'sin medio se movió el cajón';
  end if;
  raise notice '  v sin medio se comporta como antes';

  -- ═══ 4. Un medio mal escrito no toma el cupo ═══
  -- Si validara después de tomar_cupo, quedaría un cupo ocupado con la
  -- plata sin registrar: el peor de los estados.
  v_r := admin_crear_reserva(v_token, v_clase, 'Dani Malmedio', '3004445566',
                             'suelta', null, 'tarjeta');
  if (v_r->>'ok')::boolean is not false or v_r->>'error' <> 'MEDIO_INVALIDO' then
    raise exception 'un medio inventado debería rechazarse: %', v_r;
  end if;
  if exists (select 1 from reservas where nombre = 'Dani Malmedio') then
    raise exception 'se creó la reserva con un medio inválido';
  end if;
  raise notice '  v un medio inventado no crea reserva ni toma cupo';

  -- ═══ 5. Un miembro no genera ingreso aunque digan efectivo ═══
  -- Quien tiene plan no paga en la puerta. Registrar un ingreso sería
  -- inventarse plata que nadie entregó.
  insert into membresias (afiliado, membresia, hora, tipo, inicio, fin, celular)
  -- La hora se compara contra la de Bogotá, no contra la del servidor.
  -- Con ::time a secas salían cinco horas de diferencia y el miembro
  -- caía en OTRO_HORARIO, así que esta comprobación no se ejecutaba.
  values ('Eva Miembro', 'Plan mensual',
          ((now() + interval '3 hours') at time zone 'America/Bogota')::time,
          'plan', current_date - 1, current_date + 30, '3005556677');
  v_ef0 := (caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date)
            ->>'ingreso_efectivo')::int;
  v_r := admin_crear_reserva(v_token, v_clase, 'Eva Miembro', '3005556677',
                             'miembro', null, 'efectivo');
  -- Pase lo que pase con la reserva, lo que NO puede pasar es que se
  -- invente un ingreso. Se comprueba en las dos ramas: si se creó, que
  -- no cobró; y si se rechazó —lo normal, porque el plan ya la cubre—,
  -- que tampoco tocó el cajón de rebote.
  v_dia := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  if (v_dia->>'ingreso_efectivo')::int <> v_ef0 then
    raise exception 'un miembro generó un ingreso en efectivo (antes %, ahora %)',
      v_ef0, (v_dia->>'ingreso_efectivo')::int;
  end if;
  if (v_r->>'ok')::boolean is true then
    raise notice '  v un miembro no genera ingreso aunque digan efectivo';
  else
    raise notice '  v a un miembro en su hora ni se le cobra ni se le apunta (%)',
      v_r->>'error';
  end if;

  -- ═══ 6. Las de a mano NO se cuentan dos veces ═══
  -- Es lo que arregló la 0030 y no se puede romper: si el efectivo entra
  -- por caja Y además suma en reservas_cop, el cierre miente al alza.
  v_dia := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  v_mano_n := (v_dia->>'reservas_a_mano_n')::int;
  if v_mano_n < 3 then
    raise exception 'las reservas a mano no se están contando (n=%)', v_mano_n;
  end if;
  if (v_dia->>'reservas_cop')::int <> 0 then
    raise exception 'una reserva a mano se coló en reservas_cop (%), se contaría dos veces',
      v_dia->>'reservas_cop';
  end if;
  raise notice '  v las de a mano no se cuelan en reservas_cop';

  raise notice ' ';
  raise notice 'TODO EN VERDE';
end $$;
