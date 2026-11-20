-- 0082 · Las tarjetas del dueño: hoy, la semana, el mes y contra qué.
--
-- Damián: «cuando ingrese desde el celular tenga una visual tipo
-- tarjetas con las cosas importantes para ese día, algo muy para el
-- propietario y administrador para saber cómo está el día. La semana y
-- el mes. Comenzar a tener comparativos rápidos de ventas con el mes
-- anterior y de ingresos versus gastos del mes.»
--
-- ── LA DECISIÓN QUE MANDA SOBRE TODO LO DEMÁS ───────────────────────
--
-- «Ventas del día» ya tiene una definición en esta casa: la que imprime
-- la tirilla de cierre. Y ya hubo un incidente por tener dos: el 5 de
-- septiembre la hoja 1 decía 300.000 y la hoja 2 decía 315.000, y
-- Damián lo dijo con todas las letras —«esas son las diferencias que
-- causan las confusiones»—. Una tarjeta que sume distinto que la
-- tirilla del mismo día no es una tarjeta nueva: es una tercera
-- versión de la verdad.
--
-- Así que `ventas_entre` copia la regla de `caja_del_dia`, pieza por
-- pieza, y `pruebas/humo-tarjetas.sql` compara día por día las dos
-- cuentas contra TODOS los días con datos. Si alguien cambia una y no
-- la otra, la prueba lo grita. Eso es lo que sostiene que no se
-- despeguen; no el buen propósito de este comentario.
--
-- La regla, para que quede escrita en un solo sitio:
--
--   ingresos del día =
--       todo ingreso de caja_movimientos fechado ese día (no anulado)
--     + lo que pagó por la página quien ENTRÓ ese día
--     + lo que se apuntó en recepción sin que el cobro quedara registrado
--
-- Las dos últimas van por FECHA DE CLASE, no por fecha de pago: es la
-- cuenta de quién entró por la puerta, que es la que el dueño lee. Y
-- excluyen a quien no vino o se reprogramó (la 0071).
--
-- ── POR QUÉ UNA SOLA FUNCIÓN PARA RANGOS ────────────────────────────
--
-- `ventas_entre(d, d)` es el día; `ventas_entre(1, 30)` es el mes. Si
-- fueran dos funciones, el mes podría sumar distinto que la suma de sus
-- días y nadie lo notaría. Una sola no puede contradecirse a sí misma.
--
-- ── EL COMPARATIVO ES HONESTO O NO SIRVE ────────────────────────────
--
-- El mes pasado se compara HASTA EL MISMO DÍA: del 1 al 12 de
-- septiembre contra el 1 al 12 de agosto, no contra agosto entero. Y si
-- la ventana de comparación empieza antes de que la Caja estuviera en
-- uso, la función lo dice con `parcial`, porque un «+180%» que en
-- realidad compara doce días contra tres es peor que no poner nada.
--
-- La primera versión de esta migración medía eso contra `primer_dato`,
-- el primer día con CUALQUIER dato, y eso daba 28 de julio: una reserva
-- suelta de una clase de julio. Con esa referencia el aviso salía en
-- falso negativo —decía que agosto era comparable cuando la Caja no
-- empezó a registrar hasta el 10—. La referencia buena es
-- `primer_caja`: el primer movimiento de caja_movimientos, que es
-- cuando alguien empezó de verdad a apuntar la plata. Se corrigió el
-- mismo día; `primer_dato` se queda porque sigue diciendo algo
-- distinto y cierto.

