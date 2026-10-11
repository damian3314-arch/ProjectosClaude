-- 0105 · Los informes diarios por WhatsApp: 6:00 am y 10:00 pm.
--
-- LO QUE PIDIÓ DAMIÁN (27 de septiembre, noche)
-- «Un debrief todas las mañanas a las 6am diciendo qué se tiene para el
--  día, y un mensaje a las 10 de la noche reportando cómo fue ese día,
--  comparando frente a los anteriores o frente al mes anterior…
--  hacernos ver esos insights súper claves para el negocio.»
--
-- ── LAS PIEZAS ──────────────────────────────────────────────────────
--   tablero_tumbao()   Reúne en un JSON las cifras del día: la agenda,
--                      las mensualidades que vencen, la plata que entró
--                      al banco, las comparaciones. Solo lee. El texto lo
--                      escribe el modelo A PARTIR de esto: no inventa
--                      cifras porque solo tiene estas.
--   wa_informes        Un informe por (tipo, fecha, dueño), único. Si el
--                      reloj dispara dos veces, el segundo no manda nada.
--   pg_cron            El reloj. Los cron de Cloudflare no disparan en
--                      esta cuenta (ver wrangler.jsonc), así que la hora
--                      la pone la base y le toca la puerta al Worker.
--
-- ── LA VENTANA DE 24 HORAS ──────────────────────────────────────────
-- WhatsApp solo deja mandar texto libre a quien escribió en las últimas
-- 24 horas. Al dueño que no ha escrito se le manda la plantilla
-- `resumen_listo` con el botón «Ver resumen»; al tocarlo se abre la
-- ventana y le llega el informe completo.
--
-- ── DATOS QUE LLEGAN TARDE ──────────────────────────────────────────
-- ventas_mostrador (lo que se cobra en recepción) se carga a mano y el
-- 27 de septiembre iba con 8 días de atraso. El tablero dice hasta qué
-- día está cargada para que el informe lo advierta en vez de comparar
-- contra ceros.

create extension if not exists pg_cron;

-- ── el tablero del día ──────────────────────────────────────────────
create or replace function public.tablero_tumbao(p_tipo text default 'manana')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  d        date := (now() at time zone 'America/Bogota')::date;
  manana   date := d + 1;
  ini_mes  date := date_trunc('month', d)::date;
  ini_ant  date := (date_trunc('month', d) - interval '1 month')::date;
  mismo_ant date := least((date_trunc('month', d) - interval '1 month')::date
                          + (d - date_trunc('month', d)::date),
                          (date_trunc('month', d) - interval '1 day')::date);
  ult_mostrador date;
  r        jsonb := '{}'::jsonb;
