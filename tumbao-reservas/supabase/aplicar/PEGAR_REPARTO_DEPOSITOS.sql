-- =====================================================================
-- PEGAR EN SUPABASE  ·  Un depósito puede pagar varias cosas
--
-- QUÉ ARREGLA
-- El 15 de agosto entró una consignación de $30.000 que pagaba dos
-- clases de $15.000. No había forma de registrarla: la caja exigía que
-- el movimiento valiera EXACTAMENTE lo mismo que el depósito. Se quedó
-- en "sin identificar" y ahí iba a quedarse.
--
-- Después de pegar esto, un depósito se puede ir gastando de a pedazos
-- y sigue en la lista hasta que se acabe.
--
-- QUÉ NO TOCA
--   · el cruce automático de reservas: ni una línea
--   · ningún cierre ya firmado
--   · ninguna reserva
--
-- Se puede pegar dos veces sin problema: la segunda avisa y no hace nada.
--
-- OJO CON EL ORDEN: pega esto ANTES de que se despliegue el panel nuevo,
-- o justo después. El panel aguanta las dos situaciones —si el servidor
-- todavía no reparte, se comporta como antes— así que no hay prisa.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0039 — Un depósito puede pagar varias cosas
--
-- EL CASO, DEL 15 DE AGOSTO
-- Alguien consignó $30.000 a las 8 de la mañana. Pagó dos clases de
-- $15.000. En la caja no había forma de registrarlo:
--
--   · el buscador de depósitos filtra por el valor tecleado, así que
--     escribiendo 15000 el depósito de 30.000 ni siquiera aparecía
--   · y aunque apareciera, `caja_registrar` exigía que el movimiento
--     valiera EXACTAMENTE lo mismo que el depósito
--
-- Resultado: los $30.000 se quedaron en "sin identificar" para siempre,
-- y la única salida era registrar una sola línea de $30.000 que en la
-- tirilla no dice de qué fue.
--
-- LO QUE HACE
-- Un depósito se puede ir gastando de a poquitos. Se lleva cuánto se
-- lleva usado (`usado_cop`) y solo se cierra cuando se acabó.
--
-- POR QUÉ NO SE TOCA EL CRUCE AUTOMÁTICO
-- `consumido` sigue queriendo decir lo mismo para el cruce de reservas:
-- "de este no te ocupes". Un depósito al que la caja ya le mordió un
-- pedazo queda con `consumido = true`, así que el cruce automático no lo
-- va a agarrar y adjudicárselo entero a una reserva. Eso sería contar la
-- misma plata dos veces.
--
-- La consecuencia es que el reparto es SIEMPRE a mano, decidido por una
-- persona que está mirando el depósito. Es lo que se quiere: adivinar
-- repartos de plata automáticamente es la clase de ayuda que nadie pidió.
--
-- Por eso la lista de "sin identificar" ya no pregunta `not consumido`
-- sino "¿le queda saldo?":
--
--   intacto                  -> se ve         (consumido false, usado 0)
--   se lo llevó una reserva  -> no se ve      (consumido true,  usado 0)
--   la caja usó una parte    -> se ve         (0 < usado < valor)
--   la caja lo acabó         -> no se ve      (usado = valor)
--
-- Así el lado de las reservas no se toca ni una línea.
--
-- POR QUÉ SE PARCHEA EL TEXTO
-- Lo mismo que en la 0037 y la 0038: `caja_del_dia` ya fue arreglada en
-- producción desde otra sesión y ese arreglo no está en el repositorio.
-- Reemplazar las funciones enteras lo borraría en silencio. Ver
-- `aplicar/LEEME-ANTES-DE-PEGAR.md`.
-- ---------------------------------------------------------------------

alter table pagos add column if not exists usado_cop int not null default 0;

comment on column pagos.usado_cop is
  'Cuánto de este depósito ya se adjudicó en caja. Cero si nadie lo ha '
  'tocado o si se lo llevó entero una reserva.';

