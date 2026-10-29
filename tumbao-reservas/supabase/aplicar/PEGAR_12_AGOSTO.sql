-- =====================================================================
-- TUMBAO — pegar esta noche (12 de agosto)
--
-- Tres cosas, en orden. Se puede pegar con el día empezado y correrlo
-- dos veces no hace daño. NO se borra ni se toca ninguna reserva de las
-- que ya existen: todo lo nuevo son columnas que nacen vacías, y para
-- una reserva de una sola persona el sistema se comporta exactamente
-- igual que hasta ahora.
--
--   PARTE A — un solo nombre para el cruce de pagos
--             (el arreglo del choque de nombres que quedó pendiente)
--
--   PARTE B — varios cupos con un solo pago
--             seis personas, un giro de $90.000, y el banco lo cruza
--
--   PARTE C — pagó y no vino
--             se marca en la puerta y le quedan 3 días para usarla
--
-- Cómo: Supabase → SQL Editor → pegar todo → Run.
--
-- Ojo con el orden si vas a pegar por partes: B y C dan por hecho que A
-- ya corrió. Pegándolo todo de una no hay nada que pensar.
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



-- ---------------------------------------------------------------------
-- 0034 — Varios cupos con un solo pago
--
-- LO QUE PIDE EL MOSTRADOR
-- Alguien llega y reserva para seis. Hoy eso se hace a mano por WhatsApp,
-- una reserva por persona, y el banco recibe UN giro de $90.000 que no
-- cuadra con ningún cupo de $15.000. Ninguna de las seis se cruza sola.
--
-- CÓMO SE MODELA: SEIS FILAS, UN GRUPO
-- No una fila con `cantidad = 6`. Cada persona que entra por la puerta
-- es una persona: se marca su entrada por separado, se la busca por su
-- nombre, y el aforo cuenta seis. Una fila con un contador obligaría a
-- inventar medias-asistencias en la lista de la puerta.
--
--   `grupo_id` = el id de la PRIMERA reserva del grupo.
--   El líder es la fila donde `grupo_id = id`.
--   Una reserva sola tiene `grupo_id` en null, y así se queda: no hay
--   nada que migrar en lo que ya existe.
--
-- POR QUÉ EL DEPÓSITO SE COPIA EN LAS SEIS FILAS
-- Se podría dejar el `pago_id` solo en el líder. No: la caja suma
-- `precio_cop` de las reservas confirmadas CON depósito, y las que no lo
-- tienen las cuenta aparte como "a mano". Con el pago solo en el líder,
-- un grupo de seis entraría como $15.000 de banco y $75.000 cobrados a
-- mano — plata bien contada en el total pero mal repartida justo en la
-- pantalla que sirve para cuadrar contra AdminGym.
--
-- Copiándolo en las seis, ni caja_del_dia ni el arqueo ni la tirilla se
-- enteran de que existen los grupos. La regla de "un pago no confirma
-- dos reservas" se mantiene, pero ahora se mide entre LÍDERES: el índice
-- único pasa a ser parcial sobre las filas que encabezan grupo.
-- ---------------------------------------------------------------------

alter table reservas add column if not exists grupo_id uuid references reservas(id);

create index if not exists reservas_por_grupo on reservas (grupo_id)
  where grupo_id is not null;

comment on column reservas.grupo_id is
  'Reservas hechas de una sola vez y pagadas de un solo giro. Apunta a la primera del grupo; null si va sola.';

-- Un pago sigue sin poder confirmar dos reservas — pero un grupo entero
-- comparte el suyo. Se mide sobre los líderes: si dos líderes tuvieran
-- el mismo depósito serían dos grupos cobrando la misma plata.
--
-- Lo mismo con el comprobante: las seis del grupo llevan la misma
-- referencia a propósito, porque es un solo comprobante. Lo que hay que
-- impedir sigue siendo que DOS grupos distintos lo reusen.
--
-- Los dos índices se recrean con la misma condición añadida: la fila
-- encabeza grupo. Para todo lo que existe hoy —donde grupo_id es null—
-- la condición es cierta y el índice significa exactamente lo mismo que
-- significaba.
drop index if exists reservas_pago_unico;
create unique index reservas_pago_unico on reservas (pago_id)
  where pago_id is not null and (grupo_id is null or grupo_id = id);

drop index if exists reservas_referencia_unica;
create unique index reservas_referencia_unica
  on reservas (upper(btrim(referencia_pago)))
  where referencia_pago is not null and btrim(referencia_pago) <> ''
    and (grupo_id is null or grupo_id = id);


