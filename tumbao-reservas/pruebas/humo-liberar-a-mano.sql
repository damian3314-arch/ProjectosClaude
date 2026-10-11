-- ---------------------------------------------------------------------
-- Liberar una reserva apuntada a mano
--
-- LO QUE MIDE
-- Que un error de mostrador se pueda corregir entero: el cupo vuelve a
-- estar a la venta, la plata sale de la caja y la entrada deja de estar
-- marcada. Y que esa puerta NO se abra para las reservas que cruzó la
-- página, que tienen un depósito de verdad detrás.
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on
set client_min_messages = notice;

do $$
declare
  v_token text;
  v_clase uuid;
  v_r     jsonb;
  v_l     jsonb;
  v_dia   jsonb;
  v_ef0   int;
  v_cod   text;
  v_tomado0 int; v_tomado1 int;
  v_lista jsonb;
  v_fila  jsonb;
begin
  delete from admin_tokens;
  v_token := (crear_token_admin('Prueba liberar'))->>'token';

  insert into clases (fecha_hora, nombre, profesor, aforo, cupo_total,
                      cupo_tomado, precio_cop, activa)
  values (now() + interval '3 hours', 'Clase de prueba', 'Kevin',
          30, 30, 0, 15000, true)
  returning id into v_clase;

  v_ef0 := (caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date)
            ->>'ingreso_efectivo')::int;
  select cupo_tomado into v_tomado0 from clases where id = v_clase;

  -- ═══ 1. Se apunta cobrando en efectivo ═══
  v_r := admin_crear_reserva(v_token, v_clase, 'Ana Error', '3001112233',
                             'suelta', null, 'efectivo');
  v_cod := v_r->>'codigo';
  if (v_r->>'efectivo_registrado') <> 'true' then
    raise exception 'no entró el efectivo: %', v_r;
  end if;

  -- ═══ 2. La lista dice que se puede liberar y cuánto devuelve ═══
  -- Sin esto el panel tendría que adivinar en qué se puede clicar.
  v_lista := admin_lista_clase(v_token, v_clase);
  select e into v_fila from jsonb_array_elements(v_lista->'reservas') e
   where e->>'codigo' = v_cod;
  if (v_fila->>'a_mano') <> 'true' then
    raise exception 'la lista no la marca como de mostrador: %', v_fila;
  end if;
  if (v_fila->>'cobrado_cop')::int <> 15000 then
    raise exception 'la lista no dice cuánto devuelve: %', v_fila;
  end if;
  raise notice '  v la lista dice que es de mostrador y que devuelve 15.000';

  -- Se le marca la entrada, como pasaría de verdad antes de darse cuenta
  -- del error.
  perform admin_marcar_asistencia(v_token, v_clase, 'r:' || v_cod, true);

  -- ═══ 3. Liberar: cupo, plata y entrada ═══
  v_l := admin_rechazar(v_token, v_cod);
  if (v_l->>'ok')::boolean is not true then
    raise exception 'no dejó liberar una de mostrador: %', v_l;
  end if;
  if (v_l->>'devuelto_cop')::int <> 15000 then
    raise exception 'no dijo que devolvía la plata: %', v_l;
  end if;

  v_dia := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  if (v_dia->>'ingreso_efectivo')::int <> v_ef0 then
    raise exception 'la plata sigue en la caja: % vs %',
      v_dia->>'ingreso_efectivo', v_ef0;
  end if;
  raise notice '  v al liberar, los 15.000 salen de la caja';

  select cupo_tomado into v_tomado1 from clases where id = v_clase;
  if v_tomado1 <> v_tomado0 then
    raise exception 'el cupo no volvió a estar libre: % vs %', v_tomado1, v_tomado0;
  end if;
  raise notice '  v y el cupo vuelve a estar a la venta';

  if exists (select 1 from asistencias a
              join reservas r on r.id = a.reserva_id
             where r.codigo = v_cod) then
    raise exception 'quedó marcada la entrada de una reserva liberada';
  end if;
  raise notice '  v y deja de contar como que entró';

  -- Ya no sale en la lista de la puerta: está rechazada.
  v_lista := admin_lista_clase(v_token, v_clase);
  if exists (select 1 from jsonb_array_elements(v_lista->'reservas') e
              where e->>'codigo' = v_cod) then
    raise exception 'sigue apareciendo en la puerta';
  end if;
  raise notice '  v y desaparece de la lista de la puerta';

  -- ═══ 4. Liberar dos veces no devuelve dos veces ═══
  v_l := admin_rechazar(v_token, v_cod);
  v_dia := caja_del_dia(v_token, (now() at time zone 'America/Bogota')::date);
  if (v_dia->>'ingreso_efectivo')::int <> v_ef0 then
    raise exception 'liberar dos veces movió la caja otra vez';
  end if;
  raise notice '  v liberar dos veces no devuelve dos veces';

  -- ═══ 5. Una de "paga al llegar" sin cobrar: no hay nada que devolver ═══
  v_r := admin_crear_reserva(v_token, v_clase, 'Beto Puerta', '3002223344',
                             'suelta', null, 'en_puerta');
  v_l := admin_rechazar(v_token, v_r->>'codigo');
  if (v_l->>'ok')::boolean is not true then
    raise exception 'no dejó liberar una de paga-al-llegar: %', v_l;
  end if;
  if v_l->>'devuelto_cop' is not null then
    raise exception 'devolvió plata que nunca entró: %', v_l;
  end if;
  raise notice '  v una sin cobrar se libera sin devolver nada';

  -- ═══ 6. LA PUERTA QUE NO SE ABRE ═══
  -- Una reserva que cruzó la página está confirmada porque llegó un
  -- depósito. Soltarla con un clic dejaría el dinero huérfano.
  insert into reservas (clase_id, codigo, nombre, telefono, tipo, estado,
                        origen, expira_en)
  values (v_clase, 'WEBWEB', 'Caro Web', '3003334455', 'suelta',
          'confirmada', 'formulario', now() + interval '1 hour');
  v_l := admin_rechazar(v_token, 'WEBWEB');
  if (v_l->>'ok')::boolean is not false or v_l->>'error' <> 'YA_CONFIRMADA' then
    raise exception 'dejó liberar una confirmada que vino de la página: %', v_l;
  end if;
  if (select estado from reservas where codigo = 'WEBWEB') <> 'confirmada' then
    raise exception 'la de la página cambió de estado';
  end if;
  raise notice '  v una confirmada de la pagina sigue sin poder liberarse';

  -- Y la lista la marca como NO liberable, para que el botón ni salga.
  v_lista := admin_lista_clase(v_token, v_clase);
  select e into v_fila from jsonb_array_elements(v_lista->'reservas') e
   where e->>'codigo' = 'WEBWEB';
  if (v_fila->>'a_mano') <> 'false' then
    raise exception 'la lista marca como de mostrador una de la pagina: %', v_fila;
  end if;
  raise notice '  v y la lista no la marca como de mostrador';

  raise notice ' ';
  raise notice 'TODO EN VERDE';
end $$;