-- ── los ingresos y los gastos de un rango de días ───────────────────
create or replace function public.ventas_entre(p_desde date, p_hasta date)
returns jsonb
language sql
stable
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
  with caja as (
    select
      coalesce(sum(valor_cop) filter (where sentido = 'ingreso'), 0) as ingreso,
      coalesce(sum(valor_cop) filter (where sentido = 'egreso'), 0)  as egreso,
      -- 0069/0077: de qué bolsillo salió. El dueño quiere saber si el
      -- gasto se pagó del cajón de la cajera o de la plata de la empresa.
      coalesce(sum(valor_cop) filter (where sentido = 'egreso'
                                        and medio = 'efectivo'
                                        and coalesce(origen, 'caja_menor') = 'caja_menor'), 0)
        as egreso_caja_menor,
      coalesce(sum(valor_cop) filter (where sentido = 'ingreso'
                                        and concepto in ('mensualidad', 'media_mensualidad')), 0)
        as mensualidades_cop,
      coalesce(count(*) filter (where sentido = 'ingreso'
                                  and concepto in ('mensualidad', 'media_mensualidad')), 0)
        as mensualidades_n
      from caja_movimientos
     where dia between p_desde and p_hasta and not anulado
  ),
  -- Quien pagó por la página y entró. Palabra por palabra el
  -- `v_entra_pag_tr` de caja_del_dia.
  pagina as (
    select coalesce(sum(c.precio_cop), 0) as cop
      from reservas r join clases c on c.id = r.clase_id
     where r.estado = 'confirmada' and r.tipo = 'suelta'
       and r.pago_id is not null
       and r.origen in ('web', 'formulario')
       and r.no_vino_at is null and r.reprogramada_a is null
       and (c.fecha_hora at time zone 'America/Bogota')::date between p_desde and p_hasta
  ),
  -- Apuntada en recepción y el cobro no quedó en ninguna parte. Entró
  -- igual, así que cuenta. Palabra por palabra el `v_a_mano`.
  mano as (
    select coalesce(sum(c.precio_cop), 0) as cop
      from reservas r join clases c on c.id = r.clase_id
     where r.estado = 'confirmada' and r.tipo = 'suelta'
       and r.origen = 'recepcion'
       and r.cobro_mov_id is null and r.pago_id is null
       and (c.fecha_hora at time zone 'America/Bogota')::date between p_desde and p_hasta
  ),
  -- Cuánta GENTE entró a clase suelta, el `v_personas_n` de la 0059:
  -- no se suman casillas de plata, se cuenta a quien pasó la puerta.
  suyas as (
    select r.id, r.pago_id
      from reservas r join clases c on c.id = r.clase_id
     where r.estado = 'confirmada' and r.tipo = 'suelta'
       and r.no_vino_at is null and r.reprogramada_a is null
       and (c.fecha_hora at time zone 'America/Bogota')::date between p_desde and p_hasta
  ),
  puerta as (
    select (select count(*) from suyas)
           -- 0065: tres que pagan juntas son UN movimiento y TRES
           -- personas. Y si el cobro es el depósito de una reserva de
           -- arriba, es la misma persona: no se cuenta dos veces.
           + (select coalesce(sum(m.cantidad), 0) from caja_movimientos m
               where m.dia between p_desde and p_hasta and not m.anulado
                 and m.sentido = 'ingreso' and m.concepto = 'clase_suelta'
                 and not exists (select 1 from suyas s
                                  where s.pago_id is not null
                                    and s.pago_id = m.pago_id)) as personas
  )
  select jsonb_build_object(
    'desde', p_desde, 'hasta', p_hasta,
    'dias', (p_hasta - p_desde) + 1,
    'ingreso_cop', caja.ingreso + pagina.cop + mano.cop,
    'egreso_cop',  caja.egreso,
    'egreso_caja_menor_cop', caja.egreso_caja_menor,
    'queda_cop',   (caja.ingreso + pagina.cop + mano.cop) - caja.egreso,
    'personas',    puerta.personas,
    'mensualidades_cop', caja.mensualidades_cop,
    'mensualidades_n',   caja.mensualidades_n,
    -- El desglose, para no tener que volver a preguntar de dónde sale.
    'de_caja_cop',   caja.ingreso,
    'de_pagina_cop', pagina.cop,
    'a_mano_cop',    mano.cop)
    from caja, pagina, mano, puerta;
$function$;

comment on function public.ventas_entre(date, date) is
  '0082: ingresos y gastos de un rango, con la MISMA regla que la tirilla '
  'de cierre. Si cambia una, pruebas/humo-tarjetas.sql falla.';

