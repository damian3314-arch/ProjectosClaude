-- =====================================================================
-- TUMBAO — pegar esta noche, de una sola vez
--
-- Son las dos cosas juntas, en orden. Se puede pegar con el día
-- empezado: nada de esto rompe lo que ya está andando, y correrlo dos
-- veces no hace daño.
--
--   PARTE A — abrir la caja y cerrarla de verdad
--             (lo del mensaje anterior; si ya lo pegaste, esta parte no
--              cambia nada al volver a pasar)
--
--   PARTE B — cruzar los pagos en las dos direcciones
--             el arreglo de hoy: el dinero casi siempre llega ANTES de
--             que la persona dé "ya pagué", y el cruce solo se intentaba
--             en el orden contrario
--
-- Cómo: Supabase → SQL Editor → pegar todo → Run.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0031 — Abrir la caja, y que cerrarla signifique algo
--
-- SE APLICA CON EL DÍA EMPEZADO
-- Hoy ya se usó el sistema: hay movimientos y no hay apertura. Nada de
-- esto exige que la haya. Un día sin apertura sigue funcionando igual
-- que hasta ahora —la base sale del cierre de ayer— y se puede abrir a
-- media tarde si se quiere. Bloquear el turno en curso por estrenar una
-- función sería el peor cambio posible.
--
--
-- 1. ABRIR
--
-- Hasta ahora la caja no se abría: la base aparecía sola, heredada del
-- `dejado_cop` de ayer. Nadie contaba los billetes por la mañana.
--
-- El problema de eso no es de forma. Si ayer se anotó que quedaban
-- $100.000 y de verdad quedaron $95.000, el faltante se descubre HOY a
-- las 9 de la noche, mezclado con las ventas de todo el día, y ya no hay
-- forma de saber si faltaron anoche o esta tarde. Contar al abrir parte
-- el problema en dos y cada mitad tiene dueño.
--
-- Por eso la base del día pasa a ser lo que se CONTÓ al abrir, no lo que
-- decía el papel de ayer. Si no cuadran, la diferencia queda anotada en
-- la apertura y el día arranca con la verdad.
--
--
-- 2. QUE CERRADO SIGNIFIQUE CERRADO
--
-- Dos agujeros que había, los dos reales:
--
--   · `caja_registrar` no miraba si el día estaba cerrado. Se podía
--     cerrar a las 9, registrar una venta a las 9:05, y el cierre
--     archivado —el que se imprime y se compara con AdminGym— quedaba
--     mintiendo sin que nadie lo notara. `caja_anular` sí lo miraba, así
--     que se podía deshacer pero no agregar: incoherente.
--
--   · `caja_cerrar` hacía `on conflict do update`. Cerrar dos veces
--     sobrescribía el arqueo original en silencio. Si alguien tecleaba
--     mal el conteo, lo corregía y volvía a cerrar, el primer intento
--     desaparecía — y con él la prueba de que hubo un descuadre.
--
-- Ahora cerrar es definitivo. Rehacerlo se puede, pero hay que pedirlo a
-- propósito, con motivo, y queda contado: `rehecho_n` dice cuántas veces
-- y `rehecho_motivo` por qué. Un cierre que se rehizo tres veces es un
-- dato, no un accidente que conviene esconder.
-- ---------------------------------------------------------------------

create table if not exists caja_aperturas (
  dia            date primary key,
  contado_cop    int  not null check (contado_cop >= 0),
  -- Lo que decía el cierre de ayer. Se guarda para que la diferencia se
  -- pueda explicar meses después sin tener que reconstruirla.
  esperado_cop   int  not null,
  diferencia_cop int  not null,
  nota           text,
  abierto_por    uuid references admin_tokens(id),
  abierto_at     timestamptz not null default now()
);

comment on table caja_aperturas is
  'El conteo de billetes al abrir. Parte el descuadre en dos: lo de anoche y lo de hoy.';

alter table caja_cierres add column if not exists rehecho_n      int not null default 0;
alter table caja_cierres add column if not exists rehecho_motivo text;

comment on column caja_cierres.rehecho_n is
  'Cuántas veces se rehizo este cierre. Un cierre rehecho varias veces es información, no ruido.';


