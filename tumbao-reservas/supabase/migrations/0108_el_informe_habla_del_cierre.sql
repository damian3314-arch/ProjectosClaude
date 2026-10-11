-- 0108 · El informe de la noche habla del cierre de caja, no de listas
--        pendientes, y trae con qué sacar conclusiones que sirvan.
--
-- LO QUE DIJO DAMIÁN (28 sep)
-- «La cajera registra todas las operaciones del dinero que ingresa en el
--  día; esa misma información es la de AdminGym. Cuando hay registros que
--  no se seleccionaron desde la lista pero ella sí los registra a mano,
--  el cierre igual se realizó bien. Y hay gente que envía plata y queda
--  sin asignar porque no ha escrito ni se ha presentado. Mencionar "pagos
--  sin asignar" es confuso: parece que el cuadre no se hizo bien.»
-- «Lo de recepción cargado hasta el 19 era histórico para confrontar
--  gastos. El cierre de la página de Tumbao es real y es igual a AdminGym.»
-- «En el resumen de las 10 pm: cuántas clases sueltas, cuántas
--  mensualidades, cuánto entró al banco, cuánto se cruzó en el cierre,
--  cuánto quedó pendiente por cruzar (pagos futuros o sin identificar).
--  Y los insights, apuntados a mover la aguja: ventas, reservas.»
--
-- QUÉ CAMBIA EN tablero_tumbao
--   · Sale de 'plata': pagos_sin_asignar (la lista acumulada) y todo lo
--     de ventas_mostrador (recepcion_*). El modelo no puede mencionar lo
--     que no recibe.
--   · Entra 'ventas': las del cierre de caja, con ventas_entre(), la
--     misma función que usan la tirilla y el resumen del dueño. Hoy
--     desglosado (sueltas, mensualidades, otros, tiqueteras en línea),
--     el mes contra el mismo tramo del anterior y contra la meta.
--   · Entra 'cruce_banco': lo que entró al banco hoy, lo que quedó
--     cruzado y lo pendiente. Lo registrado a mano por transferencia
--     (sin escoger el depósito de la lista) CUENTA como cruzado.
--   · Entra 'para_insights': ocupación por franja, clientes nuevos que
--     vuelven, clientes de suelta que ya pagan más que una tiquetera,
--     renovaciones en juego y resultado de las campañas de WhatsApp.
--
-- La meta del mes vive en ajustes.meta_ventas_mes ({"AAAA-MM": valor}).
-- Septiembre 2026: $16.000.000, la que puso Damián el 27 sep.

insert into public.ajustes (clave, valor, nota) values
  ('meta_ventas_mes', '{"2026-09": 16000000}',
   'Meta de ventas por mes (cifra del cierre de caja, ventas_entre). La lee el informe de la noche. 0108.')
on conflict (clave) do nothing;

create or replace function public.tablero_tumbao(p_tipo text default 'manana')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  -- tumbao.dia (set local) deja probar el informe de un día pasado.
  d        date := coalesce(nullif(current_setting('tumbao.dia', true), '')::date,
                            (now() at time zone 'America/Bogota')::date);
  manana   date := d + 1;
  ini_mes  date := date_trunc('month', d)::date;
  fin_mes  date := (date_trunc('month', d) + interval '1 month - 1 day')::date;
  ini_ant  date := (date_trunc('month', d) - interval '1 month')::date;
  mismo_ant date := least((date_trunc('month', d) - interval '1 month')::date
                          + (d - date_trunc('month', d)::date),
                          (date_trunc('month', d) - interval '1 day')::date);
  v_hoy    jsonb;
  v_mes    jsonb;
  v_ant    jsonb;
  v_meta   bigint;
  v_habiles int;
  v_otros  bigint; v_otros_n int;
  v_banco  bigint; v_libre bigint; v_a_mano bigint;
  v_cierre caja_cierres;
  r        jsonb := '{}'::jsonb;
