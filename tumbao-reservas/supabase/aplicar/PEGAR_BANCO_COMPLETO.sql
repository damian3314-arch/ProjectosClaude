-- =====================================================================
-- TUMBAO · CONTROL DEL BANCO EN LA CAJA
-- Pegar completo en el editor SQL de Supabase y darle Run.
--
-- QUÉ HACE
--   · La caja aprende a enlazar cada transferencia que cobra con el
--     depósito que Bancolombia confirmó por correo.
--   · La pestaña Caja gana una tarjeta: cuánto entró al banco hoy y,
--     de eso, cuánto sigue sin dueño.
--
-- POR QUÉ LA ALARMA ES SOLO LA DE HOY
--   Hay 75 depósitos sin reclamar de antes de que existiera este
--   módulo. Ese número no baja a cero nunca, así que como alarma diaria
--   no sirve: se ignora a los tres días. Lo de hoy sí cierra en cero, y
--   si no cierra hay algo concreto que buscar. El arrastre viejo sigue
--   ofreciéndose en la lista para escoger —quien transfirió el lunes
--   tiene que poder aparecer el miércoles— pero va en letra chica.
--
-- SEGURIDAD
--   No borra ninguna fila. No toca los datos de `pagos` ni de las
--   reservas. No cambia la comparación con AdminGym. Se puede correr
--   dos veces sin problema. Si algo saliera mal, la página sigue
--   funcionando igual — la tarjeta simplemente no aparece.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Constancia de lo que decía el banco al cerrar el día
-- ---------------------------------------------------------------------
alter table caja_cierres add column if not exists banco_cop            int;
alter table caja_cierres add column if not exists banco_sin_ident_cop  int;

comment on column caja_cierres.banco_cop is
  'Lo que Bancolombia confirmó ese día. No lo teclea nadie: sale del correo.';

-- Los sumatorios del día van por rango de fecha y no por ::date, para
-- que este índice sirva: `x at time zone 'America/Bogota'` es STABLE,
-- no IMMUTABLE, y envuelto en un ::date obliga a recorrer la tabla.
create index if not exists pagos_por_fecha on pagos (fecha_pago);


-- ---------------------------------------------------------------------
-- 0027 — Conciliar depósito por depósito, no día contra día
--
-- LO QUE ESTABA MAL EN 0026
-- Comparaba la suma del banco de hoy contra la suma de la caja de hoy.
-- La plata no se mueve así. Caso real: transfiere el 3, llega el 5. La
-- cajera lo registra el 5; el banco no vio nada el 5, así que la resta
-- daba negativo y la pantalla gritaba "comprobante sin confirmar". Una
-- falsa alarma casi diaria — y una alarma que se ignora es peor que no
-- tenerla. Ese semáforo se retira aquí.
--
-- EL MODELO QUE SÍ FUNCIONA
-- Un depósito del banco no pertenece a un día: pertenece a alguien.
-- Cada fila de `pagos` está en uno de dos estados y nada más:
--
--   RECLAMADO   alguien se lo adjudicó: la página al confirmar una
--               reserva, o la cajera al cobrar en el mostrador.
--   LIBRE       entró plata y nadie ha dicho de qué es.
--
-- `pagos.consumido` ya era exactamente esa marca desde el esquema
-- inicial; hasta ahora solo la ponía la conciliación automática.
--
-- Entonces la pregunta del cierre deja de ser "¿cuadran las sumas de
-- hoy?" y pasa a ser dos preguntas que sí tienen respuesta:
--
--   1. ¿Queda plata en el banco que nadie ha reclamado?
--      → alguien pagó y no se le registró el servicio. Hay que buscarlo.
--
--   2. ¿Hay transferencias apuntadas que no señalan a ningún depósito?
--      → o entraron por otra cuenta (Nequi), o el comprobante no era
--        real. La cajera lo sabe en el momento, no a fin de mes.
--
-- Y LA VERIFICACIÓN SE MUEVE AL MOSTRADOR
-- Antes la cajera miraba una foto y le creía. Ahora, al registrar una
-- transferencia, escoge de una lista los depósitos que el banco confirmó
-- y todavía nadie reclamó — de los últimos 20 días, así que el del 3 de
-- agosto sigue ahí el 5. Si el depósito está, la plata llegó de verdad.
-- Si no está, no llegó. Eso es comprobarlo; mirar la foto no lo era.
-- ---------------------------------------------------------------------