-- ── las tarjetas, ya armadas ────────────────────────────────────────
create or replace function public.admin_resumen_gerencia(p_token text, p_dia date default null)
returns jsonb
language plpgsql
-- VOLATILE obligatorio: verificar_token_admin_rol actualiza ultimo_uso, y
-- una función STABLE corre en transacción de solo lectura. Eso ya rompió
-- /api/mensualidad una vez (la 0073).
volatile
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_admin record;
  v_hoy   date;
  v_sem_ini date; v_sem_ant_ini date; v_sem_ant_fin date;
  v_mes_ini date; v_mes_ant_ini date; v_mes_ant_fin date;
  v_primer  date;
  v_primer_caja date;
  v_gastos  jsonb;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  -- Esto es la plata del negocio: la ve quien manda. Un token de antes
  -- de que existieran los roles (rol nulo) sigue viendo todo, igual que
  -- en el resto del panel.
  if v_admin.rol = 'cajero' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO',
      'mensaje', 'Esta vista es del propietario y el administrador.');
  end if;

  v_hoy := coalesce(p_dia, (now() at time zone 'America/Bogota')::date);

  -- Semana de lunes a domingo, como se cuenta aquí.
  v_sem_ini     := date_trunc('week', v_hoy::timestamp)::date;
  v_sem_ant_ini := v_sem_ini - 7;
  v_sem_ant_fin := v_sem_ant_ini + (v_hoy - v_sem_ini);

  v_mes_ini     := date_trunc('month', v_hoy::timestamp)::date;
  v_mes_ant_ini := (v_mes_ini - interval '1 month')::date;
  -- Hasta el mismo día del mes, y nunca más allá del último día de ese
  -- mes: el 31 de marzo contra febrero se queda en el 28.
  v_mes_ant_fin := least(v_mes_ant_ini + (v_hoy - v_mes_ini), v_mes_ini - 1);

  -- Desde cuándo hay algo que comparar. Sin esto, un mes sin datos
  -- parecería un mes sin ventas.
  select least(
           (select min(dia) from caja_movimientos where not anulado),
           (select min((c.fecha_hora at time zone 'America/Bogota')::date)
              from reservas r join clases c on c.id = r.clase_id
             where r.estado = 'confirmada' and r.tipo = 'suelta'))
    into v_primer;

  -- Desde cuándo se está apuntando la plata de verdad. Es otra cosa que
  -- `v_primer`, y es la que decide si una comparación con el pasado es
  -- justa: antes de este día la Caja no existía, así que ese tramo no
  -- está en cero porque no se vendiera, sino porque nadie lo apuntaba.
  select min(dia) into v_primer_caja from caja_movimientos where not anulado;

  -- En qué se fue la plata este mes. Es la pregunta que Damián hizo
  -- para la tirilla —«cuándo salió para pagar a un profesor o gasto»— y
  -- la misma sirve para el mes.
  select coalesce(jsonb_agg(jsonb_build_object(
           'concepto', t.concepto, 'cop', t.cop, 'n', t.n,
           'de_caja_menor', t.menor) order by t.cop desc), '[]'::jsonb)
    into v_gastos
    from (select m.concepto,
                 sum(m.valor_cop) as cop,
                 count(*) as n,
                 bool_and(m.medio = 'efectivo'
                          and coalesce(m.origen, 'caja_menor') = 'caja_menor') as menor
            from caja_movimientos m
           where m.dia between v_mes_ini and v_hoy
             and not m.anulado and m.sentido = 'egreso'
           group by m.concepto) t;

  return jsonb_build_object(
    'ok', true,
    'hoy', v_hoy,
    'primer_dato', v_primer,
    'primer_caja', v_primer_caja,
    'dia',            ventas_entre(v_hoy, v_hoy),
    -- El mismo día de la semana pasada, que es la comparación justa para
    -- un día: un martes no se parece a un sábado.
    'dia_semana_antes', ventas_entre(v_hoy - 7, v_hoy - 7),
    'semana',         ventas_entre(v_sem_ini, v_hoy),
    'semana_antes',   ventas_entre(v_sem_ant_ini, v_sem_ant_fin),
    'mes',            ventas_entre(v_mes_ini, v_hoy),
    'mes_antes',      ventas_entre(v_mes_ant_ini, v_mes_ant_fin),
    -- Lo que hace honesto el comparativo: avisar cuando la ventana de
    -- atrás empieza antes de que la Caja estuviera en uso.
    'mes_antes_parcial',    v_mes_ant_ini < v_primer_caja,
    'semana_antes_parcial', v_sem_ant_ini < v_primer_caja,
    'gastos_mes', v_gastos);
end;
$function$;

revoke execute on function public.ventas_entre(date, date) from public, anon, authenticated;
revoke execute on function public.admin_resumen_gerencia(text, date)
  from public, anon, authenticated;
grant execute on function public.admin_resumen_gerencia(text, date) to service_role;
