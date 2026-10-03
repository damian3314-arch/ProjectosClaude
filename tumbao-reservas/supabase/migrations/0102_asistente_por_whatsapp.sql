-- 0102 · El asistente de Tumbao por WhatsApp, y lo que entra al número.
--
-- LO QUE PIDIÓ DAMIÁN (28 de septiembre)
-- Un asistente al que le pueda escribir por WhatsApp para pedirle datos
-- de Tumbao. Con cerebro de OpenAI (gpt-4o-mini, el mismo que ya lee los
-- comprobantes) porque sale más barato.
--
-- ── CÓMO FUNCIONA ───────────────────────────────────────────────────
--   1. Meta le avisa al Worker (/wa/webhook) de cada mensaje que llega al
--      número de Tumbao. El Worker lo guarda aquí (wa_mensajes) y
--      contesta 200 en el acto.
--   2. Si el mensaje es de un DUEÑO (ajustes.wa_duenos), un disparador le
--      pide al Worker que lo atienda (/wa/agente) con pg_net y un plazo
--      largo: pensar y consultar puede tardar más de lo que Meta espera,
--      y así la conversación no depende de que Meta tenga paciencia.
--   3. El asistente SOLO LEE. Sus consultas pasan por agente_consulta,
--      que es STABLE (Postgres no deja escribir desde ahí) y el Worker la
--      llama por GET (PostgREST la corre en una transacción de solo
--      lectura). Dos candados, no uno.
--
-- ── LOS CLIENTES QUE ESCRIBEN AL NÚMERO ─────────────────────────────
-- Se guardan. «SALIR» (y parecidos) los pone en wa_bajas SIEMPRE.
-- Contestarles algo es otra cosa: sale solo si ajustes.wa_respuesta_auto
-- = encendido, que nace APAGADO porque es escribirle a clientes reales y
-- eso lo decide Damián.

insert into public.ajustes (clave, valor, nota) values
  ('wa_duenos', '3015373964',
   'Celulares (10 dígitos, separados por coma) que pueden hablar con el asistente de '
   'Tumbao por WhatsApp. Nadie más recibe respuestas del asistente. 0102.'),
  ('wa_agente_url', 'https://tumbao-caja.damian3314.workers.dev/wa/agente',
   'A dónde toca la base cuando un dueño le escribe al número. 0102.'),
  ('wa_respuesta_auto', 'apagado',
   'encendido = a un cliente que le escribe al número de avisos se le contesta (una vez '
   'al día) que escriba al WhatsApp de siempre, y SALIR se le confirma. Apagado = se '
   'guarda y SALIR igual lo da de baja, pero no se le contesta nada. 0102.')
on conflict (clave) do nothing;

-- Lo que Meta cuenta después de mandar un aviso: entregado, leído, falló.
alter table public.wa_avisos
  add column if not exists entrega       text,
  add column if not exists entrega_error text;

-- ── lo que entra y sale por el número ───────────────────────────────
create table if not exists public.wa_mensajes (
  id         bigint generated always as identity primary key,
  wa_msg_id  text unique,
  telefono   text not null,
  nombre     text,
  direccion  text not null check (direccion in ('entrante', 'saliente')),
  tipo       text not null default 'text',
  texto      text,
  estado     text not null default 'recibido'
             check (estado in ('recibido', 'procesando', 'respondido', 'ignorado', 'error', 'enviado')),
  creado_at  timestamptz not null default now()
);
create index if not exists wa_mensajes_por_telefono on public.wa_mensajes (telefono, creado_at desc);
alter table public.wa_mensajes enable row level security;
comment on table public.wa_mensajes is
  '0102: mensajes que entran al número de avisos y lo que se les contesta. '
  'wa_msg_id único: si Meta repite un aviso, no se procesa dos veces.';

create or replace function public.wa_es_dueno(p_tel text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 10) = any (
    string_to_array(replace(coalesce(
      (select valor from ajustes where clave = 'wa_duenos'), ''), ' ', ''), ','));
$$;

