-- ---------------------------------------------------------------------
-- 0023 — Caja de mostrador
--
-- Hoy la cajera lleva los comprobantes en WhatsApp, anota en un cuaderno
-- y después transcribe a AdminGym. Cuando no cuadra, no hay forma de
-- saber dónde se perdió.
--
-- Esto NO reemplaza a AdminGym: las membresías siguen viviendo allá, y
-- de allá sale el reporte que alimenta los cupos. Reemplaza el cuaderno,
-- y produce un cierre que se puede poner al lado del de AdminGym.
--
-- LO QUE HACE QUE ESTO SIRVA
-- Un cierre que solo diga "hoy entraron $450.000" no permite cuadrar
-- nada. El que importa es este:
--
--     base + efectivo recibido − efectivo pagado = lo que debe haber
--     menos lo que la cajera contó de verdad     = la diferencia
--
-- Esa última línea es la razón de existir del módulo.
--
-- Las transferencias van aparte: no están en el cajón, así que no entran
-- en el arqueo del efectivo, pero sí en el total del día.
-- ---------------------------------------------------------------------

create table if not exists caja_movimientos (
  id           uuid primary key default extensions.gen_random_uuid(),
  -- El día contable en Bogotá. Se guarda aparte de created_at porque un
  -- movimiento de las 11pm pertenece a ese día, no al siguiente en UTC.
  dia          date not null,
  sentido      text not null check (sentido in ('ingreso', 'egreso')),
  -- 'clase_suelta' | 'mensualidad' | 'cumpleanos' | 'otro_ingreso'
  -- 'profesores' | 'cafeteria' | 'aseo' | 'papeleria' | 'otro_egreso'
  concepto     text not null,
  valor_cop    int  not null check (valor_cop > 0),
  medio        text not null check (medio in ('efectivo', 'transferencia')),
  nota         text,
  -- Quién lo registró, del token de admin. Si hay dos personas en
  -- recepción, el cierre dice quién hizo qué.
  registrado_por uuid references admin_tokens(id),
  created_at   timestamptz not null default now(),
  -- Anular en vez de borrar: en un mostrador uno se equivoca, y el
  -- rastro de la equivocación es parte del cuadre.
  anulado      boolean not null default false,
  anulado_at   timestamptz,
  anulado_por  uuid references admin_tokens(id)
);

create index if not exists caja_por_dia
  on caja_movimientos (dia, created_at desc) where not anulado;

-- El cierre del día. Uno por fecha; se puede reabrir mientras nadie lo
-- haya firmado, porque siempre aparece un movimiento tarde.
create table if not exists caja_cierres (
  dia             date primary key,
  base_cop        int not null default 100000,
  contado_cop     int not null,           -- lo que la cajera contó
  esperado_cop    int not null,           -- lo que la cuenta dice que debería haber
  diferencia_cop  int not null,           -- contado − esperado
  nota            text,
  cerrado_por     uuid references admin_tokens(id),
  cerrado_at      timestamptz not null default now()
);

alter table caja_movimientos enable row level security;
alter table caja_cierres     enable row level security;


-- ---------------------------------------------------------------------
-- caja_registrar
-- ---------------------------------------------------------------------
create or replace function caja_registrar(
  p_token    text,
  p_sentido  text,
  p_concepto text,
  p_valor    int,
  p_medio    text,
  p_nota     text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_id    uuid;
  v_dia   date;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  if p_valor is null or p_valor <= 0 then
    return jsonb_build_object('ok', false, 'error', 'VALOR_INVALIDO',
      'mensaje', 'El valor tiene que ser mayor que cero.');
  end if;
  -- Un tope alto pero real: atrapa el cero de más al teclear, que es el
  -- error que de verdad pasa en un mostrador.
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

  v_dia := (now() at time zone 'America/Bogota')::date;

  insert into caja_movimientos (dia, sentido, concepto, valor_cop, medio,
                                nota, registrado_por)
  values (v_dia, p_sentido, left(coalesce(p_concepto, 'otro'), 40), p_valor,
          p_medio, nullif(btrim(coalesce(p_nota, '')), ''), v_admin)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id, 'dia', v_dia);
end;
$$;


-- ---------------------------------------------------------------------
-- caja_anular — deshacer un movimiento
--
-- Solo del día en curso y solo si el día no está cerrado. Después del
-- cierre, un movimiento no se toca: se hace el ajuste al día siguiente,
-- que es como funciona una caja de verdad.
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
     set anulado = true, anulado_at = now(), anulado_por = v_admin
   where id = p_id;

  return jsonb_build_object('ok', true, 'valor_cop', v_mov.valor_cop,
                            'concepto', v_mov.concepto);
end;
$$;


