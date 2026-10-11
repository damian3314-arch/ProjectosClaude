-- ═══════════════════════════════════════════════════════════════════════
--
--   TUMBAO — CAJA: DEJAR LA BASE Y COMPARAR CON ADMINGYM
--
--   Pégalo en el SQL Editor de Supabase y dale Run. Va DESPUÉS de
--   PEGAR_CAJA.sql. Se puede correr las veces que quieras.
--
--   Sale del cierre real de AdminGym del 1 de agosto:
--
--       DINERO EN CAJA          $ 215.000
--       Dinero retirado         $ 115.000
--       Dinero dejado en caja   $ 100.000
--
--   Agrega lo que faltaba —cuánto se deja en el cajón para mañana— y
--   devuelve los cuatro números con el NOMBRE que usa AdminGym, para
--   que comparar sea leer dos columnas y ya.
--
--   Probado: 4 comprobaciones, incluida que la base de mañana sea lo
--   que se dejó hoy.
--
-- ═══════════════════════════════════════════════════════════════════════

-- ---------------------------------------------------------------------
-- 0024 — Al cerrar no solo se cuenta: se saca la plata y se deja la base
--
-- Del cierre real de AdminGym del 1 de agosto:
--
--     DINERO EN CAJA          $ 215.000
--     Dinero retirado         $ 115.000
--     Dinero dejado en caja   $ 100.000
--
-- 0023 preguntaba cuánto contaste, pero no cuánto dejaste. Sin eso el
-- arqueo del día siguiente arranca adivinando su propia base.
--
-- Se guarda lo dejado y se calcula lo retirado, no al revés: lo que la
-- cajera decide es cuánto deja en el cajón; lo que sale es la resta.
-- ---------------------------------------------------------------------

alter table caja_cierres add column if not exists dejado_cop   int;
alter table caja_cierres add column if not exists retirado_cop int;

comment on column caja_cierres.dejado_cop is
  'Lo que queda en el cajón como base del día siguiente.';
comment on column caja_cierres.retirado_cop is
  'contado − dejado. Lo que sale de la caja ese día.';


-- ---------------------------------------------------------------------
-- caja_cerrar — ahora con la base que se deja
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
  -- No se puede dejar más de lo que hay en el cajón. Si pasa, es que
  -- alguien tecleó mal una de las dos cifras, y conviene frenarlo antes
  -- de que el día siguiente arranque con una base falsa.
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

  v_esp := coalesce(p_base, 100000) + v_ing - v_egr;
  v_ret := p_contado - v_dej;

  insert into caja_cierres (dia, base_cop, contado_cop, esperado_cop,
                            diferencia_cop, dejado_cop, retirado_cop,
                            nota, cerrado_por)
  values (v_dia, coalesce(p_base, 100000), p_contado, v_esp,
          p_contado - v_esp, v_dej, v_ret,
          nullif(btrim(coalesce(p_nota, '')), ''), v_admin)
  on conflict (dia) do update
     set base_cop = excluded.base_cop, contado_cop = excluded.contado_cop,
         esperado_cop = excluded.esperado_cop,
         diferencia_cop = excluded.diferencia_cop,
         dejado_cop = excluded.dejado_cop,
         retirado_cop = excluded.retirado_cop,
         nota = excluded.nota, cerrado_por = excluded.cerrado_por,
         cerrado_at = now();

  return jsonb_build_object('ok', true, 'dia', v_dia,
    'esperado_cop', v_esp, 'contado_cop', p_contado,
    'diferencia_cop', p_contado - v_esp,
    'dejado_cop', v_dej, 'retirado_cop', v_ret);
end;
$$;


-- ---------------------------------------------------------------------
-- caja_del_dia — la base del día sale del cierre de ayer
--
-- Antes siempre asumía 100.000. Ahora, si ayer se cerró dejando otra
-- cantidad, hoy arranca con esa. Es lo que hace que el arqueo encadene
-- de un día al siguiente en vez de resetearse.
--
-- Se añaden también los cuatro números que hay que enfrentar contra el
-- cierre de AdminGym, con los nombres que usa AdminGym, para que quien
-- compare no tenga que traducir.
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

  -- La base de hoy es lo que se dejó ayer. Si ayer no se cerró, o se
  -- cerró sin anotar cuánto quedaba, se asume la base de siempre.
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
    -- Los cuatro que se enfrentan al cierre de AdminGym, con SU nombre.
    -- AdminGym recibe todos los pagos, incluidos los de la página que la
    -- recepcionista mete al abrir la puerta: son la misma plata anotada
    -- dos veces, así que estos números deben coincidir exactos. Si no
    -- coinciden, es que algo se le pasó en el mostrador.
    'contra_admingym', jsonb_build_object(
      'venta_membresias', v_ing_ef,
      'ingresos_a_banco', v_ing_tr + v_reservas,
      'retirar_dinero_de_caja', v_egr_ef,
      'dinero_en_caja', v_base + v_ing_ef - v_egr_ef
    ),
    'cerrado', v_cierre.dia is not null,
    'cierre', case when v_cierre.dia is null then null else jsonb_build_object(
        'contado_cop', v_cierre.contado_cop,
        'esperado_cop', v_cierre.esperado_cop,
        'diferencia_cop', v_cierre.diferencia_cop,
        'dejado_cop', v_cierre.dejado_cop,
        'retirado_cop', v_cierre.retirado_cop,
        'nota', v_cierre.nota,
        'cerrado_at', v_cierre.cerrado_at) end
  );
end;
$$;

-- La firma de caja_cerrar cambió (tiene un parámetro más), así que la
-- de 4 argumentos queda huérfana. Se quita para que nadie la llame por
-- accidente y guarde un cierre sin la base que se deja.
drop function if exists caja_cerrar(text, int, int, text);

revoke execute on function caja_cerrar(text, int, int, text, int) from public, anon, authenticated;
revoke execute on function caja_del_dia(text, date)               from public, anon, authenticated;
grant  execute on function caja_cerrar(text, int, int, text, int) to service_role;
grant  execute on function caja_del_dia(text, date)               to service_role;
