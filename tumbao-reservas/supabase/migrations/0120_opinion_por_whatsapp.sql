-- 0120 · La opinión se toma en el mismo WhatsApp.
--
-- Damián, 29 sep: «¿Qué te parece si en vez de enviarle el link a que
-- entren a Tumbao Opina, le tomas en ese WhatsApp lo que nos comparten?»
--
-- CÓMO FUNCIONA
--   1. opinion_invitar_nuevos() (pg_cron 10 am L-S): a quien tomó su
--      PRIMERA clase en los últimos 3 días le encola la plantilla
--      'como_te_fue' (una sola vez por persona) y le abre una fila en
--      wa_opiniones con estado 'invitada'.
--   2. Cuando esa persona responde, wa_guardar_entrante lo marca como
--      opinión y el disparador llama a /wa/opinion (Worker), que conversa
--      con ella: agradece, máximo 2 preguntas, cierra con cariño. Entiende
--      notas de voz. Máximo 4 respuestas del bot por opinión.
--   3. Al cerrar queda resumen, tipo y si es urgente; lo urgente se le
--      avisa a Damián al momento (nota_asistente) y todo sale el lunes en
--      «Lo que dice la gente».
--   · Quien no tiene opinión abierta sigue recibiendo la respuesta
--     automática de siempre. Nunca domingos (Ley 2300).

create table if not exists public.wa_opiniones (
  id              bigint generated always as identity primary key,
  telefono        text not null check (telefono ~ '^3[0-9]{9}$'),
  nombre          text,
  origen          text not null default 'primera_clase',
  clase           text,
  estado          text not null default 'invitada'
                  check (estado in ('invitada', 'conversando', 'cerrada')),
  turnos          int not null default 0,
  resumen         text,
  tipo            text,
  urgente         boolean not null default false,
  motivo_urgente  text,
  invitada_at     timestamptz not null default now(),
  ultima_at       timestamptz,
  cerrada_at      timestamptz
);
create index if not exists wa_opiniones_por_telefono on public.wa_opiniones (telefono, invitada_at desc);
alter table public.wa_opiniones enable row level security;
revoke all on table public.wa_opiniones from public, anon, authenticated;

insert into public.ajustes (clave, valor, nota) values
  ('wa_opinion_url', 'https://tumbao-caja.damian3314.workers.dev/wa/opinion',
   'Ruta del Worker que conversa con quien responde «¿cómo te fue?». 0120.'),
  ('wa_opinion_invitar', 'apagado',
   'Invitar a opinar por WhatsApp a quien tomó su primera clase. Se enciende cuando Meta aprueba la plantilla como_te_fue. 0120.')
on conflict (clave) do nothing;

-- La opinión viva de un teléfono: invitada o conversando (72 h), o cerrada
-- hace menos de 24 h (para no contestarle con el «no revisamos mensajes»
-- a quien acaba de contarnos algo).
create or replace function public.wa_opinion_viva(p_tel text)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select id from wa_opiniones
   where telefono = right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 10)
     and ((estado in ('invitada', 'conversando') and invitada_at > now() - interval '72 hours')
          or (estado = 'cerrada' and cerrada_at > now() - interval '24 hours'))
   order by invitada_at desc limit 1;
$$;
revoke all on function public.wa_opinion_viva(text) from public, anon, authenticated;

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
    'opinion', (not wa_es_dueno(p_tel)) and wa_opinion_viva(p_tel) is not null,
    'responder', coalesce((select valor from ajustes where clave = 'wa_respuesta_auto'), 'apagado') = 'encendido');
end;
$$;

-- El disparador de 0102 también despierta a /wa/opinion.
create or replace function public.wa_llamar_agente()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_url text;
begin
  if new.direccion <> 'entrante' then return null; end if;
  if wa_es_dueno(new.telefono) then
    select valor into v_url from ajustes where clave = 'wa_agente_url';
  elsif wa_opinion_viva(new.telefono) is not null then
    select valor into v_url from ajustes where clave = 'wa_opinion_url';
  end if;
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

-- El Worker toma el mensaje y la conversación completa de esa opinión.
create or replace function public.wa_tomar_opinion(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare m wa_mensajes; o wa_opiniones; v_his jsonb;
begin
  update wa_mensajes set estado = 'procesando'
   where id = p_id and estado = 'recibido' and direccion = 'entrante'
  returning * into m;
  if m.id is null or wa_es_dueno(m.telefono) then return null; end if;
  if exists (select 1 from wa_bajas b where b.telefono = right(m.telefono, 10)) then
    update wa_mensajes set estado = 'ignorado' where id = m.id;
    return null;
  end if;
  select * into o from wa_opiniones where id = wa_opinion_viva(m.telefono);
  if o.id is null then
    update wa_mensajes set estado = 'ignorado' where id = m.id;
    return null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('direccion', h.direccion, 'texto', h.texto)
                            order by h.id), '[]'::jsonb)
    into v_his
    from (select id, direccion, texto from wa_mensajes
           where right(telefono, 10) = o.telefono and id < m.id and texto is not null
             and creado_at >= o.invitada_at
           order by id desc limit 20) h;

  return jsonb_build_object('id', m.id, 'telefono', m.telefono, 'wa_msg_id', m.wa_msg_id,
    'tipo', m.tipo, 'texto', m.texto, 'historial', v_his,
    'opinion', jsonb_build_object('id', o.id, 'nombre', o.nombre, 'clase', o.clase,
                                  'estado', o.estado, 'turnos', o.turnos));