-- El enlace entre un cobro del mostrador y el depósito que lo respalda.
alter table caja_movimientos add column if not exists pago_id uuid references pagos(id);

comment on column caja_movimientos.pago_id is
  'El depósito del banco que respalda este cobro. Nulo = se apuntó sin enlazar (efectivo, u otra cuenta).';

-- Un depósito no puede pagar dos cosas. Igual que reservas_pago_unico.
create unique index if not exists caja_mov_pago_unico
  on caja_movimientos (pago_id) where pago_id is not null;

-- La lista de libres se pide por fecha descendente sobre los no
-- consumidos: el índice parcial que ya existía va por (valor, fecha),
-- que no sirve para ordenar. Este sí.
create index if not exists pagos_libres_por_fecha
  on pagos (fecha_pago desc) where not consumido;


-- ---------------------------------------------------------------------
-- caja_registrar — ahora puede adjudicar un depósito
--
-- Cambia la firma, así que la de 6 argumentos se retira más abajo: si
-- quedara viva, PostgREST no sabría a cuál llamar.
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

  -- ---- adjudicación del depósito ----
  if p_pago_id is not null then
    if p_sentido <> 'ingreso' or p_medio <> 'transferencia' then
      return jsonb_build_object('ok', false, 'error', 'ENLACE_NO_APLICA',
        'mensaje', 'Solo una transferencia que entra puede enlazarse a un depósito.');
    end if;

    -- El bloqueo de fila es lo que impide que dos cajeras adjudiquen el
    -- mismo depósito a la vez. Sin esto, el índice único lo atraparía
    -- igual, pero con un error feo en vez de un mensaje.
    select * into v_pago from pagos where id = p_pago_id for update;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'PAGO_NO_EXISTE');
    end if;
    if v_pago.consumido then
      return jsonb_build_object('ok', false, 'error', 'PAGO_YA_USADO',
        'mensaje', 'Ese depósito ya se lo adjudicaron. Recarga la lista.');
    end if;
    -- El valor tiene que ser el del banco, no el que se tecleó. Si no
    -- coinciden es que se escogió el depósito equivocado, y dejarlo
    -- pasar metería una diferencia que después nadie sabe explicar.
    if v_pago.valor_cop <> p_valor then
      return jsonb_build_object('ok', false, 'error', 'VALOR_NO_COINCIDE',
        'mensaje', 'El depósito es de ' || to_char(v_pago.valor_cop, 'FM999G999G999') ||
                   ' y estás registrando ' || to_char(p_valor, 'FM999G999G999') || '.');
    end if;
  end if;

  v_dia := (now() at time zone 'America/Bogota')::date;

  insert into caja_movimientos (dia, sentido, concepto, valor_cop, medio,
                                nota, registrado_por, pago_id)
  values (v_dia, p_sentido, left(coalesce(p_concepto, 'otro'), 40), p_valor,
          p_medio, nullif(btrim(coalesce(p_nota, '')), ''), v_admin, p_pago_id)
  returning id into v_id;

  -- Marcarlo consumido lo saca de la lista de libres Y evita que la
  -- conciliación automática se lo asigne después a una reserva: las dos
  -- rutas miran la misma bandera.
  if p_pago_id is not null then
    update pagos set consumido = true where id = p_pago_id;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'dia', v_dia,
                            'pago_id', p_pago_id);
end;
$$;

drop function if exists caja_registrar(text, text, text, int, text, text);


