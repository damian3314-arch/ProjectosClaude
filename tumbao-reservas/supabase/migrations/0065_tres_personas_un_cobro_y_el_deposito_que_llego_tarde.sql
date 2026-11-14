-- ---------------------------------------------------------------------
-- 0065 — Tres personas en un solo cobro, y el depósito que llegó tarde
--
-- Dos cosas distintas que descuadran la misma caja, y por eso van juntas
-- en la misma migración: las dos hacen que un número de la tirilla no
-- signifique lo que dice.
--
-- ── 1. LA CAJA NO SABÍA CUÁNTA GENTE ENTRÓ ──────────────────────────
-- Llegan tres personas juntas y pagan $45.000 en efectivo. La cajera
-- registra UN movimiento de $45.000, porque es un solo cobro. El cierre
-- cuenta UNA persona: `caja_movimientos` no tenía ninguna columna de
-- cantidad, así que la única forma de contar gente era contar filas.
--
-- La plata siempre estuvo bien. Lo que estaba mal era la cuenta de
-- gente, y nadie sabía por qué: el arqueo del efectivo cuadraba y el
-- número de personas no, sin ninguna pista de dónde salía la diferencia.
--
-- El valor no se teclea aparte: es cantidad × precio. Tres clases
-- sueltas son exactamente $45.000. Así monto y cantidad no se pueden
-- contradecir nunca, que es lo que pasaría si fueran dos casillas
-- independientes en la pantalla.
--
-- POR QUÉ `default 1` Y NO NULL
-- Las filas viejas significaban exactamente una cosa cobrada: no hay
-- nada que adivinar ni ningún día que recalcular. Un `not null default 1`
-- las deja diciendo lo que ya decían.
--
-- ── 2. EL PAGO MANUAL Y EL DEPÓSITO QUE LLEGA DESPUÉS ───────────────
-- Este es el que más descuadra. La cajera cobra una mensualidad por
-- transferencia y la registra a mano EN EL MOMENTO, porque la clienta
-- está delante. Segundos u horas después llega la alerta del banco y
-- entra un depósito sin asociar. Nadie los cruza nunca.
--
-- Esa plata queda contada una vez en la Caja y además aparece como
-- «depósito sin dueño» en la tirilla, así que la dueña la persigue a
-- mano todos los días. La 0062 ya nombró el problema —el renglón
-- `sin_enlazar`, "esto hay que buscarlo a mano en el extracto"— pero no
-- daba forma de resolverlo: `caja_registrar` enlaza en el momento de
-- registrar, y a esa hora el depósito todavía no existía.
--
-- `caja_enlazar_deposito` es esa misma operación hecha tarde. El
-- movimiento ya está; lo único que falta es decir con qué línea del
-- extracto se corresponde.
--
-- POR QUÉ NO SE EXIGE QUE LOS VALORES SEAN IDÉNTICOS
-- Se exige que el depósito ALCANCE, no que sea igual. Es literalmente
-- la regla que `caja_registrar` ya aplica desde la 0057: «Puede valer
-- menos que el depósito: uno de 30.000 paga dos clases de 15.000. Lo que
-- no puede es pasarse». Si enlazar fuera más estricto que registrar, la
-- misma pareja de números se aceptaría por un camino y se rechazaría por
-- el otro, y la cajera no tendría cómo saber cuál de los dos miente.
-- Lo que sobra se gasta con `gastar_del_grupo` y queda como saldo del
-- depósito: sigue en la lista de plata sin adjudicar, con lo que de
-- verdad le queda.
--
-- POR QUÉ UN COBRO EN EFECTIVO NO SE PUEDE ENLAZAR
-- No es una regla de formulario: es que no es el mismo dinero. El
-- efectivo entró al cajón y el depósito entró al banco. Enlazarlos haría
-- que el arqueo del cajón y el extracto se contradijeran, que es
-- exactamente el descuadre que se está tratando de cerrar.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- 1. La cantidad
-- ---------------------------------------------------------------------
alter table caja_movimientos
  add column if not exists cantidad int not null default 1;

do $$
begin
  -- `add constraint` no tiene `if not exists`, así que se pregunta. Sin
  -- esto la migración no se podría volver a correr, y aquí se corre dos
  -- veces a propósito para comprobar que es repetible.
  if not exists (select 1 from pg_constraint
                  where conname = 'caja_movimientos_cantidad_ck'
                    and conrelid = 'caja_movimientos'::regclass) then
    alter table caja_movimientos
      add constraint caja_movimientos_cantidad_ck check (cantidad >= 1);
  end if;
