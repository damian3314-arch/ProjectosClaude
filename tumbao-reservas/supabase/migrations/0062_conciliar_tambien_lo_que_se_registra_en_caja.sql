-- ---------------------------------------------------------------------
-- 0062 — La tirilla de conciliación incluye lo que se registra en Caja
--
-- LO QUE FALTABA
-- La tirilla de "cuándo pagaron" solo cubría clase suelta, y lo decía al
-- pie: «el banco reportó $580.000 en total, aquí solo está lo de clase
-- suelta». Pero de esos $580.000, $445.000 eran mensualidades y otros
-- ingresos registrados a mano en la Caja — que es justo lo que hay que
-- tachar en el extracto. El papel dejaba fuera la mayor parte del
-- trabajo.
--
-- UN DEPÓSITO JUNTADO SON VARIAS LÍNEAS DEL EXTRACTO
-- Esto es lo que más cuidado necesitaba. La mensualidad de Genny son
-- $125.000 en la Caja pero DOS movimientos en el banco: $85.000 a las
-- 09:39 y $40.000 a las 17:45, que la 0057 dejó juntados en uno solo.
-- Si el papel enseñara solo la cabeza diría $85.000 donde la caja dice
-- $125.000, y la línea de $40.000 parecería sin reclamar en el extracto.
-- Así que se enseñan las dos, las dos etiquetadas con lo que pagaron.
--
-- LA UNIDAD ES LA LÍNEA DEL BANCO, NO EL COBRO
-- Antes era «un depósito por cada cosa cobrada»; ahora es «una fila por
-- cada movimiento que aparece en el extracto», y debajo se dice qué
-- pagó: los nombres si fue clase suelta, el concepto si fue una
-- mensualidad o una camiseta. Es la única forma de que el papel se pueda
-- ir tachando contra el extracto renglón por renglón.
--
-- LO QUE NO SE PUEDE BUSCAR VA APARTE, Y SE DICE
--   · efectivo — entró al cajón, no va a estar en el banco nunca
--   · transferencias registradas sin enlazar a un depósito: hay que
--     buscarlas a mano, y hasta ahora ni se nombraban
--   · gente que entró sin depósito que la respalde
--
-- CUÁNTO DE LO QUE REPORTÓ EL BANCO QUEDA IDENTIFICADO
-- Se añade `banco_hoy_cop`: de las líneas listadas, las que el banco
-- recibió HOY. Contra `recibido_cop` da la cifra que de verdad importa
-- al conciliar — lo que el banco vio hoy y todavía no tiene dueño. La
-- diferencia no es un error: suelen ser depósitos de clases de otro día
-- (el 28 de agosto eran $195.000 de las reservas del sábado).
-- ---------------------------------------------------------------------

do $$
declare
  v_def text;
  v_ini int;
  v_fin int;
  c_ini constant text := '  -- 0060: de la gente que entro hoy';
  c_fin constant text := '  into v_concilia;';
  v_nuevo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if v_def is null then raise exception 'no existe caja_del_dia'; end if;

  if position('0062:' in v_def) > 0 then
    raise notice '0062: ya estaba aplicada';
    return;
  end if;

  -- Se localiza el bloque por sus dos extremos y se empalma, en vez de
  -- reproducir cuatro mil caracteres exactos: el bloque lo escribieron
  -- la 0060 y la 0061 y reescribirlo entero a mano se rompe con
  -- cualquier espacio de diferencia.
  v_ini := position(c_ini in v_def);
  v_fin := position(c_fin in v_def);
  if v_ini = 0 or v_fin = 0 or v_fin < v_ini then
    raise exception '0062: no se encontro el bloque de conciliacion de la 0060';
  end if;

  v_nuevo :=
