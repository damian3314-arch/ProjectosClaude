-- ---------------------------------------------------------------------
-- 0064 — Lo que entró por la puerta no es lo que entró al banco
--
-- LO QUE PASÓ EL SÁBADO 29 DE AGOSTO
-- La tirilla decía, una debajo de la otra:
--
--     Entradas del día:        $360.000
--     Bancolombia reportó hoy: $195.000
--
-- Y no hay error en ninguna de las dos. De las 21 personas que
-- entraron ese sábado, 16 habían pagado días antes: su plata está en
-- el extracto de otro día, no en el de hoy. Y al revés, parte de lo
-- que sí entró al banco ese sábado es de clases que todavía no se han
-- dictado. Son dos cosas distintas puestas una encima de otra, y sin
-- un puente entre ellas el cuadre no da nunca — se resta y sale una
-- diferencia que no significa nada.
--
-- LO QUE ELLA QUIERE PODER DECIR
-- «Hoy al banco entró un millón, y son cinco clases de hoy más cinco
-- futuras más dos mensualidades.» Eso es el bloque `cuadre`: por un
-- lado, de los que entraron, cuántos traían la plata de antes; por
-- otro, de lo que reportó el banco hoy, qué era cada peso.
--
-- POR QUÉ CUPOS Y DEPÓSITOS VAN SEPARADOS EN LAS FUTURAS
-- Tres amigas que reservan la clase del sábado próximo con un solo
-- depósito de $45.000 son TRES cupos y UNA línea del extracto. Si el
-- papel dijera solo «3 futuras» habría que buscar tres renglones que
-- no existen; si dijera solo «1», parecería que va una sola persona.
-- Se dicen los dos números.
--
-- POR QUÉ LAS MENSUALIDADES NO SON «FUTURAS»
-- Una mensualidad también paga clases que no se han dictado, pero no
-- tiene cupo ni fecha: no se puede buscar «la clase» de una
-- mensualidad. Va en su propio renglón, junto a lo demás que se cobra
-- en la Caja, y el criterio para saber de qué fue cada depósito es
-- exactamente el de la 0062 — el cruce contra `caja_movimientos`. Que
-- las dos mitades de la misma tirilla clasificaran distinto el mismo
-- dinero sería peor que no tener el bloque.
--
-- LO QUE NO SE PUEDE EXPLICAR SE DICE, NO SE ESCONDE
-- `sin_identificar_cop` es lo que reportó el banco menos lo que este
-- bloque supo nombrar. No es un error: casi siempre son depósitos que
-- todavía no se han adjudicado a nadie. Pero es la cifra que dice
-- cuánto trabajo queda, y se calcula por resta contra el mismo
-- `recibido_cop` que ya se imprime como «Entró al banco» — no se
-- recalcula aparte, porque dos formas de contar el extracto en el
-- mismo papel es justo lo que se está tratando de arreglar.
-- ---------------------------------------------------------------------