end $$;

comment on column caja_movimientos.cantidad is
  'Cuántas cosas cubre este cobro: tres clases sueltas pagadas juntas '
  'son un movimiento con cantidad 3. valor_cop es cantidad x precio, no '
  'se teclea aparte. Las filas anteriores a la 0065 valen 1, que es lo '
  'que significaban.';


-- ---------------------------------------------------------------------
-- 2. caja_registrar acepta la cantidad
--
-- Se parchea el texto de la función VIVA en vez de reescribirla, por lo
-- mismo que la 0039, la 0055, la 0057 y la 0064: producción tiene
-- arreglos que no están en el repositorio y un `create or replace`
-- entero los borraría en silencio.
-- ---------------------------------------------------------------------
do $$
declare
  v_def text;
  c_firma  constant text := 'p_pago_id uuid DEFAULT NULL::uuid)';
  c_decl   constant text := '  v_pago  pagos%rowtype;';
  c_medio  constant text :=
    '  if p_medio not in (''efectivo'', ''transferencia'') then' || E'\n' ||
    '    return jsonb_build_object(''ok'', false, ''error'', ''MEDIO_INVALIDO'');' || E'\n' ||
    '  end if;';
  c_insert constant text :=
    '  insert into caja_movimientos (dia, sentido, concepto, valor_cop, medio,' || E'\n' ||
    '                                nota, registrado_por, pago_id)' || E'\n' ||
    '  values (v_dia, p_sentido, left(coalesce(p_concepto, ''otro''), 40), p_valor,' || E'\n' ||
    '          p_medio, nullif(btrim(coalesce(p_nota, '''')), ''''), v_admin, p_pago_id)';
  c_return constant text :=
    '  return jsonb_build_object(''ok'', true, ''id'', v_id, ''dia'', v_dia,' || E'\n' ||
    '                            ''pago_id'', p_pago_id);';
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_registrar'
     and pg_get_function_identity_arguments(p.oid)
         = 'p_token text, p_sentido text, p_concepto text, p_valor integer,'
        || ' p_medio text, p_nota text, p_pago_id uuid';

  if v_def is null then
    -- Puede que ya esté la de ocho parámetros de una corrida anterior.
    if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname = 'caja_registrar'
                  and pg_get_function_identity_arguments(p.oid) like '%p_cantidad integer') then
      raise notice '0065: caja_registrar ya tenía p_cantidad, no se toca';
      return;
    end if;
    raise exception '0065: no está caja_registrar(text,text,text,int,text,text,uuid)';
  end if;

  -- ── la firma ──────────────────────────────────────────────────────
  -- Va al final y con default, para que una llamada que no la mande
  -- siga funcionando igual. El Worker solo la manda cuando es > 1.
  if position(c_firma in v_def) = 0 then
    raise exception '0065: no encajó el anclaje de la firma de caja_registrar';
  end if;
  v_def := replace(v_def, c_firma,
    'p_pago_id uuid DEFAULT NULL::uuid, p_cantidad integer DEFAULT 1)');

  -- ── la variable ───────────────────────────────────────────────────
  if position(c_decl in v_def) = 0 then
    raise exception '0065: no encajó el anclaje del declare de caja_registrar';
  end if;
  v_def := replace(v_def, c_decl,
    c_decl || E'\n' ||
    '  v_cantidad int;   -- 0065: cuánta gente cubre este cobro');

  -- ── la validación ─────────────────────────────────────────────────
  if position(c_medio in v_def) = 0 then
    raise exception '0065: no encajó el anclaje de MEDIO_INVALIDO';
  end if;
  v_def := replace(v_def, c_medio, c_medio || E'\n\n' || $q$  -- 0065: cuántas cosas cubre este cobro. Null es 1: una llamada
  -- vieja que no manda cantidad significa exactamente lo de siempre.
  v_cantidad := coalesce(p_cantidad, 1);
  if v_cantidad < 1 then
    return jsonb_build_object('ok', false, 'error', 'CANTIDAD_INVALIDA',
      'mensaje', 'La cantidad tiene que ser al menos 1.');
  end if;
  -- El mismo criterio que VALOR_SOSPECHOSO: un tope alto pero real, que
  -- atrapa el dedo pegado al teclear y no estorba a nadie. La clase más
  -- grande tiene treinta cupos.
  if v_cantidad > 50 then
    return jsonb_build_object('ok', false, 'error', 'CANTIDAD_SOSPECHOSA',
      'mensaje', 'Cincuenta personas en un solo cobro no es un cobro, '
                 'es un error de tecleo. Revísalo.');
  end if;$q$);

  -- ── el insert ─────────────────────────────────────────────────────
  if position(c_insert in v_def) = 0 then
    raise exception '0065: no encajó el anclaje del insert de caja_registrar';
  end if;
  v_def := replace(v_def, c_insert,
    '  insert into caja_movimientos (dia, sentido, concepto, valor_cop, medio,' || E'\n' ||
    '                                nota, registrado_por, pago_id, cantidad)' || E'\n' ||
    '  values (v_dia, p_sentido, left(coalesce(p_concepto, ''otro''), 40), p_valor,' || E'\n' ||
    '          p_medio, nullif(btrim(coalesce(p_nota, '''')), ''''), v_admin, p_pago_id,' || E'\n' ||
    '          v_cantidad)');

  -- ── lo que devuelve ───────────────────────────────────────────────
  if position(c_return in v_def) = 0 then
    raise exception '0065: no encajó el anclaje del return de caja_registrar';
  end if;
  v_def := replace(v_def, c_return,
    '  return jsonb_build_object(''ok'', true, ''id'', v_id, ''dia'', v_dia,' || E'\n' ||
    '                            ''pago_id'', p_pago_id,' || E'\n' ||
    '                            ''cantidad'', v_cantidad);');

  if position('0065:' in v_def) = 0 then
    raise exception '0065: el empalme de caja_registrar no dejó la marca';
  end if;
  execute v_def;
  raise notice '0065: caja_registrar parcheada';
