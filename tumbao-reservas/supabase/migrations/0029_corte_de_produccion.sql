-- ---------------------------------------------------------------------
-- 0029 — Corte de producción
--
-- EL PROBLEMA
-- La cola de "Por validar" enseña todo lo que alguna vez quedó a medias,
-- desde el primer día de pruebas. En el estreno eso significa abrir el
-- panel y encontrarse veintitantas reservas de julio que nadie va a
-- resolver nunca — reservas de prueba, abandonos, gente que se arrepintió
-- cuando la página todavía no existía para el público.
--
-- Una bandeja de entrada que arranca con basura no se vacía nunca, y una
-- que no se vacía deja de mirarse. Lo mismo con los 73 depósitos sin
-- reclamar del banco: son de antes de que hubiera dónde reclamarlos.
--
-- LO QUE HACE
-- Fija una fecha de arranque. Todo lo anterior sigue en la base —no se
-- borra ni una fila, la contabilidad de julio queda intacta— pero deja
-- de aparecer en las pantallas de trabajo del día a día.
--
-- POR QUÉ SE FILTRA POR LA FECHA DE LA CLASE Y NO POR LA DE LA RESERVA
-- Porque una reserva a medias de una clase que ya pasó no tiene arreglo:
-- da igual resolverla. Pero una reserva vieja de una clase FUTURA sigue
-- ocupando un cupo, así que tiene que seguir viéndose pase lo que pase.
-- Filtrar por la fecha de la clase da las dos cosas de una: lo que ya no
-- importa desaparece y lo que todavía tiene un cupo vivo no se puede
-- esconder. Filtrar por `created_at` habría escondido justo eso.
--
-- CÓMO SE CAMBIA LA FECHA DESPUÉS
--   update ajustes set valor = '2026-08-10' where clave = 'inicio_produccion';
-- ---------------------------------------------------------------------

create table if not exists ajustes (
  clave      text primary key,
  valor      text not null,
  nota       text,
  updated_at timestamptz not null default now()
);

comment on table ajustes is
  'Cuatro cosas que se ajustan sin migración. No es un cajón de sastre: si algo necesita validación propia, va en su tabla.';

-- Arranca hoy. Si se pega esto un día antes del estreno, se cambia con
-- el update de arriba — por eso es una fila y no una constante en el
-- código.
insert into ajustes (clave, valor, nota)
values ('inicio_produccion',
        ((now() at time zone 'America/Bogota')::date)::text,
        'Desde esta fecha cuentan las pantallas de trabajo. Lo anterior sigue guardado pero no se muestra.')
on conflict (clave) do nothing;

create or replace function inicio_produccion()
returns date
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- El coalesce es la red: si alguien borra la fila, el panel enseña
  -- todo en vez de quedarse en blanco. Fallar mostrando de más es
  -- recuperable; fallar escondiendo no se nota hasta que es tarde.
  select coalesce((select valor::date from ajustes where clave = 'inicio_produccion'),
                  date '2000-01-01')
$$;

revoke execute on function inicio_produccion() from public, anon, authenticated;
grant  execute on function inicio_produccion() to service_role;


-- ---------------------------------------------------------------------
-- admin_pendientes — la cola arranca vacía el día del estreno
-- ---------------------------------------------------------------------
create or replace function admin_pendientes(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_out   jsonb;
  v_desde timestamptz;
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
                 'remitente', p.remitente,
                 'parecido',  round(similitud_nombre(
                                coalesce(r.pagador_nombre, r.nombre), p.remitente), 2),
                 'minutos',   case when r.pagado_en is null then null
                              else round(extract(epoch from
                                     (p.fecha_pago - r.pagado_en)) / 60) end)
               order by case when r.pagado_en is null then 0
                        else abs(extract(epoch from (p.fecha_pago - r.pagado_en))) end)
          from pagos p
         where p.valor_cop = c.precio_cop
           and p.fecha_pago between coalesce(r.pagado_en, r.created_at) - interval '1 hour'
                               and coalesce(r.pagado_en, r.created_at) + interval '3 hours'
           and not exists (select 1 from reservas r2 where r2.pago_id = p.id)
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

  return jsonb_build_object('ok', true, 'reservas', v_out);
end;
$$;


-- ---------------------------------------------------------------------
-- caja_del_dia — el banco tampoco arrastra lo de antes
--
-- Eran 73 depósitos y $3.2 millones sin reclamar, todos de cuando no
-- existía la pantalla para reclamarlos. Mostrarlos como pendientes hacía
-- que "pendiente" no significara nada.
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
  v_desde timestamptz; v_hasta timestamptz; v_corte timestamptz;
  v_recibido int; v_ultimo timestamptz;
  v_libre_hoy int; v_libre_hoy_n int;
  v_libre int; v_libre_n int;
  v_mes int;
  v_sin_resp int; v_sin_resp_n int;
  v_libres jsonb;
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
   where r.estado = 'confirmada'
     and r.tipo = 'suelta'
     and (c.fecha_hora at time zone 'America/Bogota')::date = v_dia;

  v_desde := v_dia::timestamp        at time zone 'America/Bogota';
  v_hasta := (v_dia + 1)::timestamp  at time zone 'America/Bogota';
  -- Nada de antes del estreno entra en el inventario ni en la lista.
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
               'id', p.id,
               'valor_cop', p.valor_cop,
               'fecha_pago', p.fecha_pago,
               'cuando', to_char(p.fecha_pago at time zone 'America/Bogota',
                                 'DD/MM HH24:MI'),
               'dias', (v_dia - (p.fecha_pago at time zone 'America/Bogota')::date),
               'remitente', p.remitente,
               'referencia', p.referencia) as x
        from pagos p
       where not p.consumido and p.fecha_pago >= v_corte
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
    from caja_cierres c where c.dia < v_dia order by c.dia desc limit 1;
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

-- caja_cerrar guarda la misma cifra que enseña la pantalla; si una
-- filtrara por el corte y la otra no, el cierre archivado no cuadraría
-- con lo que la cajera vio al firmarlo.
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

-- La tabla de ajustes no la toca la llave pública: quien pudiera
-- escribirla movería el corte y escondería la cola entera.
alter table ajustes enable row level security;
revoke all on table ajustes from public, anon, authenticated;
grant  select, insert, update on table ajustes to service_role;

revoke execute on function admin_pendientes(text)                 from public, anon, authenticated;
revoke execute on function caja_del_dia(text, date)               from public, anon, authenticated;
revoke execute on function caja_cerrar(text, int, int, text, int) from public, anon, authenticated;
grant  execute on function admin_pendientes(text)                 to service_role;
grant  execute on function caja_del_dia(text, date)               to service_role;
grant  execute on function caja_cerrar(text, int, int, text, int) to service_role;
