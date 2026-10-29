-- ---------------------------------------------------------------------
-- 0032 — Cruzar en las dos direcciones
--
-- EL PROBLEMA, MEDIDO
-- El 11 de agosto entraron cinco consignaciones y solo UNA se cruzó sola.
-- Las otras cuatro salieron con `sin_reserva_que_casar` y se quedaron
-- ahí. Mirando las horas se ve por qué:
--
--   15:48  Yiraudis reserva
--   15:49  transfiere  → el correo del banco llega y se procesa 15:50
--   15:5x  Yiraudis termina de escribir la referencia y da "ya pagué"
--
-- Cuando el correo se procesó, la reserva todavía estaba en
-- `pendiente_pago`, que NO es candidata. Un minuto después pasó a
-- `verificando` — y nadie volvió a mirar.
--
-- La transferencia es instantánea y el correo llega en menos de un
-- minuto. La persona parada en el celular tarda más que eso en llenar el
-- formulario. O sea que el orden normal es: primero el dinero, después
-- la reserva lista para cruzarse. Y el cruce solo se intentaba en el
-- orden contrario.
--
-- LO QUE HACE
-- El cruce deja de ser un evento y pasa a ser una pregunta que se hace
-- desde los dos lados:
--
--   · llega un correo   → ¿hay una reserva esperando este dinero?   (ya existía)
--   · alguien dice "ya pagué" → ¿hay dinero esperando esta reserva?  (nuevo)
--   · y una barrida para lo que quedó a medias por diferencias de hora
--
-- POR QUÉ NO HAY UN CRON
-- Porque no hace falta. Todo pago genera un correo, y toda reserva pasa
-- por "ya pagué". Con los dos lados cubiertos no queda ventana: lo que
-- llegue primero espera, y lo segundo que llegue lo encuentra. Un
-- programado sería una pieza más que se puede caer sin que nadie lo note.
--
-- LO QUE NO CAMBIA
-- `registrar_pago_y_conciliar` se deja como está. Funciona, es la que
-- toca plata primero, y lo que le faltaba no era arreglarla sino
-- preguntarle lo mismo desde el otro lado.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- 1. ¿Qué depósito le corresponde a esta reserva?
--
-- El espejo de _cand en registrar_pago_y_conciliar, mirando al revés.
-- Devuelve un uuid solo cuando NO hay duda; en cuanto hay dos que se
-- parecen igual, devuelve null y el caso se va a la cola humana. Eso es
-- a propósito: amarrar el dinero de otra persona es peor que dejarlo
-- pendiente cinco minutos.
--
-- LA VENTANA ES ±30 MIN, NO ±15
-- La de registrar_pago_y_conciliar son ±15 minutos alrededor de la hora
-- declarada. El 11 de agosto una reserva declaró 15:52 y el depósito
-- entró 16:10: dieciocho minutos, y se perdió por tres. La gente no mira
-- el reloj cuando transfiere, lo estima. Ampliar no afloja la seguridad
-- porque el desempate sigue siendo el mismo: un solo candidato, o un
-- nombre que gana claramente.
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
  v_id     uuid;
begin
  select * into v_r from reservas where id = p_reserva_id;
  if not found or v_r.pago_id is not null then return null; end if;
  if v_r.estado not in ('verificando', 'pendiente_validacion') then return null; end if;

  select precio_cop into v_precio from clases where id = v_r.clase_id;
  if v_precio is null or v_precio <= 0 then return null; end if;

  -- La hora que declaró quien paga. Si no declaró ninguna, el momento en
  -- que empezó a reservar, con la ventana larga hacia adelante: entre
  -- que se toma el cupo y se transfiere pueden pasar minutos.
  v_ref := coalesce(v_r.pagado_en, v_r.created_at);
  -- Contra quien PAGA, no contra quien reserva: cuando paga la mamá o la
  -- pareja son personas distintas, y comparar contra quien reserva daría
  -- cero justo cuando hace falta desempatar.
  v_quien := coalesce(v_r.pagador_nombre, v_r.nombre);

  with cand as (
    select p.id, similitud_nombre(v_quien, p.remitente) as pt
      from pagos p
     where not p.consumido
       and p.valor_cop = v_precio
       and p.fecha_pago >= inicio_produccion()::timestamp at time zone 'America/Bogota'
       and case
             when v_r.pagado_en is not null then
               p.fecha_pago between v_ref - interval '30 minutes'
                                and v_ref + interval '30 minutes'
             else
               p.fecha_pago between v_ref - interval '30 minutes'
                                and v_ref + interval '3 hours'
           end
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
     -- parecerse (>= 0.5) Y estar por encima del segundo. Dos empatados
     -- es exactamente el caso en que adivinar sale caro, y ahí se
     -- devuelve null para que lo mire una persona.
          or (pt >= 0.5 and pt > coalesce(segundo, -1)));

  return v_id;
