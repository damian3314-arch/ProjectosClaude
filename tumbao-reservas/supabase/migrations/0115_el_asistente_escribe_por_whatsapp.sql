-- 0115 · El asistente le escribe a Damián por WhatsApp: reportes de lo
--        que va haciendo y alertas si algo pasa.
--
-- LO QUE PIDIÓ DAMIÁN (28 sep)
-- «Necesito estar tranquilo de que me estés ayudando y que seas ese
--  asistente efectivo, que ejecuta y me hace ver las cosas. Que si algo
--  pasa me escribas por WhatsApp. Tienes varias cosas que dijiste que vas
--  a ir haciendo: por WhatsApp me puedes ir contando.»
--
-- LO QUE SE CREA
--   · wa_notas: cada mensaje del asistente para el dueño, con su estado.
--   · nota_asistente(titulo, texto, clave): lo llama cualquier revisión o
--     hito programado. Si Damián habló con el número en las últimas 23 h
--     le llega el texto directo; si no, la plantilla aprobada
--     resumen_listo («Tu reporte del asistente de Tumbao está listo») y al
--     tocar «Ver resumen» le llega el texto. La clave evita repetir la
--     misma alerta el mismo día.
--   · centinela: cada hora de 7 am a 9 pm el Worker revisa la calidad del
--     número, la salud de la página, avisos fallando, bajas, la cola de
--     envíos y tiqueteras que dijeron "ya pagué" sin validar. Solo escribe
--     si algo está mal.
--   · Los dueños quedan fuera del tope de 3 mensajes por persona al día:
--     ese tope protege a los clientes, no a quien recibe los informes.

create table if not exists public.wa_notas (
  id           bigint generated always as identity primary key,
  clave        text unique,
  telefono     text not null check (telefono ~ '^3[0-9]{9}$'),
  titulo       text not null,
  texto        text not null,
  estado       text not null default 'pendiente'
               check (estado in ('pendiente', 'enviando', 'entregado', 'aviso_enviado', 'fallido')),
  creado_at    timestamptz not null default now(),
  entregado_at timestamptz
);
alter table public.wa_notas enable row level security;
revoke all on table public.wa_notas from public, anon, authenticated;

insert into public.ajustes (clave, valor, nota) values
  ('wa_notas_para', '3015373964',
   'A quién le escribe el asistente sus reportes y alertas (celulares separados por coma). 0115.'),
  ('wa_notas_url', 'https://tumbao-caja.damian3314.workers.dev/wa/notas',
   'Ruta del Worker que entrega las notas del asistente. 0115.'),
  ('wa_centinela_url', 'https://tumbao-caja.damian3314.workers.dev/wa/centinela',
   'Ruta del Worker que revisa cada hora si algo anda mal. 0115.')
on conflict (clave) do nothing;

-- ── escribirle a Damián ──────────────────────────────────────────────
create or replace function public.nota_asistente(p_titulo text, p_texto text, p_clave text default null)
returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_tel text; n int := 0; k int;
begin
  if coalesce(btrim(p_texto), '') = '' then return 0; end if;
  for v_tel in
    select distinct trim(t)
      from unnest(string_to_array(coalesce((select valor from ajustes where clave = 'wa_notas_para'), ''), ',')) t
     where trim(t) ~ '^3[0-9]{9}$'
  loop
    insert into wa_notas (clave, telefono, titulo, texto)
    values (case when p_clave is null then null else p_clave || ':' || v_tel end,
            v_tel, left(coalesce(nullif(btrim(p_titulo), ''), 'Reporte'), 80), left(p_texto, 3500))
    on conflict (clave) do nothing;
    get diagnostics k = row_count;
    n := n + k;
  end loop;
  if n > 0 then
    perform net.http_post(
      url := (select valor from ajustes where clave = 'wa_notas_url'),
      body := '{}'::jsonb,
      headers := '{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds := 60000);
  end if;
  return n;
end;
$$;
revoke all on function public.nota_asistente(text, text, text) from public, anon, authenticated;

create or replace function public.wa_tomar_notas()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare out jsonb;
begin
  with t as (
    update wa_notas set estado = 'enviando'
     where id in (select id from wa_notas where estado = 'pendiente'
                   order by id limit 10 for update skip locked)
    returning id, telefono, titulo, texto)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'telefono', t.telefono, 'titulo', t.titulo, 'texto', t.texto,
           'ventana_abierta', exists (select 1 from wa_mensajes m
                                       where right(m.telefono, 10) = t.telefono
                                         and m.direccion = 'entrante'
                                         and m.creado_at > now() - interval '23 hours'))
         order by t.id), '[]'::jsonb)
    into out from t;
  return out;
end;
$$;
revoke all on function public.wa_tomar_notas() from public, anon, authenticated;