begin
  r := r || jsonb_build_object(
    'tipo', p_tipo,
    'fecha', d,
    'dia_semana', (array['lunes','martes','miércoles','jueves','viernes','sábado','domingo'])[extract(isodow from d)::int]);

  r := r || jsonb_build_object('clases_hoy', (
    select coalesce(jsonb_agg(x.j order by x.h), '[]'::jsonb) from (
      select c.fecha_hora as h, jsonb_build_object(
        'hora', to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'),
        'clase', c.nombre,
        'reservas_confirmadas', (select count(*) from reservas x where x.clase_id = c.id and x.estado = 'confirmada'),
        'con_tiquetera', (select count(*) from reservas x where x.clase_id = c.id and x.estado = 'confirmada' and x.tiquetera_id is not null),
        'mensualidades_de_esa_hora', (select count(*) from membresias m
                                        where m.fin >= d and m.inicio <= d
                                          and m.hora = (c.fecha_hora at time zone 'America/Bogota')::time),
        'cupo_para_reservar', c.cupo_total,
        'libres', greatest(c.cupo_total - c.cupo_tomado, 0),
        'asistieron', (select count(*) from asistencias a where a.clase_id = c.id)) as j
      from clases c
     where c.activa and (c.fecha_hora at time zone 'America/Bogota')::date = d) x));

  r := r || jsonb_build_object('clases_manana', (
    select coalesce(jsonb_agg(x.j order by x.h), '[]'::jsonb) from (
      select c.fecha_hora as h, jsonb_build_object(
        'hora', to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'),
        'clase', c.nombre,
        'reservas_confirmadas', (select count(*) from reservas x where x.clase_id = c.id and x.estado = 'confirmada'),
        'mensualidades_de_esa_hora', (select count(*) from membresias m
                                        where m.fin >= manana and m.inicio <= manana
                                          and m.hora = (c.fecha_hora at time zone 'America/Bogota')::time),
        'libres', greatest(c.cupo_total - c.cupo_tomado, 0)) as j
      from clases c
     where c.activa and (c.fecha_hora at time zone 'America/Bogota')::date = manana) x));

  r := r || jsonb_build_object('reservas', jsonb_build_object(
    'para_hoy', (select count(*) from reservas x join clases c on c.id = x.clase_id
                  where x.estado = 'confirmada' and (c.fecha_hora at time zone 'America/Bogota')::date = d),
    'para_hoy_promedio_4_semanas', (select round(count(*) / 4.0, 1) from reservas x join clases c on c.id = x.clase_id
                  where x.estado = 'confirmada'
                    and (c.fecha_hora at time zone 'America/Bogota')::date in (d - 7, d - 14, d - 21, d - 28)),
    'hechas_hoy', (select count(*) from reservas x
                    where x.estado = 'confirmada' and (x.created_at at time zone 'America/Bogota')::date = d),
    'hechas_hoy_promedio_4_semanas', (select round(count(*) / 4.0, 1) from reservas x
                    where x.estado = 'confirmada'
                      and (x.created_at at time zone 'America/Bogota')::date in (d - 7, d - 14, d - 21, d - 28)),
    'clientes_nuevos_hoy', (select count(*) from (
                    select right(regexp_replace(telefono, '\D', '', 'g'), 10) t, min(created_at) primera
                      from reservas where estado = 'confirmada' group by 1) p
                    where (p.primera at time zone 'America/Bogota')::date = d),
    'mes_en_curso', (select count(*) from reservas x where x.estado = 'confirmada'
                      and (x.created_at at time zone 'America/Bogota')::date between ini_mes and d),
    'mes_anterior_mismo_tramo', (select count(*) from reservas x where x.estado = 'confirmada'
                      and (x.created_at at time zone 'America/Bogota')::date between ini_ant and mismo_ant),
    'proximos_7_dias', (select count(*) from reservas x join clases c on c.id = x.clase_id
                  where x.estado = 'confirmada'
                    and (c.fecha_hora at time zone 'America/Bogota')::date between d + 1 and d + 7),
    'pendientes_de_pago', (select count(*) from reservas x join clases c on c.id = x.clase_id
                  where x.estado in ('pendiente_pago', 'verificando', 'pendiente_validacion')
                    and c.fecha_hora >= now())));

  r := r || jsonb_build_object('asistencias', jsonb_build_object(
    'hoy', (select count(*) from asistencias a join clases c on c.id = a.clase_id
             where (c.fecha_hora at time zone 'America/Bogota')::date = d),
    'ayer', (select count(*) from asistencias a join clases c on c.id = a.clase_id
             where (c.fecha_hora at time zone 'America/Bogota')::date = d - 1),
    'mismo_dia_promedio_4_semanas', (select round(count(*) / 4.0, 1) from asistencias a join clases c on c.id = a.clase_id
             where (c.fecha_hora at time zone 'America/Bogota')::date in (d - 7, d - 14, d - 21, d - 28)),
    'mes_en_curso', (select count(*) from asistencias a join clases c on c.id = a.clase_id
             where (c.fecha_hora at time zone 'America/Bogota')::date between ini_mes and d),
    'mes_anterior_mismo_tramo', (select count(*) from asistencias a join clases c on c.id = a.clase_id
             where (c.fecha_hora at time zone 'America/Bogota')::date between ini_ant and mismo_ant)));

  -- ── VENTAS: las del cierre de caja (ventas_entre, igual que la tirilla) ──
  v_hoy := ventas_entre(d, d);
  v_mes := ventas_entre(ini_mes, d);
  v_ant := ventas_entre(ini_ant, mismo_ant);

  select coalesce(sum(valor_cop), 0), count(*) into v_otros, v_otros_n
    from caja_movimientos
   where dia = d and not anulado and sentido = 'ingreso'
     and concepto not in ('clase_suelta', 'mensualidad', 'media_mensualidad');

  select (valor::jsonb ->> to_char(d, 'YYYY-MM'))::bigint into v_meta
    from ajustes where clave = 'meta_ventas_mes';

  -- Días con clase que quedan DESPUÉS de hoy: lunes a sábado, sin festivos.
  select count(*) into v_habiles
    from generate_series(d + 1, fin_mes, interval '1 day') g
   where extract(isodow from g) < 7
     and not exists (select 1 from festivos f where f.fecha = g::date);

  r := r || jsonb_build_object('ventas', jsonb_build_object(
    'fuente', 'cierre de caja de la página (igual a AdminGym)',
    'hoy', jsonb_build_object(
      'total_cop', (v_hoy->>'ingreso_cop')::bigint,
      'sueltas_personas', (v_hoy->>'personas')::int,
      'sueltas_cop', (v_hoy->>'ingreso_cop')::bigint - (v_hoy->>'mensualidades_cop')::bigint - v_otros,
      'mensualidades_n', (v_hoy->>'mensualidades_n')::int,
      'mensualidades_cop', (v_hoy->>'mensualidades_cop')::bigint,
      'otros_n', v_otros_n,
      'otros_cop', v_otros,
      'efectivo_cop', (select coalesce(sum(valor_cop), 0) from caja_movimientos
                        where dia = d and not anulado and sentido = 'ingreso' and medio = 'efectivo'),
      'tiqueteras_en_linea_n', (select count(*) from tiqueteras
                        where pagado_en is not null and (pagado_en at time zone 'America/Bogota')::date = d),
      'tiqueteras_en_linea_cop', (select coalesce(sum(precio_cop), 0) from tiqueteras
                        where pagado_en is not null and (pagado_en at time zone 'America/Bogota')::date = d),
      'promedio_mismo_dia_4_semanas_cop', (
        select round(avg((ventas_entre(x, x)->>'ingreso_cop')::bigint))
          from unnest(array[d - 7, d - 14, d - 21, d - 28]) x)),
    'mes', jsonb_build_object(
      'total_cop', (v_mes->>'ingreso_cop')::bigint,
      'sueltas_personas', (v_mes->>'personas')::int,
      'mensualidades_n', (v_mes->>'mensualidades_n')::int,
      'mensualidades_cop', (v_mes->>'mensualidades_cop')::bigint,
      'tiqueteras_en_linea_n', (select count(*) from tiqueteras
                        where pagado_en is not null and (pagado_en at time zone 'America/Bogota')::date between ini_mes and d),
      'mes_anterior_mismo_tramo_cop', (v_ant->>'ingreso_cop')::bigint,
      'mes_anterior_mismo_tramo_mensualidades_n', (v_ant->>'mensualidades_n')::int,
      'mes_anterior_mismo_tramo_sueltas_personas', (v_ant->>'personas')::int,
      'meta_cop', v_meta,
      'falta_para_meta_cop', case when v_meta is null then null
                                  else greatest(v_meta - (v_mes->>'ingreso_cop')::bigint, 0) end,
      'dias_con_clase_que_quedan', v_habiles,
      'necesario_por_dia_cop', case when v_meta is null or v_habiles = 0 then null
                                    else round(greatest(v_meta - (v_mes->>'ingreso_cop')::bigint, 0)::numeric / v_habiles) end)));

  -- ── CRUCE CON EL BANCO: lo que entró hoy, lo cruzado y lo pendiente ──
  -- Lo registrado a mano por transferencia (sin escoger el depósito de la
  -- lista) también es plata cruzada: la cajera la vio y la registró.
  select coalesce(sum(valor_cop), 0), coalesce(sum(valor_cop) filter (where not consumido), 0)
    into v_banco, v_libre
    from pagos
   where fecha_pago >= d::timestamp at time zone 'America/Bogota'
     and fecha_pago <  (d + 1)::timestamp at time zone 'America/Bogota';
  select coalesce(sum(valor_cop), 0) into v_a_mano
    from caja_movimientos
   where dia = d and not anulado and sentido = 'ingreso' and medio = 'transferencia' and pago_id is null;
  select * into v_cierre from caja_cierres where dia = d;

  r := r || jsonb_build_object('cruce_banco', jsonb_build_object(
    'entro_al_banco_hoy_cop', v_banco,
    'cruzado_cop', v_banco - greatest(v_libre - v_a_mano, 0),
    'pendiente_por_cruzar_cop', greatest(v_libre - v_a_mano, 0),
    'que_es_lo_pendiente', 'Transferencias que llegaron y todavía no corresponden a una venta registrada: pagos adelantados (una mensualidad o una clase de otro día) o de alguien que aún no ha escrito ni se ha presentado. Es normal y no es descuadre.',
    'cierre_hecho', v_cierre.dia is not null,
    'cierre_hora', to_char(v_cierre.cerrado_at at time zone 'America/Bogota', 'HH12:MI am'),
    'efectivo_diferencia_cop', v_cierre.diferencia_cop));

  r := r || jsonb_build_object('plata', jsonb_build_object(
    'banco_hoy', v_banco,
    'banco_mes_en_curso', (select coalesce(sum(valor_cop), 0) from pagos
                   where fusionado_en is null and (fecha_pago at time zone 'America/Bogota')::date between ini_mes and d),
    'banco_mes_anterior_mismo_tramo', (select coalesce(sum(valor_cop), 0) from pagos
                   where fusionado_en is null and (fecha_pago at time zone 'America/Bogota')::date between ini_ant and mismo_ant),
    'gastos_mes_en_curso', (select coalesce(sum(valor_cop), 0) from gastos
                   where not coalesce(anulado, false) and dia between ini_mes and d)));

  r := r || jsonb_build_object('mensualidades', jsonb_build_object(
    'vigentes', (select count(*) from membresias where fin >= d and inicio <= d),
    'vigentes_por_hora', (select coalesce(jsonb_object_agg(h, n), '{}'::jsonb) from (
                           select to_char(hora, 'HH24:MI') h, count(*) n from membresias
                            where fin >= d and inicio <= d group by 1) z),
    'vencen_proximos_7_dias', (select coalesce(jsonb_agg(jsonb_build_object(
                                 'nombre', initcap(split_part(afiliado, ' ', 1)), 'vence', fin,
                                 'hora', to_char(hora, 'HH24:MI'), 'tipo', tipo) order by fin), '[]'::jsonb)
                               from membresias where fin between d and d + 7),
    'lista_de_espera', (select count(*) from mensualidad_solicitudes where estado = 'lista_espera'),
    'esperando_pago', (select count(*) from mensualidad_solicitudes where estado = 'esperando_pago')));

  r := r || jsonb_build_object('tiqueteras', jsonb_build_object(
    'vendidas_mes', (select count(*) from tiqueteras where pagado_en is not null
                      and (pagado_en at time zone 'America/Bogota')::date between ini_mes and d),
    'vigentes_con_clases', (select count(*) from tiqueteras where pagado_en is not null
                      and vence_el >= d and clases_usadas < clases_totales),
    'vencen_en_5_dias_con_clases', (select count(*) from tiqueteras where pagado_en is not null
                      and vence_el between d and d + 5 and clases_usadas < clases_totales)));

  r := r || jsonb_build_object('clientes', jsonb_build_object(
    'se_estan_enfriando_21_a_60_dias', (select count(*) from (
        select right(regexp_replace(x.telefono, '\D', '', 'g'), 10) t, max(c.fecha_hora) ult
          from reservas x join clases c on c.id = x.clase_id
         where x.estado = 'confirmada' group by 1) u
        where u.ult < now() - interval '21 days' and u.ult >= now() - interval '60 days'),
    'activos_ultimos_30_dias', (select count(distinct right(regexp_replace(x.telefono, '\D', '', 'g'), 10))
          from reservas x join clases c on c.id = x.clase_id
         where x.estado = 'confirmada' and c.fecha_hora >= now() - interval '30 days')));

  -- ── PARA LOS INSIGHTS: cruces que a mano no se ven ──────────────────
  r := r || jsonb_build_object('para_insights', jsonb_build_object(
    -- Cada franja de las últimas 4 semanas: cuánta gente entra de verdad
    -- (asistencias) contra el aforo. Dice dónde sobra puesto y dónde no.
    'ocupacion_por_franja_4_semanas', (
      select coalesce(jsonb_agg(z order by z->>'dia', z->>'hora'), '[]'::jsonb) from (
        select jsonb_build_object(
                 'dia', (array['1 lun','2 mar','3 mié','4 jue','5 vie','6 sáb','7 dom'])[extract(isodow from c.fecha_hora at time zone 'America/Bogota')::int],
                 'hora', to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'),
                 'clases', count(*),
                 'asistencia_promedio', round(avg((select count(*) from asistencias a where a.clase_id = c.id)), 1),
                 'sueltas_promedio', round(avg((select count(*) from reservas x where x.clase_id = c.id
                                                  and x.estado = 'confirmada' and x.tipo = 'suelta')), 1),
                 -- Las mensualidades no reservan ni marcan asistencia:
                 -- sin esto, 6 y 7 pm entre semana se verían vacías.
                 'mensualidades_vigentes_a_esa_hora', max(case
                     when extract(isodow from c.fecha_hora at time zone 'America/Bogota') < 6 then
                       (select count(*) from membresias m where m.fin >= d and m.inicio <= d
                          and to_char(m.hora, 'HH24:MI') = to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'))
                     else 0 end),
                 'aforo', max(coalesce(c.aforo, c.cupo_total))) z
          from clases c
         where c.activa and c.fecha_hora >= now() - interval '28 days' and c.fecha_hora < now()
         group by extract(isodow from c.fecha_hora at time zone 'America/Bogota'),
                  to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI')) q),
    -- Primera vez este mes y cuántos de ellos ya volvieron.
    'clientes_nuevos_mes', (
      with p as (
        select right(regexp_replace(x.telefono, '\D', '', 'g'), 10) t, min(c.fecha_hora) primera, count(*) veces
          from reservas x join clases c on c.id = x.clase_id
         where x.estado = 'confirmada' group by 1)
      select jsonb_build_object(
        'nuevos', count(*) filter (where (primera at time zone 'America/Bogota')::date between ini_mes and d),
        'volvieron_2_o_mas', count(*) filter (where (primera at time zone 'America/Bogota')::date between ini_mes and d and veces >= 2),
        'nuevos_mes_anterior', count(*) filter (where (primera at time zone 'America/Bogota')::date between ini_ant and (ini_mes - 1)),
        'mes_anterior_volvieron_2_o_mas', count(*) filter (where (primera at time zone 'America/Bogota')::date between ini_ant and (ini_mes - 1) and veces >= 2))
        from p),
    -- Quienes pagan clase suelta seguido: con 4 o más en 30 días ya
    -- gastaron más de lo que les costaría una tiquetera.
    'sueltas_frecuentes_sin_tiquetera_30_dias', (
      with fr as (
        select right(regexp_replace(x.telefono, '\D', '', 'g'), 10) t, count(*) veces
          from reservas x join clases c on c.id = x.clase_id
         where x.estado = 'confirmada' and x.tipo = 'suelta' and x.tiquetera_id is null
           and c.fecha_hora >= now() - interval '30 days' and c.fecha_hora < now()
         group by 1)
      select jsonb_build_object(
        'con_3_o_mas', count(*) filter (where veces >= 3),
        'con_4_o_mas', count(*) filter (where veces >= 4),
        'sin_tiquetera_vigente', count(*) filter (where veces >= 3 and not exists (
            select 1 from tiqueteras tq where right(regexp_replace(tq.telefono, '\D', '', 'g'), 10) = fr.t
               and tq.pagado_en is not null and tq.vence_el >= d)))
        from fr),
    'precio_suelta_cop', (select precio_cop from clases where activa and fecha_hora >= now() order by fecha_hora limit 1),
    'tiquetera_paquetes', (select valor from ajustes where clave = 'tiquetera_paquetes'),
    -- Renovaciones en juego esta semana, en plata (valor típico del mes).
    'renovaciones_7_dias', jsonb_build_object(
      'personas', (select count(*) from membresias where fin between d and d + 7),
      'valor_tipico_mensualidad_cop', case when (v_mes->>'mensualidades_n')::int > 0
          then round((v_mes->>'mensualidades_cop')::numeric / (v_mes->>'mensualidades_n')::int) end),
    -- Campañas de WhatsApp de los últimos 7 días y qué hizo la gente después.
    'campanas_whatsapp_7_dias', (
      with a as (
        select telefono, plantilla, enviado_at, entrega from wa_avisos
         where tipo = 'campana' and estado = 'enviado' and enviado_at > now() - interval '7 days')
      select coalesce(jsonb_agg(jsonb_build_object(
               'plantilla', plantilla, 'enviados', n, 'leidos', leidos,
               'reservaron_despues', reservaron, 'compraron_tiquetera_despues', tiq,
               'pidieron_no_mas_mensajes', bajas)), '[]'::jsonb)
        from (
          select a.plantilla, count(*) n,
                 count(*) filter (where a.entrega = 'read') leidos,
                 count(*) filter (where exists (select 1 from reservas x
                    where right(regexp_replace(x.telefono, '\D', '', 'g'), 10) = a.telefono
                      and x.estado = 'confirmada' and x.created_at > a.enviado_at)) reservaron,
                 count(*) filter (where exists (select 1 from tiqueteras tq
                    where right(regexp_replace(tq.telefono, '\D', '', 'g'), 10) = a.telefono
                      and tq.pagado_en > a.enviado_at)) tiq,
                 count(*) filter (where exists (select 1 from wa_bajas b where b.telefono = a.telefono)) bajas
            from a group by a.plantilla) g)));

  r := r || jsonb_build_object('whatsapp', jsonb_build_object(
    'avisos_hoy', (select count(*) from wa_avisos where estado = 'enviado'
                    and (enviado_at at time zone 'America/Bogota')::date = d),
    'avisos_hoy_leidos', (select count(*) from wa_avisos where estado = 'enviado' and entrega = 'read'
                    and (enviado_at at time zone 'America/Bogota')::date = d),
    'avisos_fallidos_7_dias', (select count(*) from wa_avisos
                    where (estado = 'fallido' or entrega = 'failed') and creado_at > now() - interval '7 days'),
    'bajas_total', (select count(*) from wa_bajas),
    'mensajes_de_clientes_hoy', (select count(*) from wa_mensajes m where m.direccion = 'entrante'
                    and not wa_es_dueno(m.telefono)
                    and (m.creado_at at time zone 'America/Bogota')::date = d)));

  return r;
end;
$function$;
revoke all on function public.tablero_tumbao(text) from public, anon, authenticated;

-- ── VISTA PREVIA DEL INFORME, SIN ENVIAR NADA ───────────────────────
-- Para revisar el texto antes de que llegue a los dueños. El Worker pide
-- turno (uno cada 5 minutos: la ruta no lleva token y cada borrador
-- cuesta una llamada al modelo), redacta y guarda el texto aquí. No
-- devuelve el texto por HTTP: se lee en la base.
create or replace function public.wa_turno_borrador()
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare n int;
begin
  insert into ajustes (clave, valor, nota)
  values ('informe_borrador_at', '2000-01-01', 'Último borrador del informe (vista previa). 0108.')
  on conflict (clave) do nothing;
  update ajustes set valor = now()::text, updated_at = now()
   where clave = 'informe_borrador_at' and valor::timestamptz < now() - interval '5 minutes';
  get diagnostics n = row_count;
  return n > 0;
end;
$$;
revoke all on function public.wa_turno_borrador() from public, anon, authenticated;

create or replace function public.wa_guardar_borrador(p_tipo text, p_dia date, p_texto text)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into ajustes (clave, valor, nota)
  values ('informe_borrador', p_texto, p_tipo || ' · ' || coalesce(p_dia::text, 'hoy') || ' · vista previa, no se envió. 0108.')
  on conflict (clave) do update set valor = excluded.valor, nota = excluded.nota, updated_at = now();
$$;
revoke all on function public.wa_guardar_borrador(text, date, text) from public, anon, authenticated;

-- El tablero de otro día (para la vista previa). Solo lee.
create or replace function public.tablero_tumbao_del_dia(p_tipo text, p_dia date)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform set_config('tumbao.dia', coalesce(p_dia::text, ''), true);
  return tablero_tumbao(p_tipo);
end;
$$;
revoke all on function public.tablero_tumbao_del_dia(text, date) from public, anon, authenticated;