-- ---------------------------------------------------------------------
-- caja_anular — al deshacer, el depósito vuelve a estar libre
--
-- Sin esto, anular un cobro mal enlazado dejaba la plata del banco
-- marcada como reclamada para siempre y desaparecía del control.
-- ---------------------------------------------------------------------
create or replace function caja_anular(p_token text, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_mov   caja_movimientos;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_mov from caja_movimientos where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;
  if v_mov.anulado then
    return jsonb_build_object('ok', false, 'error', 'YA_ANULADO');
  end if;
  if v_mov.dia <> (now() at time zone 'America/Bogota')::date then
    return jsonb_build_object('ok', false, 'error', 'OTRO_DIA',
      'mensaje', 'Solo se pueden anular movimientos de hoy.');
  end if;
  if exists (select 1 from caja_cierres where dia = v_mov.dia) then
    return jsonb_build_object('ok', false, 'error', 'DIA_CERRADO',
      'mensaje', 'El día ya está cerrado. El ajuste va mañana.');
  end if;

  update caja_movimientos
     set anulado = true, anulado_at = now(), anulado_por = v_admin,
         pago_id = null
   where id = p_id;

  if v_mov.pago_id is not null then
    update pagos set consumido = false where id = v_mov.pago_id;
  end if;

  return jsonb_build_object('ok', true, 'valor_cop', v_mov.valor_cop,
                            'concepto', v_mov.concepto,
                            'libero_pago', v_mov.pago_id is not null);
end;
$$;


-- ---------------------------------------------------------------------
-- caja_del_dia — el bloque `banco`, rehecho
--
-- Fuera la resta día contra día. Entra el inventario: cuánta plata del
-- banco sigue sin dueño, y cuántas transferencias se apuntaron sin
-- señalar a ningún depósito.
--
-- `pagos_libres` viaja en la misma respuesta para que la ventana de
-- registro no tenga que pedir nada aparte: en un mostrador con cola, una
-- llamada extra es medio segundo mirando una lista vacía.
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
  v_cierre caja_cierres;
  v_ing_ef int; v_ing_tr int; v_egr_ef int; v_egr_tr int;
  v_reservas int; v_base int;
  v_desde timestamptz; v_hasta timestamptz;
  v_recibido int; v_ultimo timestamptz;
  v_libre int; v_libre_n int;
  v_sin_resp int; v_sin_resp_n int;
  v_libres jsonb;
  c_dias constant int := 20;   -- cuánto atrás se ofrecen los depósitos
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
    -- Transferencias apuntadas que no señalan a ningún depósito.
    coalesce(sum(valor_cop) filter (
      where sentido='ingreso' and medio='transferencia' and pago_id is null), 0),
    count(*) filter (
      where sentido='ingreso' and medio='transferencia' and pago_id is null)
  into v_ing_ef, v_ing_tr, v_egr_ef, v_egr_tr, v_sin_resp, v_sin_resp_n
  from caja_movimientos where dia = v_dia and not anulado;

  select coalesce(sum(c.precio_cop), 0) into v_reservas
    from reservas r join clases c on c.id = r.clase_id
   where r.estado = 'confirmada'
     and r.tipo = 'suelta'
     and (c.fecha_hora at time zone 'America/Bogota')::date = v_dia;

  -- Lo que el banco confirmó ese día. Informativo: sirve para ver que la
  -- plata está entrando, no para cuadrar contra nada.
  v_desde := v_dia::timestamp        at time zone 'America/Bogota';
  v_hasta := (v_dia + 1)::timestamp  at time zone 'America/Bogota';
  select coalesce(sum(valor_cop), 0), max(fecha_pago)
    into v_recibido, v_ultimo
    from pagos where fecha_pago >= v_desde and fecha_pago < v_hasta;

  -- El inventario: plata del banco que nadie ha reclamado todavía. No se
  -- limita al día, y ese es justo el punto — el depósito del 3 tiene que
  -- seguir apareciendo el 5.
  select coalesce(sum(valor_cop), 0), count(*)
    into v_libre, v_libre_n
    from pagos
   where not consumido
     and fecha_pago >= v_hasta - make_interval(days => c_dias);

  select coalesce(jsonb_agg(x order by x->>'fecha_pago' desc), '[]'::jsonb)
    into v_libres
    from (
      select jsonb_build_object(
               'id', p.id,
               'valor_cop', p.valor_cop,
               'fecha_pago', p.fecha_pago,
               'cuando', to_char(p.fecha_pago at time zone 'America/Bogota',
                                 'DD/MM HH24:MI'),
               -- Contra v_dia, no contra v_hasta: v_hasta es la medianoche
               -- del día siguiente, y castearla a date daba un día de más.
               'dias', (v_dia - (p.fecha_pago at time zone 'America/Bogota')::date),
               'remitente', p.remitente,
               'referencia', p.referencia) as x
        from pagos p
       where not p.consumido
         and p.fecha_pago >= v_hasta - make_interval(days => c_dias)
       order by p.fecha_pago desc
       limit 40
    ) s;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'sentido', m.sentido, 'concepto', m.concepto,
           'valor_cop', m.valor_cop, 'medio', m.medio, 'nota', m.nota,
           'hora', to_char(m.created_at at time zone 'America/Bogota', 'HH24:MI'),
           'quien', t.nombre,
           'con_banco', m.pago_id is not null)
         order by m.created_at desc), '[]'::jsonb)
    into v_movs
    from caja_movimientos m
    left join admin_tokens t on t.id = m.registrado_por
   where m.dia = v_dia and not m.anulado;

  select * into v_cierre from caja_cierres where dia = v_dia;

  select coalesce(c.dejado_cop, 100000) into v_base
    from caja_cierres c
   where c.dia < v_dia
   order by c.dia desc limit 1;
  v_base := coalesce(v_cierre.base_cop, v_base, 100000);

  return jsonb_build_object(
    'ok', true,
    'dia', v_dia,
    'movimientos', v_movs,
    'base_cop', v_base,
    'ingreso_efectivo', v_ing_ef,
    'egreso_efectivo',  v_egr_ef,
    'esperado_efectivo', v_base + v_ing_ef - v_egr_ef,
    'ingreso_transferencia', v_ing_tr,
    'egreso_transferencia',  v_egr_tr,
    'reservas_cop', v_reservas,
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
      'libre_cop', v_libre,
      'libre_n', v_libre_n,
      'sin_respaldo_cop', v_sin_resp,
      'sin_respaldo_n', v_sin_resp_n,
      'ventana_dias', c_dias,
      'corte', case when v_ultimo is null then null
               else to_char(v_ultimo at time zone 'America/Bogota', 'HH24:MI') end
    ),
    'pagos_libres', v_libres,
    'cerrado', v_cierre.dia is not null,
    'cierre', case when v_cierre.dia is null then null else jsonb_build_object(
        'contado_cop', v_cierre.contado_cop,
        'esperado_cop', v_cierre.esperado_cop,
        'diferencia_cop', v_cierre.diferencia_cop,
        'dejado_cop', v_cierre.dejado_cop,
        'retirado_cop', v_cierre.retirado_cop,
        'banco_cop', v_cierre.banco_cop,
        'banco_sin_ident_cop', v_cierre.banco_sin_ident_cop,
        'nota', v_cierre.nota,
        'cerrado_at', v_cierre.cerrado_at) end
  );
