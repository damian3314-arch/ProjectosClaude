-- Cheo: el agente de feedback de Tumbao.
-- Estado final aplicado al proyecto Supabase tumbao-reservas (fobpccreihcylpsullhu).
--
-- Aditivo: no toca clases, reservas, pagos, membresias, asistencias ni caja.
-- Para revertirlo completo basta con:
--   drop table cheo_mensajes, cheo_conversaciones, cheo_reportes cascade;
--   drop function cheo_abrir, cheo_historial, cheo_guardar_turno,
--        cheo_guardar_contacto, cheo_pendientes_de_clasificar, cheo_clasificar,
--        cheo_semana, cheo_guardar_reporte;

create table if not exists public.cheo_conversaciones (
  id             uuid primary key default gen_random_uuid(),
  sesion_id      text not null unique,
  origen         text not null default 'widget'
                 check (origen in ('widget','pagina','whatsapp','admin')),
  pagina_url     text,
  user_agent     text,

  -- Lo que la persona comparta, si lo comparte. Nada es obligatorio:
  -- pedir datos antes de escuchar espanta a quien viene a quejarse.
  nombre         text,
  telefono       text,
  email          text,
  habeas         boolean not null default false,

  iniciada_en       timestamptz not null default now(),
  ultima_actividad  timestamptz not null default now(),
  cerrada_en        timestamptz,
  estado            text not null default 'abierta'
                    check (estado in ('abierta','cerrada')),
  mensajes_count    integer not null default 0,

  -- Clasificacion: la escribe el workflow de insights cuando la
  -- conversacion se enfria. Nula mientras la persona sigue escribiendo.
  clasificada      boolean not null default false,
  tipo             text check (tipo in ('sugerencia','queja','reclamo','duda','idea','elogio','otro')),
  tema             text,
  resumen          text,
  urgencia         smallint check (urgencia between 1 and 5),
  sentimiento      text check (sentimiento in ('positivo','neutral','negativo')),
  accion_sugerida  text
);

create index if not exists cheo_conv_actividad_idx
  on public.cheo_conversaciones (ultima_actividad desc);
create index if not exists cheo_conv_sin_clasificar_idx
  on public.cheo_conversaciones (clasificada, ultima_actividad)
  where clasificada = false;

create table if not exists public.cheo_mensajes (
  id              bigserial primary key,
  conversacion_id uuid not null references public.cheo_conversaciones(id) on delete cascade,
  rol             text not null check (rol in ('usuario','cheo')),
  texto           text not null,
  creado_en       timestamptz not null default now()
);

create index if not exists cheo_msg_conv_idx
  on public.cheo_mensajes (conversacion_id, id);

create table if not exists public.cheo_reportes (
  id                   uuid primary key default gen_random_uuid(),
  semana_inicio        date not null,
  semana_fin           date not null,
  generado_en          timestamptz not null default now(),
  total_conversaciones integer not null default 0,
  total_mensajes       integer not null default 0,
  insights             jsonb,
  resumen_md           text,
  html                 text,
  unique (semana_inicio)
);

comment on table public.cheo_conversaciones is
  'Cada charla con Cheo. La clasificacion la llena el workflow cuando la conversacion lleva rato quieta, no en vivo.';
comment on table public.cheo_mensajes is
  'Turnos de la conversacion, en orden. Sin PII adicional: lo que la persona escriba va tal cual.';
comment on table public.cheo_reportes is
  'Un reporte por semana. Se guarda el HTML que se envio por correo para poder releerlo despues.';

-- Mismo criterio que el resto del esquema: RLS prendido y sin politicas,
-- asi solo entra service_role desde n8n. La pagina nunca habla con
-- Supabase directamente, y la llave nunca sale del servidor.
alter table public.cheo_conversaciones enable row level security;
alter table public.cheo_mensajes       enable row level security;
alter table public.cheo_reportes       enable row level security;