begin
  select max(dia) into ult_mostrador from ventas_mostrador;

  r := r || jsonb_build_object(
    'tipo', p_tipo,
    'fecha', d,
    'dia_semana', (array['lunes','martes','miércoles','jueves','viernes','sábado','domingo'])[extract(isodow from d)::int]);

  -- La agenda del día (y de mañana, para el informe de la noche).
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
        'libres', greatest(c.cupo_total - c.cupo_tomado, 0)) as j
      from clases c
     where c.activa and (c.fecha_hora at time zone 'America/Bogota')::date = manana) x));

  -- Reservas: el día contra el mismo día de las 4 semanas anteriores.
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

  -- Asistencia real (lo que marca recepción).
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

  -- La plata: banco al día; recepción con la fecha hasta la que está cargada.
  r := r || jsonb_build_object('plata', jsonb_build_object(
    'banco_hoy', (select coalesce(sum(valor_cop), 0) from pagos
                   where fusionado_en is null and (fecha_pago at time zone 'America/Bogota')::date = d),
    'banco_ayer', (select coalesce(sum(valor_cop), 0) from pagos
                   where fusionado_en is null and (fecha_pago at time zone 'America/Bogota')::date = d - 1),
    'banco_mes_en_curso', (select coalesce(sum(valor_cop), 0) from pagos
                   where fusionado_en is null and (fecha_pago at time zone 'America/Bogota')::date between ini_mes and d),
    'banco_mes_anterior_mismo_tramo', (select coalesce(sum(valor_cop), 0) from pagos
                   where fusionado_en is null and (fecha_pago at time zone 'America/Bogota')::date between ini_ant and mismo_ant),
    'pagos_sin_asignar', (select jsonb_build_object('cuantos', count(*), 'valor', coalesce(sum(saldo_grupo_cop), 0))
                            from pagos_sin_asignar),
    'recepcion_cargada_hasta', ult_mostrador,
    'recepcion_mes_de_la_ultima_carga', (select coalesce(sum(cobrado_cop), 0) from ventas_mostrador
                   where dia between date_trunc('month', ult_mostrador)::date and ult_mostrador),
    'recepcion_mes_anterior_mismo_tramo', (select coalesce(sum(cobrado_cop), 0) from ventas_mostrador
                   where dia between (date_trunc('month', ult_mostrador) - interval '1 month')::date
                                 and (ult_mostrador - interval '1 month')::date),
    'gastos_mes_en_curso', (select coalesce(sum(valor_cop), 0) from gastos
                   where not coalesce(anulado, false) and dia between ini_mes and d)));

  -- Mensualidades: las que vencen son la renovación de la semana.
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

  -- Tiqueteras.
  r := r || jsonb_build_object('tiqueteras', jsonb_build_object(
    'vendidas_mes', (select count(*) from tiqueteras where pagado_en is not null
                      and (pagado_en at time zone 'America/Bogota')::date between ini_mes and d),
    'vigentes_con_clases', (select count(*) from tiqueteras where pagado_en is not null
                      and vence_el >= d and clases_usadas < clases_totales),
    'vencen_en_5_dias_con_clases', (select count(*) from tiqueteras where pagado_en is not null
                      and vence_el between d and d + 5 and clases_usadas < clases_totales)));

  -- Clientes que se están yendo: última reserva hace 21 a 60 días.
  r := r || jsonb_build_object('clientes', jsonb_build_object(
    'se_estan_enfriando_21_a_60_dias', (select count(*) from (
        select right(regexp_replace(x.telefono, '\D', '', 'g'), 10) t, max(c.fecha_hora) ult
          from reservas x join clases c on c.id = x.clase_id
         where x.estado = 'confirmada' group by 1) u
        where u.ult < now() - interval '21 days' and u.ult >= now() - interval '60 days'),
    'activos_ultimos_30_dias', (select count(distinct right(regexp_replace(x.telefono, '\D', '', 'g'), 10))
          from reservas x join clases c on c.id = x.clase_id
         where x.estado = 'confirmada' and c.fecha_hora >= now() - interval '30 days')));

  -- WhatsApp.
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
$$;

-- ── los informes ────────────────────────────────────────────────────
create table if not exists public.wa_informes (
  id           bigint generated always as identity primary key,
  tipo         text not null check (tipo in ('manana', 'noche')),
  fecha        date not null,
  telefono     text not null,
  texto        text,
  estado       text not null default 'generando'
               check (estado in ('generando', 'pendiente', 'entregado', 'aviso_enviado', 'fallido')),
  creado_at    timestamptz not null default now(),
  entregado_at timestamptz,
  unique (tipo, fecha, telefono)
);
alter table public.wa_informes enable row level security;
comment on table public.wa_informes is
  '0105: un informe por (tipo, fecha, dueño). El único que evita mandar dos veces el mismo informe.';