end;
$$;


-- ---------------------------------------------------------------------
-- caja_cerrar — guarda el inventario, no la resta de ayer
--
-- `banco_sin_ident_cop` cambia de significado: antes era una resta entre
-- días que podía dar negativo por puro desfase; ahora es cuánta plata
-- del banco quedó sin dueño al cerrar. La columna se reusa porque nunca
-- llegó a producción con el significado viejo.
-- ---------------------------------------------------------------------
create or replace function caja_cerrar(
  p_token   text,
  p_contado int,
  p_base    int  default 100000,
  p_nota    text default null,
  p_dejado  int  default 100000)
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
  v_recibido int; v_libre int;
  v_desde timestamptz; v_hasta timestamptz;
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

  select
    coalesce(sum(valor_cop) filter (where sentido='ingreso' and medio='efectivo'), 0),
    coalesce(sum(valor_cop) filter (where sentido='egreso'  and medio='efectivo'), 0)
  into v_ing, v_egr
  from caja_movimientos where dia = v_dia and not anulado;

  v_desde := v_dia::timestamp       at time zone 'America/Bogota';
  v_hasta := (v_dia + 1)::timestamp at time zone 'America/Bogota';
  select coalesce(sum(valor_cop), 0) into v_recibido
    from pagos where fecha_pago >= v_desde and fecha_pago < v_hasta;
  select coalesce(sum(valor_cop), 0) into v_libre
    from pagos where not consumido and fecha_pago >= v_hasta - make_interval(days => 20);

  v_esp := coalesce(p_base, 100000) + v_ing - v_egr;
  v_ret := p_contado - v_dej;

  insert into caja_cierres (dia, base_cop, contado_cop, esperado_cop,
                            diferencia_cop, dejado_cop, retirado_cop,
                            banco_cop, banco_sin_ident_cop,
                            nota, cerrado_por)
  values (v_dia, coalesce(p_base, 100000), p_contado, v_esp,
          p_contado - v_esp, v_dej, v_ret,
          v_recibido, v_libre,
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
         cerrado_at = now();

  return jsonb_build_object('ok', true, 'dia', v_dia,
    'esperado_cop', v_esp, 'contado_cop', p_contado,
    'diferencia_cop', p_contado - v_esp,
    'dejado_cop', v_dej, 'retirado_cop', v_ret,
    'banco_cop', v_recibido, 'banco_libre_cop', v_libre);
end;
$$;

comment on column caja_cierres.banco_sin_ident_cop is
  'Plata del banco que seguía sin dueño al cerrar (últimos 20 días).';

revoke execute on function caja_registrar(text,text,text,int,text,text,uuid) from public, anon, authenticated;
revoke execute on function caja_anular(text, uuid)                           from public, anon, authenticated;
revoke execute on function caja_del_dia(text, date)                          from public, anon, authenticated;
revoke execute on function caja_cerrar(text, int, int, text, int)            from public, anon, authenticated;
grant  execute on function caja_registrar(text,text,text,int,text,text,uuid) to service_role;
grant  execute on function caja_anular(text, uuid)                           to service_role;
grant  execute on function caja_del_dia(text, date)                          to service_role;
grant  execute on function caja_cerrar(text, int, int, text, int)            to service_role;


-- ---------------------------------------------------------------------
-- 0028 — La alarma es la de hoy; el resto es histórico
--
-- QUÉ SALIÓ MAL EN 0027
-- La tarjeta mostraba el inventario completo de depósitos sin reclamar:
-- 75 depósitos, $3.211.000. Casi todo es de antes de que este módulo
-- existiera — plata que entró cuando nadie la enlazaba porque no había
-- dónde enlazarla. Ese número no baja a cero nunca, así que como alarma
-- diaria no sirve: se ignora a los tres días, y una alarma ignorada es
-- ruido con presupuesto.
--
-- LO QUE SÍ ES ACCIONABLE
-- De lo que entró HOY, cuánto sigue sin dueño. Ese número sí cierra en
-- cero al final del día, y si no cierra hay algo concreto que buscar:
-- alguien pagó hoy y no se le registró el servicio.
--
-- El histórico no desaparece —la lista para escoger lo sigue usando,
-- porque quien transfirió el lunes tiene que poder aparecer el
-- miércoles— pero baja a letra chica, que es donde va lo que no exige
-- una acción hoy.
--
-- Y SE AÑADE EL MES
-- Cuánto ha entrado al banco en lo que va del mes. No cuadra contra
-- nada: sirve para ver de un vistazo si la plata está entrando al ritmo
-- que debería.
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
  v_cierre caja_cierres;
  v_ing_ef int; v_ing_tr int; v_egr_ef int; v_egr_tr int;
  v_reservas int; v_base int;
  v_desde timestamptz; v_hasta timestamptz;
  v_recibido int; v_ultimo timestamptz;
  v_libre_hoy int; v_libre_hoy_n int;
  v_libre int; v_libre_n int;
  v_mes int;
  v_sin_resp int; v_sin_resp_n int;
  v_libres jsonb;
  c_dias constant int := 20;   -- cuánto atrás se ofrecen los depósitos
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
   where r.estado = 'confirmada'
     and r.tipo = 'suelta'
     and (c.fecha_hora at time zone 'America/Bogota')::date = v_dia;

  v_desde := v_dia::timestamp        at time zone 'America/Bogota';
  v_hasta := (v_dia + 1)::timestamp  at time zone 'America/Bogota';

  -- Lo del día: total recibido, y cuánto de eso sigue sin dueño. Esta
  -- segunda cifra es la única que exige hacer algo hoy.
  select
    coalesce(sum(valor_cop), 0),
    max(fecha_pago),
    coalesce(sum(valor_cop) filter (where not consumido), 0),
    count(*) filter (where not consumido)
  into v_recibido, v_ultimo, v_libre_hoy, v_libre_hoy_n
  from pagos where fecha_pago >= v_desde and fecha_pago < v_hasta;

  -- El histórico: todo lo que la lista puede ofrecer. Incluye lo de
  -- antes del módulo, así que arranca alto y baja despacio. Va a letra
  -- chica a propósito.
  select coalesce(sum(valor_cop), 0), count(*)
    into v_libre, v_libre_n
    from pagos
   where not consumido
     and fecha_pago >= v_hasta - make_interval(days => c_dias);

  -- Lo que va del mes. Informativo puro: si la plata está entrando.
  select coalesce(sum(valor_cop), 0) into v_mes
    from pagos
   where fecha_pago >= date_trunc('month', v_dia)::timestamp at time zone 'America/Bogota'
     and fecha_pago < v_hasta;

  select coalesce(jsonb_agg(x order by x->>'fecha_pago' desc), '[]'::jsonb)
    into v_libres
    from (
      select jsonb_build_object(
               'id', p.id,
               'valor_cop', p.valor_cop,
               'fecha_pago', p.fecha_pago,
               'cuando', to_char(p.fecha_pago at time zone 'America/Bogota',
                                 'DD/MM HH24:MI'),
               'dias', (v_dia - (p.fecha_pago at time zone 'America/Bogota')::date),
               'remitente', p.remitente,
               'referencia', p.referencia) as x
        from pagos p
       where not p.consumido
         and p.fecha_pago >= v_hasta - make_interval(days => c_dias)
       order by p.fecha_pago desc
       limit 120
    ) s;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'sentido', m.sentido, 'concepto', m.concepto,
           'valor_cop', m.valor_cop, 'medio', m.medio, 'nota', m.nota,
           'hora', to_char(m.created_at at time zone 'America/Bogota', 'HH24:MI'),
           'quien', t.nombre,
           'con_banco', m.pago_id is not null)
         order by m.created_at desc), '[]'::jsonb)
    into v_movs
    from caja_movimientos m
    left join admin_tokens t on t.id = m.registrado_por
   where m.dia = v_dia and not m.anulado;

  select * into v_cierre from caja_cierres where dia = v_dia;

  select coalesce(c.dejado_cop, 100000) into v_base
    from caja_cierres c
   where c.dia < v_dia
   order by c.dia desc limit 1;
  v_base := coalesce(v_cierre.base_cop, v_base, 100000);

  return jsonb_build_object(
    'ok', true,
    'dia', v_dia,
    'movimientos', v_movs,
    'base_cop', v_base,
    'ingreso_efectivo', v_ing_ef,
    'egreso_efectivo',  v_egr_ef,
    'esperado_efectivo', v_base + v_ing_ef - v_egr_ef,
    'ingreso_transferencia', v_ing_tr,
    'egreso_transferencia',  v_egr_tr,
    'reservas_cop', v_reservas,
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
      'libre_hoy_cop', v_libre_hoy,
      'libre_hoy_n', v_libre_hoy_n,
      'libre_cop', v_libre,
      'libre_n', v_libre_n,
      -- Lo de días anteriores, ya restado: es el arrastre histórico.
      'atras_cop', v_libre - v_libre_hoy,
      'atras_n', v_libre_n - v_libre_hoy_n,
      'mes_cop', v_mes,
      'sin_respaldo_cop', v_sin_resp,
      'sin_respaldo_n', v_sin_resp_n,
      'ventana_dias', c_dias,
      'corte', case when v_ultimo is null then null
               else to_char(v_ultimo at time zone 'America/Bogota', 'HH24:MI') end
    ),
    'pagos_libres', v_libres,
    'cerrado', v_cierre.dia is not null,
    'cierre', case when v_cierre.dia is null then null else jsonb_build_object(
        'contado_cop', v_cierre.contado_cop,
        'esperado_cop', v_cierre.esperado_cop,
        'diferencia_cop', v_cierre.diferencia_cop,
        'dejado_cop', v_cierre.dejado_cop,
        'retirado_cop', v_cierre.retirado_cop,
        'banco_cop', v_cierre.banco_cop,
        'banco_sin_ident_cop', v_cierre.banco_sin_ident_cop,
        'nota', v_cierre.nota,
        'cerrado_at', v_cierre.cerrado_at) end
  );