end;
$$;


-- ---------------------------------------------------------------------
-- 2. Amarrarlo
--
-- Separada de la búsqueda porque la búsqueda es STABLE y se puede llamar
-- para "¿qué habría pasado?" sin tocar nada. Esta sí escribe.
-- ---------------------------------------------------------------------
create or replace function conciliar_reserva(p_reserva_id uuid)
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
-- 3. La barrida
--
-- Para lo que quedó a medias: la persona declaró una hora que no cuadró,
-- y media hora después entra OTRO depósito que sí deja el panorama
-- claro. Se llama después de registrar un correo que no casó con nada.
-- No cuesta una ejecución extra de n8n: va en la misma.
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
    v_res := conciliar_reserva(v_r.id);
    if (v_res->>'cruzada')::boolean then
      v_n := v_n + 1;
      v_cods := v_cods || (v_res->>'codigo');
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'cruzadas', v_n, 'codigos', to_jsonb(v_cods));
end;
$$;


-- ---------------------------------------------------------------------
-- 4. "Ya pagué" ahora también busca
--
-- Idéntica a la de 0013 salvo las últimas líneas. Se repite entera
-- porque `create or replace` reemplaza la función completa: copiar el
-- cuerpo viejo es la única forma de no perder la validación de
-- referencia repetida, que sigue haciendo falta.
--
-- Y el cambio que se nota en el celular del cliente: cuando el dinero ya
-- estaba, la respuesta pasa de "estamos validando" a "confirmado" en el
-- mismo clic.
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

  -- LO NUEVO. El dinero casi siempre llegó antes que este clic.
  v_cruce := conciliar_reserva(v_reserva.id);
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
-- 5. La cola de "Por validar" deja de mentir
--
-- TRES COSAS ESTABAN MAL:
--
-- a) Preguntaba por lo que está libre de la forma equivocada. Miraba
--    `not exists (select 1 from reservas where pago_id = p.id)`, pero la
--    marca de verdad es `pagos.consumido`, que es la que pone también la
--    caja. Un depósito ya cobrado en la caja se seguía ofreciendo aquí:
--    dos cobros, un solo dinero.
--
-- b) Exigía que el valor cuadrara EXACTO con el precio de la clase. Así,
--    quien paga 30.000 por dos personas o 60.000 por cuatro clases no
--    aparece nunca al lado de su reserva. La cola es de decisión humana:
--    esconder al que no cuadra es esconder justo el caso que necesita
--    ojos. Ahora se muestra, marcado, y de último.
--
-- c) No enseñaba la plata que no casó con NADA. Solo se veía dentro de
--    la pestaña de Caja, en el selector de un cobro. El 11 de agosto
--    había $60.000 de una persona sin reclamar y en "Por validar" no
--    aparecía ni una señal.
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
      'precio_cop',  c.precio_cop,
      'pagos_sueltos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'pago_id',   p.id,
                 'valor_cop', p.valor_cop,
                 'fecha',     p.fecha_pago,
                 -- Lo que antes era un requisito ahora es un dato: la
                 -- recepcionista ve si cuadra y decide.
                 'cuadra',    p.valor_cop = c.precio_cop,
                 'parecido',  round(similitud_nombre(
                                coalesce(r.pagador_nombre, r.nombre), p.remitente), 2),
                 'remitente', p.remitente,
                 'minutos',   case when r.pagado_en is null then null
                              else round(extract(epoch from
                                     (p.fecha_pago - r.pagado_en)) / 60) end)
               -- Primero los que cuadran, y entre esos el nombre más
               -- parecido. Los que no cuadran van al final: están para
               -- que se vean, no para que sean lo primero que se toca.
               order by (p.valor_cop = c.precio_cop) desc,
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
--
-- Las tres nuevas no las llama nadie de fuera: se usan desde dentro de
-- registrar_aviso_pago y desde el workflow de ingesta, que entra como
-- service_role. Nada de anon.
-- ---------------------------------------------------------------------
revoke execute on function buscar_deposito_libre(uuid) from public, anon, authenticated;
revoke execute on function conciliar_reserva(uuid)     from public, anon, authenticated;
revoke execute on function conciliar_pendientes()      from public, anon, authenticated;
grant  execute on function buscar_deposito_libre(uuid) to service_role;
grant  execute on function conciliar_reserva(uuid)     to service_role;
grant  execute on function conciliar_pendientes()      to service_role;

revoke execute on function registrar_aviso_pago(text, timestamptz, text, text, text)
  from public, anon, authenticated;
grant  execute on function registrar_aviso_pago(text, timestamptz, text, text, text)
  to service_role;
revoke execute on function admin_pendientes(text) from public, anon, authenticated;
grant  execute on function admin_pendientes(text) to service_role;
