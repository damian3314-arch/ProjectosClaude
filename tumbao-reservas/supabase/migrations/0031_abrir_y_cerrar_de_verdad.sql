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