-- ---------------------------------------------------------------------
-- caja_abrir
-- ---------------------------------------------------------------------
create or replace function caja_abrir(
  p_token   text,
  p_contado int,
  p_nota    text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_dia   date;
  v_esp   int;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if p_contado is null or p_contado < 0 then
    return jsonb_build_object('ok', false, 'error', 'CONTADO_INVALIDO',
      'mensaje', 'Escribe cuánto hay en el cajón.');
  end if;
  -- Mismo tope que al registrar: atrapa el cero de más al teclear, que
  -- es el error que de verdad pasa en un mostrador.
  if p_contado > 5000000 then
    return jsonb_build_object('ok', false, 'error', 'VALOR_SOSPECHOSO',
      'mensaje', 'Ese valor parece tener un cero de más. Revísalo.');
  end if;

  v_dia := (now() at time zone 'America/Bogota')::date;

  if exists (select 1 from caja_cierres where dia = v_dia) then
    return jsonb_build_object('ok', false, 'error', 'DIA_CERRADO',
      'mensaje', 'El día ya está cerrado. No se puede volver a abrir.');
  end if;
  if exists (select 1 from caja_aperturas where dia = v_dia) then
    return jsonb_build_object('ok', false, 'error', 'YA_ABIERTA',
      'mensaje', 'La caja de hoy ya se abrió.');
  end if;

  select coalesce(c.dejado_cop, 100000) into v_esp
    from caja_cierres c where c.dia < v_dia order by c.dia desc limit 1;
  v_esp := coalesce(v_esp, 100000);

  insert into caja_aperturas (dia, contado_cop, esperado_cop, diferencia_cop,
                              nota, abierto_por)
  values (v_dia, p_contado, v_esp, p_contado - v_esp,
          nullif(btrim(coalesce(p_nota, '')), ''), v_admin);

  return jsonb_build_object('ok', true, 'dia', v_dia,
    'contado_cop', p_contado, 'esperado_cop', v_esp,
    'diferencia_cop', p_contado - v_esp);
end;
$$;


-- ---------------------------------------------------------------------
-- caja_registrar — no se registra nada sobre un día cerrado
--
-- Es el mismo cuerpo de 0027 con una comprobación al principio. Sin
-- ella, el papel que se imprime al cerrar podía dejar de coincidir con
-- la base cinco minutos después de imprimirlo.
-- ---------------------------------------------------------------------
create or replace function caja_registrar(
  p_token    text,
  p_sentido  text,
  p_concepto text,
  p_valor    int,
  p_medio    text,
  p_nota     text default null,
  p_pago_id  uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_id    uuid;
  v_dia   date;
  v_pago  pagos%rowtype;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  v_dia := (now() at time zone 'America/Bogota')::date;

  -- Lo nuevo. `caja_anular` ya lo comprobaba, así que hasta hoy se podía
  -- deshacer sobre un día cerrado pero no agregar — al revés de como
  -- debía ser.
  if exists (select 1 from caja_cierres where dia = v_dia) then
    return jsonb_build_object('ok', false, 'error', 'DIA_CERRADO',
      'mensaje', 'El día ya está cerrado. Este movimiento va mañana.');
  end if;

  if p_valor is null or p_valor <= 0 then
    return jsonb_build_object('ok', false, 'error', 'VALOR_INVALIDO',
      'mensaje', 'El valor tiene que ser mayor que cero.');
  end if;
  if p_valor > 5000000 then
    return jsonb_build_object('ok', false, 'error', 'VALOR_SOSPECHOSO',
      'mensaje', 'Ese valor parece tener un cero de más. Revísalo.');
  end if;
  if p_sentido not in ('ingreso', 'egreso') then
    return jsonb_build_object('ok', false, 'error', 'SENTIDO_INVALIDO');
  end if;
  if p_medio not in ('efectivo', 'transferencia') then
    return jsonb_build_object('ok', false, 'error', 'MEDIO_INVALIDO');
  end if;

  if p_pago_id is not null then
    if p_sentido <> 'ingreso' or p_medio <> 'transferencia' then
      return jsonb_build_object('ok', false, 'error', 'ENLACE_NO_APLICA',
        'mensaje', 'Solo una transferencia que entra puede enlazarse a un depósito.');
    end if;

    select * into v_pago from pagos where id = p_pago_id for update;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'PAGO_NO_EXISTE');
    end if;
    if v_pago.consumido then
      return jsonb_build_object('ok', false, 'error', 'PAGO_YA_USADO',
        'mensaje', 'Ese depósito ya se lo adjudicaron. Recarga la lista.');
    end if;
    if v_pago.valor_cop <> p_valor then
      return jsonb_build_object('ok', false, 'error', 'VALOR_NO_COINCIDE',
        'mensaje', 'El depósito es de ' || to_char(v_pago.valor_cop, 'FM999G999G999') ||
                   ' y estás registrando ' || to_char(p_valor, 'FM999G999G999') || '.');
    end if;
  end if;

  insert into caja_movimientos (dia, sentido, concepto, valor_cop, medio,
                                nota, registrado_por, pago_id)
  values (v_dia, p_sentido, left(coalesce(p_concepto, 'otro'), 40), p_valor,
          p_medio, nullif(btrim(coalesce(p_nota, '')), ''), v_admin, p_pago_id)
  returning id into v_id;

  if p_pago_id is not null then
    update pagos set consumido = true where id = p_pago_id;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'dia', v_dia,
                            'pago_id', p_pago_id);