end $$;

-- La de siete parámetros se va. Dejarla viva haría la llamada AMBIGUA:
-- PostgREST manda los argumentos por nombre y Postgres no sabría si la
-- de siete o la de ocho con el default. Es lo mismo que hizo la 0027 al
-- añadir p_pago_id.
drop function if exists public.caja_registrar(text, text, text, int, text, text, uuid);

-- La firma cambió, así que los permisos NO viajan: la función nueva
-- nace con execute para PUBLIC. Es justo lo que se perdió en la 0056.
revoke execute on function
  caja_registrar(text, text, text, int, text, text, uuid, int)
  from public, anon, authenticated;
grant  execute on function
  caja_registrar(text, text, text, int, text, text, uuid, int)
  to service_role;


-- ---------------------------------------------------------------------
-- 3. Que el cierre cuente la gente de verdad
--
-- Todo lo que responde «cuántas personas / cuántas cosas» pasa a sumar
-- `cantidad`. Lo que responde «cuántas líneas hay que buscar» se queda
-- contando filas, porque ahí la unidad sí es la fila.
-- ---------------------------------------------------------------------
do $$
declare
  v_def text;

  -- 0059: la cuenta de gente del cierre. El motivo de toda la migración.
  c_personas constant text :=
    '  select (select count(*) from suyas)' || E'\n' ||
    '       + (select count(*) from caja_movimientos m' || E'\n' ||
    '           where m.dia = v_dia and not m.anulado';

  -- 0062: el CTE del que se leen los movimientos de la conciliación.
  c_movs constant text :=
    '    select m.id, m.concepto, m.medio, m.valor_cop, m.pago_id, m.created_at' || E'\n' ||
    '      from caja_movimientos m';

  -- 0061: cuánta gente cubre cada línea del banco.
  c_cobros constant text :=
    '               ''cobros'', case when l.es_parte then 0 else' || E'\n' ||
    '                 (select count(*) from movs m2';

  -- 0064: el `n` de `otros` en el cuadre.
  c_otros constant text :=
    '           (select count(*) from caja_movimientos m' || E'\n' ||
    '             where m.pago_id = u.grupo and m.dia = v_dia' || E'\n' ||
    '               and not m.anulado and m.sentido = ''ingreso'') as cobros';

  -- Las dos casillas de entradas que se leen de la Caja.
  c_ef constant text :=
    '  select coalesce(sum(valor_cop), 0), count(*)' || E'\n' ||
    '    into v_entra_ef, v_entra_ef_n';
  c_tr constant text :=
    '  select coalesce(sum(valor_cop), 0), count(*)' || E'\n' ||
    '    into v_entra_recep_tr, v_entra_recep_tr_n';

  -- El resumen por concepto que se imprime en la tirilla.
  c_resumen constant text :=
    '      select sentido, concepto, medio, count(*) as n, sum(valor_cop) as total' || E'\n' ||
    '        from caja_movimientos';

  -- La lista de movimientos del día.
  c_lista constant text :=
    '           ''quien'', t.nombre, ''con_banco'', m.pago_id is not null)';
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if v_def is null then raise exception '0065: no existe caja_del_dia'; end if;

  if position('0065:' in v_def) > 0 then
    raise notice '0065: caja_del_dia ya estaba parcheada, no se toca';
    return;
  end if;

  -- ── a. la cuenta de gente del cierre (0059) ───────────────────────
  if position(c_personas in v_def) = 0 then
    raise exception '0065: no encajó el anclaje de v_personas_n (bloque 0059)';
  end if;
  v_def := replace(v_def, c_personas,
    '  select (select count(*) from suyas)' || E'\n' ||
    '       -- 0065: tres personas que pagan juntas son UN movimiento y' || E'\n' ||
    '       -- TRES personas. Contar filas decía una, y de ahí salía que' || E'\n' ||
    '       -- la cuenta de gente del día nunca cuadrara con la puerta.' || E'\n' ||
    '       + (select coalesce(sum(m.cantidad), 0) from caja_movimientos m' || E'\n' ||
    '           where m.dia = v_dia and not m.anulado');

  -- ── b. la conciliación necesita la cantidad a mano (0062) ─────────
  if position(c_movs in v_def) = 0 then
    raise exception '0065: no encajó el anclaje del CTE movs (bloque 0062)';
  end if;
  v_def := replace(v_def, c_movs,
    '    select m.id, m.concepto, m.medio, m.valor_cop, m.pago_id, m.created_at,' || E'\n' ||
    '           -- 0065: cuánta gente cubre cada cobro.' || E'\n' ||
    '           m.cantidad' || E'\n' ||
    '      from caja_movimientos m');

  -- ── c. cuánta gente cubre cada línea del banco (0061) ─────────────
  if position(c_cobros in v_def) = 0 then
    raise exception '0065: no encajó el anclaje de cobros (bloque 0061)';
  end if;
  v_def := replace(v_def, c_cobros,
    '               ''cobros'', case when l.es_parte then 0 else' || E'\n' ||
    '                 -- 0065: se suma la cantidad, no las filas. La 0061' || E'\n' ||
    '                 -- existe para que `para` + `cobros` de todas las' || E'\n' ||
    '                 -- líneas dé exactamente personas_n; si allá se' || E'\n' ||
    '                 -- cuentan personas y aquí líneas, los dos papeles' || E'\n' ||
    '                 -- del mismo día vuelven a contradecirse.' || E'\n' ||
    '                 (select coalesce(sum(m2.cantidad), 0) from movs m2');

  -- ── d. el `n` de `otros` en el cuadre (0064) ──────────────────────
  if position(c_otros in v_def) = 0 then
    raise exception '0065: no encajó el anclaje de otros_dep (bloque 0064)';
  end if;
  v_def := replace(v_def, c_otros,
    '           -- 0065: `n` dice cuántas cosas se cobraron, no cuántas' || E'\n' ||
    '           -- veces se tecleó: dos mensualidades en un solo cobro' || E'\n' ||
    '           -- son dos, y así lo lee quien tacha el extracto.' || E'\n' ||
    '           (select coalesce(sum(m.cantidad), 0) from caja_movimientos m' || E'\n' ||
    '             where m.pago_id = u.grupo and m.dia = v_dia' || E'\n' ||
    '               and not m.anulado and m.sentido = ''ingreso'') as cobros');

  -- ── e. las dos casillas de entradas que salen de la Caja ──────────
  -- Estas son las que la 0059 dejó de sumar para contar gente, pero
  -- siguen imprimiéndose con su propio `_n` al lado de la plata. Un
  -- «1 · $45.000» junto a un «personas: 3» es la misma contradicción de
  -- antes escrita más pequeño. La plata no se toca: sum(valor_cop) ya
  -- era correcta, porque el valor es cantidad × precio.
  if position(c_ef in v_def) = 0 then
    raise exception '0065: no encajó el anclaje de v_entra_ef_n';
  end if;
  v_def := replace(v_def, c_ef,
    '  select coalesce(sum(valor_cop), 0), coalesce(sum(cantidad), 0)  -- 0065' || E'\n' ||
    '    into v_entra_ef, v_entra_ef_n');

  if position(c_tr in v_def) = 0 then
    raise exception '0065: no encajó el anclaje de v_entra_recep_tr_n';
  end if;
  v_def := replace(v_def, c_tr,
    '  select coalesce(sum(valor_cop), 0), coalesce(sum(cantidad), 0)  -- 0065' || E'\n' ||
    '    into v_entra_recep_tr, v_entra_recep_tr_n');

  -- ── f. el resumen por concepto de la tirilla ──────────────────────
  -- «clase_suelta · efectivo · 1 · $45.000» no se puede leer en voz
  -- alta sin equivocarse. Son tres a quince mil.
  if position(c_resumen in v_def) = 0 then
    raise exception '0065: no encajó el anclaje del resumen por concepto';
  end if;
  v_def := replace(v_def, c_resumen,
    '      select sentido, concepto, medio, sum(cantidad) as n,  -- 0065' || E'\n' ||
    '             sum(valor_cop) as total' || E'\n' ||
    '        from caja_movimientos');

  -- ── g. la lista del día dice cuántos cubre cada línea ─────────────
  if position(c_lista in v_def) = 0 then
    raise exception '0065: no encajó el anclaje de la lista de movimientos';
  end if;
  v_def := replace(v_def, c_lista,
    '           ''quien'', t.nombre, ''con_banco'', m.pago_id is not null,' || E'\n' ||
    '           -- 0065: para poder escribir «3 x clase suelta» en vez de' || E'\n' ||
    '           -- una línea de $45.000 que no dice a cuántos cubrió.' || E'\n' ||
    '           ''cantidad'', m.cantidad)');

  if position('0065:' in v_def) = 0 then
    raise exception '0065: el empalme de caja_del_dia no dejó la marca';
  end if;
  execute v_def;
  raise notice '0065: caja_del_dia parcheada';
