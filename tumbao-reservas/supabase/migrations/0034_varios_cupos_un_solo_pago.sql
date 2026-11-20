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