end;
$$;


-- ---------------------------------------------------------------------
-- caja_cerrar — definitivo, y rehacerlo deja rastro
-- ---------------------------------------------------------------------
create or replace function caja_cerrar(
  p_token   text,
  p_contado int,
  p_base    int  default 100000,
  p_nota    text default null,
  p_dejado  int  default 100000,
  p_rehacer boolean default false,
  p_motivo  text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_dia   date;
  v_esp   int;
  v_ing   int; v_egr int;
  v_dej   int; v_ret int;
  v_recibido int; v_libre_hoy int;
  v_desde timestamptz; v_hasta timestamptz;
  v_previo caja_cierres;
  v_base  int;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if p_contado is null or p_contado < 0 then
    return jsonb_build_object('ok', false, 'error', 'CONTADO_INVALIDO');
  end if;

  v_dej := coalesce(p_dejado, 100000);
  if v_dej < 0 then
    return jsonb_build_object('ok', false, 'error', 'DEJADO_INVALIDO');
  end if;
  if v_dej > p_contado then
    return jsonb_build_object('ok', false, 'error', 'DEJADO_MAYOR_QUE_CONTADO',
      'mensaje', 'No puedes dejar más de lo que contaste. Revisa las dos cifras.');
  end if;

  v_dia := (now() at time zone 'America/Bogota')::date;
  select * into v_previo from caja_cierres where dia = v_dia;

  -- Cerrado es cerrado. Rehacerlo se puede, pero se pide a propósito y
  -- con motivo: si el segundo intento borrara el primero en silencio, la
  -- prueba de que hubo un descuadre desaparecería con él.
  if v_previo.dia is not null and not coalesce(p_rehacer, false) then
    return jsonb_build_object('ok', false, 'error', 'DIA_YA_CERRADO',
      'mensaje', 'El día ya se cerró a las ' ||
                 to_char(v_previo.cerrado_at at time zone 'America/Bogota', 'HH12:MI am') ||
                 '. Para rehacerlo hay que decir por qué.');
  end if;
  if v_previo.dia is not null
     and length(btrim(coalesce(p_motivo, ''))) < 4 then
    return jsonb_build_object('ok', false, 'error', 'MOTIVO_REQUERIDO',
      'mensaje', 'Escribe por qué se rehace el cierre.');
  end if;

  select
    coalesce(sum(valor_cop) filter (where sentido='ingreso' and medio='efectivo'), 0),
    coalesce(sum(valor_cop) filter (where sentido='egreso'  and medio='efectivo'), 0)
  into v_ing, v_egr
  from caja_movimientos where dia = v_dia and not anulado;

  -- La base la manda la apertura si la hubo: es lo que de verdad había
  -- en el cajón, contado. Lo que mande el panel es solo el respaldo para
  -- los días en que nadie abrió.
  select a.contado_cop into v_base from caja_aperturas a where a.dia = v_dia;
  v_base := coalesce(v_base, p_base, 100000);

  v_desde := v_dia::timestamp       at time zone 'America/Bogota';
  v_hasta := (v_dia + 1)::timestamp at time zone 'America/Bogota';
  select coalesce(sum(valor_cop), 0),
         coalesce(sum(valor_cop) filter (where not consumido), 0)
    into v_recibido, v_libre_hoy
    from pagos where fecha_pago >= v_desde and fecha_pago < v_hasta;

  v_esp := v_base + v_ing - v_egr;
  v_ret := p_contado - v_dej;

  insert into caja_cierres (dia, base_cop, contado_cop, esperado_cop,
                            diferencia_cop, dejado_cop, retirado_cop,
                            banco_cop, banco_sin_ident_cop,
                            nota, cerrado_por)
  values (v_dia, v_base, p_contado, v_esp,
          p_contado - v_esp, v_dej, v_ret,
          v_recibido, v_libre_hoy,
          nullif(btrim(coalesce(p_nota, '')), ''), v_admin)
  on conflict (dia) do update
     set base_cop = excluded.base_cop, contado_cop = excluded.contado_cop,
         esperado_cop = excluded.esperado_cop,
         diferencia_cop = excluded.diferencia_cop,
         dejado_cop = excluded.dejado_cop,
         retirado_cop = excluded.retirado_cop,
         banco_cop = excluded.banco_cop,
         banco_sin_ident_cop = excluded.banco_sin_ident_cop,
         nota = excluded.nota, cerrado_por = excluded.cerrado_por,
         cerrado_at = now(),
         rehecho_n = caja_cierres.rehecho_n + 1,
         rehecho_motivo = btrim(p_motivo);

  return jsonb_build_object('ok', true, 'dia', v_dia,
    'esperado_cop', v_esp, 'contado_cop', p_contado,
    'diferencia_cop', p_contado - v_esp,
    'base_cop', v_base,
    'dejado_cop', v_dej, 'retirado_cop', v_ret,
    'banco_cop', v_recibido, 'banco_libre_hoy_cop', v_libre_hoy,
    'rehecho', v_previo.dia is not null);
end;
$$;

drop function if exists caja_cerrar(text, int, int, text, int);


-- ---------------------------------------------------------------------
-- caja_del_dia — la base sale de la apertura, y viaja lo que falta
--                para poder imprimir la tirilla
--
-- Se añade `apertura`, `cierre.rehecho_n`, y el resumen por concepto:
-- una tirilla que solo trajera totales obliga a mirar la pantalla para
-- saber de qué eran, y entonces no reemplaza a la pantalla.
-- ---------------------------------------------------------------------
create or replace function caja_del_dia(p_token text, p_dia date default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_dia    date;
  v_movs   jsonb;
  v_resumen jsonb;
  v_cierre caja_cierres;
  v_ap     caja_aperturas;
  v_ing_ef int; v_ing_tr int; v_egr_ef int; v_egr_tr int;
  v_reservas int; v_base int;
  v_res_mano int; v_res_mano_n int;
  v_desde timestamptz; v_hasta timestamptz; v_corte timestamptz;
  v_recibido int; v_ultimo timestamptz;
  v_libre_hoy int; v_libre_hoy_n int;
  v_libre int; v_libre_n int;
  v_mes int;
  v_sin_resp int; v_sin_resp_n int;
  v_libres jsonb;
  v_quien_abrio text; v_quien_cerro text;
  c_dias constant int := 20;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  v_dia := coalesce(p_dia, (now() at time zone 'America/Bogota')::date);

  select
    coalesce(sum(valor_cop) filter (where sentido='ingreso' and medio='efectivo'), 0),
    coalesce(sum(valor_cop) filter (where sentido='ingreso' and medio='transferencia'), 0),
    coalesce(sum(valor_cop) filter (where sentido='egreso'  and medio='efectivo'), 0),
    coalesce(sum(valor_cop) filter (where sentido='egreso'  and medio='transferencia'), 0),
    coalesce(sum(valor_cop) filter (
      where sentido='ingreso' and medio='transferencia' and pago_id is null), 0),
    count(*) filter (
      where sentido='ingreso' and medio='transferencia' and pago_id is null)
  into v_ing_ef, v_ing_tr, v_egr_ef, v_egr_tr, v_sin_resp, v_sin_resp_n
  from caja_movimientos where dia = v_dia and not anulado;

  select coalesce(sum(c.precio_cop), 0) into v_reservas
    from reservas r join clases c on c.id = r.clase_id
   where r.estado = 'confirmada' and r.tipo = 'suelta'
     and r.pago_id is not null
     and (c.fecha_hora at time zone 'America/Bogota')::date = v_dia;

  select coalesce(sum(c.precio_cop), 0), count(*)
    into v_res_mano, v_res_mano_n
    from reservas r join clases c on c.id = r.clase_id
   where r.estado = 'confirmada' and r.tipo = 'suelta'
     and r.pago_id is null
     and (c.fecha_hora at time zone 'America/Bogota')::date = v_dia;

  v_desde := v_dia::timestamp        at time zone 'America/Bogota';
  v_hasta := (v_dia + 1)::timestamp  at time zone 'America/Bogota';
  v_corte := greatest(v_hasta - make_interval(days => c_dias),
                      inicio_produccion()::timestamp at time zone 'America/Bogota');

  select coalesce(sum(valor_cop), 0), max(fecha_pago),
         coalesce(sum(valor_cop) filter (where not consumido), 0),
         count(*) filter (where not consumido)
    into v_recibido, v_ultimo, v_libre_hoy, v_libre_hoy_n
    from pagos where fecha_pago >= v_desde and fecha_pago < v_hasta;

  select coalesce(sum(valor_cop), 0), count(*)
    into v_libre, v_libre_n
    from pagos where not consumido and fecha_pago >= v_corte;

  select coalesce(sum(valor_cop), 0) into v_mes
    from pagos
   where fecha_pago >= greatest(
           date_trunc('month', v_dia)::timestamp at time zone 'America/Bogota',
           inicio_produccion()::timestamp at time zone 'America/Bogota')
     and fecha_pago < v_hasta;

  select coalesce(jsonb_agg(x order by x->>'fecha_pago' desc), '[]'::jsonb)
    into v_libres
    from (
      select jsonb_build_object(
               'id', p.id, 'valor_cop', p.valor_cop, 'fecha_pago', p.fecha_pago,
               'cuando', to_char(p.fecha_pago at time zone 'America/Bogota', 'DD/MM HH24:MI'),
               'dias', (v_dia - (p.fecha_pago at time zone 'America/Bogota')::date),
               'remitente', p.remitente, 'referencia', p.referencia) as x
        from pagos p
       where not p.consumido and p.fecha_pago >= v_corte
       order by p.fecha_pago desc limit 120
    ) s;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'sentido', m.sentido, 'concepto', m.concepto,
           'valor_cop', m.valor_cop, 'medio', m.medio, 'nota', m.nota,
           'hora', to_char(m.created_at at time zone 'America/Bogota', 'HH24:MI'),
           'quien', t.nombre, 'con_banco', m.pago_id is not null)
         order by m.created_at desc), '[]'::jsonb)
    into v_movs
    from caja_movimientos m
    left join admin_tokens t on t.id = m.registrado_por
   where m.dia = v_dia and not m.anulado;

  -- Agrupado por concepto y medio: es lo que va en la tirilla. Con solo
  -- el total, para saber de qué eran los $340.000 hay que volver a la
  -- pantalla — y entonces el papel no sirve de nada.
  select coalesce(jsonb_agg(jsonb_build_object(
           'sentido', s.sentido, 'concepto', s.concepto, 'medio', s.medio,
           'n', s.n, 'valor_cop', s.total)
         order by s.sentido desc, s.total desc), '[]'::jsonb)
    into v_resumen
    from (
      select sentido, concepto, medio, count(*) as n, sum(valor_cop) as total
        from caja_movimientos
       where dia = v_dia and not anulado
       group by sentido, concepto, medio
    ) s;

  select * into v_cierre from caja_cierres where dia = v_dia;
  select * into v_ap     from caja_aperturas where dia = v_dia;

  select t.nombre into v_quien_abrio from admin_tokens t where t.id = v_ap.abierto_por;
  select t.nombre into v_quien_cerro from admin_tokens t where t.id = v_cierre.cerrado_por;

  -- La base es lo que se CONTÓ al abrir. Solo si nadie abrió se cae al
  -- comportamiento viejo, que es heredar lo que decía el cierre de ayer.
  if v_ap.dia is not null then
    v_base := v_ap.contado_cop;
  else
    select coalesce(c.dejado_cop, 100000) into v_base
      from caja_cierres c where c.dia < v_dia order by c.dia desc limit 1;
    v_base := coalesce(v_cierre.base_cop, v_base, 100000);
  end if;

  return jsonb_build_object(
    'ok', true,
    'dia', v_dia,
    'movimientos', v_movs,
    'resumen_conceptos', v_resumen,
    'base_cop', v_base,
    'ingreso_efectivo', v_ing_ef,
    'egreso_efectivo',  v_egr_ef,
    'esperado_efectivo', v_base + v_ing_ef - v_egr_ef,
    'ingreso_transferencia', v_ing_tr,
    'egreso_transferencia',  v_egr_tr,
    'reservas_cop', v_reservas,
    'reservas_a_mano_cop', v_res_mano,
    'reservas_a_mano_n',   v_res_mano_n,
    'total_ingresos', v_ing_ef + v_ing_tr + v_reservas,
    'total_egresos',  v_egr_ef + v_egr_tr,
    'contra_admingym', jsonb_build_object(
      'venta_membresias', v_ing_ef,
      'ingresos_a_banco', v_ing_tr + v_reservas,
      'retirar_dinero_de_caja', v_egr_ef,
      'dinero_en_caja', v_base + v_ing_ef - v_egr_ef
    ),
    'banco', jsonb_build_object(
      'recibido_cop', v_recibido,
      'libre_hoy_cop', v_libre_hoy, 'libre_hoy_n', v_libre_hoy_n,
      'libre_cop', v_libre, 'libre_n', v_libre_n,
      'atras_cop', v_libre - v_libre_hoy, 'atras_n', v_libre_n - v_libre_hoy_n,
      'mes_cop', v_mes,
      'sin_respaldo_cop', v_sin_resp, 'sin_respaldo_n', v_sin_resp_n,
      'ventana_dias', c_dias,
      'corte', case when v_ultimo is null then null
               else to_char(v_ultimo at time zone 'America/Bogota', 'HH24:MI') end
    ),
    'pagos_libres', v_libres,
    'abierta', v_ap.dia is not null,
    'apertura', case when v_ap.dia is null then null else jsonb_build_object(
        'contado_cop', v_ap.contado_cop,
        'esperado_cop', v_ap.esperado_cop,
        'diferencia_cop', v_ap.diferencia_cop,
        'nota', v_ap.nota,
        'quien', v_quien_abrio,
        'hora', to_char(v_ap.abierto_at at time zone 'America/Bogota', 'HH24:MI')) end,
    'cerrado', v_cierre.dia is not null,
    'cierre', case when v_cierre.dia is null then null else jsonb_build_object(
        'contado_cop', v_cierre.contado_cop,
        'esperado_cop', v_cierre.esperado_cop,
        'diferencia_cop', v_cierre.diferencia_cop,
        'dejado_cop', v_cierre.dejado_cop,
        'retirado_cop', v_cierre.retirado_cop,
        'banco_cop', v_cierre.banco_cop,
        'banco_sin_ident_cop', v_cierre.banco_sin_ident_cop,
        'rehecho_n', v_cierre.rehecho_n,
        'rehecho_motivo', v_cierre.rehecho_motivo,
        'quien', v_quien_cerro,
        'nota', v_cierre.nota,
        'hora', to_char(v_cierre.cerrado_at at time zone 'America/Bogota', 'HH24:MI'),
        'cerrado_at', v_cierre.cerrado_at) end
  );
end;
$$;

alter table caja_aperturas enable row level security;
revoke all on table caja_aperturas from public, anon, authenticated;
grant  select, insert on table caja_aperturas to service_role;

revoke execute on function caja_abrir(text, int, text)                          from public, anon, authenticated;
revoke execute on function caja_registrar(text,text,text,int,text,text,uuid)    from public, anon, authenticated;
revoke execute on function caja_cerrar(text,int,int,text,int,boolean,text)      from public, anon, authenticated;
revoke execute on function caja_del_dia(text, date)                             from public, anon, authenticated;
grant  execute on function caja_abrir(text, int, text)                          to service_role;
grant  execute on function caja_registrar(text,text,text,int,text,text,uuid)    to service_role;
grant  execute on function caja_cerrar(text,int,int,text,int,boolean,text)      to service_role;
grant  execute on function caja_del_dia(text, date)                             to service_role;



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