end $$;

-- La firma no cambió, así que los permisos siguen puestos. Se reafirman
-- igual, que es lo que se echó de menos en la 0056.
revoke execute on function caja_del_dia(text, date)
  from public, anon, authenticated;
grant  execute on function caja_del_dia(text, date) to service_role;


-- ---------------------------------------------------------------------
-- 4. caja_enlazar_deposito — el depósito que llegó tarde
--
-- La cajera ya registró el cobro. Después llegó la alerta del banco.
-- Esto es lo único que faltaba: decir que son la misma plata.
-- ---------------------------------------------------------------------
create or replace function caja_enlazar_deposito(
  p_token  text,
  p_mov_id uuid,
  p_pago_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_admin uuid;
  v_mov   caja_movimientos;
  v_pago  pagos%rowtype;
  v_saldo int;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  -- ── el movimiento ─────────────────────────────────────────────────
  select * into v_mov from caja_movimientos where id = p_mov_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'MOV_NO_EXISTE',
      'mensaje', 'No se encuentra ese movimiento. Recarga la caja del día.');
  end if;

  if v_mov.anulado then
    return jsonb_build_object('ok', false, 'error', 'MOV_ANULADO',
      'mensaje', 'Ese movimiento está anulado, así que no cobró nada. '
                 'Regístralo otra vez y enlázalo entonces.');
  end if;

  -- Mismo límite que `caja_anular`: lo de otro día ya se imprimió y se
  -- cerró. Un enlace movería el «sin identificar» de una tirilla que ya
  -- está firmada.
  if v_mov.dia <> (now() at time zone 'America/Bogota')::date then
    return jsonb_build_object('ok', false, 'error', 'OTRO_DIA',
      'mensaje', 'Solo se pueden enlazar movimientos de hoy.');
  end if;
  if exists (select 1 from caja_cierres where dia = v_mov.dia) then
    return jsonb_build_object('ok', false, 'error', 'DIA_CERRADO',
      'mensaje', 'El día ya está cerrado. Este enlace va mañana.');
  end if;

  -- Un egreso es plata que SALE. El banco reportando una entrada no
  -- puede ser el mismo hecho.
  if v_mov.sentido <> 'ingreso' then
    return jsonb_build_object('ok', false, 'error', 'NO_ES_INGRESO',
      'mensaje', 'Ese movimiento es un egreso: es plata que salió, no '
                 'un cobro que el banco pueda haber recibido.');
  end if;

  if v_mov.pago_id is not null then
    return jsonb_build_object('ok', false, 'error', 'YA_ENLAZADO',
      'mensaje', 'Ese cobro ya tiene su depósito enlazado. Si el que '
                 'tiene no es el correcto, anula el movimiento y '
                 'vuelve a registrarlo con el bueno.',
      'pago_id', v_mov.pago_id);
  end if;

  -- El freno que de verdad protege el arqueo. No es una regla de
  -- formulario: el efectivo entró al cajón y el depósito entró al
  -- banco, así que no hay forma de que sean la misma plata.
  if v_mov.medio <> 'transferencia' then
    return jsonb_build_object('ok', false, 'error', 'ES_EFECTIVO',
      'mensaje', 'Ese cobro se registró en efectivo: esa plata está en '
                 'el cajón, no en el banco, así que no puede ser esta '
                 'transferencia. No es el mismo dinero. Si de verdad '
                 'fue transferencia, anula el movimiento y regístralo '
                 'otra vez como transferencia.');
  end if;

  -- ── el depósito ───────────────────────────────────────────────────
  select * into v_pago from pagos where id = p_pago_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'PAGO_NO_EXISTE',
      'mensaje', 'No se encuentra ese depósito. Recarga la lista.');
  end if;

  -- `pagos_sin_asignar` (0057) es la ÚNICA lista de «plata sin dueño»
  -- que ve la cajera, así que es la que decide qué se puede enlazar.
  -- De un golpe deja fuera lo que ya se gastó entero, lo que se le
  -- adjudicó a una reserva (queda `consumido` con usado_cop en cero) y
  -- las partes de un grupo, que se enlazan por su cabeza. Preguntarlo
  -- con tres condiciones sueltas aquí sería una cuarta forma de decir
  -- lo mismo, y tarde o temprano diría algo distinto.
  if not exists (select 1 from pagos_sin_asignar where id = p_pago_id) then
    return jsonb_build_object('ok', false, 'error', 'PAGO_YA_USADO',
      'mensaje', 'Ese depósito ya tiene dueño: se lo adjudicaron a una '
                 'reserva, ya se cobró entero, o es parte de un grupo. '
                 'Recarga la lista.');
  end if;

  -- ── que la plata alcance ──────────────────────────────────────────
  -- Exactamente la regla de `caja_registrar` desde la 0057: el depósito
  -- puede ser MAYOR y quedar con saldo —uno de $30.000 paga dos clases
  -- de $15.000— pero no puede quedarse corto. Si enlazar fuera más
  -- estricto que registrar, la misma pareja de números se aceptaría por
  -- un camino y se rechazaría por el otro.
  v_saldo := saldo_grupo(p_pago_id);
  if v_saldo < v_mov.valor_cop then
    return jsonb_build_object('ok', false, 'error', 'VALORES_DISTINTOS',
      'movimiento_cop', v_mov.valor_cop,
      'deposito_cop',   v_saldo,
      'mensaje', 'El cobro es de ' ||
                 to_char(v_mov.valor_cop, 'FM999G999G999') ||
                 ' y a ese depósito solo le quedan ' ||
                 to_char(v_saldo, 'FM999G999G999') ||
                 '. No alcanza, así que no son el mismo pago.');
  end if;

  -- ── enlazar ───────────────────────────────────────────────────────
  update caja_movimientos set pago_id = p_pago_id where id = p_mov_id;

  -- Igual que `caja_registrar`: se gasta del grupo, en el orden en que
  -- el banco recibió las partes. Deja el depósito fuera del cruce
  -- automático de reservas y, si sobra, con su saldo a la vista. Y
  -- `caja_anular` ya sabe deshacer esto: devuelve al grupo y suelta el
  -- pago_id, así que enlazar mal no es un camino sin regreso.
  perform gastar_del_grupo(p_pago_id, v_mov.valor_cop);

  return jsonb_build_object(
    'ok', true,
    'mov_id', p_mov_id,
    'pago_id', p_pago_id,
    'concepto', v_mov.concepto,
    'valor_cop', v_mov.valor_cop,
    -- Lo que le queda al depósito después de este cobro. Cero es el
    -- caso normal; si sobra, esa plata sigue sin dueño y hay que
    -- decirlo, no esconderlo.
    'sobrante_cop', saldo_grupo(p_pago_id));
end;
$$;

comment on function caja_enlazar_deposito(text, uuid, uuid) is
  'Enlaza un movimiento de caja ya registrado con el depósito del banco '
  'que llegó después. Es caja_registrar hecho tarde: mismas reglas de '
  'saldo, y caja_anular lo deshace.';

revoke execute on function caja_enlazar_deposito(text, uuid, uuid)
  from public, anon, authenticated;
grant  execute on function caja_enlazar_deposito(text, uuid, uuid)
  to service_role;
