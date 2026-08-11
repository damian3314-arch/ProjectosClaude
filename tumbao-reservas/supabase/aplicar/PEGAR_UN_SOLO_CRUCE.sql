-- =====================================================================
-- TUMBAO — segundo pegado (encima de lo que ya pegaste esta noche)
--
-- Arregla un error que metí yo en el archivo anterior: creé una función
-- llamada `conciliar_reserva` sin ver que YA existía otra con ese nombre
-- —la que llama la barra de progreso de la página pública en cada
-- consulta de estado—. No rompió nada, pero dos funciones con el mismo
-- nombre es la trampa que ya nos costó un 502 antes.
--
-- De paso, las dos usan ahora la misma búsqueda: la vieja tenía su
-- propia copia, y cuando había varios depósitos parecidos se llevaba uno
-- CUALQUIERA. Podía amarrarle a alguien la plata de otra persona.
--
-- Y la ventana se intenta dos veces: primero alrededor de la hora que
-- declara quien paga, y si no encuentra nada, la ventana larga desde que
-- reservó. Recoge a quien escribe mal la hora, sin aflojar la regla de
-- no adivinar cuando hay empate.
--
-- Se puede pegar con el día empezado. Correrlo dos veces no hace daño.
-- Supabase → SQL Editor → pegar todo → Run.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0033 — Un solo cruce, con un solo nombre
--
-- DOS COSAS, Y LA PRIMERA ES UN ERROR MÍO
--
-- 1. La 0032 creó `conciliar_reserva(uuid)` sin ver que YA EXISTÍA
--    `conciliar_reserva(text)` desde la 0004, y que sigue viva: la llama
--    el polling de la barra de progreso en cada consulta de estado desde
--    la página pública.
--
--    No rompió nada —Postgres las distingue por el tipo del argumento y
--    las dos llamadas son inequívocas— pero dos funciones con el mismo
--    nombre haciendo casi lo mismo es exactamente la clase de trampa que
--    ya nos costó un 502: PostgREST resuelve las sobrecargas por los
--    nombres de los parámetros que recibe, y basta un parámetro de más
--    para caer en la que no era. Se renombra a `cruzar_reserva` y la
--    sobrecarga se borra.
--
-- 2. Y ya que hay que tocarlas: la vieja tenía su propia copia de las
--    reglas, peor que la nueva. Cuando encontraba VARIOS depósitos que
--    se parecían al nombre, se llevaba uno cualquiera —`for update skip
--    locked` sin ningún orden— o sea que podía amarrarle a alguien la
--    plata de otra persona. Ahora las dos usan la misma búsqueda, que
--    ante el empate no adivina.
--
-- LA VENTANA AHORA SE INTENTA DOS VECES
-- La 0032 buscaba solo alrededor de la hora declarada (±30 min). Eso es
-- más preciso, pero pierde a quien escribe mal la hora o se demora en
-- transferir: la vieja miraba desde 15 minutos antes de reservar hasta 3
-- horas después, y esos casos sí los agarraba.
--
-- Se hacen las dos, en orden: primero la estrecha, y solo si no
-- encuentra nada, la ancha. Lo que impide un error no es lo corta que
-- sea la ventana sino la regla de decisión —un solo candidato, o un
-- nombre que gane claramente—, y esa no se toca. Así se gana alcance sin
-- soltar la seguridad: si la ventana ancha trae dos, sigue yendo a
-- manos humanas.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- 1. La búsqueda, ahora en dos pasadas
-- ---------------------------------------------------------------------
create or replace function buscar_deposito_libre(p_reserva_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_r      reservas%rowtype;
  v_precio int;
  v_ref    timestamptz;
  v_quien  text;
  v_corte  timestamptz;
  v_id     uuid;
  v_desde  timestamptz;
  v_hasta  timestamptz;
  v_pasada int;
begin
  select * into v_r from reservas where id = p_reserva_id;
  if not found or v_r.pago_id is not null then return null; end if;
  if v_r.estado not in ('verificando', 'pendiente_validacion') then return null; end if;

  select precio_cop into v_precio from clases where id = v_r.clase_id;
  if v_precio is null or v_precio <= 0 then return null; end if;

  v_ref   := coalesce(v_r.pagado_en, v_r.created_at);
  -- Contra quien PAGA, no contra quien reserva: cuando paga la mamá o la
  -- pareja son personas distintas, y comparar contra quien reserva daría
  -- cero justo cuando hace falta desempatar.
  v_quien := coalesce(v_r.pagador_nombre, v_r.nombre);
  v_corte := inicio_produccion()::timestamp at time zone 'America/Bogota';

  for v_pasada in 1..2 loop
    if v_pasada = 1 then
      -- Estrecha: alrededor de la hora que declaró quien paga. Es la que
      -- acierta cuando la persona escribió bien la hora, que es casi
      -- siempre.
      v_desde := v_ref - interval '30 minutes';
      v_hasta := v_ref + interval '30 minutes';
    else
      -- Ancha: desde antes de reservar hasta tres horas después. Recoge
      -- a quien puso mal la hora o se demoró en transferir. Solo se
      -- llega aquí si la estrecha no encontró nada.
      v_desde := v_r.created_at - interval '15 minutes';
      v_hasta := v_r.created_at + interval '3 hours';
    end if;

    with cand as (
      select p.id, similitud_nombre(v_quien, p.remitente) as pt
        from pagos p
       where not p.consumido
         and p.valor_cop = v_precio
         and p.fecha_pago >= v_corte
         and p.fecha_pago between v_desde and v_hasta
    ), orden as (
      select id, pt,
             count(*) over ()                     as n,
             row_number() over (order by pt desc) as rn,
             lead(pt)     over (order by pt desc) as segundo
        from cand
    )
    select id into v_id from orden
     where rn = 1
       -- Uno solo: se amarra sin mirar el nombre. Es el caso "pagó la
       -- mamá": el nombre no coincide y da igual, no hay con quién
       -- confundirlo.
       and (n = 1
       -- Varios: gana el nombre, pero solo si gana de verdad. Tiene que
       -- parecerse (>= 0.5) Y estar por encima del segundo. Dos
       -- empatados es exactamente el caso en que adivinar sale caro, y
       -- ahí se devuelve null para que lo mire una persona.
            or (pt >= 0.5 and pt > coalesce(segundo, -1)));

    if v_id is not null then return v_id; end if;
  end loop;

  return null;
end;
$$;


-- ---------------------------------------------------------------------
-- 2. El amarre, con el nombre que no choca con nada
-- ---------------------------------------------------------------------
create or replace function cruzar_reserva(p_reserva_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_pago uuid;
  v_cod  text;
begin
  v_pago := buscar_deposito_libre(p_reserva_id);
  if v_pago is null then
    return jsonb_build_object('ok', true, 'cruzada', false);
  end if;

  -- Entre buscar y amarrar pudo pasar otra transacción. Se bloquea la
  -- fila del pago y se vuelve a comprobar que siga libre: es lo que
  -- impide que dos reservas se lleven el mismo depósito.
  perform 1 from pagos where id = v_pago and not consumido for update;
  if not found then
    return jsonb_build_object('ok', true, 'cruzada', false, 'motivo', 'lo_tomaron');
  end if;

  update reservas
     set estado = 'confirmada', pago_id = v_pago, updated_at = now()
   where id = p_reserva_id
     and pago_id is null
     and estado in ('verificando', 'pendiente_validacion')
  returning codigo into v_cod;

  if v_cod is null then
    return jsonb_build_object('ok', true, 'cruzada', false, 'motivo', 'ya_no_aplica');
  end if;

  update pagos set consumido = true where id = v_pago;

  return jsonb_build_object('ok', true, 'cruzada', true,
                            'pago_id', v_pago, 'codigo', v_cod);
end;
$$;


-- ---------------------------------------------------------------------
-- 3. La barrida, apuntando a la nueva
-- ---------------------------------------------------------------------
create or replace function conciliar_pendientes()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_r    record;
  v_res  jsonb;
  v_n    int := 0;
  v_cods text[] := '{}';
begin
  for v_r in
    select r.id
      from reservas r
      join clases c on c.id = r.clase_id
     where r.estado in ('verificando', 'pendiente_validacion')
       and r.pago_id is null
       and c.fecha_hora >= inicio_produccion()::timestamp at time zone 'America/Bogota'
     -- Por orden de llegada: si dos reservas se pelean el mismo
     -- depósito, que se lo lleve la que lleva más rato esperando.
     order by r.created_at
  loop
    v_res := cruzar_reserva(v_r.id);
    if (v_res->>'cruzada')::boolean then
      v_n := v_n + 1;
      v_cods := v_cods || (v_res->>'codigo');
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'cruzadas', v_n, 'codigos', to_jsonb(v_cods));
end;
$$;


-- ---------------------------------------------------------------------
-- 4. "Ya pagué", apuntando a la nueva
--
-- Igual que en 0032 salvo el nombre de la función del final. Se repite
-- entera porque `create or replace` reemplaza la función completa.
-- ---------------------------------------------------------------------
create or replace function registrar_aviso_pago(
  p_codigo      text,
  p_pagado_en   timestamptz default null,
  p_referencia  text default null,
  p_pagador     text default null,
  p_qr          text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_reserva reservas%rowtype;
  v_ref     text := nullif(btrim(coalesce(p_referencia, '')), '');
  v_duena   text;
  v_cruce   jsonb;
begin
  select * into v_reserva from reservas
   where upper(btrim(codigo)) = upper(btrim(p_codigo))
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_encontrada',
      'mensaje', 'No encontramos esa reserva.');
  end if;

  if v_reserva.estado = 'confirmada' then
    return jsonb_build_object('ok', true, 'estado', 'confirmada',
      'codigo', v_reserva.codigo, 'mensaje', 'Tu pago ya estaba confirmado.');
  end if;

  if v_reserva.estado not in ('pendiente_pago', 'verificando') then
    return jsonb_build_object('ok', false, 'error', 'estado_invalido',
      'estado', v_reserva.estado,
      'mensaje', 'Esa reserva esta en ' || v_reserva.estado || '. Escribenos por WhatsApp.');
  end if;

  -- Si esa referencia ya sustenta otra reserva, es el mismo comprobante
  -- reusado. Se avisa en vez de dejarlo pasar.
  if v_ref is not null then
    select codigo into v_duena from reservas
     where upper(btrim(referencia_pago)) = upper(v_ref)
       and id <> v_reserva.id
     limit 1;
    if v_duena is not null then
      return jsonb_build_object('ok', false, 'error', 'referencia_repetida',
        'mensaje', 'Ese comprobante ya se uso para otra reserva. ' ||
                   'Si crees que es un error escribenos por WhatsApp.');
    end if;
  end if;

  update reservas
     set estado          = 'verificando',
         pagado_en       = coalesce(p_pagado_en, pagado_en, now()),
         pagador_nombre  = coalesce(nullif(btrim(coalesce(p_pagador, '')), ''), pagador_nombre),
         referencia_pago = coalesce(v_ref, referencia_pago),
         comprobante_qr  = coalesce(nullif(btrim(coalesce(p_qr, '')), ''), comprobante_qr),
         updated_at      = now()
   where id = v_reserva.id;

  -- El dinero casi siempre llegó antes que este clic.
  v_cruce := cruzar_reserva(v_reserva.id);
  if (v_cruce->>'cruzada')::boolean then
    return jsonb_build_object('ok', true, 'estado', 'confirmada',
      'codigo', v_reserva.codigo, 'cruzada_al_vuelo', true,
      'mensaje', 'Tu pago quedo confirmado.');
  end if;

  return jsonb_build_object('ok', true, 'estado', 'verificando',
    'codigo', v_reserva.codigo);
end;
$$;


-- ---------------------------------------------------------------------
-- 5. La vieja deja de tener reglas propias
--
-- Esta es la que llama el polling de la página en cada consulta de
-- estado, y por eso NO se puede borrar ni cambiarle la firma ni la forma
-- de la respuesta: `Armar respuesta estado` en el workflow de la API lee
-- ok, estado, codigo, clase y metodo.
--
-- Lo que cambia es de dónde saca la decisión. Antes tenía su propia
-- copia de la búsqueda, con un empate resuelto a la suerte. Ahora
-- pregunta lo mismo que preguntan las otras dos puertas.
--
-- Se deja de devolver `candidatos`: no lo lee nadie, y era el resto de
-- una versión en que la página enseñaba "hay 2 pagos parecidos".
-- ---------------------------------------------------------------------
create or replace function conciliar_reserva(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_reserva reservas%rowtype;
  v_clase   clases%rowtype;
  v_cruce   jsonb;
begin
  select * into v_reserva from reservas
   where upper(btrim(codigo)) = upper(btrim(p_codigo))
     for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_encontrada');
  end if;

  select * into v_clase from clases where id = v_reserva.clase_id;

  if v_reserva.estado <> 'verificando' then
    return jsonb_build_object('ok', true, 'estado', v_reserva.estado,
      'codigo', v_reserva.codigo, 'clase', v_clase.nombre,
      'fecha_hora', v_clase.fecha_hora);
  end if;

  v_cruce := cruzar_reserva(v_reserva.id);

  if (v_cruce->>'cruzada')::boolean then
    return jsonb_build_object('ok', true, 'estado', 'confirmada',
      'metodo', 'deposito_unico', 'codigo', v_reserva.codigo,
      'clase', v_clase.nombre, 'fecha_hora', v_clase.fecha_hora);
  end if;

  return jsonb_build_object('ok', true, 'estado', 'verificando',
    'codigo', v_reserva.codigo, 'clase', v_clase.nombre,
    'fecha_hora', v_clase.fecha_hora);
end;
$$;


-- ---------------------------------------------------------------------
-- 6. Fuera la sobrecarga
--
-- Se borra AL FINAL, cuando ya nadie la llama: las tres que la usaban
-- —registrar_aviso_pago, conciliar_pendientes y ella misma— quedaron
-- reescritas arriba. Nació hace unas horas en la 0032 y no la referencia
-- nada más.
--
-- `if exists` para que esto se pueda pegar dos veces, y para que no
-- reviente en una base donde la 0032 nunca llegó a aplicarse.
-- ---------------------------------------------------------------------
drop function if exists conciliar_reserva(uuid);


-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke execute on function buscar_deposito_libre(uuid) from public, anon, authenticated;
revoke execute on function cruzar_reserva(uuid)        from public, anon, authenticated;
revoke execute on function conciliar_pendientes()      from public, anon, authenticated;
revoke execute on function conciliar_reserva(text)     from public, anon, authenticated;
grant  execute on function buscar_deposito_libre(uuid) to service_role;
grant  execute on function cruzar_reserva(uuid)        to service_role;
grant  execute on function conciliar_pendientes()      to service_role;
grant  execute on function conciliar_reserva(text)     to service_role;

revoke execute on function registrar_aviso_pago(text, timestamptz, text, text, text)
  from public, anon, authenticated;
grant  execute on function registrar_aviso_pago(text, timestamptz, text, text, text)
  to service_role;