-- ---------------------------------------------------------------------
-- A qué grupo pertenece una reserva
-- ---------------------------------------------------------------------
create or replace function grupo_de(p_reserva_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(grupo_id, id) from reservas where id = p_reserva_id
$$;


-- ---------------------------------------------------------------------
-- Tomar varios cupos de una
--
-- NO REPITE LAS REGLAS DE AFORO
-- Podría copiar aquí las comprobaciones de tomar_cupo —clase activa, ya
-- pasó, cupo lleno, tope de sueltas del sábado partido— pero entonces
-- habría dos sitios que decidir mantener iguales, y el día que se
-- cambie uno el otro vende cupos que no existen.
--
-- En vez de eso: se comprueba UNA cosa que tomar_cupo no sabe mirar
-- —que quepan los N, no solo el primero— y después se llama a
-- tomar_cupo N veces. Todo dentro de la misma transacción y del mismo
-- bloqueo de fila, así que nadie se cuela en medio.
--
-- Y si aun así una de las N fallara, `raise exception` deshace TODAS.
-- Media reserva de un grupo de seis sería lo peor de los dos mundos:
-- cupos ocupados que nadie va a usar y un cobro que no cuadra con nada.
-- ---------------------------------------------------------------------
create or replace function tomar_cupos(
  p_clase_id uuid,
  p_nombres  text[],
  p_telefono text,
  p_email    text default null,
  p_origen   text default 'web'
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_clase   clases%rowtype;
  v_n       int;
  v_i       int;
  v_r       jsonb;
  v_ids     uuid[] := '{}';
  v_cods    text[] := '{}';
  v_lider   uuid;
  v_nombre  text;
  v_tomadas int;
  v_libres  int;
begin
  v_n := coalesce(array_length(p_nombres, 1), 0);

  -- El tope no es una regla de negocio, es un freno: ocho es más gente
  -- de la que cabe en un solo giro razonable, y sin tope un cero de más
  -- en el contador se lleva la clase entera.
  if v_n < 1 or v_n > 8 then
    return jsonb_build_object('ok', false, 'error', 'CANTIDAD_INVALIDA',
      'mensaje', 'Se pueden reservar entre 1 y 8 cupos a la vez.');
  end if;

  for v_i in 1..v_n loop
    if length(btrim(coalesce(p_nombres[v_i], ''))) < 2 then
      return jsonb_build_object('ok', false, 'error', 'FALTA_NOMBRE',
        'cual', v_i,
        'mensaje', 'Falta el nombre de la persona ' || v_i || '.');
    end if;
  end loop;

  select * into v_clase from clases where id = p_clase_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'CLASE_NO_EXISTE',
      'mensaje', 'Esa clase ya no está disponible.');
  end if;

  -- Suelta lo que nunca pagó antes de contar. Es el mismo gesto que hace
  -- tomar_cupo, y aquí importa más: se está preguntando por N puestos.
  perform liberar_cupos_de_clase(p_clase_id);
  select * into v_clase from clases where id = p_clase_id;

  if not v_clase.activa then
    return jsonb_build_object('ok', false, 'error', 'CLASE_INACTIVA',
      'mensaje', 'Esa clase fue cancelada.');
  end if;
  if v_clase.fecha_hora < now() then
    return jsonb_build_object('ok', false, 'error', 'CLASE_YA_PASO',
      'mensaje', 'Esa clase ya empezó. Elige otro horario.');
  end if;

  -- LO ÚNICO QUE TOMAR_CUPO NO SABE MIRAR: que quepan los N.
  -- Sin esto, seis personas con cuatro cupos libres entrarían cuatro y
  -- las otras dos reventarían a mitad del grupo.
  v_libres := v_clase.cupo_total - v_clase.cupo_tomado;
  if v_libres < v_n then
    return jsonb_build_object('ok', false, 'error', 'NO_CABEN_TANTOS',
      'libres', greatest(v_libres, 0), 'pedidos', v_n,
      'mensaje', case when v_libres <= 0
                   then 'Esa clase se llenó. Elige otro horario.'
                   else 'En esa clase solo queda' ||
                        case when v_libres = 1 then ' 1 cupo' else 'n ' || v_libres || ' cupos' end ||
                        ', y estás pidiendo ' || v_n || '.' end);
  end if;

  -- Y lo mismo con el reparto del sábado, cuando la clase está partida.
  if v_clase.cupo_sueltas is not null then
    select count(*) into v_tomadas
      from reservas r
     where r.clase_id = p_clase_id
       and r.tipo = 'suelta'
       and r.estado not in ('rechazada', 'expirada');
    if v_tomadas + v_n > v_clase.cupo_sueltas then
      return jsonb_build_object('ok', false, 'error', 'NO_CABEN_TANTOS',
        'libres', greatest(v_clase.cupo_sueltas - v_tomadas, 0), 'pedidos', v_n,
        'mensaje', 'No quedan tantos cupos en esa clase. Elige otro horario.');
    end if;
  end if;

  foreach v_nombre in array p_nombres loop
    v_r := tomar_cupo(p_clase_id, btrim(v_nombre), p_telefono, p_email,
                      p_origen, 'suelta');
    if not coalesce((v_r->>'ok')::boolean, false) then
      -- Se comprobó arriba que caben. Si aun así falla, algo cambió por
      -- debajo y lo correcto es deshacerlo todo, no dejar medio grupo.
      raise exception 'tomar_cupos: falló el cupo % de %: %',
        array_position(p_nombres, v_nombre), v_n, v_r->>'error';
    end if;
    v_ids  := v_ids  || (v_r->>'reserva_id')::uuid;
    v_cods := v_cods || (v_r->>'codigo');
  end loop;

  -- Una sola no es grupo: se queda exactamente como cualquier reserva de
  -- siempre, con grupo_id en null. Así el camino de todos los días no
  -- cambia ni de forma.
  if v_n > 1 then
    v_lider := v_ids[1];
    update reservas set grupo_id = v_lider where id = any(v_ids);
  end if;

  return jsonb_build_object(
    'ok', true,
    'cupos',       v_n,
    'grupo',       v_n > 1,
    -- El código que se le da a la persona es el del líder. Es con el que
    -- va a decir "ya pagué", y mueve el grupo entero.
    'codigo',      v_cods[1],
    'codigos',     to_jsonb(v_cods),
    'reserva_id',  v_ids[1],
    'nombres',     to_jsonb(p_nombres),
    'telefono',    solo_digitos(p_telefono),
    'requiere_pago', true,
    'precio_cop',  v_clase.precio_cop,
    'total_cop',   v_clase.precio_cop * v_n,
    'clase',       v_clase.nombre,
    'profesor',    v_clase.profesor,
    'fecha_hora',  v_clase.fecha_hora,
    'lugar',       v_clase.lugar,
    'expira_en',   (select expira_en from reservas where id = v_ids[1]),
    'cupos_restantes', greatest(v_clase.cupo_total - v_clase.cupo_tomado, 0));
end;
$$;


-- ---------------------------------------------------------------------
-- Lo que hay que cobrar por una reserva
--
-- Sale de contar el grupo, no de un número guardado. Un contador
-- guardado se desincroniza el día que alguien rechace a uno de los seis;
-- contar no.
-- ---------------------------------------------------------------------
create or replace function precio_del_grupo(p_reserva_id uuid)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select max(c.precio_cop) * count(*)::int
    from reservas r
    join reservas yo on yo.id = p_reserva_id
    join clases c    on c.id = yo.clase_id
   where coalesce(r.grupo_id, r.id) = coalesce(yo.grupo_id, yo.id)
     and r.estado not in ('rechazada', 'expirada')
$$;


-- ---------------------------------------------------------------------
-- El cruce con el banco, ahora por el total del grupo
--
-- Igual que en 0033 salvo el precio: se busca lo que de verdad tiene que
-- haber entrado, no el precio de una clase. Un grupo de seis manda
-- $90.000 de una sola vez.
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

  -- El total del grupo. Para una reserva sola es el precio de la clase,
  -- exactamente como antes.
  v_precio := precio_del_grupo(p_reserva_id);
  if v_precio is null or v_precio <= 0 then return null; end if;

  v_ref   := coalesce(v_r.pagado_en, v_r.created_at);
  -- Contra quien PAGA, no contra quien reserva: cuando paga la mamá o la
  -- pareja son personas distintas.
  v_quien := coalesce(v_r.pagador_nombre, v_r.nombre);
  v_corte := inicio_produccion()::timestamp at time zone 'America/Bogota';

  for v_pasada in 1..2 loop
    if v_pasada = 1 then
      v_desde := v_ref - interval '30 minutes';
      v_hasta := v_ref + interval '30 minutes';
    else
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
       and (n = 1
            or (pt >= 0.5 and pt > coalesce(segundo, -1)));

    if v_id is not null then return v_id; end if;
  end loop;

  return null;
end;
$$;


-- ---------------------------------------------------------------------
-- Amarrar: el grupo entero, o ninguno
-- ---------------------------------------------------------------------
create or replace function cruzar_reserva(p_reserva_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_pago  uuid;
  v_grupo uuid;
  v_n     int;
  v_cod   text;
begin
  v_pago := buscar_deposito_libre(p_reserva_id);
  if v_pago is null then
    return jsonb_build_object('ok', true, 'cruzada', false);
  end if;

  perform 1 from pagos where id = v_pago and not consumido for update;
  if not found then
    return jsonb_build_object('ok', true, 'cruzada', false, 'motivo', 'lo_tomaron');
  end if;

  v_grupo := grupo_de(p_reserva_id);

  -- El depósito se copia en todas las filas del grupo. Ver la cabecera:
  -- es lo que deja intacta toda la contabilidad de la caja.
  with tocadas as (
    update reservas
       set estado = 'confirmada', pago_id = v_pago, updated_at = now()
     where coalesce(grupo_id, id) = v_grupo
       and pago_id is null
       and estado in ('verificando', 'pendiente_validacion')
    returning id, codigo, grupo_id
  )
  select count(*)::int,
         max(codigo) filter (where grupo_id is null or grupo_id = id)
    into v_n, v_cod
    from tocadas;

  if coalesce(v_n, 0) = 0 then
    return jsonb_build_object('ok', true, 'cruzada', false, 'motivo', 'ya_no_aplica');
  end if;

  update pagos set consumido = true where id = v_pago;

  return jsonb_build_object('ok', true, 'cruzada', true,
    'pago_id', v_pago, 'cupos', v_n,
    'codigo', coalesce(v_cod, (select codigo from reservas where id = p_reserva_id)));
end;
$$;


-- ---------------------------------------------------------------------
-- "Ya pagué" mueve el grupo entero
--
-- La persona tiene UN código —el del líder— y con él dice que pagó por
-- los seis. Si solo se moviera su fila, las otras cinco seguirían en
-- pendiente_pago y se soltarían solas a la media hora, dejando a cinco
-- personas pagadas sin cupo.
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
  v_grupo   uuid;
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
  -- reusado. Se avisa en vez de dejarlo pasar. Las hermanas del mismo
  -- grupo no cuentan: comparten comprobante a propósito.
  v_grupo := grupo_de(v_reserva.id);
  if v_ref is not null then
    select codigo into v_duena from reservas
     where upper(btrim(referencia_pago)) = upper(v_ref)
       and coalesce(grupo_id, id) <> v_grupo
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
   where coalesce(grupo_id, id) = v_grupo
     and estado in ('pendiente_pago', 'verificando');

  -- El dinero casi siempre llegó antes que este clic.
  v_cruce := cruzar_reserva(v_reserva.id);
  if (v_cruce->>'cruzada')::boolean then
    return jsonb_build_object('ok', true, 'estado', 'confirmada',
      'codigo', v_reserva.codigo, 'cruzada_al_vuelo', true,
      'cupos', v_cruce->'cupos',
      'mensaje', 'Tu pago quedo confirmado.');
  end if;

  return jsonb_build_object('ok', true, 'estado', 'verificando',
    'codigo', v_reserva.codigo);
end;
$$;


-- ---------------------------------------------------------------------
-- Confirmar a mano: el grupo entero
-- ---------------------------------------------------------------------
create or replace function admin_confirmar(
  p_token text, p_codigo text, p_pago_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin   uuid;
  v_reserva reservas%rowtype;
  v_grupo   uuid;
  v_n       int;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_reserva from reservas
   where codigo = upper(trim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  if v_reserva.estado = 'confirmada' then
    return jsonb_build_object('ok', true, 'estado', 'confirmada',
      'codigo', v_reserva.codigo, 'mensaje', 'Ya estaba confirmada.');
  end if;

  if v_reserva.estado not in ('pendiente_validacion', 'verificando', 'pendiente_pago') then
    return jsonb_build_object('ok', false, 'error', 'ESTADO_INVALIDO',
      'estado', v_reserva.estado,
      'mensaje', 'Esa reserva esta en ' || v_reserva.estado || ', no se puede confirmar.');
  end if;

  v_grupo := grupo_de(v_reserva.id);

  if p_pago_id is not null then
    -- Las hermanas del grupo comparten depósito a propósito; lo que no
    -- puede pasar es que se lo lleve OTRO grupo.
    if exists (select 1 from reservas
                where pago_id = p_pago_id
                  and coalesce(grupo_id, id) <> v_grupo) then
      return jsonb_build_object('ok', false, 'error', 'PAGO_YA_USADO',
        'mensaje', 'Ese pago ya esta amarrado a otra reserva.');
    end if;
    if not exists (select 1 from pagos where id = p_pago_id) then
      return jsonb_build_object('ok', false, 'error', 'PAGO_NO_EXISTE');
    end if;
    update pagos set consumido = true where id = p_pago_id;
  end if;

  with tocadas as (
    update reservas
       set estado = 'confirmada',
           pago_id = coalesce(p_pago_id, pago_id),
           -- El rastro para poder deshacer: de donde venia y a que
           -- apuntaba. Se guarda antes de pisarlo.
           estado_antes  = estado,
           pago_id_antes = pago_id,
           resuelta_por  = v_admin,
           resuelta_at   = now(),
           updated_at    = now()
     where coalesce(grupo_id, id) = v_grupo
       and estado in ('pendiente_validacion', 'verificando', 'pendiente_pago')
    returning 1
  )
  select count(*)::int into v_n from tocadas;

  return jsonb_build_object('ok', true, 'estado', 'confirmada',
    'codigo', v_reserva.codigo, 'nombre', v_reserva.nombre,
    'telefono', v_reserva.telefono, 'cupos', v_n,
    'se_puede_deshacer', true,
    'mensaje', case when v_n > 1
                 then 'Confirmadas a mano las ' || v_n || ' del grupo.'
                 else 'Confirmada a mano.' end);
end;
$$;


-- ---------------------------------------------------------------------
-- Rechazar: el grupo entero, y suelta sus N cupos
-- ---------------------------------------------------------------------
create or replace function admin_rechazar(p_token text, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin   uuid;
  v_reserva reservas%rowtype;
  v_grupo   uuid;
  v_n       int;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_reserva from reservas
   where codigo = upper(trim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  if v_reserva.estado = 'rechazada' then
    return jsonb_build_object('ok', true, 'estado', 'rechazada',
      'codigo', v_reserva.codigo, 'mensaje', 'Ya estaba rechazada.');
  end if;
  if v_reserva.estado = 'confirmada' then
    return jsonb_build_object('ok', false, 'error', 'YA_CONFIRMADA',
      'mensaje', 'Esa reserva ya esta confirmada. Si te acabas de equivocar, '
              || 'usa Deshacer; si no, hay que arreglarlo a mano.');
  end if;

  v_grupo := grupo_de(v_reserva.id);

  with tocadas as (
    update reservas
       set estado        = 'rechazada',
           estado_antes  = estado,
           pago_id_antes = pago_id,
           resuelta_por  = v_admin,
           resuelta_at   = now(),
           updated_at    = now()
     where coalesce(grupo_id, id) = v_grupo
       and estado not in ('rechazada', 'confirmada')
    returning 1
  )
  select count(*)::int into v_n from tocadas;

  -- Un cupo por persona soltada, no uno por grupo.
  update clases set cupo_tomado = greatest(cupo_tomado - v_n, 0)
   where id = v_reserva.clase_id;

  return jsonb_build_object('ok', true, 'estado', 'rechazada',
    'codigo', v_reserva.codigo, 'nombre', v_reserva.nombre,
    'telefono', v_reserva.telefono, 'cupos', v_n,
    'se_puede_deshacer', true,
    'mensaje', case when v_n > 1
                 then 'Rechazadas, quedaron libres ' || v_n || ' cupos.'
                 else 'Rechazada, el cupo quedo libre.' end);
end;
$$;


-- ---------------------------------------------------------------------
-- Deshacer: el grupo entero
-- ---------------------------------------------------------------------
create or replace function admin_deshacer(p_token text, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin   uuid;
  v_reserva reservas%rowtype;
  v_clase   clases%rowtype;
  v_minutos int;
  v_grupo   uuid;
  v_n       int;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_reserva from reservas
   where codigo = upper(trim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  if v_reserva.estado not in ('confirmada', 'rechazada') then
    return jsonb_build_object('ok', false, 'error', 'NADA_QUE_DESHACER',
      'mensaje', 'Esa reserva no esta confirmada ni rechazada.');
  end if;

  -- Candado 1: lo que concilio solo el sistema no se deshace desde
  -- aqui. No fue el movimiento de nadie.
  if v_reserva.resuelta_por is null or v_reserva.estado_antes is null then
    return jsonb_build_object('ok', false, 'error', 'NO_FUE_A_MANO',
      'mensaje', 'Esta se resolvio sola, no desde el panel. No se deshace desde aqui.');
  end if;

  -- Candado 2: la ventana. Pasados 15 minutos ya no es un resbalon.
  v_minutos := floor(extract(epoch from (now() - v_reserva.resuelta_at)) / 60);
  if v_minutos > 15 then
    return jsonb_build_object('ok', false, 'error', 'FUERA_DE_TIEMPO',
      'minutos', v_minutos,
      'mensaje', 'Ya pasaron ' || v_minutos || ' minutos. Deshacer solo sirve '
              || 'en los primeros 15; despues hay que resolverlo a mano.');
  end if;

  v_grupo := grupo_de(v_reserva.id);
  select count(*)::int into v_n from reservas
   where coalesce(grupo_id, id) = v_grupo and resuelta_at is not null;

  -- Deshacer un rechazo tiene que volver a tomar los cupos, y en ese
  -- rato alguien pudo comprarlos. Antes de sobrevender, se niega.
  if v_reserva.estado = 'rechazada' then
    select * into v_clase from clases where id = v_reserva.clase_id for update;
    if v_clase.cupo_tomado + v_n > v_clase.cupo_total then
      return jsonb_build_object('ok', false, 'error', 'SIN_CUPO',
        'mensaje', 'Mientras tanto se vendio ese cupo y la clase quedo llena. '
                || 'Si hay que meter a esta persona, primero sube el cupo a mano '
                || 'en la pestana Horario.');
    end if;
    update clases set cupo_tomado = cupo_tomado + v_n where id = v_clase.id;
  end if;

  -- Si el pago se marcó consumido al confirmar, vuelve a estar libre.
  if v_reserva.estado = 'confirmada' and v_reserva.pago_id is not null
     and v_reserva.pago_id_antes is null then
    update pagos set consumido = false where id = v_reserva.pago_id;
  end if;

  -- Vuelve a como estaba, no a un estado inventado. Y se borra el
  -- rastro: deshacer se usa una vez.
  update reservas
     set estado        = estado_antes,
         pago_id       = pago_id_antes,
         estado_antes  = null,
         pago_id_antes = null,
         resuelta_por  = null,
         resuelta_at   = null,
         updated_at    = now()
   where coalesce(grupo_id, id) = v_grupo
     and resuelta_at is not null;

  return jsonb_build_object('ok', true,
    'codigo',  v_reserva.codigo,
    'nombre',  v_reserva.nombre,
    'estado',  v_reserva.estado_antes,
    'deshizo', v_reserva.estado,
    'cupos',   v_n,
    'mensaje', 'Deshecho. Vuelve a la cola tal como estaba.');
end;
$$;


-- ---------------------------------------------------------------------
-- La cola: un grupo es UNA tarjeta
--
-- Seis tarjetas iguales con el mismo comprobante y el mismo celular no
-- son seis decisiones, son una. Y peor: resolver la primera resolvería
-- las otras cinco por debajo, así que la recepcionista vería cinco
-- tarjetas que ya no existen.
--
-- Sale solo el líder, con los nombres de los demás y el total a cobrar.
-- ---------------------------------------------------------------------
create or replace function admin_pendientes(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_out    jsonb;
  v_libres jsonb;
  v_desde  timestamptz;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  v_desde := inicio_produccion()::timestamp at time zone 'America/Bogota';

  select coalesce(jsonb_agg(x order by x->>'creada_at'), '[]'::jsonb) into v_out
  from (
    select jsonb_build_object(
      'codigo',      r.codigo,
      'nombre',      r.nombre,
      'telefono',    r.telefono,
      'estado',      r.estado,
      'tipo',        r.tipo,
      'creada_at',   r.created_at,
      'pagado_en',   r.pagado_en,
      'pagador',     r.pagador_nombre,
      'referencia',  r.referencia_pago,
      'clase_id',    c.id,
      'clase',       c.nombre,
      'fecha_hora',  c.fecha_hora,
      -- El precio que se enseña es el del GRUPO. Enseñar $15.000 al lado
      -- de un depósito de $90.000 haría que el candidato bueno pareciera
      -- el equivocado.
      'precio_cop',  precio_del_grupo(r.id),
      'cupos',       (select count(*)::int from reservas h
                       where coalesce(h.grupo_id, h.id) = coalesce(r.grupo_id, r.id)
                         and h.estado not in ('rechazada', 'expirada')),
      'acompanantes', coalesce((
        select jsonb_agg(h.nombre order by h.created_at)
          from reservas h
         where coalesce(h.grupo_id, h.id) = coalesce(r.grupo_id, r.id)
           and h.id <> r.id
           and h.estado not in ('rechazada', 'expirada')), '[]'::jsonb),
      'pagos_sueltos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'pago_id',   p.id,
                 'valor_cop', p.valor_cop,
                 'fecha',     p.fecha_pago,
                 'cuadra',    p.valor_cop = precio_del_grupo(r.id),
                 'parecido',  round(similitud_nombre(
                                coalesce(r.pagador_nombre, r.nombre), p.remitente), 2),
                 'remitente', p.remitente,
                 'minutos',   case when r.pagado_en is null then null
                              else round(extract(epoch from
                                     (p.fecha_pago - r.pagado_en)) / 60) end)
               order by (p.valor_cop = precio_del_grupo(r.id)) desc,
                        similitud_nombre(coalesce(r.pagador_nombre, r.nombre),
                                         p.remitente) desc,
                        abs(extract(epoch from
                              (p.fecha_pago - coalesce(r.pagado_en, r.created_at)))))
          from pagos p
         where not p.consumido
           and p.fecha_pago >= v_desde
           and p.fecha_pago between coalesce(r.pagado_en, r.created_at) - interval '2 hours'
                               and coalesce(r.pagado_en, r.created_at) + interval '3 hours'
      ), '[]'::jsonb)
    ) as x
    from reservas r
    join clases c on c.id = r.clase_id
   where r.estado in ('pendiente_validacion', 'verificando')
     -- Solo el líder del grupo. Las hermanas se resuelven con él.
     and (r.grupo_id is null or r.grupo_id = r.id)
     -- Por la fecha de la CLASE: lo de clases pasadas ya no tiene
     -- arreglo, y lo de clases futuras sigue ocupando cupo aunque la
     -- reserva sea vieja, así que no se puede esconder.
     and c.fecha_hora >= v_desde
  ) s;

  -- La plata que llegó y no casó con nada. Tres días: más atrás ya es
  -- trabajo de la caja, no del mostrador.
  select coalesce(jsonb_agg(y order by y->>'fecha_pago' desc), '[]'::jsonb)
    into v_libres
  from (
    select jsonb_build_object(
             'pago_id',   p.id,
             'valor_cop', p.valor_cop,
             'fecha_pago', p.fecha_pago,
             'remitente', p.remitente,
             'cuando',    to_char(p.fecha_pago at time zone 'America/Bogota',
                                  'DD/MM HH24:MI')) as y
      from pagos p
     where not p.consumido
       and p.fecha_pago >= greatest(v_desde, now() - interval '3 days')
     order by p.fecha_pago desc
     limit 40
  ) t;

  return jsonb_build_object('ok', true, 'reservas', v_out,
                            'pagos_libres', v_libres);
end;
$$;


-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke execute on function tomar_cupos(uuid, text[], text, text, text)
  from public, anon, authenticated;
revoke execute on function grupo_de(uuid)         from public, anon, authenticated;
revoke execute on function precio_del_grupo(uuid) from public, anon, authenticated;
grant  execute on function tomar_cupos(uuid, text[], text, text, text) to service_role;
grant  execute on function grupo_de(uuid)         to service_role;
grant  execute on function precio_del_grupo(uuid) to service_role;

revoke execute on function buscar_deposito_libre(uuid) from public, anon, authenticated;
revoke execute on function cruzar_reserva(uuid)        from public, anon, authenticated;
revoke execute on function admin_pendientes(text)      from public, anon, authenticated;
revoke execute on function admin_confirmar(text, text, uuid) from public, anon, authenticated;
revoke execute on function admin_rechazar(text, text)  from public, anon, authenticated;
revoke execute on function admin_deshacer(text, text)  from public, anon, authenticated;
revoke execute on function registrar_aviso_pago(text, timestamptz, text, text, text)
  from public, anon, authenticated;

grant execute on function buscar_deposito_libre(uuid) to service_role;
grant execute on function cruzar_reserva(uuid)        to service_role;
grant execute on function admin_pendientes(text)      to service_role;
grant execute on function admin_confirmar(text, text, uuid) to service_role;
grant execute on function admin_rechazar(text, text)  to service_role;
grant execute on function admin_deshacer(text, text)  to service_role;
grant execute on function registrar_aviso_pago(text, timestamptz, text, text, text)
  to service_role;



-- ---------------------------------------------------------------------
-- 0035 — Pagó y no vino: clases por disfrutar
--
-- EL PROBLEMA
-- Alguien paga su clase y no aparece. Hoy eso no se puede ni anotar: en
-- la lista de la puerta o se marca que entró o se queda sin marcar, y
-- "sin marcar" también es lo que le pasa a quien todavía no ha llegado.
-- A las nueve de la noche nadie sabe quién faltó, y al día siguiente esa
-- persona escribe diciendo que pagó, con razón, y no hay dónde mirarlo.
--
-- LO QUE HACE
-- Un tercer estado en la puerta: "no vino". Marcarlo no borra el pago —
-- esa plata entró y está bien contada— sino que le abre a la persona un
-- crédito de TRES DÍAS para usar esa clase otro día.
--
-- POR QUÉ TRES DÍAS Y NO "para siempre"
-- Porque un crédito sin fecha es un pasivo que crece solo y que nadie
-- vuelve a mirar. Tres días es lo que pidió el negocio, y la fecha se
-- calcula desde la clase que se perdió, no desde el día que alguien
-- se acordó de marcarlo.
--
-- POR QUÉ NO SE BORRA NADA AL VENCER
-- La fila se queda como está: `no_vino_at` puesto y `credito_vence`
-- pasado. Deja de salir en la pantalla, que es lo que se pidió, pero
-- si alguien reclama en una semana se puede mirar qué pasó. Borrar
-- para que una lista se vea corta es perder la única prueba.
-- ---------------------------------------------------------------------

alter table reservas add column if not exists no_vino_at     timestamptz;
alter table reservas add column if not exists credito_vence  date;
alter table reservas add column if not exists reprogramada_a uuid references reservas(id);
alter table reservas add column if not exists viene_de       uuid references reservas(id);

comment on column reservas.no_vino_at is
  'Se marcó en la puerta que pagó y no asistió. El pago se queda donde está: lo que se abre es un crédito.';
comment on column reservas.credito_vence is
  'Último día para usar la clase que no disfrutó. Se cuenta desde la clase perdida, no desde el día que se marcó.';
comment on column reservas.reprogramada_a is
  'La reserva nueva a la que se movió. Puesto esto, el crédito ya se usó.';

create index if not exists reservas_por_disfrutar on reservas (credito_vence)
  where no_vino_at is not null and reprogramada_a is null;


-- ---------------------------------------------------------------------
-- Marcar que no vino
--
-- Solo sobre reservas confirmadas: si no pagó, no hay nada que
-- devolverle, y marcarlo solo ensuciaría la lista. Y solo sobre sueltas:
-- quien tiene mensualidad no perdió una clase pagada, perdió un día de
-- su plan, y eso no se arregla con un crédito.
-- ---------------------------------------------------------------------
create or replace function admin_marcar_no_vino(
  p_token text, p_clase_id uuid, p_ref text, p_no_vino boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_res   reservas%rowtype;
  v_clase clases%rowtype;
  v_dias  constant int := 3;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_clase from clases where id = p_clase_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'CLASE_NO_EXISTE');
  end if;

  -- Misma forma de referencia que usa la lista de la puerta: 'r:CODIGO'.
  if split_part(p_ref, ':', 1) <> 'r' then
    return jsonb_build_object('ok', false, 'error', 'SOLO_RESERVAS',
      'mensaje', 'Solo se marca en quien reservó y pagó, no en quien viene por plan.');
  end if;

  select * into v_res from reservas
   where codigo = upper(trim(substring(p_ref from position(':' in p_ref) + 1)))
     and clase_id = p_clase_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE',
      'mensaje', 'Esa reserva no es de esta clase.');
  end if;

  if not p_no_vino then
    update reservas set no_vino_at = null, credito_vence = null, updated_at = now()
     where id = v_res.id;
    return jsonb_build_object('ok', true, 'no_vino', false,
      'codigo', v_res.codigo, 'nombre', v_res.nombre,
      'mensaje', 'Se quitó la marca.');
  end if;

  if v_res.estado <> 'confirmada' then
    return jsonb_build_object('ok', false, 'error', 'NO_PAGO',
      'mensaje', 'Esa reserva no está confirmada: no hay clase pagada que guardarle. '
              || 'Si el cupo hay que soltarlo, usa Liberar.');
  end if;
  if v_res.tipo <> 'suelta' then
    return jsonb_build_object('ok', false, 'error', 'ES_MIEMBRO',
      'mensaje', 'Quien viene por mensualidad no pierde una clase pagada.');
  end if;
  if v_res.reprogramada_a is not null then
    return jsonb_build_object('ok', false, 'error', 'YA_REPROGRAMADA',
      'mensaje', 'Esa clase ya se movió a otro día.');
  end if;

  -- No vino: si alguien le había marcado la entrada, sobra.
  delete from asistencias where reserva_id = v_res.id and clase_id = p_clase_id;

  update reservas
     set no_vino_at    = now(),
         -- Desde la clase que se perdió. Marcarlo tres días tarde no le
         -- regala tres días más a nadie.
         credito_vence = (v_clase.fecha_hora at time zone 'America/Bogota')::date + v_dias,
         updated_at    = now()
   where id = v_res.id;

  return jsonb_build_object('ok', true, 'no_vino', true,
    'codigo', v_res.codigo, 'nombre', v_res.nombre,
    'vence', (v_clase.fecha_hora at time zone 'America/Bogota')::date + v_dias,
    'entraron', (select count(*)::int from asistencias where clase_id = p_clase_id),
    'mensaje', 'Anotado. Tiene ' || v_dias || ' días para usar esa clase.');
end;
$$;


-- ---------------------------------------------------------------------
-- Quiénes tienen clase pagada sin disfrutar
--
-- Sale ordenado por lo que se vence primero: es una lista para llamar
-- gente, y a quien le queda un día hay que llamarlo hoy.
-- ---------------------------------------------------------------------
create or replace function admin_por_disfrutar(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_hoy    date;
  v_out    jsonb;
  v_clases jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  v_hoy := (now() at time zone 'America/Bogota')::date;

  select coalesce(jsonb_agg(x order by x->>'vence', x->>'nombre'), '[]'::jsonb)
    into v_out
  from (
    select jsonb_build_object(
      'codigo',     r.codigo,
      'nombre',     r.nombre,
      'telefono',   r.telefono,
      'clase',      c.nombre,
      'clase_id',   c.id,
      'fecha_hora', c.fecha_hora,
      'precio_cop', c.precio_cop,
      'vence',      r.credito_vence,
      -- Cero = se vence hoy. Es el dato con el que se decide a quién
      -- llamar primero.
      'dias',       (r.credito_vence - v_hoy),
      'marcada_at', r.no_vino_at
    ) as x
    from reservas r
    join clases c on c.id = r.clase_id
   where r.no_vino_at is not null
     and r.reprogramada_a is null
     and r.estado = 'confirmada'
     and r.credito_vence >= v_hoy
  ) s;

  -- Y las clases a las que se puede mover a alguien, aquí mismo.
  --
  -- Se podría sacar del horario que el panel ya se trae para la
  -- cuadrícula, pero esa respuesta tiene otra forma —día y hora por
  -- separado— y armar una fecha a partir de ella es justo donde salen
  -- los "Invalid time value". Quien pinta el desplegable no debería
  -- tener que saber cómo se llaman los campos de otra pantalla.
  select coalesce(jsonb_agg(y order by y->>'fecha_hora'), '[]'::jsonb)
    into v_clases
  from (
    select jsonb_build_object(
             'clase_id',   c.id,
             'nombre',     c.nombre,
             'fecha_hora', c.fecha_hora,
             'libres',     greatest(c.cupo_total - c.cupo_tomado, 0)) as y
      from clases c
     where c.activa
       and c.fecha_hora > now()
       and c.cupo_tomado < c.cupo_total
     order by c.fecha_hora
     limit 40
  ) t;

  return jsonb_build_object('ok', true, 'gente', v_out,
                            'clases', v_clases, 'hoy', v_hoy);
end;
$$;


-- ---------------------------------------------------------------------
-- Reprogramar
--
-- Le da el cupo en otra clase sin volver a cobrar. La reserva vieja NO
-- se borra ni se rechaza: se queda confirmada y apuntando a la nueva.
-- Esa plata entró el día que entró y la caja de ese día ya cuadró;
-- moverla ahora descuadraría un cierre que ya se imprimió y se archivó.
-- ---------------------------------------------------------------------
create or replace function admin_reprogramar(
  p_token text, p_codigo text, p_clase_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_res    reservas%rowtype;
  v_hoy    date;
  v_nueva  jsonb;
  v_id     uuid;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  v_hoy := (now() at time zone 'America/Bogota')::date;

  select * into v_res from reservas
   where codigo = upper(trim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;
  if v_res.no_vino_at is null then
    return jsonb_build_object('ok', false, 'error', 'NO_TIENE_CREDITO',
      'mensaje', 'Esa reserva no está marcada como que no vino.');
  end if;
  if v_res.reprogramada_a is not null then
    return jsonb_build_object('ok', false, 'error', 'YA_REPROGRAMADA',
      'mensaje', 'Esa clase ya se movió a otro día.');
  end if;
  if v_res.credito_vence < v_hoy then
    return jsonb_build_object('ok', false, 'error', 'VENCIDA',
      'vencio', v_res.credito_vence,
      'mensaje', 'El plazo se venció el ' || to_char(v_res.credito_vence, 'DD/MM') ||
                 '. Si se le va a dar igual, hay que apuntarla a mano.');
  end if;
  if p_clase_id = v_res.clase_id then
    return jsonb_build_object('ok', false, 'error', 'MISMA_CLASE',
      'mensaje', 'Esa es la clase que se perdió. Escoge otra.');
  end if;

  -- El cupo lo da tomar_cupo con su bloqueo de fila: si la clase nueva
  -- está llena, aquí se acaba. Reprogramar no puede sobrevender.
  v_nueva := tomar_cupo(p_clase_id, v_res.nombre, v_res.telefono, v_res.email,
                        'reprogramada', 'suelta');
  if (v_nueva->>'ok')::boolean is not true then
    return v_nueva;   -- SIN_CUPO, CLASE_YA_PASO…
  end if;

  v_id := (v_nueva->>'reserva_id')::uuid;

  -- La nueva nace confirmada y sin pago propio: la plata ya entró con la
  -- vieja. `viene_de` es lo que deja ver, mirando una fila, que no es un
  -- cobro que se perdió sino una clase que se movió.
  update reservas
     set estado       = 'confirmada',
         viene_de     = v_res.id,
         resuelta_por = v_admin,
         resuelta_at  = now(),
         updated_at   = now()
   where id = v_id;

  update reservas
     set reprogramada_a = v_id, updated_at = now()
   where id = v_res.id;

  return jsonb_build_object('ok', true,
    'codigo',       v_nueva->>'codigo',
    'codigo_viejo', v_res.codigo,
    'nombre',       v_res.nombre,
    'telefono',     v_res.telefono,
    'clase',        v_nueva->>'clase',
    'fecha_hora',   v_nueva->>'fecha_hora',
    'mensaje',      'Reprogramada. Código nuevo: ' || (v_nueva->>'codigo') || '.');
end;
$$;


-- ---------------------------------------------------------------------
-- La lista de la puerta dice quién no vino
--
-- Se añaden dos campos a cada fila. Sin ellos el botón no sabría si ya
-- está marcado, y marcar dos veces se sentiría como que no responde.
-- ---------------------------------------------------------------------
create or replace function admin_lista_clase(p_token text, p_clase_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_clase  clases%rowtype;
  v_fecha  date;
  v_hora   time;
  v_res    jsonb;
  v_plan   jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_clase from clases where id = p_clase_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  v_fecha := (v_clase.fecha_hora at time zone 'America/Bogota')::date;
  v_hora  := (v_clase.fecha_hora at time zone 'America/Bogota')::time;

  select coalesce(jsonb_agg(x order by x->>'nombre'), '[]'::jsonb) into v_res
  from (
    select jsonb_build_object(
      'ref',        'r:' || r.codigo,
      'codigo',     r.codigo,
      'nombre',     r.nombre,
      'telefono',   r.telefono,
      'tipo',       r.tipo,
      'estado',     r.estado,
      'confirmada', r.estado = 'confirmada',
      'asistio',    a.id is not null,
      'marcada_at', a.marcada_at,
      -- Pagó y no vino. Sin esto el botón no sabría si ya está marcado,
      -- y volver a tocarlo se sentiría como que no responde.
      'no_vino',    r.no_vino_at is not null,
      'credito_vence', r.credito_vence
    ) as x
    from reservas r
    left join asistencias a on a.reserva_id = r.id
   where r.clase_id = p_clase_id
     and r.estado not in ('expirada', 'rechazada')
  ) s;

  select coalesce(jsonb_agg(x order by x->>'nombre'), '[]'::jsonb) into v_plan
  from (
    select jsonb_build_object(
      'ref',        'p:' || coalesce(solo_digitos(m.celular), m.afiliado),
      'nombre',     m.afiliado,
      'telefono',   m.celular,
      'membresia',  m.membresia,
      'hasta',      m.fin,
      'vence_hoy',  m.fin = v_fecha,
      'asistio',    a.id is not null,
      'marcada_at', a.marcada_at
    ) as x
    from membresias m
    left join asistencias a
           on a.clase_id = p_clase_id
          and a.origen = 'plan'
          and solo_digitos(a.telefono) = solo_digitos(m.celular)
   where m.hora = v_hora
     and v_fecha between m.inicio and m.fin
     and not exists (
       select 1 from reservas r
        where r.clase_id = p_clase_id
          and r.estado not in ('expirada', 'rechazada')
          and solo_digitos(r.telefono) = solo_digitos(m.celular))
  ) s;

  return jsonb_build_object(
    'ok', true,
    'clase', jsonb_build_object(
      'clase_id', v_clase.id,
      'nombre',   v_clase.nombre,
      'fecha',    v_fecha,
      'hora',     to_char(v_hora, 'HH24:MI'),
      'aforo',    v_clase.aforo,
      'ya_paso',  v_clase.fecha_hora <= now()),
    'reservas', v_res,
    'con_plan', v_plan,
    'resumen', jsonb_build_object(
      'reservas',        jsonb_array_length(v_res),
      'con_plan',        jsonb_array_length(v_plan),
      'esperados',       jsonb_array_length(v_res) + jsonb_array_length(v_plan),
      'entraron',        (select count(*)::int from asistencias where clase_id = p_clase_id),
      'vencen',          (select count(*)::int from jsonb_array_elements(v_plan) e
                           where (e->>'vence_hoy')::boolean),
      'sin_confirmar',   (select count(*)::int from jsonb_array_elements(v_res) e
                           where (e->>'confirmada')::boolean is not true)));
end;
$$;


-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke execute on function admin_marcar_no_vino(text, uuid, text, boolean)
  from public, anon, authenticated;
revoke execute on function admin_por_disfrutar(text) from public, anon, authenticated;
revoke execute on function admin_reprogramar(text, text, uuid)
  from public, anon, authenticated;
revoke execute on function admin_lista_clase(text, uuid) from public, anon, authenticated;

grant execute on function admin_marcar_no_vino(text, uuid, text, boolean) to service_role;
grant execute on function admin_por_disfrutar(text)                       to service_role;
grant execute on function admin_reprogramar(text, text, uuid)             to service_role;
grant execute on function admin_lista_clase(text, uuid)                   to service_role;