-- ---------------------------------------------------------------------
-- caja_del_dia — todo lo que necesita la pantalla y el cierre
--
-- Junta las tres fuentes de plata del día:
--   · mostrador en efectivo   -> sí está en el cajón
--   · mostrador transferencia -> no está en el cajón
--   · reservas confirmadas    -> tampoco, entraron al banco solas
--
-- El arqueo solo mira el efectivo. Mezclar las tres en un solo número es
-- lo que hace que un cierre no sirva para cuadrar.
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
    coalesce(sum(valor_cop) filter (where sentido='egreso'  and medio='transferencia'), 0)
  into v_ing_ef, v_ing_tr, v_egr_ef, v_egr_tr
  from caja_movimientos where dia = v_dia and not anulado;

  -- Lo que entró por la página ese día, ya confirmado. Se cuenta por la
  -- clase, no por cuándo se pagó: es como lo cuenta AdminGym.
  select coalesce(sum(c.precio_cop), 0) into v_reservas
    from reservas r join clases c on c.id = r.clase_id
   where r.estado = 'confirmada'
     and r.tipo = 'suelta'
     and (c.fecha_hora at time zone 'America/Bogota')::date = v_dia;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'sentido', m.sentido, 'concepto', m.concepto,
           'valor_cop', m.valor_cop, 'medio', m.medio, 'nota', m.nota,
           'hora', to_char(m.created_at at time zone 'America/Bogota', 'HH24:MI'),
           'quien', t.nombre)
         order by m.created_at desc), '[]'::jsonb)
    into v_movs
    from caja_movimientos m
    left join admin_tokens t on t.id = m.registrado_por
   where m.dia = v_dia and not m.anulado;

  select * into v_cierre from caja_cierres where dia = v_dia;
  v_base := coalesce(v_cierre.base_cop, 100000);

  return jsonb_build_object(
    'ok', true,
    'dia', v_dia,
    'movimientos', v_movs,
    'base_cop', v_base,
    -- Efectivo: esto sí se cuenta a mano al cerrar.
    'ingreso_efectivo', v_ing_ef,
    'egreso_efectivo',  v_egr_ef,
    'esperado_efectivo', v_base + v_ing_ef - v_egr_ef,
    -- Lo que no pasa por el cajón.
    'ingreso_transferencia', v_ing_tr,
    'egreso_transferencia',  v_egr_tr,
    'reservas_cop', v_reservas,
    -- El total del día, para comparar contra AdminGym.
    'total_ingresos', v_ing_ef + v_ing_tr + v_reservas,
    'total_egresos',  v_egr_ef + v_egr_tr,
    'cerrado', v_cierre.dia is not null,
    'cierre', case when v_cierre.dia is null then null else jsonb_build_object(
        'contado_cop', v_cierre.contado_cop,
        'esperado_cop', v_cierre.esperado_cop,
        'diferencia_cop', v_cierre.diferencia_cop,
        'nota', v_cierre.nota,
        'cerrado_at', v_cierre.cerrado_at) end
  );
end;
$$;


-- ---------------------------------------------------------------------
-- caja_cerrar — el arqueo
--
-- No impide cerrar con diferencia: una caja que no cuadra es un hecho,
-- no un error de captura. Se guarda la diferencia y se sigue.
-- ---------------------------------------------------------------------
create or replace function caja_cerrar(
  p_token text, p_contado int, p_base int default 100000, p_nota text default null)
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
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if p_contado is null or p_contado < 0 then
    return jsonb_build_object('ok', false, 'error', 'CONTADO_INVALIDO');
  end if;

  v_dia := (now() at time zone 'America/Bogota')::date;

  select
    coalesce(sum(valor_cop) filter (where sentido='ingreso' and medio='efectivo'), 0),
    coalesce(sum(valor_cop) filter (where sentido='egreso'  and medio='efectivo'), 0)
  into v_ing, v_egr
  from caja_movimientos where dia = v_dia and not anulado;

  v_esp := coalesce(p_base, 100000) + v_ing - v_egr;

  insert into caja_cierres (dia, base_cop, contado_cop, esperado_cop,
                            diferencia_cop, nota, cerrado_por)
  values (v_dia, coalesce(p_base, 100000), p_contado, v_esp,
          p_contado - v_esp, nullif(btrim(coalesce(p_nota, '')), ''), v_admin)
  on conflict (dia) do update
     set base_cop = excluded.base_cop, contado_cop = excluded.contado_cop,
         esperado_cop = excluded.esperado_cop,
         diferencia_cop = excluded.diferencia_cop,
         nota = excluded.nota, cerrado_por = excluded.cerrado_por,
         cerrado_at = now();

  return jsonb_build_object('ok', true, 'dia', v_dia,
    'esperado_cop', v_esp, 'contado_cop', p_contado,
    'diferencia_cop', p_contado - v_esp);
end;
$$;


revoke execute on function caja_registrar(text,text,text,int,text,text) from public, anon, authenticated;
revoke execute on function caja_anular(text, uuid)                      from public, anon, authenticated;
revoke execute on function caja_del_dia(text, date)                     from public, anon, authenticated;
revoke execute on function caja_cerrar(text, int, int, text)            from public, anon, authenticated;

grant execute on function caja_registrar(text,text,text,int,text,text) to service_role;
grant execute on function caja_anular(text, uuid)                      to service_role;
grant execute on function caja_del_dia(text, date)                     to service_role;
grant execute on function caja_cerrar(text, int, int, text)            to service_role;