'  -- 0062: todo lo que entro hoy y se puede ir tachando contra el
  -- extracto. `suyas` es palabra por palabra el de la 0059 a proposito:
  -- si las dos tirillas usaran reglas distintas, una diria 11 personas y
  -- la otra listaria 10 y no habria como saber cual miente.
  with suyas as (
    select r.id, r.nombre, r.pago_id, r.origen::text as origen
      from reservas r join clases c on c.id = r.clase_id
     where r.estado = ''confirmada'' and r.tipo = ''suelta''
       and r.reprogramada_a is null
       and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia),
  -- Todo lo que se registro en la Caja hoy, no solo la clase suelta: la
  -- mensualidad que se apunta a mano tambien llega al banco y tambien
  -- hay que tacharla.
  movs as (
    select m.id, m.concepto, m.medio, m.valor_cop, m.pago_id, m.created_at
      from caja_movimientos m
     where m.dia = v_dia and not m.anulado and m.sentido = ''ingreso''),
  -- Los depositos que respaldan algo de hoy: los de las reservas que
  -- entraron y los de los movimientos de caja.
  raiz as (
    select distinct z.pago_id as id from (
      select pago_id from suyas where pago_id is not null
      union all
      select pago_id from movs  where pago_id is not null) z),
  -- Un deposito juntado (0057) son VARIAS lineas del extracto: la cabeza
  -- y sus partes. Si solo saliera la cabeza, el papel diria 85.000 donde
  -- la caja dice 125.000 y la parte de 40.000 pareceria sin reclamar.
  lineas as (
    select p.id, p.fecha_pago, p.valor_cop, p.remitente, p.referencia,
           coalesce(p.fusionado_en, p.id) as grupo,
           p.fusionado_en is not null as es_parte
      from pagos p
     where p.id in (select id from raiz)
        or p.fusionado_en in (select id from raiz))
  select jsonb_build_object(
    ''banco'', coalesce((
      select jsonb_agg(jsonb_build_object(
               ''dia'',        (l.fecha_pago at time zone ''America/Bogota'')::date,
               ''dias_antes'', v_dia - (l.fecha_pago at time zone ''America/Bogota'')::date,
               ''hora'',       to_char(l.fecha_pago at time zone ''America/Bogota'', ''HH24:MI''),
               ''valor_cop'',  l.valor_cop,
               ''remitente'',  l.remitente,
               ''referencia'', nullif(btrim(coalesce(l.referencia, '''')), ''''),
               -- Parte de un pago que llego en dos transferencias. Se
               -- marca para que quien lea no crea que le sobra plata.
               ''es_parte'',   l.es_parte,
               -- Que pago esta linea: los nombres si fue clase suelta,
               -- el concepto si fue mensualidad, camiseta u otro.
               ''para'', coalesce((select jsonb_agg(s.nombre order by s.nombre)
                                     from suyas s where s.pago_id = l.grupo), ''[]''::jsonb),
               ''conceptos'', coalesce((select jsonb_agg(distinct mv.concepto)
                                          from movs mv where mv.pago_id = l.grupo), ''[]''::jsonb),
               -- 0061: cobros en puerta sin reserva a nombre de nadie.
               -- Solo en la cabeza del grupo, para no contarlos dos veces.
               ''cobros'', case when l.es_parte then 0 else
                 (select count(*) from movs m2
                   where m2.pago_id = l.grupo and m2.concepto = ''clase_suelta''
                     and not exists (select 1 from suyas s2 where s2.pago_id = l.grupo)) end)
             order by l.fecha_pago)
        from lineas l), ''[]''::jsonb),
    ''banco_cop'', coalesce((select sum(l.valor_cop) from lineas l), 0),
    -- De lo listado, lo que el banco recibio HOY. Es lo que se compara
    -- contra recibido_cop para saber cuanto de hoy sigue sin dueño.
    ''banco_hoy_cop'', coalesce((select sum(l.valor_cop) from lineas l
       where (l.fecha_pago at time zone ''America/Bogota'')::date = v_dia), 0),
    -- Entro al cajon: no va a aparecer en el extracto nunca.
    ''efectivo'', coalesce((
      select jsonb_agg(jsonb_build_object(
               ''hora'', to_char(m.created_at at time zone ''America/Bogota'', ''HH24:MI''),
               ''concepto'', m.concepto,
               ''valor_cop'', m.valor_cop) order by m.created_at)
        from movs m where m.medio = ''efectivo''), ''[]''::jsonb),
    ''efectivo_cop'', coalesce((select sum(m.valor_cop) from movs m
       where m.medio = ''efectivo''), 0),
    -- Se registro como transferencia pero sin enlazar ningun deposito.
    -- Esta plata hay que buscarla a mano en el extracto: no se sabe que
    -- linea es. Hasta la 0062 ni se nombraba en el papel.
    ''sin_enlazar'', coalesce((
      select jsonb_agg(jsonb_build_object(
               ''hora'', to_char(m.created_at at time zone ''America/Bogota'', ''HH24:MI''),
               ''concepto'', m.concepto,
               ''valor_cop'', m.valor_cop) order by m.created_at)
        from movs m where m.medio = ''transferencia'' and m.pago_id is null), ''[]''::jsonb),
    ''sin_enlazar_cop'', coalesce((select sum(m.valor_cop) from movs m
       where m.medio = ''transferencia'' and m.pago_id is null), 0),
    -- Entro y no hay deposito que lo respalde. Esto no se cuadra: se
    -- averigua.
    ''sin_pago'', coalesce((
      select jsonb_agg(jsonb_build_object(
               ''nombre'', s.nombre,
               ''motivo'', case when s.origen = ''reprogramada''
                             then ''reprogramada, pago otro dia''
                             else ''sin deposito enlazado'' end)
             order by s.nombre)
        from suyas s where s.pago_id is null), ''[]''::jsonb))
  into v_concilia;';

  v_def := left(v_def, v_ini - 1) || v_nuevo
        || substr(v_def, v_fin + length(c_fin));

  if position('0062:' in v_def) = 0 then
    raise exception '0062: el empalme no dejo la marca';
  end if;
  execute v_def;
  raise notice '0062: caja_del_dia parcheada';
end $$;