-- ---------------------------------------------------------------
create or replace function public.cheo_abrir(
  p_sesion_id  text,
  p_origen     text default 'widget',
  p_pagina_url text default null,
  p_user_agent text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_nueva boolean := false;
begin
  if coalesce(trim(p_sesion_id), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'sesion_requerida');
  end if;

  select id into v_id from cheo_conversaciones where sesion_id = p_sesion_id;

  if v_id is null then
    insert into cheo_conversaciones (sesion_id, origen, pagina_url, user_agent)
    values (
      left(p_sesion_id, 80),
      case when p_origen in ('widget','pagina','whatsapp','admin') then p_origen else 'widget' end,
      left(p_pagina_url, 300),
      left(p_user_agent, 300)
    )
    returning id into v_id;
    v_nueva := true;
  else
    update cheo_conversaciones set ultima_actividad = now() where id = v_id;
  end if;

  return jsonb_build_object('ok', true, 'conversacion_id', v_id, 'nueva', v_nueva);
end $$;


-- ---------------------------------------------------------------
create or replace function public.cheo_historial(
  p_sesion_id text,
  p_limite    integer default 24
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_conv record; v_msgs jsonb;
begin
  select * into v_conv from cheo_conversaciones where sesion_id = p_sesion_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_existe');
  end if;

  -- Se traen los ultimos N (order by id desc) y se reordenan a cronologico,
  -- que es como el modelo necesita leerlos.
  select coalesce(jsonb_agg(jsonb_build_object('rol', ult.rol, 'texto', ult.texto)
                            order by ult.id), '[]'::jsonb)
    into v_msgs
  from (
    select id, rol, texto from cheo_mensajes
    where conversacion_id = v_conv.id
    order by id desc
    limit greatest(coalesce(p_limite, 24), 1)
  ) ult;

  return jsonb_build_object(
    'ok', true,
    'conversacion_id', v_conv.id,
    'mensajes_count', v_conv.mensajes_count,
    'nombre', v_conv.nombre,
    'telefono', v_conv.telefono,
    'email', v_conv.email,
    'origen', v_conv.origen,
    'mensajes', v_msgs
  );
end $$;


-- ---------------------------------------------------------------
-- Guardar el turno completo. Va junto a proposito: si se guardara solo
-- la pregunta y el modelo fallara, quedaria una conversacion coja.
create or replace function public.cheo_guardar_turno(
  p_sesion_id text,
  p_usuario   text,
  p_cheo      text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_conv record;
begin
  select * into v_conv from cheo_conversaciones where sesion_id = p_sesion_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_existe');
  end if;

  -- Tope duro por conversacion. No es para castigar a quien hable mucho:
  -- es para que un bucle o un bot no llene la tabla ni la factura.
  if v_conv.mensajes_count >= 120 then
    return jsonb_build_object('ok', false, 'error', 'conversacion_muy_larga');
  end if;

  if coalesce(trim(p_usuario), '') <> '' then
    insert into cheo_mensajes (conversacion_id, rol, texto)
    values (v_conv.id, 'usuario', left(p_usuario, 4000));
  end if;

  if coalesce(trim(p_cheo), '') <> '' then
    insert into cheo_mensajes (conversacion_id, rol, texto)
    values (v_conv.id, 'cheo', left(p_cheo, 4000));
  end if;

  update cheo_conversaciones
  set ultima_actividad = now(),
      mensajes_count = mensajes_count
        + (case when coalesce(trim(p_usuario), '') <> '' then 1 else 0 end)
        + (case when coalesce(trim(p_cheo), '') <> '' then 1 else 0 end),
      -- Si alguien retoma una charla ya clasificada, vuelve a la cola:
      -- lo nuevo que diga tiene que entrar al reporte.
      clasificada = false,
      estado = 'abierta',
      cerrada_en = null
  where id = v_conv.id;

  return jsonb_build_object('ok', true, 'conversacion_id', v_conv.id);
end $$;


-- ---------------------------------------------------------------
create or replace function public.cheo_guardar_contacto(
  p_sesion_id text,
  p_nombre    text default null,
  p_telefono  text default null,
  p_email     text default null,
  p_habeas    boolean default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tel text;
begin
  v_tel := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  if length(v_tel) = 12 and left(v_tel, 2) = '57' then v_tel := substr(v_tel, 3); end if;

  update cheo_conversaciones set
    nombre   = coalesce(nullif(left(trim(coalesce(p_nombre, '')), 80), ''), nombre),
    telefono = coalesce(nullif(v_tel, ''), telefono),
    email    = coalesce(nullif(left(trim(coalesce(p_email, '')), 120), ''), email),
    habeas   = coalesce(p_habeas, habeas),
    ultima_actividad = now()
  where sesion_id = p_sesion_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_existe');
  end if;
  return jsonb_build_object('ok', true);
end $$;


-- ---------------------------------------------------------------
create or replace function public.cheo_pendientes_de_clasificar(
  p_minutos integer default 20,
  p_limite  integer default 25
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  select coalesce(jsonb_agg(t), '[]'::jsonb) into v from (
    select c.sesion_id, c.id as conversacion_id, c.origen, c.iniciada_en,
           (select string_agg(
                     case m.rol when 'usuario' then 'Persona: ' else 'Cheo: ' end || m.texto,
                     E'\n' order by m.id)
              from cheo_mensajes m where m.conversacion_id = c.id) as transcripcion
    from cheo_conversaciones c
    where c.clasificada = false
      and c.mensajes_count > 0
      and c.ultima_actividad < now() - make_interval(mins => greatest(coalesce(p_minutos,20), 1))
    order by c.ultima_actividad
    limit greatest(coalesce(p_limite, 25), 1)
  ) t;
  return jsonb_build_object('ok', true, 'pendientes', v);
end $$;


-- ---------------------------------------------------------------
create or replace function public.cheo_clasificar(
  p_sesion_id   text,
  p_tipo        text,
  p_tema        text,
  p_resumen     text,
  p_urgencia    integer,
  p_sentimiento text,
  p_accion      text
) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  update cheo_conversaciones set
    clasificada = true,
    estado      = 'cerrada',
    cerrada_en  = coalesce(cerrada_en, now()),
    tipo        = case when p_tipo in ('sugerencia','queja','reclamo','duda','idea','elogio','otro')
                       then p_tipo else 'otro' end,
    tema        = left(nullif(trim(coalesce(p_tema, '')), ''), 120),
    resumen     = left(nullif(trim(coalesce(p_resumen, '')), ''), 1000),
    urgencia    = least(greatest(coalesce(p_urgencia, 3), 1), 5),
    sentimiento = case when p_sentimiento in ('positivo','neutral','negativo')
                       then p_sentimiento else 'neutral' end,
    accion_sugerida = left(nullif(trim(coalesce(p_accion, '')), ''), 500)
  where sesion_id = p_sesion_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_existe');
  end if;
  return jsonb_build_object('ok', true);
end $$;


-- ---------------------------------------------------------------
-- Sin argumentos devuelve la semana pasada completa, lunes a domingo,
-- en hora Bogota. Es lo que llama el reporte de los lunes.
create or replace function public.cheo_semana(
  p_desde date default null,
  p_hasta date default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_desde date; v_hasta date;
  v_convs jsonb; v_total int; v_msgs int; v_conteo jsonb;
begin
  v_hasta := coalesce(p_hasta, (date_trunc('week', (now() at time zone 'America/Bogota')))::date - 1);
  v_desde := coalesce(p_desde, v_hasta - 6);

  select count(*)::int, coalesce(sum(mensajes_count), 0)::int
    into v_total, v_msgs
  from cheo_conversaciones
  where (ultima_actividad at time zone 'America/Bogota')::date between v_desde and v_hasta
    and mensajes_count > 0;

  select coalesce(jsonb_agg(t order by (t->>'urgencia')::int desc), '[]'::jsonb) into v_convs from (
    select jsonb_build_object(
      'origen', c.origen,
      'tipo', coalesce(c.tipo, 'sin_clasificar'),
      'tema', c.tema,
      'resumen', c.resumen,
      'urgencia', coalesce(c.urgencia, 3),
      'sentimiento', coalesce(c.sentimiento, 'neutral'),
      'accion_sugerida', c.accion_sugerida,
      'dejo_contacto', (c.telefono is not null or c.email is not null),
      -- OJO: esto trae VARIOS mensajes pegados con ' | '. El prompt del
      -- reporte tiene que saberlo, o el modelo copia el bloque entero
      -- creyendo que es una sola cita.
      'dice_la_persona', left(coalesce((
          select string_agg(m.texto, ' | ' order by m.id)
          from cheo_mensajes m
          where m.conversacion_id = c.id and m.rol = 'usuario'), ''), 1200)
    ) as t
    from cheo_conversaciones c
    where (c.ultima_actividad at time zone 'America/Bogota')::date between v_desde and v_hasta
      and c.mensajes_count > 0
    limit 200
  ) s;

  select coalesce(jsonb_object_agg(tipo, n), '{}'::jsonb) into v_conteo from (
    select coalesce(tipo, 'sin_clasificar') as tipo, count(*)::int as n
    from cheo_conversaciones
    where (ultima_actividad at time zone 'America/Bogota')::date between v_desde and v_hasta
      and mensajes_count > 0
    group by 1
  ) k;

  return jsonb_build_object(
    'ok', true,
    'semana_inicio', v_desde,
    'semana_fin', v_hasta,
    'total_conversaciones', v_total,
    'total_mensajes', v_msgs,
    'por_tipo', v_conteo,
    'conversaciones', v_convs
  );
end $$;


-- ---------------------------------------------------------------
create or replace function public.cheo_guardar_reporte(
  p_desde      date,
  p_hasta      date,
  p_total_conv integer,
  p_total_msg  integer,
  p_insights   jsonb,
  p_resumen_md text,
  p_html       text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  insert into cheo_reportes (semana_inicio, semana_fin, total_conversaciones,
                             total_mensajes, insights, resumen_md, html)
  values (p_desde, p_hasta, coalesce(p_total_conv, 0), coalesce(p_total_msg, 0),
          p_insights, p_resumen_md, p_html)
  on conflict (semana_inicio) do update set
    semana_fin = excluded.semana_fin,
    generado_en = now(),
    total_conversaciones = excluded.total_conversaciones,
    total_mensajes = excluded.total_mensajes,
    insights = excluded.insights,
    resumen_md = excluded.resumen_md,
    html = excluded.html
  returning id into v_id;

  return jsonb_build_object('ok', true, 'reporte_id', v_id);
end $$;