-- El índice `caja_mov_pago_unico` decía, literal, "un depósito no puede
-- pagar dos cosas". Esa es exactamente la regla que aquí deja de valer:
-- uno de $30.000 paga dos clases de $15.000.
--
-- Lo que lo reemplaza es más fuerte, no más débil. El índice limitaba la
-- CANTIDAD de líneas y no miraba la plata: nada impedía enlazar un
-- depósito de $15.000 a un movimiento de $500.000. Ahora `caja_registrar`
-- limita el DINERO —no se puede adjudicar más de lo que le queda— y lo
-- hace con el depósito bloqueado (`for update`), así que dos cajeros a la
-- vez tampoco pueden pasarse.
drop index if exists caja_mov_pago_unico;

-- Los que ya estaban cerrados por la caja quedan con su valor completo.
-- Los que cerró una reserva se quedan en cero a propósito: ahí no hay
-- nada que repartir, y así no reaparecen en la lista.
update pagos p
   set usado_cop = p.valor_cop
 where p.consumido
   and p.usado_cop = 0
   and exists (select 1 from caja_movimientos m
                where m.pago_id = p.id and not m.anulado);


do $mig$
declare
  v_def   text;
  v_nueva text;
  v_veces int;
  v_fn    text;
  i       int;
  j       int;

  -- función, y luego pares viejo/nuevo
  v_planes constant jsonb := jsonb_build_array(

    jsonb_build_object('fn', 'caja_registrar', 'pares', jsonb_build_array(
      -- 1. Ya no se exige que el valor calce: basta con que quepa.
      jsonb_build_array(
        E'    if v_pago.consumido then\n' ||
        E'      return jsonb_build_object(''ok'', false, ''error'', ''PAGO_YA_USADO'',\n' ||
        E'        ''mensaje'', ''Ese depósito ya se lo adjudicaron. Recarga la lista.'');\n' ||
        E'    end if;\n' ||
        E'    if v_pago.valor_cop <> p_valor then\n' ||
        E'      return jsonb_build_object(''ok'', false, ''error'', ''VALOR_NO_COINCIDE'',\n' ||
        E'        ''mensaje'', ''El depósito es de '' || to_char(v_pago.valor_cop, ''FM999G999G999'') ||\n' ||
        E'                   '' y estás registrando '' || to_char(p_valor, ''FM999G999G999'') || ''.'');\n' ||
        E'    end if;',

        E'    if v_pago.valor_cop - v_pago.usado_cop <= 0 then\n' ||
        E'      return jsonb_build_object(''ok'', false, ''error'', ''PAGO_YA_USADO'',\n' ||
        E'        ''mensaje'', ''Ese depósito ya se lo adjudicaron entero. Recarga la lista.'');\n' ||
        E'    end if;\n' ||
        E'    -- Puede valer menos que el depósito: uno de 30.000 paga dos\n' ||
        E'    -- clases de 15.000. Lo que no puede es pasarse.\n' ||
        E'    if p_valor > v_pago.valor_cop - v_pago.usado_cop then\n' ||
        E'      return jsonb_build_object(''ok'', false, ''error'', ''VALOR_NO_COINCIDE'',\n' ||
        E'        ''mensaje'', ''A ese depósito le quedan '' ||\n' ||
        E'                   to_char(v_pago.valor_cop - v_pago.usado_cop, ''FM999G999G999'') ||\n' ||
        E'                   '' y estás registrando '' || to_char(p_valor, ''FM999G999G999'') || ''.'');\n' ||
        E'    end if;'
      ),
      -- 2. Se apunta lo gastado, y se cierra solo cuando se acabó.
      jsonb_build_array(
        E'    update pagos set consumido = true where id = p_pago_id;',

        E'    update pagos\n' ||
        E'       set usado_cop = usado_cop + p_valor,\n' ||
        E'           -- Se marca consumido apenas se le usa un pedazo: es lo\n' ||
        E'           -- que saca al depósito del cruce automático de reservas,\n' ||
        E'           -- que se lo adjudicaría entero. Lo que le quede se\n' ||
        E'           -- reparte a mano desde la caja.\n' ||
        E'           consumido = true\n' ||
        E'     where id = p_pago_id;'
      )
    )),

    jsonb_build_object('fn', 'caja_anular', 'pares', jsonb_build_array(
      -- Anular devuelve el pedazo, no el depósito entero.
      jsonb_build_array(
        E'    update pagos set consumido = false where id = v_mov.pago_id;',

        E'    update pagos\n' ||
        E'       set usado_cop = greatest(usado_cop - v_mov.valor_cop, 0),\n' ||
        E'           consumido = greatest(usado_cop - v_mov.valor_cop, 0) > 0\n' ||
        E'     where id = v_mov.pago_id;'
      )
    )),

    jsonb_build_object('fn', 'caja_del_dia', 'pares', jsonb_build_array(
      -- Lo que queda libre HOY: el saldo, no el valor completo.
      jsonb_build_array(
        E'         coalesce(sum(valor_cop) filter (where not consumido), 0),\n' ||
        E'         count(*) filter (where not consumido)',

        E'         coalesce(sum(valor_cop - usado_cop)\n' ||
        E'                  filter (where valor_cop > usado_cop and (not consumido or usado_cop > 0)), 0),\n' ||
        E'         count(*) filter (where valor_cop > usado_cop and (not consumido or usado_cop > 0))'
      ),
      -- Lo mismo para la ventana de días atrás.
      jsonb_build_array(
        E'    from pagos where not consumido and fecha_pago >= v_corte;',

        E'    from pagos\n' ||
        E'   where valor_cop > usado_cop and (not consumido or usado_cop > 0)\n' ||
        E'     and fecha_pago >= v_corte;'
      ),
      -- Y la lista que se ve en el modal, con su saldo.
      jsonb_build_array(
        E'       where not p.consumido and p.fecha_pago >= v_corte',

        E'       where p.valor_cop > p.usado_cop\n' ||
        E'         and (not p.consumido or p.usado_cop > 0)\n' ||
        E'         and p.fecha_pago >= v_corte'
      ),
      jsonb_build_array(
        E'               ''remitente'', p.remitente, ''referencia'', p.referencia) as x',

        E'               ''remitente'', p.remitente, ''referencia'', p.referencia,\n' ||
        E'               ''usado_cop'', p.usado_cop,\n' ||
        E'               ''saldo_cop'', p.valor_cop - p.usado_cop) as x'
      )
    ))
  );