do $$
declare
  v_def text;
  v_ini int;
  c_dec constant text := '  c_dias constant int := 20;';
  c_ret constant text := E'\n  return jsonb_build_object(\n';
  c_key constant text := '    ''conciliacion'', v_concilia,';
  v_nuevo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if v_def is null then raise exception '0064: no existe caja_del_dia'; end if;

  if position('0064:' in v_def) > 0 then
    raise notice '0064 ya estaba puesta, no se toca';
    return;
  end if;

  -- Se empalma por marcadores sobre la definición VIVA: producción
  -- tiene arreglos que no están en el repo y reescribir la función
  -- entera los borraría. Si un anclaje no aparece se falla: parchear a
  -- ciegas una función de caja es peor que no parchearla.

  -- ── 1. la variable ────────────────────────────────────────────────
  v_ini := position(c_dec in v_def);
  if v_ini = 0 then
    raise exception '0064: no se encontró dónde declarar v_cuadre';
  end if;
  v_nuevo := '  v_cuadre jsonb;    -- 0064: el puente entre la puerta y el banco'
             || E'\n';
  v_def := left(v_def, v_ini - 1) || v_nuevo || substr(v_def, v_ini);

  -- ── 2. el cálculo ─────────────────────────────────────────────────
  -- Va justo antes del return, y no junto al bloque de la 0062, porque
  -- necesita v_recibido: el total del extracto ya lo calcula la
  -- función más abajo y aquí se reutiliza tal cual.
  v_ini := position(c_ret in v_def);
  if v_ini = 0 then
    raise exception '0064: no se encontró dónde calcular el cuadre';
  end if;
  v_ini := v_ini + 1;   -- después del salto de línea, antes del return

  v_nuevo := $q$  -- 0064: el puente entre lo que entró por la puerta y lo que
  -- entró al banco. Son dos plata distintas: la de la puerta la
  -- pagaron muchos días antes, y la del banco paga clases que aún no
  -- se dictan.
  with entraron as (
    -- Los mismos de la 0059/0060, palabra por palabra: si esta mitad
    -- de la tirilla contara distinto que la otra, el papel se
    -- contradiría solo.
    select r.id,
           coalesce(r.pago_id,
             (select x.pago_id from reservas x
               where x.grupo_id = r.grupo_id and x.pago_id is not null
               limit 1)) as pago
      from reservas r join clases c on c.id = r.clase_id
     where r.estado = 'confirmada' and r.tipo = 'suelta'
       and r.reprogramada_a is null
       and (c.fecha_hora at time zone 'America/Bogota')::date = v_dia),
  con_pago as (
    select e.id, (p.fecha_pago at time zone 'America/Bogota')::date as dia_pago
      from entraron e left join pagos p on p.id = e.pago),
  quien as (
    select count(*)::int as personas,
           count(*) filter (where dia_pago < v_dia)::int  as antes,
           count(*) filter (where dia_pago = v_dia)::int  as hoy,
           count(*) filter (where dia_pago is null)::int  as sin_dep
      from con_pago),
  -- Todo lo que el banco reportó hoy, renglón por renglón. Sin filtrar
  -- los juntados de la 0057: un pago que llegó en dos transferencias
  -- son dos renglones del extracto y las dos hay que explicarlas.
  pagos_dia as (
    select p.id, p.valor_cop, coalesce(p.fusionado_en, p.id) as grupo
      from pagos p
     where (p.fecha_pago at time zone 'America/Bogota')::date = v_dia),
  cupos as (
    select coalesce(r.pago_id,
             (select x.pago_id from reservas x
               where x.grupo_id = r.grupo_id and x.pago_id is not null
               limit 1)) as pago,
           (c.fecha_hora at time zone 'America/Bogota')::date as dia_clase
      from reservas r join clases c on c.id = r.clase_id
     where r.estado = 'confirmada' and r.tipo = 'suelta'
       and r.reprogramada_a is null),
  -- Un depósito, una fila: aunque haya llegado partido, la plata se
  -- clasifica una sola vez. La fecha es la de la clase más cercana que
  -- sostiene — si un mismo depósito paga hoy y el sábado que viene,
  -- manda hoy, que es lo que la dueña tiene delante.
  uso as (
    select pd.grupo,
           sum(pd.valor_cop)::int as cop,
           (select min(k.dia_clase) from cupos k where k.pago = pd.grupo)
             as dia_clase,
           (select count(*) from cupos k
             where k.pago = pd.grupo and k.dia_clase > v_dia)::int
             as cupos_futuros
      from pagos_dia pd
     group by pd.grupo),
  -- Lo que entró al banco y no paga ninguna clase: de qué fue se
  -- averigua con el MISMO cruce de la 0062 contra la Caja. Cuando un
  -- depósito cubre varias cosas manda el concepto que más plata
  -- explica, para no partir un renglón del extracto en dos.
  otros_dep as (
    select u.grupo, u.cop,
           (select m.concepto from caja_movimientos m
             where m.pago_id = u.grupo and m.dia = v_dia
               and not m.anulado and m.sentido = 'ingreso'
             order by m.valor_cop desc, m.concepto limit 1) as concepto,
           (select count(*) from caja_movimientos m
             where m.pago_id = u.grupo and m.dia = v_dia
               and not m.anulado and m.sentido = 'ingreso') as cobros
      from uso u
     where u.dia_clase is null),
  otros as (
    select o.concepto, sum(o.cobros)::int as n, sum(o.cop)::int as cop
      from otros_dep o
     where o.concepto is not null
     group by o.concepto),
  tot as (
    select
      coalesce((select sum(u.cop) from uso u where u.dia_clase = v_dia), 0)::int
        as hoy_cop,
      coalesce((select sum(u.cop) from uso u where u.dia_clase > v_dia), 0)::int
        as fut_cop,
      coalesce((select count(*) from uso u where u.dia_clase > v_dia), 0)::int
        as fut_dep,
      coalesce((select sum(u.cupos_futuros) from uso u
                 where u.dia_clase > v_dia), 0)::int as fut_cupos,
      coalesce((select sum(o.cop) from otros o), 0)::int as otros_cop)
  select jsonb_build_object(
    -- De los que cruzaron la puerta hoy, cuántos traían la plata de
    -- otro día. Es la mitad que explica por qué las dos cifras de
    -- arriba de la tirilla nunca se van a parecer.
    'quien_entro', jsonb_build_object(
      'personas',        q.personas,
      'pagaron_antes',   q.antes,
      'pagaron_hoy',     q.hoy,
      'pagaron_hoy_cop', t.hoy_cop,
      'sin_deposito',    q.sin_dep),
    -- Y de lo que el banco reportó hoy, qué era cada peso.
    'entro_al_banco', jsonb_build_object(
      -- Los cupos de hoy pagados hoy: es la misma cuenta de
      -- `pagaron_hoy`, no otra, y la plata también se cuenta una sola
      -- vez (por depósito, no por persona: dos amigas con un solo
      -- depósito de $30.000 son una línea del extracto).
      'clases_hoy_n',   q.hoy,
      'clases_hoy_cop', t.hoy_cop,
      -- Cupos y depósitos aparte: tres amigas con un solo pago son
      -- tres sillas del sábado que viene y UN renglón que buscar.
      'futuras_cupos',     t.fut_cupos,
      'futuras_depositos', t.fut_dep,
      'futuras_cop',       t.fut_cop,
      -- Mensualidades y demás: pagan clases sin dictar, pero no tienen
      -- cupo ni fecha que buscar, así que no son "futuras".
      'otros', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'concepto', o.concepto, 'n', o.n, 'cop', o.cop)
               order by o.cop desc, o.concepto)
          from otros o), '[]'::jsonb),
      'otros_cop', t.otros_cop,
      'identificado_cop', t.hoy_cop + t.fut_cop + t.otros_cop,
      -- El mismo número que se imprime arriba como "Entró al banco".
      'reporto_banco_cop', v_recibido,
      -- Por resta contra ese mismo número, nunca por una cuenta
      -- paralela: son los depósitos que todavía no tienen dueño.
      'sin_identificar_cop',
        v_recibido - (t.hoy_cop + t.fut_cop + t.otros_cop)))
  into v_cuadre
  from quien q, tot t;

$q$;
  v_def := left(v_def, v_ini - 1) || v_nuevo || substr(v_def, v_ini);

  -- ── 3. la llave en el JSON ────────────────────────────────────────
  v_ini := position(c_key in v_def);
  if v_ini = 0 then
    raise exception '0064: no se encontró dónde colgar `cuadre` del JSON';
  end if;
  v_nuevo := '    -- 0064: el puente entre la puerta y el banco.' || E'\n'
          || '    ''cuadre'', v_cuadre,' || E'\n';
  v_def := left(v_def, v_ini - 1) || v_nuevo || substr(v_def, v_ini);

  if position('0064:' in v_def) = 0 then
    raise exception '0064: el empalme no dejó la marca';
  end if;
  execute v_def;
  raise notice '0064: caja_del_dia parcheada';
end $$;
