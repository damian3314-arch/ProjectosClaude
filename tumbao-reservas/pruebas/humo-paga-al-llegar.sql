-- ---------------------------------------------------------------------
-- Paga al llegar
--
-- LO QUE MIDE
-- La regla que hace auditable una caja: la plata entra al cajón cuando
-- entra la plata. Ni antes.
--
-- El caso que lo motivó: se aparta un cupo por teléfono, la persona
-- pagaría en efectivo al llegar, y no aparece. Esa plata no puede estar
-- contada en el arqueo de la noche.
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on
set client_min_messages = notice;

do $$
declare
  v_token text;
  v_clase uuid;
  v_r     jsonb;
  v_a     jsonb;
  v_dia   jsonb;
  v_ef0   int; v_esp0 int;
  v_cod   text;
  v_pend  jsonb;
  v_movs  int;
begin
  delete from admin_tokens;
  v_token := (crear_token_admin('Prueba puerta'))->>'token';

  insert into clases (fecha_hora, nombre, profesor, aforo, cupo_total,
                      cupo_tomado, precio_cop, activa)
  values (now() + interval '3 hours', 'Clase de prueba', 'Kevin',
          30, 30, 0, 15000, true)
  returning id into v_clase;

  v_dia  := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  v_ef0  := (v_dia->>'ingreso_efectivo')::int;
  v_esp0 := (v_dia->>'esperado_efectivo')::int;

  -- ═══ 1. Al apuntar, la plata NO entra ═══
  v_r := admin_crear_reserva(v_token, v_clase, 'Ana Puerta', '3001112233',
                             'suelta', null, 'en_puerta');
  if (v_r->>'ok')::boolean is not true then
    raise exception 'no se creó: %', v_r;
  end if;
  if (v_r->>'cobra_en_puerta') <> 'true' then
    raise exception 'no quedó marcada como cobrar al llegar: %', v_r;
  end if;
  v_cod := v_r->>'codigo';

  -- La clase se creó en el futuro porque tomar_cupo lo exige, pero a las
  -- 10 de la noche "dentro de 3 horas" ya es otro día en Bogotá y la
  -- lista de pendientes mira SOLO el día de hoy. Se mueve la clase a hoy
  -- una vez tomada, para que la prueba no dependa de la hora a la que se
  -- corra: eso ya rompió cuatro pruebas de este proyecto.
  update clases
     set fecha_hora = ((now() at time zone 'America/Bogota')::date
                       + time '12:00') at time zone 'America/Bogota'
   where id = v_clase;

  v_dia := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  if (v_dia->>'ingreso_efectivo')::int <> v_ef0 then
    raise exception 'entró plata al apuntar, y no debía: antes % ahora %',
      v_ef0, (v_dia->>'ingreso_efectivo')::int;
  end if;
  -- Lo que de verdad decide el arqueo: si esto sube, el cajón espera un
  -- dinero que todavía no está.
  if (v_dia->>'esperado_efectivo')::int <> v_esp0 then
    raise exception 'el cajón ya espera esa plata sin tenerla';
  end if;
  raise notice '  v al apuntar no entra nada al cajón';

  -- ═══ 2. Se ve que está pendiente ═══
  -- Si no se viera, cambiaríamos un problema por otro más callado.
  v_pend := admin_por_cobrar_en_puerta(v_token);
  if (v_pend->>'n')::int <> 1 or (v_pend->>'total_cop')::int <> 15000 then
    raise exception 'no aparece como pendiente de cobrar: %', v_pend;
  end if;
  raise notice '  v aparece en lo que falta cobrar hoy (%)', v_pend->>'total_cop';

  -- ═══ 3. Al marcarle la entrada, ENTRA ═══
  v_a := admin_marcar_asistencia(v_token, v_clase, 'r:' || v_cod, true);
  if (v_a->>'ok')::boolean is not true then
    raise exception 'no se pudo marcar la entrada: %', v_a;
  end if;
  if (v_a->>'cobrado_cop')::int <> 15000 then
    raise exception 'no dijo que cobró: %', v_a;
  end if;

  v_dia := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  if (v_dia->>'ingreso_efectivo')::int - v_ef0 <> 15000 then
    raise exception 'el cajón no subió al entrar: antes % ahora %',
      v_ef0, (v_dia->>'ingreso_efectivo')::int;
  end if;
  if (v_dia->>'esperado_efectivo')::int - v_esp0 <> 15000 then
    raise exception 'lo esperado en el cajón no subió al entrar';
  end if;
  raise notice '  v al marcarle la entrada, el cajón sube 15.000';

  -- Ya no está pendiente.
  v_pend := admin_por_cobrar_en_puerta(v_token);
  if (v_pend->>'n')::int <> 0 then
    raise exception 'sigue apareciendo como pendiente: %', v_pend;
  end if;
  raise notice '  v y deja de aparecer como pendiente';

  -- ═══ 4. Marcar dos veces no cobra dos veces ═══
  -- Es un botón que se toca con prisa y con gente en la puerta.
  v_a := admin_marcar_asistencia(v_token, v_clase, 'r:' || v_cod, true);
  v_dia := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  if (v_dia->>'ingreso_efectivo')::int - v_ef0 <> 15000 then
    raise exception 'cobró dos veces: %', v_dia->>'ingreso_efectivo';
  end if;
  raise notice '  v marcar dos veces no cobra dos veces';

  -- ═══ 5. Desmarcar devuelve la plata ═══
  -- Un clic equivocado no puede dejar en la caja un ingreso que nadie
  -- entregó: es el mismo problema al revés.
  v_a := admin_marcar_asistencia(v_token, v_clase, 'r:' || v_cod, false);
  if (v_a->>'cobrado_cop')::int <> -15000 then
    raise exception 'no dijo que devolvía: %', v_a;
  end if;
  v_dia := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  if (v_dia->>'ingreso_efectivo')::int <> v_ef0 then
    raise exception 'al desmarcar no volvió el cajón a su sitio: % vs %',
      v_dia->>'ingreso_efectivo', v_ef0;
  end if;
  raise notice '  v desmarcar la entrada devuelve la plata';

  -- Y vuelve a estar pendiente, que es la verdad: se apuntó y no ha pagado.
  v_pend := admin_por_cobrar_en_puerta(v_token);
  if (v_pend->>'n')::int <> 1 then
    raise exception 'al desmarcar no volvió a pendiente: %', v_pend;
  end if;
  raise notice '  v y vuelve a contarse como pendiente de cobrar';

  -- ═══ 6. El que no viene nunca no deja rastro de plata ═══
  -- El caso que motivó todo esto.
  --
  -- Hace falta otra clase: la de arriba ya se movió a mediodía de hoy y
  -- tomar_cupo no deja apuntar a una clase que ya pasó.
  insert into clases (fecha_hora, nombre, profesor, aforo, cupo_total,
                      cupo_tomado, precio_cop, activa)
  values (now() + interval '3 hours', 'Otra clase', 'Kevin',
          30, 30, 0, 15000, true)
  returning id into v_clase;

  v_r := admin_crear_reserva(v_token, v_clase, 'Beto NoVino', '3002223344',
                             'suelta', null, 'en_puerta');
  v_dia := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  if (v_dia->>'ingreso_efectivo')::int <> v_ef0 then
    raise exception 'alguien que no ha llegado movió el cajón';
  end if;
  raise notice '  v quien no llega no aparece en el cajón';

  -- ═══ 7. Los otros dos medios no cambiaron ═══
  v_r := admin_crear_reserva(v_token, v_clase, 'Caro Efectivo', '3003334455',
                             'suelta', null, 'efectivo');
  v_dia := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  if (v_dia->>'ingreso_efectivo')::int - v_ef0 <> 15000 then
    raise exception '"ya pagó en efectivo" dejó de entrar al apuntar';
  end if;
  raise notice '  v "ya pagó en efectivo" sigue entrando al apuntar';

  -- ═══ 8. Un miembro no paga en la puerta ═══
  select count(*) into v_movs from caja_movimientos
   where dia = (now() at time zone 'America/Bogota')::date;
  v_a := admin_marcar_asistencia(v_token, v_clase, 'p:3009998877', true);
  if (select count(*) from caja_movimientos
       where dia = (now() at time zone 'America/Bogota')::date) <> v_movs then
    raise exception 'marcar a alguien con plan movió la caja';
  end if;
  raise notice '  v marcar a alguien con plan no toca la caja';

  raise notice ' ';
  raise notice 'TODO EN VERDE';
end $$;