-- Guarda un mensaje entrante. nuevo=false si Meta ya lo había mandado.
create or replace function public.wa_guardar_entrante(p_wa_msg_id text, p_tel text,
                                                      p_nombre text, p_tipo text, p_texto text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id bigint;
begin
  insert into wa_mensajes (wa_msg_id, telefono, nombre, direccion, tipo, texto)
  values (p_wa_msg_id, regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'),
          left(p_nombre, 120), 'entrante', coalesce(p_tipo, 'text'), left(p_texto, 4000))
  on conflict (wa_msg_id) do nothing
  returning id into v_id;
  if v_id is null then return jsonb_build_object('nuevo', false); end if;
  return jsonb_build_object('nuevo', true, 'id', v_id, 'dueno', wa_es_dueno(p_tel),
    'responder', coalesce((select valor from ajustes where clave = 'wa_respuesta_auto'), 'apagado') = 'encendido');
end;
$$;

create or replace function public.wa_guardar_saliente(p_tel text, p_texto text, p_wa_msg_id text default null)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into wa_mensajes (wa_msg_id, telefono, direccion, texto, estado)
  values (p_wa_msg_id, regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 'saliente',
          left(p_texto, 4000), 'enviado')
  on conflict (wa_msg_id) do nothing;
$$;

-- ¿Ya se le escribió a este número en las últimas 24 horas?
create or replace function public.wa_respondido_24h(p_tel text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from wa_mensajes
                  where telefono = regexp_replace(coalesce(p_tel, ''), '\D', '', 'g')
                    and direccion = 'saliente'
                    and creado_at > now() - interval '24 hours');
$$;

-- Da de baja. true si es nueva (para confirmarle una sola vez).
create or replace function public.wa_dar_baja(p_tel text, p_motivo text default 'pidio_salir')
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_tel text := right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 10);
begin
  if v_tel !~ '^3[0-9]{9}$' then return false; end if;
  insert into wa_bajas (telefono, motivo) values (v_tel, p_motivo) on conflict do nothing;
  return found;
end;
$$;

-- Lo que Meta cuenta de un aviso ya enviado. Los estados llegan en
-- desorden (a veces «leído» antes que «entregado»): solo se sube.
create or replace function public.wa_estado_entrega(p_wa_id text, p_estado text, p_error text default null)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update wa_avisos
     set entrega = p_estado,
         entrega_error = coalesce(left(p_error, 500), entrega_error)
   where wa_id = p_wa_id
     and (p_estado = 'failed'
          or coalesce(array_position(array['sent','delivered','read'], entrega), 0)
             < coalesce(array_position(array['sent','delivered','read'], p_estado), 0));
$$;