end;
$$;

-- El cierre guarda lo del día, no el arrastre. Guardar el histórico
-- dejaría en cada cierre un número que solo dice cuántos días llevaba
-- acumulándose, que no es información de ese día.
create or replace function caja_cerrar(
  p_token   text,
  p_contado int,
  p_base    int  default 100000,
  p_nota    text default null,
  p_dejado  int  default 100000)
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

  select
    coalesce(sum(valor_cop) filter (where sentido='ingreso' and medio='efectivo'), 0),
    coalesce(sum(valor_cop) filter (where sentido='egreso'  and medio='efectivo'), 0)
  into v_ing, v_egr
  from caja_movimientos where dia = v_dia and not anulado;

  v_desde := v_dia::timestamp       at time zone 'America/Bogota';
  v_hasta := (v_dia + 1)::timestamp at time zone 'America/Bogota';
  select coalesce(sum(valor_cop), 0),
         coalesce(sum(valor_cop) filter (where not consumido), 0)
    into v_recibido, v_libre_hoy
    from pagos where fecha_pago >= v_desde and fecha_pago < v_hasta;

  v_esp := coalesce(p_base, 100000) + v_ing - v_egr;
  v_ret := p_contado - v_dej;

  insert into caja_cierres (dia, base_cop, contado_cop, esperado_cop,
                            diferencia_cop, dejado_cop, retirado_cop,
                            banco_cop, banco_sin_ident_cop,
                            nota, cerrado_por)
  values (v_dia, coalesce(p_base, 100000), p_contado, v_esp,
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
         cerrado_at = now();

  return jsonb_build_object('ok', true, 'dia', v_dia,
    'esperado_cop', v_esp, 'contado_cop', p_contado,
    'diferencia_cop', p_contado - v_esp,
    'dejado_cop', v_dej, 'retirado_cop', v_ret,
    'banco_cop', v_recibido, 'banco_libre_hoy_cop', v_libre_hoy);
end;
$$;

comment on column caja_cierres.banco_sin_ident_cop is
  'De lo que entró al banco ESE día, cuánto seguía sin dueño al cerrar.';

revoke execute on function caja_del_dia(text, date)               from public, anon, authenticated;
revoke execute on function caja_cerrar(text, int, int, text, int) from public, anon, authenticated;
grant  execute on function caja_del_dia(text, date)               to service_role;
grant  execute on function caja_cerrar(text, int, int, text, int) to service_role;
