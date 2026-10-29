-- ---------------------------------------------------------------------
-- 0038 — La caja del día es la plata del día
--
-- EL PROBLEMA, MEDIDO
-- El 11 de agosto la tirilla dijo "Reservas de la página: $45.000".
-- Ese día entraron $135.000 en reservas: nueve personas pagaron. La
-- caja contó tres.
--
-- ¿Por qué? Porque contaba las reservas por la fecha de la CLASE, no
-- por cuándo entró la plata. Las otras seis pagaron el 11 una clase del
-- 12 y del 15, así que su plata se fue a contar esos días.
--
-- Eso vuelve el cierre imposible de cuadrar: el banco dice una cosa, la
-- caja dice otra, y no hay forma de saber cuál está mal porque están
-- midiendo días distintos. Al entrar al panel no se entiende nada, y
-- con razón.
--
-- LO QUE CAMBIA
-- Una reserva entra en la caja del día en que ENTRÓ SU PLATA:
--
--   · con depósito del banco  ->  la fecha del depósito (pagos.fecha_pago)
--   · confirmada a mano       ->  cuándo se confirmó (reservas.created_at)
--
-- Es la misma fecha con la que ya se cuenta `banco.recibido_cop`, así
-- que por primera vez las dos mitades del panel hablan del mismo día.
--
-- Si alguien paga hoy la clase del sábado, esa plata es de hoy: hoy
-- llegó al banco y hoy hay que cuadrarla. El sábado ya está cobrada.
--
-- LO QUE NO CAMBIA
-- Nada de la plata en efectivo. Lo que se recibe en la puerta entra por
-- `caja_movimientos` y se sigue contando igual, el mismo día en que se
-- registra. Esta migración no toca un solo movimiento de caja.
--
-- Tampoco hay doble conteo que arreglar, aunque lo parecía: se revisó
-- pago por pago del 10 al 14 de agosto y ninguno está pegado a la vez a
-- una reserva y a un movimiento de caja. Los `clase_suelta` de caja son
-- clases sueltas registradas a mano —plata distinta de las reservas de
-- la web— y se siguen sumando como siempre.
--
-- LO QUE SE AÑADE
-- `reservas_dictadas_cop`: lo que valen las clases que se dictaron ese
-- día, que era el número viejo. Sigue sirviendo —para saber cuánto
-- valió la operación del día— pero ya no se mezcla con la plata.
--
-- LOS CIERRES YA FIRMADOS NO SE TOCAN. Esta migración no escribe en
-- `caja_cierres`. Lo que ya se firmó se firmó con el criterio de
-- entonces; el cambio aplica de aquí en adelante.
--
-- POR QUÉ SE PARCHEA EL TEXTO
-- Lo mismo que en la 0037, y aquí con más razón: `caja_del_dia` ya fue
-- arreglada una vez en producción desde otra sesión —un doble conteo de
-- plata— y ese arreglo no está en el repositorio. Reemplazarla entera
-- lo borraría en silencio y el cierre volvería a inflarse sin que nadie
-- se entere hasta que un cuadre no dé. Ver `aplicar/LEEME-ANTES-DE-PEGAR.md`.
--
-- Así que se toma el texto que de verdad está en la base y se cambian
-- cuatro trozos exactos. Si alguno no aparece exactamente una vez, la
-- migración revienta en vez de aplicar algo a medias.
-- ---------------------------------------------------------------------

do $mig$
declare
  v_def   text;
  v_nueva text;
  v_veces int;
  i       int;

  -- viejo -> nuevo, en pares
  v_pares constant text[][] := array[

    -- 1. Dos variables nuevas para el número informativo.
    [
      '  v_res_mano int; v_res_mano_n int;',
      '  v_res_mano int; v_res_mano_n int;' || E'\n' ||
      '  v_reservas_n int;' || E'\n' ||
      '  v_res_dictadas int; v_res_dictadas_n int;'
    ],

    -- 2. Las reservas con depósito: por la fecha del depósito, no la de
    --    la clase. Y de paso se calcula el número viejo aparte.
    [
      '  select coalesce(sum(c.precio_cop), 0) into v_reservas'         || E'\n' ||
      '    from reservas r join clases c on c.id = r.clase_id'          || E'\n' ||
      '   where r.estado = ''confirmada'' and r.tipo = ''suelta'''      || E'\n' ||
      '     and r.pago_id is not null'                                  || E'\n' ||
      '     and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia;',

      '  select coalesce(sum(c.precio_cop), 0), count(*)'               || E'\n' ||
      '    into v_reservas, v_reservas_n'                               || E'\n' ||
      '    from reservas r'                                             || E'\n' ||
      '    join clases c on c.id = r.clase_id'                          || E'\n' ||
      '    left join pagos p on p.id = r.pago_id'                       || E'\n' ||
      '   where r.estado = ''confirmada'' and r.tipo = ''suelta'''      || E'\n' ||
      '     and r.pago_id is not null'                                  || E'\n' ||
      '     and (coalesce(p.fecha_pago, r.created_at)'                  || E'\n' ||
      '            at time zone ''America/Bogota'')::date = v_dia;'     || E'\n' ||
      ''                                                                || E'\n' ||
      '  -- Lo que valen las clases dictadas hoy. Ya no es plata del'    || E'\n' ||
      '  -- día: es cuánto valió la operación. Va aparte a propósito.'   || E'\n' ||
      '  select coalesce(sum(c.precio_cop), 0), count(*)'               || E'\n' ||
      '    into v_res_dictadas, v_res_dictadas_n'                       || E'\n' ||
      '    from reservas r join clases c on c.id = r.clase_id'          || E'\n' ||
      '   where r.estado = ''confirmada'' and r.tipo = ''suelta'''      || E'\n' ||
      '     and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia;'
    ],

    -- 3. Las confirmadas a mano: cuándo se confirmaron.
    [
      '     and r.pago_id is null'                                      || E'\n' ||
      '     and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia;',

      '     and r.pago_id is null'                                      || E'\n' ||
      '     and (r.created_at at time zone ''America/Bogota'')::date = v_dia;'
    ],

    -- 4. Sacar el número nuevo por la respuesta.
    [
      '    ''reservas_a_mano_n'',   v_res_mano_n,',

      '    ''reservas_a_mano_n'',   v_res_mano_n,'                      || E'\n' ||
      '    ''reservas_n'',            v_reservas_n,'                    || E'\n' ||
      '    ''reservas_dictadas_cop'', v_res_dictadas,'                  || E'\n' ||
      '    ''reservas_dictadas_n'',   v_res_dictadas_n,'
    ]
  ];
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';

  if v_def is null then
    raise exception '0038: no existe caja_del_dia';
  end if;

  -- Idempotente: si ya se aplicó, no hay nada que hacer.
  if position('v_res_dictadas' in v_def) > 0 then
    raise notice '0038: caja_del_dia ya cuenta por la fecha del pago, se deja como está';
    return;
  end if;

  v_nueva := v_def;
  for i in 1 .. array_length(v_pares, 1) loop
    v_veces := (length(v_nueva) - length(replace(v_nueva, v_pares[i][1], '')))
               / length(v_pares[i][1]);
    if v_veces <> 1 then
      raise exception '0038: el trozo % aparece % veces en caja_del_dia, esperaba 1. '
                      'Alguien la cambió; hay que mirarla a mano antes de parchear.',
                      i, v_veces;
    end if;
    v_nueva := replace(v_nueva, v_pares[i][1], v_pares[i][2]);
  end loop;

  execute v_nueva;
  raise notice '0038: caja_del_dia parcheada — la caja del día ya es la plata del día';
end $mig$;