create or replace function public.wa_marcar_nota(p_id bigint, p_estado text)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update wa_notas
     set estado = p_estado,
         entregado_at = case when p_estado = 'entregado' then now() else entregado_at end
   where id = p_id;
$$;
revoke all on function public.wa_marcar_nota(bigint, text) from public, anon, authenticated;

-- Sin ventana abierta: la plantilla aprobada, y el texto queda esperando
-- a que toque «Ver resumen».
create or replace function public.wa_avisar_nota(p_id bigint)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v wa_notas;
begin
  update wa_notas set estado = 'aviso_enviado' where id = p_id returning * into v;
  if v.id is null then return; end if;
  insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
  values ('nota:' || v.id, 'informe', v.telefono, 'resumen_listo',
          jsonb_build_array('reporte del asistente'), now() + interval '24 hours')
  on conflict (clave) do nothing;
end;
$$;
revoke all on function public.wa_avisar_nota(bigint) from public, anon, authenticated;

-- «Ver resumen» entrega primero el informe del día y, si no hay, la nota
-- más vieja que esté esperando. Cada botón entrega una cosa.
create or replace function public.wa_informe_pendiente(p_tel text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare i wa_informes; n wa_notas; v_tel text := right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 10);
begin
  update wa_informes set estado = 'entregado', entregado_at = now()
   where id = (select id from wa_informes
                where telefono = v_tel and estado = 'aviso_enviado' and texto is not null
                order by creado_at desc limit 1)
  returning * into i;
  if i.id is not null then
    return jsonb_build_object('id', i.id, 'tipo', i.tipo, 'texto', i.texto);
  end if;

  update wa_notas set estado = 'entregado', entregado_at = now()
   where id = (select id from wa_notas
                where telefono = v_tel and estado = 'aviso_enviado'
                order by creado_at limit 1)
  returning * into n;
  if n.id is not null then
    return jsonb_build_object('id', n.id, 'tipo', 'nota',
      'texto', '*' || n.titulo || '*' || E'\n\n' || n.texto);
  end if;
  return null;
end;
$$;

-- ── el tope por persona no aplica a los dueños ──────────────────────
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.wa_tomar_avisos(integer)'::regprocedure) into v_src;
  if position('not wa_es_dueno(r.telefono) and' in v_src) > 0 then return; end if;
  v_new := replace(v_src,
    '    if (select count(*) from wa_avisos x',
    '    if not wa_es_dueno(r.telefono) and (select count(*) from wa_avisos x');
  if v_new = v_src then raise exception '0115: no encontré el tope por persona'; end if;
  execute v_new;
end
$mig$;

-- ── lo que el centinela mira en la base ──────────────────────────────
create or replace function public.centinela_datos()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'fallidos_2h', (select count(*) from wa_avisos
                     where (estado = 'fallido' or entrega = 'failed')
                       and coalesce(entrega_error, '') not like '131026%'   -- número sin WhatsApp: normal
                       and coalesce(enviado_at, creado_at) > now() - interval '2 hours'),
    'bajas_hoy', (select count(*) from wa_bajas
                   where (creado_at at time zone 'America/Bogota')::date = (now() at time zone 'America/Bogota')::date),
    'cola_atascada', (select count(*) from wa_avisos
                       where estado = 'pendiente' and creado_at < now() - interval '30 minutes'
                         and (vence_at is null or vence_at > now())),
    'informes_fallidos_hoy', (select count(*) from wa_informes
                               where estado = 'fallido' and fecha = (now() at time zone 'America/Bogota')::date),
    'tiqueteras_por_validar', (select coalesce(jsonb_agg(jsonb_build_object(
                                  'nombre', nombre, 'clases', clases_totales, 'precio', precio_cop,
                                  'desde', to_char(pagado_en at time zone 'America/Bogota', 'DD/MM HH12:MI am'))
                                  order by pagado_en), '[]'::jsonb)
                                 from tiqueteras
                                where estado <> 'confirmada' and pagado_en is not null
                                  and pagado_en < now() - interval '1 hour'
                                  and pagado_en > now() - interval '7 days'));
$$;
revoke all on function public.centinela_datos() from public, anon, authenticated;

create or replace function public.wa_disparar_centinela()
returns void
language sql
security definer
set search_path = public, extensions, pg_temp
as $$
  select net.http_post(
    url := (select valor from ajustes where clave = 'wa_centinela_url'),
    body := '{}'::jsonb,
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 60000);
$$;
revoke all on function public.wa_disparar_centinela() from public, anon, authenticated;

-- Cada hora al minuto 7, de 7:07 am a 9:07 pm Bogotá (12-23 y 0-2 UTC).
select cron.schedule('tumbao-centinela', '7 0-2,12-23 * * *', $$select public.wa_disparar_centinela()$$);