end;
$$;
revoke all on function public.wa_tomar_opinion(bigint) from public, anon, authenticated;

-- Guarda el turno: texto transcrito de una nota de voz, estado, ficha.
create or replace function public.wa_opinion_turno(
  p_opinion bigint, p_mensaje bigint, p_texto_entrante text, p_cerrar boolean,
  p_resumen text, p_tipo text, p_urgente boolean, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_texto_entrante is not null then
    update wa_mensajes set texto = left(p_texto_entrante, 4000) where id = p_mensaje;
  end if;
  update wa_mensajes set estado = 'respondido' where id = p_mensaje and estado = 'procesando';
  update wa_opiniones
     set turnos = turnos + 1,
         ultima_at = now(),
         estado = case when p_cerrar then 'cerrada' else 'conversando' end,
         cerrada_at = case when p_cerrar and cerrada_at is null then now() else cerrada_at end,
         resumen = coalesce(nullif(btrim(coalesce(p_resumen, '')), ''), resumen),
         tipo = coalesce(nullif(btrim(coalesce(p_tipo, '')), ''), tipo),
         urgente = urgente or coalesce(p_urgente, false),
         motivo_urgente = coalesce(nullif(btrim(coalesce(p_motivo, '')), ''), motivo_urgente)
   where id = p_opinion;
end;
$$;
revoke all on function public.wa_opinion_turno(bigint, bigint, text, boolean, text, text, boolean, text)
  from public, anon, authenticated;

-- ── a quién invitar: primera clase en los últimos 3 días ────────────
create or replace function public.opinion_invitar_nuevos()
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare n int := 0; hoy date := (now() at time zone 'America/Bogota')::date;
begin
  if coalesce((select valor from ajustes where clave = 'wa_opinion_invitar'), 'apagado') <> 'encendido' then
    return 0;
  end if;
  if extract(isodow from hoy) = 7 or exists (select 1 from festivos where fecha = hoy) then
    return 0;   -- Ley 2300: nada de mensajes comerciales domingos ni festivos
  end if;

  with primera as (
    select distinct on (right(regexp_replace(x.telefono, '\D', '', 'g'), 10))
           right(regexp_replace(x.telefono, '\D', '', 'g'), 10) tel,
           initcap(split_part(btrim(x.nombre), ' ', 1)) nombre,
           c.nombre clase, c.fecha_hora, x.no_vino_at
      from reservas x join clases c on c.id = x.clase_id
     where x.estado = 'confirmada'
     order by right(regexp_replace(x.telefono, '\D', '', 'g'), 10), c.fecha_hora),
  elegidos as (
    select p.* from primera p
     where (p.fecha_hora at time zone 'America/Bogota')::date between hoy - 3 and hoy - 1
       and p.no_vino_at is null
       and p.tel ~ '^3[0-9]{9}$'
       and not wa_es_dueno(p.tel)
       and not exists (select 1 from wa_bajas b where b.telefono = p.tel)
       and not exists (select 1 from wa_opiniones o where o.telefono = p.tel)),
  nuevas as (
    insert into wa_opiniones (telefono, nombre, origen, clase)
    select tel, nullif(nombre, ''), 'primera_clase', clase from elegidos
    returning telefono, nombre, clase)
  insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
  select 'opinion:' || telefono, 'opinion', telefono, 'como_te_fue',
         jsonb_build_array(coalesce(nombre, 'hola'), coalesce(clase, 'baile')),
         now() + interval '8 hours'
    from nuevas
  on conflict (clave) do nothing;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.opinion_invitar_nuevos() from public, anon, authenticated;

select cron.schedule('tumbao-opinion-nuevos', '0 15 * * 1-6', $$select public.opinion_invitar_nuevos()$$);

-- ── para el lunes: las opiniones tomadas por WhatsApp ────────────────
create or replace function public.opiniones_wa_semana()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'nombre', nombre, 'clase', clase, 'estado', estado,
           'resumen', resumen, 'tipo', tipo, 'urgente', urgente,
           'motivo_urgente', motivo_urgente)
           order by urgente desc, invitada_at desc), '[]'::jsonb)
    from wa_opiniones
   where invitada_at > now() - interval '7 days' and turnos > 0;
$$;
revoke all on function public.opiniones_wa_semana() from public, anon, authenticated;

-- Los mensajes de quien estuvo opinando no se repiten en la lista de
-- «lo que escribieron»: ya salen resumidos como opinión.
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.mensajes_clientes_semana()'::regprocedure) into v_src;
  if position('wa_opiniones' in v_src) > 0 then return; end if;
  v_new := replace(v_src, '       and coalesce(btrim(texto), '''') <> ''''),',
    '       and coalesce(btrim(texto), '''') <> ''''' || E'\n' ||
    '       and not exists (select 1 from wa_opiniones o where o.telefono = right(regexp_replace(wa_mensajes.telefono, ''\D'', '''', ''g''), 10)' || E'\n' ||
    '                         and o.invitada_at > now() - interval ''7 days'' and o.turnos > 0)),');
  if v_new = v_src then raise exception '0120: no se aplicó a mensajes_clientes_semana'; end if;
  execute v_new;
end
$mig$;
