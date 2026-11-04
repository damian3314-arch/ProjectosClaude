-- ---------------------------------------------------------------------
-- 0026 — El banco como tercer testigo del cierre
--
-- LO QUE YA HABÍA
-- El workflow "Tumbao · Ingesta de pagos" lleva desde julio leyendo las
-- alertas de Bancolombia y escribiendo en `pagos`. Cuando un pago casa
-- con una reserva que lo esperaba, queda `consumido = true` y la reserva
-- guarda su `pago_id`. Es decir: la plata que entra al banco ya se está
-- registrando. Lo único que faltaba era mirarla.
--
-- POR QUÉ IMPORTA QUE SEA UN TERCERO
-- El cierre de hoy compara dos columnas que, en el fondo, son la misma
-- mano: lo que la recepcionista anotó en esta página y lo que anotó en
-- AdminGym. Si se equivoca —o si aprueba un comprobante falso— las dos
-- columnas cuadran igual, porque las dos están mal de la misma forma.
--
-- El correo del banco no lo escribe nadie del mostrador. Es el único
-- dato del cierre que no se puede teclear. Por eso vale.
--
-- LA CUENTA QUE SÍ DEBERÍA DAR CERO
--
--     recibido en banco hoy
--   − el que ya casó con una reserva      (pagos.consumido)
--   − las transferencias del mostrador    (caja_movimientos)
--   = sin identificar
--
--   > 0  entró plata que nadie apuntó. Suele ser un pago adelantado o
--        alguien que transfirió sin avisar. Hay que buscarlo, no frenar.
--   < 0  se apuntó una transferencia que el banco NUNCA confirmó. Esto
--        es lo caro: un comprobante viejo, editado, o de otra cuenta.
--        Se detecta el mismo día en vez de a fin de mes.
--
-- POR QUÉ NO BLOQUEA EL CIERRE
-- Porque el banco y la caja miden días distintos a propósito. Alguien
-- paga hoy a las 7:45 pm una clase del martes: el banco lo ve hoy, la
-- clase entra el martes. Exigir que cuadren obligaría a la cajera a
-- inventar ajustes para poder cerrar, y un cierre que se fuerza deja de
-- servir para lo único que sirve. El cierre lo sigue mandando el
-- efectivo, que es lo único que se cuenta a mano.
-- ---------------------------------------------------------------------

-- Los sumatorios del día van por rango y no por ::date para que el
-- índice sirva: `x at time zone 'America/Bogota'` es STABLE, no
-- IMMUTABLE, así que envuelto en un ::date obliga a recorrer la tabla.
create index if not exists pagos_por_fecha on pagos (fecha_pago);

alter table caja_cierres add column if not exists banco_cop            int;
alter table caja_cierres add column if not exists banco_sin_ident_cop  int;

comment on column caja_cierres.banco_cop is
  'Lo que Bancolombia confirmó ese día. No lo teclea nadie: sale del correo.';
comment on column caja_cierres.banco_sin_ident_cop is
  'banco − reservas casadas − transferencias del mostrador. Negativo = se apuntó plata que el banco no confirmó.';


-- ---------------------------------------------------------------------
-- caja_del_dia — ahora con el bloque `banco`
--
-- No se toca nada de lo que ya devolvía: `contra_admingym` compara con
-- AdminGym y esa comparación sí tiene que dar exacta, porque las dos
-- partes anotan lo mismo. El bloque nuevo es otra pregunta distinta.
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
  v_banco int; v_banco_res int; v_banco_n int;
  v_ultimo timestamptz;
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

  -- ---- el tercer testigo ----
  v_desde := v_dia::timestamp        at time zone 'America/Bogota';
  v_hasta := (v_dia + 1)::timestamp  at time zone 'America/Bogota';

  select
    coalesce(sum(valor_cop), 0),
    -- Los que ya casaron con una reserva se cuentan por la fecha en que
    -- ENTRÓ LA PLATA, no por la de la clase. Es lo que hace comparable
    -- esta cifra con el extracto: quien paga hoy una clase del martes
    -- sale aquí hoy, que es cuando el banco lo vio.
    coalesce(sum(valor_cop) filter (where consumido), 0),
    max(fecha_pago)
  into v_banco, v_banco_res, v_ultimo
  from pagos
  where fecha_pago >= v_desde and fecha_pago < v_hasta;

  v_banco_n := v_banco - v_banco_res - v_ing_tr;

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
    -- Informativo, nunca bloqueante. `corte` es la hora del último aviso
    -- que llegó: a las 7:30 pm la cifra es "hasta ahora", no "del día".
    'banco', jsonb_build_object(
      'recibido_cop',   v_banco,
      'de_reservas_cop', v_banco_res,
      'de_mostrador_cop', v_ing_tr,
      'sin_identificar_cop', v_banco_n,
      'corte', case when v_ultimo is null then null
               else to_char(v_ultimo at time zone 'America/Bogota', 'HH24:MI') end
    ),
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
-- caja_cerrar — deja constancia de lo que decía el banco al cerrar
--
-- La cifra del banco sigue cambiando después del cierre (alguien paga a
-- las 11 pm). Guardar la foto del momento es lo que permite, un mes
-- después, saber si el descuadre ya estaba a las 7:30 o apareció luego.
-- La firma no cambia: se calcula aquí dentro, no se recibe.
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
  v_ing   int; v_egr int; v_ing_tr int;
  v_dej   int; v_ret int;
  v_banco int; v_banco_res int; v_banco_n int;
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
    coalesce(sum(valor_cop) filter (where sentido='egreso'  and medio='efectivo'), 0),
    coalesce(sum(valor_cop) filter (where sentido='ingreso' and medio='transferencia'), 0)
  into v_ing, v_egr, v_ing_tr
  from caja_movimientos where dia = v_dia and not anulado;

  v_desde := v_dia::timestamp       at time zone 'America/Bogota';
  v_hasta := (v_dia + 1)::timestamp at time zone 'America/Bogota';
  select coalesce(sum(valor_cop), 0),
         coalesce(sum(valor_cop) filter (where consumido), 0)
    into v_banco, v_banco_res
    from pagos where fecha_pago >= v_desde and fecha_pago < v_hasta;
  v_banco_n := v_banco - v_banco_res - v_ing_tr;

  v_esp := coalesce(p_base, 100000) + v_ing - v_egr;
  v_ret := p_contado - v_dej;

  insert into caja_cierres (dia, base_cop, contado_cop, esperado_cop,
                            diferencia_cop, dejado_cop, retirado_cop,
                            banco_cop, banco_sin_ident_cop,
                            nota, cerrado_por)
  values (v_dia, coalesce(p_base, 100000), p_contado, v_esp,
          p_contado - v_esp, v_dej, v_ret,
          v_banco, v_banco_n,
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
    'banco_cop', v_banco, 'banco_sin_ident_cop', v_banco_n);
end;
$$;

revoke execute on function caja_cerrar(text, int, int, text, int) from public, anon, authenticated;
revoke execute on function caja_del_dia(text, date)               from public, anon, authenticated;
grant  execute on function caja_cerrar(text, int, int, text, int) to service_role;
grant  execute on function caja_del_dia(text, date)               to service_role;