begin
  for i in 0 .. jsonb_array_length(v_planes) - 1 loop
    v_fn := v_planes -> i ->> 'fn';

    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;

    if v_def is null then
      raise exception '0039: no existe la función %', v_fn;
    end if;

    if position('usado_cop' in v_def) > 0 then
      raise notice '0039: % ya reparte depósitos, se deja como está', v_fn;
      continue;
    end if;

    v_nueva := v_def;
    for j in 0 .. jsonb_array_length(v_planes -> i -> 'pares') - 1 loop
      declare
        v_viejo text := v_planes -> i -> 'pares' -> j ->> 0;
        v_nuevo text := v_planes -> i -> 'pares' -> j ->> 1;
      begin
        v_veces := (length(v_nueva) - length(replace(v_nueva, v_viejo, '')))
                   / length(v_viejo);
        if v_veces <> 1 then
          raise exception '0039: en % el trozo % aparece % veces, esperaba 1. '
                          'Alguien la cambió; hay que mirarla a mano antes de parchear.',
                          v_fn, j + 1, v_veces;
        end if;
        v_nueva := replace(v_nueva, v_viejo, v_nuevo);
      end;
    end loop;

    execute v_nueva;
    raise notice '0039: % parcheada', v_fn;
  end loop;
end $mig$;