-- Aparta el informe de hoy para cada dueño que todavía no lo tiene.
-- Si ya existen todos, devuelve [] y el Worker no gasta ni una llamada.
create or replace function public.wa_reclamar_informes(p_tipo text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  d   date := (now() at time zone 'America/Bogota')::date;
  out jsonb;
begin
  with duenos as (
    select distinct trim(t) as tel
      from unnest(string_to_array(coalesce((select valor from ajustes where clave = 'wa_duenos'), ''), ',')) t
     where trim(t) ~ '^3[0-9]{9}$'),
  nuevos as (
    insert into wa_informes (tipo, fecha, telefono)
    select p_tipo, d, tel from duenos
    on conflict (tipo, fecha, telefono) do nothing
    returning id, telefono)
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'telefono', telefono,
           'ventana_abierta', exists (select 1 from wa_mensajes m
                                       where right(m.telefono, 10) = nuevos.telefono
                                         and m.direccion = 'entrante'
                                         and m.creado_at > now() - interval '23 hours'))), '[]'::jsonb)
    into out from nuevos;
  return out;
end;
$$;

create or replace function public.wa_marcar_informe(p_id bigint, p_estado text, p_texto text default null)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update wa_informes
     set estado = p_estado,
         texto = coalesce(p_texto, texto),
         entregado_at = case when p_estado = 'entregado' then now() else entregado_at end
   where id = p_id;
$$;

-- El último informe pendiente de un dueño (para cuando toca «Ver resumen»).
create or replace function public.wa_informe_pendiente(p_tel text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare i wa_informes;
begin
  update wa_informes set estado = 'entregado', entregado_at = now()
   where id = (select id from wa_informes
                where telefono = right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 10)
                  and estado = 'aviso_enviado' and texto is not null
                order by creado_at desc limit 1)
  returning * into i;
  if i.id is null then return null; end if;
  return jsonb_build_object('id', i.id, 'tipo', i.tipo, 'texto', i.texto);
end;
$$;

-- Encola la plantilla «tu resumen está listo» para un dueño sin ventana.
create or replace function public.wa_avisar_informe(p_tel text, p_tipo text)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
  values ('informe:' || p_tipo || ':' || ((now() at time zone 'America/Bogota')::date) || ':' || p_tel,
          'informe', p_tel, 'resumen_listo',
          jsonb_build_array(case when p_tipo = 'manana' then 'debrief de hoy' else 'cierre del día' end),
          now() + interval '12 hours')
  on conflict (clave) do nothing;
$$;

revoke all on function public.tablero_tumbao(text) from public, anon, authenticated;
revoke all on function public.wa_reclamar_informes(text) from public, anon, authenticated;
revoke all on function public.wa_marcar_informe(bigint, text, text) from public, anon, authenticated;
revoke all on function public.wa_informe_pendiente(text) from public, anon, authenticated;
revoke all on function public.wa_avisar_informe(text, text) from public, anon, authenticated;
grant execute on function public.tablero_tumbao(text) to service_role;
grant execute on function public.wa_reclamar_informes(text) to service_role;
grant execute on function public.wa_marcar_informe(bigint, text, text) to service_role;
grant execute on function public.wa_informe_pendiente(text) to service_role;
grant execute on function public.wa_avisar_informe(text, text) to service_role;

-- ── el reloj ────────────────────────────────────────────────────────
-- 6:00 am y 10:00 pm de Bogotá (UTC-5, sin horario de verano).
insert into public.ajustes (clave, valor, nota) values
  ('wa_informe_url', 'https://tumbao-caja.damian3314.workers.dev/wa/informe',
   'A dónde toca pg_cron para los informes de las 6 am y las 10 pm. 0105.')
on conflict (clave) do nothing;

create or replace function public.wa_disparar_informe(p_tipo text)
returns void
language sql
security definer
set search_path = public, extensions, pg_temp
as $$
  select net.http_post(
    url := (select valor from ajustes where clave = 'wa_informe_url'),
    body := jsonb_build_object('tipo', p_tipo),
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 120000);
$$;
revoke all on function public.wa_disparar_informe(text) from public, anon, authenticated;

select cron.schedule('tumbao-informe-manana', '0 11 * * *', $$select public.wa_disparar_informe('manana')$$);
select cron.schedule('tumbao-informe-noche',  '0 3 * * *',  $$select public.wa_disparar_informe('noche')$$);
