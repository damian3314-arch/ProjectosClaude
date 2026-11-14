-- ---------------------------------------------------------------------
-- 0059 — Cuánta gente entró de verdad a clase suelta
--
-- EL CASO, DEL 28 DE AGOSTO
-- El cierre decía 10 personas a clase suelta. En el cuaderno de la
-- puerta había 11. Faltaba Julieth Herrera (3RMVH4): entró a las 18:29,
-- con la asistencia marcada, usando el crédito de una clase del 27 que
-- había reprogramado.
--
-- POR QUÉ NO SE CONTABA
-- El conteo de personas se armaba sumando las cuatro casillas de DINERO
-- (efectivo, transferencia de recepción, página, apuntados a mano). Y
-- una reprogramada no cae en ninguna, por una razón buena: su plata no
-- entró hoy, entró el día que pagó. La casilla de la página lo dice
-- explícitamente en su comentario:
--
--   "Se nombran los dos origenes de la pagina en vez de 'todo lo que no
--    sea recepcion', para que 'reprogramada' —que no es plata que entro
--    hoy— no se cuele aqui el dia que traiga pago."
--
-- O sea: la exclusión es CORRECTA para el dinero y EQUIVOCADA para la
-- gente. La causa de fondo es que una misma consulta contestaba dos
-- preguntas distintas, y para una reprogramada las respuestas son
-- diferentes: cero pesos, una persona.
--
-- LO QUE HACE
-- Deja el dinero exactamente como está —ni un peso se mueve, las cuatro
-- casillas no se tocan— y añade un conteo de PERSONAS aparte, con su
-- propia regla, que es simple de decir en voz alta:
--
--   toda reserva de clase suelta confirmada cuya clase es de ese día y
--   que no se haya movido a otra fecha,
--   más los cobros de clase suelta vivos en caja que no correspondan a
--   ninguna de esas reservas (el que llega y paga en la puerta).
--
-- NO SE SUMAN LAS CASILLAS PORQUE YA FALLARON TRES VECES
-- Sumarlas dejaba fuera, además de las reprogramadas:
--
--   · a quien se le anuló el cobro y se volvió a cobrar bien: la casilla
--     "a mano" exige cobro_mov_id nulo y las de caja exigen no anulado,
--     así que se caía por el hueco entre las dos (JENNY PAOLA, 20/08);
--   · a quien se confirmó a mano sin enlazar depósito: la casilla de la
--     página exige pago_id, y esa persona no es de recepción, así que no
--     tenía casilla (tres personas el 27/08).
--
-- La regla nueva los recoge a todos sin nombrarlos: no pregunta CÓMO
-- pagaron, pregunta si entraron.
--
-- POR QUÉ `reprogramada_a is null`
-- La reserva original se queda confirmada y con su pago el día viejo. Si
-- no se excluyera, quien movió su clase contaría dos veces: una el día
-- que ya no fue y otra el día que sí fue. Con Sandra Castellanos y Alba
-- Camacho el original y la reprogramada caen el MISMO día, así que sin
-- esto se contarían dos veces en la misma tirilla.
--
-- EFECTO COMPROBADO SOBRE DÍAS REALES
--   26/08: 18 personas   27/08: 17 (antes 14)   28/08: 11 (antes 10)
-- ---------------------------------------------------------------------

do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if v_def is null then raise exception 'no existe caja_del_dia'; end if;

  if position('0059:' in v_def) > 0 then
    raise notice '0059: ya estaba aplicada';
    return;
  end if;

  v_def := replace(v_def,
    '  v_a_mano int; v_a_mano_n int;',
    '  v_a_mano int; v_a_mano_n int;' || E'\n' ||
    '  v_personas_n int;   -- 0059: la cuenta de gente, aparte de la de plata');

  v_def := replace(v_def,
    '  select coalesce(sum(c4.precio_cop), 0), count(*)' || E'\n' ||
    '    into v_a_mano, v_a_mano_n',
    '  -- 0059: cuanta GENTE entro a clase suelta. No se suman las' || E'\n' ||
    '  -- casillas de dinero: una reprogramada, un cobro anulado y' || E'\n' ||
    '  -- rehecho, o alguien confirmado a mano sin deposito enlazado se' || E'\n' ||
    '  -- caen por los huecos entre ellas. Esta pregunta es otra: no' || E'\n' ||
    '  -- COMO pagaron, sino si entraron.' || E'\n' ||
    '  with suyas as (' || E'\n' ||
    '    select r.id, r.pago_id' || E'\n' ||
    '      from reservas r join clases c on c.id = r.clase_id' || E'\n' ||
    '     where r.estado = ''confirmada'' and r.tipo = ''suelta''' || E'\n' ||
    '       -- La que se movio a otra fecha no entro este dia: su' || E'\n' ||
    '       -- reprogramada ya la cuenta el dia que si vino.' || E'\n' ||
    '       and r.reprogramada_a is null' || E'\n' ||
    '       and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia)' || E'\n' ||
    '  select (select count(*) from suyas)' || E'\n' ||
    '       + (select count(*) from caja_movimientos m' || E'\n' ||
    '           where m.dia = v_dia and not m.anulado' || E'\n' ||
    '             and m.sentido = ''ingreso'' and m.concepto = ''clase_suelta''' || E'\n' ||
    '             -- El que llega y paga en la puerta sin apuntarse. Si el' || E'\n' ||
    '             -- cobro corresponde al deposito de una reserva de arriba,' || E'\n' ||
    '             -- es la misma persona y no se cuenta dos veces.' || E'\n' ||
    '             and not exists (select 1 from suyas s' || E'\n' ||
    '                              where s.pago_id is not null' || E'\n' ||
    '                                and s.pago_id = m.pago_id))' || E'\n' ||
    '    into v_personas_n;' || E'\n\n' ||
    '  select coalesce(sum(c4.precio_cop), 0), count(*)' || E'\n' ||
    '    into v_a_mano, v_a_mano_n');

  v_def := replace(v_def,
    '      ''a_mano_cop'', v_a_mano, ''a_mano_n'', v_a_mano_n' || E'\n' ||
    '    ),',
    '      ''a_mano_cop'', v_a_mano, ''a_mano_n'', v_a_mano_n,' || E'\n' ||
    '      -- 0059: la cuenta buena de personas. Las cuatro casillas de' || E'\n' ||
    '      -- arriba siguen siendo las del dinero y no se tocaron.' || E'\n' ||
    '      ''personas_n'', v_personas_n' || E'\n' ||
    '    ),');

  if position('0059:' in v_def) = 0 then
    raise exception '0059: los anclajes no encajaron';
  end if;
  execute v_def;
  raise notice '0059: caja_del_dia parcheada';
end $$;
