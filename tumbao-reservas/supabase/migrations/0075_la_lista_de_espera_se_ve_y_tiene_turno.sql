-- 0075 · La lista de espera se ve, y cada quien tiene su turno.
--
-- Damián: «Importante que la lista de espera de mensualidad sí muestre a
-- la gente que está en espera, para tenerlos en prioridad.»
--
-- El mecanismo ya existía y funciona: `mensualidad_solicitar` mira los
-- cupos y, si la hora está llena, la solicitud nace en `lista_espera` en
-- vez de `esperando_pago`. Y `mensualidad_lista` ya las devuelve. Lo que
-- faltaba era que se VIERAN como lo que son —una cola con un orden— en
-- vez de perderse entre las pagadas.
--
-- El 9 de septiembre las tres horas se llenaron (7pm y 6pm en cero
-- libres), así que la primera persona que entre a la página desde
-- entonces cae en lista de espera. Que salgan bien no es un adorno: es
-- la diferencia entre llamar a quien lleva una semana esperando y
-- llamar a quien escribió ayer.
--
-- LO QUE SE AÑADE
--
-- `mensualidad_cupos` devuelve `en_espera` por hora: cuánta gente está
-- haciendo fila para ese horario. La tarjeta del panel puede entonces
-- decir «0 libres · 3 en espera», que es justo lo que hay que saber
-- antes de prometerle un cupo a alguien por WhatsApp.
--
-- Se cuentan las de los últimos 90 días, la misma ventana que usa
-- `mensualidad_lista`: si la tarjeta contara más atrás que la lista,
-- diría «3 en espera» y abajo se verían dos, que es peor que no decir
-- nada. Una que se atiende con el botón pasa a `atendida` y sale de
-- las dos a la vez.
--
-- El ORDEN de la cola no hace falta añadirlo: `mensualidad_lista` ya
-- ordena por `creado_at` ascendente dentro de cada estado, así que la
-- primera de la lista es la que lleva más tiempo esperando. El panel
-- solo tiene que numerarlas.
--
-- Se parchea EN SITIO sobre la definición viva, no se reescribe:
-- producción trae arreglos que no están en este repo.

do $mig$
declare
  v_src   text;
  v_new   text;
  v_ancla text;
  v_rep   text;
begin
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'mensualidad_cupos';

  if v_src is null then
    raise exception '0075: no existe public.mensualidad_cupos';
  end if;

  if position('0075:' in v_src) > 0 then
    raise notice '0075: ya aplicado, no se toca';
    return;
  end if;

  if position('0074:' in v_src) = 0 then
    raise exception '0075: falta la 0074, que es la que abrio el desglose';
  end if;

  v_new := v_src;

  -- El conteo, junto a los otros tres de la misma CTE.
  v_ancla :=
    E'           (select count(*) from mensualidad_solicitudes s\n' ||
    E'             where s.hora = h.hora and s.estado = ''pagada'')::int as pagadas';
  if position(v_ancla in v_new) = 0 then
    raise exception '0075: no se encontro el conteo de pagadas';
  end if;
  v_rep := v_ancla || E',\n' ||
    E'           -- 0075: cuanta gente hace fila por este horario. La\n' ||
    E'           -- misma ventana de 90 dias que usa mensualidad_lista:\n' ||
    E'           -- si la tarjeta contara mas atras que la lista, diria\n' ||
    E'           -- «3 en espera» y abajo se verian dos.\n' ||
    E'           (select count(*) from mensualidad_solicitudes s\n' ||
    E'             where s.hora = h.hora and s.estado = ''lista_espera''\n' ||
    E'               and s.creado_at > now() - interval ''90 days'')::int as en_espera';
  v_new := replace(v_new, v_ancla, v_rep);

  -- Y sale en el json de cada hora. NO suma a `ocupadas`: quien espera
  -- no ocupa cupo — si sumara, la hora se veria mas llena de lo que
  -- esta y nadie mas podria entrar, que es lo contrario de lo que hace
  -- falta.
  v_ancla := E'        ''apartadas'', c.apartadas,';
  if position(v_ancla in v_new) = 0 then
    raise exception '0075: no se encontro la clave apartadas';
  end if;
  v_rep :=
    E'        ''apartadas'', c.apartadas,\n' ||
    E'        ''en_espera'', c.en_espera,';
  v_new := replace(v_new, v_ancla, v_rep);

  -- La marca, junto a la de la 0074.
  v_ancla := E'-- 0074: el cupo dice de donde sale, y el tope puede ir por hora.';
  if position(v_ancla in v_new) = 0 then
    raise exception '0075: no se encontro la marca de la 0074';
  end if;
  v_new := replace(v_new, v_ancla,
    E'-- 0074: el cupo dice de donde sale, y el tope puede ir por hora.\n' ||
    E'-- 0075: y dice cuanta gente esta haciendo fila por cada horario.');

  execute v_new;
end
$mig$;