-- ── el asistente toma un mensaje ────────────────────────────────────
-- Lo marca «procesando» en la misma sentencia: si pg_net o Meta lo
-- mandan dos veces, la segunda no encuentra nada.
create or replace function public.wa_tomar_mensaje(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  m     wa_mensajes;
  v_his jsonb;
begin
  update wa_mensajes set estado = 'procesando'
   where id = p_id and estado = 'recibido' and direccion = 'entrante'
  returning * into m;
  if m.id is null or not wa_es_dueno(m.telefono) then return null; end if;

  select coalesce(jsonb_agg(jsonb_build_object('direccion', h.direccion, 'texto', h.texto)
                            order by h.id), '[]'::jsonb)
    into v_his
    from (select id, direccion, texto from wa_mensajes
           where telefono = m.telefono and id < m.id and texto is not null
             and creado_at > now() - interval '12 hours'
           order by id desc limit 16) h;

  return jsonb_build_object('id', m.id, 'telefono', m.telefono, 'wa_msg_id', m.wa_msg_id,
                            'tipo', m.tipo, 'texto', m.texto, 'historial', v_his);
end;
$$;

create or replace function public.wa_cerrar_mensaje(p_id bigint, p_estado text)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update wa_mensajes set estado = p_estado where id = p_id and estado = 'procesando';
$$;

-- ── pg_net: cuando escribe un dueño, que lo atienda el Worker ───────
create or replace function public.wa_llamar_agente()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_url text;
begin
  if new.direccion <> 'entrante' or not wa_es_dueno(new.telefono) then return null; end if;
  select valor into v_url from ajustes where clave = 'wa_agente_url';
  if coalesce(v_url, '') <> '' then
    perform net.http_post(url := v_url, body := jsonb_build_object('id', new.id),
                          headers := '{"Content-Type": "application/json"}'::jsonb,
                          timeout_milliseconds := 120000);
  end if;
  return null;
exception when others then
  raise warning 'wa_llamar_agente: %', sqlerrm;
  return null;
end;
$$;

drop trigger if exists wa_llamar_agente on public.wa_mensajes;
create trigger wa_llamar_agente
  after insert on public.wa_mensajes
  for each row execute function public.wa_llamar_agente();

-- ── lo que el asistente puede leer ──────────────────────────────────
-- STABLE: Postgres no deja INSERT/UPDATE/DELETE aquí adentro. Y el Worker
-- la llama por GET, que PostgREST corre en solo lectura. Las tablas de
-- acceso al panel quedan fuera.
create or replace function public.agente_consulta(p_sql text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
set statement_timeout = '8s'
as $$
declare
  v text := regexp_replace(trim(coalesce(p_sql, '')), ';\s*$', '');
  r jsonb;
begin
  if v ~ ';' then raise exception 'Una sola consulta, sin punto y coma.'; end if;
  if v !~* '^\s*(select|with)\s' then raise exception 'Solo consultas SELECT o WITH.'; end if;
  if v ~* '(admin_tokens|admin_users|admin_usuarios|\mauth\s*\.|\mvault\s*\.|\mstorage\s*\.|\mnet\s*\.|pg_authid|pg_shadow|pg_read|pg_ls_|lo_import|dblink|set_config)' then
    raise exception 'Esa información no está disponible para el asistente.';
  end if;
  execute format('select coalesce(jsonb_agg(t), ''[]''::jsonb) from (select * from (%s) q limit 100) t', v)
    into r;
  return r;
end;
$$;

create or replace function public.agente_esquema()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_object_agg(t.table_name, jsonb_build_object(
           'comentario', obj_description(format('public.%I', t.table_name)::regclass),
           'columnas', (select string_agg(c.column_name || ' ' ||
                          case when c.data_type = 'USER-DEFINED' then c.udt_name else c.data_type end,
                          ', ' order by c.ordinal_position)
                          from information_schema.columns c
                         where c.table_schema = 'public' and c.table_name = t.table_name)))
    from information_schema.tables t
   where t.table_schema = 'public'
     and t.table_name not in ('admin_tokens', 'admin_users', 'admin_usuarios');
$$;

revoke all on function public.wa_es_dueno(text) from public, anon, authenticated;
revoke all on function public.wa_guardar_entrante(text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.wa_guardar_saliente(text, text, text) from public, anon, authenticated;
revoke all on function public.wa_respondido_24h(text) from public, anon, authenticated;
revoke all on function public.wa_dar_baja(text, text) from public, anon, authenticated;
revoke all on function public.wa_estado_entrega(text, text, text) from public, anon, authenticated;
revoke all on function public.wa_tomar_mensaje(bigint) from public, anon, authenticated;
revoke all on function public.wa_cerrar_mensaje(bigint, text) from public, anon, authenticated;
revoke all on function public.wa_llamar_agente() from public, anon, authenticated;
revoke all on function public.agente_consulta(text) from public, anon, authenticated;
revoke all on function public.agente_esquema() from public, anon, authenticated;
grant execute on function public.wa_guardar_entrante(text, text, text, text, text) to service_role;
grant execute on function public.wa_guardar_saliente(text, text, text) to service_role;
grant execute on function public.wa_respondido_24h(text) to service_role;
grant execute on function public.wa_dar_baja(text, text) to service_role;
grant execute on function public.wa_estado_entrega(text, text, text) to service_role;
grant execute on function public.wa_tomar_mensaje(bigint) to service_role;
grant execute on function public.wa_cerrar_mensaje(bigint, text) to service_role;
grant execute on function public.agente_consulta(text) to service_role;
grant execute on function public.agente_esquema() to service_role;
