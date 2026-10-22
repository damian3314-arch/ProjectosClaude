-- 0141 · Ventas por WhatsApp: el asistente contacta clientes de la base y conversa para vender
--
-- Damián (4 oct): «necesito que el bot se encargue de vender: por lo menos 3 horas al día
-- debe contactar clientes de nuestra base y ofrecerles nuestras clases, actuar como
-- humano y lograr que compren una tiquetera o mensualidad, para asegurar que vendamos
-- los 3 horarios fijos: 7 am, 6 pm y 7 pm».
--
-- CÓMO FUNCIONA (todo APAGADO hasta que Damián lo encienda: wa_ventas = 'apagado')
--   1. ventas_ronda() corre cada 10 minutos. Solo trabaja dentro de la ventana de ventas
--      (por defecto lun–vie 10:00–13:00 = 3 horas; sábado hasta la 1 pm; nunca domingo ni
--      festivo, Ley 2300) y mete a la cola pocas personas por ronda (3), con un tope por
--      día (45). Ese ritmo lento es a propósito: se ve humano y no quema el número.
--   2. A cada persona le llega UNA apertura con una plantilla aprobada por Meta
--      ('ventas_apertura'). WhatsApp no permite escribirle libre a quien no ha respondido.
--   3. Si responde, el trigger despierta a /wa/ventas (Worker), que conversa con IA dentro
--      de la ventana de 24 h, con reglas duras: precios y cupos SOLO de la base, enlace de
--      pago de la página, y si hay duda de plata o cupo, pasa a recepción.
--   4. Quien dice «no» o pide SALIR queda fuera 45 días (o para siempre si pidió salir).
--
-- A QUIÉN SE LE ESCRIBE y qué se le ofrece (objetivo):
--   mensualidad_6pm  quien viene a las 6 pm Y cumple los requisitos, mientras haya cupo
--                    (a lo sumo tantas personas como cupos libres: nadie se cuela).
--   mensualidad_7am  quien viene a las 7 am, mientras haya cupo público a las 7 am.
--   tiquetera        quien vino 2 o más veces en 30 días con clase suelta.
--   reactivar        quien vino hace 31–90 días y no ha vuelto (tiquetera).
--   El horario de 7 pm está completo: no se le ofrece mensualidad (se le puede invitar a la
--   lista de espera si pregunta, y mientras tanto tiquetera).
--
-- Reglas que no se saltan: sin mensualidad vigente (ni en gracia), sin tiquetera con clases,
-- sin bajas ni dueños, ni a quien recibió cualquier campaña en los últimos 5 días, como
-- mucho 2 campañas cada 14 días, una apertura de ventas cada 14 días por persona.

create table if not exists public.ventas_chats (
  id          bigint generated always as identity primary key,
  telefono    text not null check (telefono ~ '^3[0-9]{9}$'),
  nombre      text,
  objetivo    text not null check (objetivo in ('mensualidad_6pm', 'mensualidad_7am', 'tiquetera', 'reactivar')),
  oferta      jsonb not null default '{}'::jsonb,
  estado      text not null default 'abierta' check (estado in ('abierta', 'conversando', 'cerrada')),
  turnos      int not null default 0,
  interes     text,
  resumen     text,
  resultado   text,
  abierta_at  timestamptz not null default now(),
  ultima_at   timestamptz,
  cerrada_at  timestamptz
);
create index if not exists ventas_chats_por_telefono on public.ventas_chats (telefono, abierta_at desc);
alter table public.ventas_chats enable row level security;
revoke all on table public.ventas_chats from public, anon, authenticated;

insert into public.ajustes (clave, valor, nota) values
  ('wa_ventas', 'apagado',
   'Ventas por WhatsApp: el asistente contacta clientes y conversa para vender. Se enciende cuando Meta aprueba la plantilla ventas_apertura y Damián lo decide. 0141.'),
  ('wa_ventas_url', 'https://tumbao-caja.damian3314.workers.dev/wa/ventas',
   'Ruta del Worker que conversa con quien responde a una apertura de ventas. 0141.'),
  ('ventas_hora_ini', '10:00', 'Ventas por WhatsApp: hora de inicio (Bogotá). 0141.'),
  ('ventas_hora_fin', '13:00', 'Ventas por WhatsApp: hora de fin (Bogotá). Los sábados nunca pasa de la 1 pm. 0141.'),
  ('ventas_por_ronda', '3', 'Ventas por WhatsApp: personas nuevas por ronda (cada 10 minutos). 0141.'),
  ('ventas_tope_dia', '45', 'Ventas por WhatsApp: máximo de aperturas nuevas por día. 0141.')
on conflict (clave) do nothing;

create or replace function public.ventas_ajuste(p_clave text, p_defecto text)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select coalesce(nullif((select valor from ajustes where clave = p_clave), ''), p_defecto) $$;
revoke all on function public.ventas_ajuste(text, text) from public, anon, authenticated;

-- La conversación de ventas viva de un teléfono: abierta o conversando (48 h desde la
-- apertura), o cerrada hace menos de 24 h (para no contestarle con el «no revisamos mensajes»
-- a quien acaba de hablar con nosotros).
create or replace function public.ventas_viva(p_tel text)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select id from ventas_chats
   where telefono = right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 10)
     and ((estado in ('abierta', 'conversando') and abierta_at > now() - interval '48 hours')
          or (estado = 'cerrada' and cerrada_at > now() - interval '24 hours'))
   order by abierta_at desc limit 1;
$$;
revoke all on function public.ventas_viva(text) from public, anon, authenticated;

-- Cupos libres para VENDER mensualidad hoy, por horario: 7 am con el tope público
-- (mensualidad_cupos) y 6/7 pm con el tope por fidelidad (premium_cupos_horario).
create or replace function public.ventas_cupos()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    '07:00', coalesce((select (h ->> 'libres')::int from jsonb_array_elements(mensualidad_cupos() -> 'horas') h where h ->> 'hora' = '07:00'), 0),
    '18:00', coalesce((premium_cupos_horario() -> '18:00' ->> 'libres')::int, 0),
    '19:00', coalesce((premium_cupos_horario() -> '19:00' ->> 'libres')::int, 0))
$$;
revoke all on function public.ventas_cupos() from public, anon, authenticated;

-- Candidatos en orden de prioridad. Solo lee. p_limite = cuántos devolver.
create or replace function public.ventas_candidatos(p_limite int default 50)
returns table (tel text, nombre text, objetivo text, visitas_30d int, hora_habitual text, prioridad int)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  hoy date := (now() at time zone 'America/Bogota')::date;
  cupos jsonb := ventas_cupos();
  v_l7 int; v_l6 int;
begin
  -- A los cupos libres se les restan las aperturas de los últimos 7 días que siguen vivas.
  v_l7 := greatest((cupos ->> '07:00')::int
            - (select count(*) from ventas_chats c where c.objetivo = 'mensualidad_7am' and c.abierta_at > now() - interval '7 days' and c.estado <> 'cerrada'), 0);
  v_l6 := greatest((cupos ->> '18:00')::int
            - (select count(*) from ventas_chats c where c.objetivo = 'mensualidad_6pm' and c.abierta_at > now() - interval '7 days' and c.estado <> 'cerrada'), 0);

  return query
  with vig as (
    select distinct right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) t
      from membresias where fin + 3 >= hoy),
  tq as (
    select distinct right(regexp_replace(telefono, '\D', '', 'g'), 10) t
      from tiqueteras
     where pagado_en is not null and vence_el >= hoy and clases_usadas < clases_totales),
  r as (
    select right(regexp_replace(x.telefono, '\D', '', 'g'), 10) t,
           (array_agg(initcap(split_part(btrim(x.nombre), ' ', 1)) order by x.created_at desc))[1] n,
           count(*) filter (where x.tipo = 'suelta' and c.fecha_hora >= now() - interval '30 days') v30,
           max(c.fecha_hora) ultima,
           mode() within group (order by to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'))
             filter (where c.fecha_hora >= now() - interval '60 days') hh
      from reservas x join clases c on c.id = x.clase_id
     where x.estado = 'confirmada' and c.fecha_hora < now()
     group by 1),
  base as (
    select r.* from r
     where r.t ~ '^3[0-9]{9}$'
       and r.t not in (select t from vig) and r.t not in (select t from tq)
       and not wa_es_dueno(r.t)
       and not exists (select 1 from wa_bajas b where b.telefono = r.t)
       and not exists (select 1 from wa_avisos a where a.telefono = r.t and a.tipo = 'campana'
                         and a.estado in ('enviando', 'enviado', 'pendiente') and a.creado_at > now() - interval '5 days')
       and (select count(*) from wa_avisos a where a.telefono = r.t and a.tipo = 'campana'
              and a.estado in ('enviando', 'enviado', 'pendiente') and a.creado_at > now() - interval '14 days') < 2
       and not exists (select 1 from ventas_chats c where c.telefono = r.t and c.abierta_at > now() - interval '14 days')
       and not exists (select 1 from ventas_chats c where c.telefono = r.t and c.resultado = 'no_interesado'
                         and c.cerrada_at > now() - interval '45 days')
       and not exists (select 1 from wa_opiniones o where o.telefono = r.t and o.estado <> 'cerrada' and o.invitada_at > now() - interval '72 hours')),
  clas as (
    select b.*,
           case
             when b.hh = '18:00' and v_l6 > 0
                  and (premium_evaluar(b.t) -> 'personas' -> 0 ->> 'veredicto') = 'aplica' then 'mensualidad_6pm'
             when b.hh = '07:00' and v_l7 > 0 and b.v30 >= 1 then 'mensualidad_7am'
             when b.v30 >= 2 then 'tiquetera'
             when b.ultima < now() - interval '30 days' and b.ultima >= now() - interval '90 days' then 'reactivar'
           end obj
      from base b),
  orden as (
    select c.*,
           row_number() over (partition by c.obj order by c.v30 desc, c.ultima desc) rn
      from clas c where c.obj is not null)
  select o.t, coalesce(nullif(o.n, ''), 'amigo(a)'), o.obj, o.v30::int, o.hh,
         case o.obj when 'mensualidad_6pm' then 1 when 'mensualidad_7am' then 2 when 'tiquetera' then 3 else 4 end
    from orden o
   where (o.obj = 'mensualidad_6pm' and o.rn <= v_l6)
      or (o.obj = 'mensualidad_7am' and o.rn <= v_l7)
      or o.obj in ('tiquetera', 'reactivar')
   order by 6, o.v30 desc, o.ultima desc
   limit greatest(p_limite, 0);
end;
$$;
revoke all on function public.ventas_candidatos(int) from public, anon, authenticated;

-- La frase que va en la apertura. La escribe el código, no el modelo: los números son los de
-- la base, siempre.
create or replace function public.ventas_gancho(p_objetivo text, p_visitas int)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_por int;
begin
  select min(round((p ->> 'precio_cop')::numeric / nullif((p ->> 'clases')::numeric, 0)))::int into v_por
    from jsonb_array_elements(tiquetera_paquetes()) p;
  v_por := coalesce(v_por, 12000);
  return case p_objetivo
    when 'mensualidad_6pm' then 'Se liberó un cupo de mensualidad en el horario de 6 pm y pensé en ti por lo constante que has sido 🧡'
    when 'mensualidad_7am' then 'Tenemos cupos de mensualidad en el horario de 7 am: bailas todos los días de la semana y te sale mucho más económico que pagar clase por clase'
    when 'reactivar' then 'Hace un tiempo no te vemos por Tumbao y te extrañamos 🧡 Esta semana hay clases todos los días y con una tiquetera cada clase te sale desde $'
                          || replace(to_char(v_por, 'FM999,999,999'), ',', '.')
    else 'Vi que este mes ya has venido ' || greatest(coalesce(p_visitas, 2), 2) || ' veces a bailar con nosotros 💃 Con una tiquetera cada clase te sale desde $'
         || replace(to_char(v_por, 'FM999,999,999'), ',', '.') || ' en vez de $15.000'
  end;
end;
$$;
revoke all on function public.ventas_gancho(text, int) from public, anon, authenticated;

-- Una ronda: abre conversaciones nuevas dentro de la ventana de ventas.
--   p_ejecutar = false: solo dice a quién le escribiría ahora (sin ventana ni interruptor).
--   p_ejecutar = true : respeta el interruptor, la ventana y los topes, y encola.
create or replace function public.ventas_ronda(p_ejecutar boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  ahora timestamp := now() at time zone 'America/Bogota';
  hoy date := ahora::date;
  v_dow int := extract(isodow from ahora)::int;
  v_ini time := ventas_ajuste('ventas_hora_ini', '10:00')::time;
  v_fin time := ventas_ajuste('ventas_hora_fin', '13:00')::time;
  v_por int := ventas_ajuste('ventas_por_ronda', '3')::int;
  v_tope int := ventas_ajuste('ventas_tope_dia', '45')::int;
  v_hoy int; v_n int := 0; v_prev jsonb;
begin
  if not p_ejecutar then
    select coalesce(jsonb_agg(jsonb_build_object('tel', right(c.tel, 4), 'nombre', c.nombre, 'objetivo', c.objetivo,
                                                  'visitas_30d', c.visitas_30d, 'hora_habitual', c.hora_habitual)), '[]'::jsonb)
      into v_prev from ventas_candidatos(50) c;
    return jsonb_build_object('ejecutado', false, 'candidatos', v_prev, 'cupos', ventas_cupos());
  end if;

  if ventas_ajuste('wa_ventas', 'apagado') <> 'encendido' then
    return jsonb_build_object('ok', true, 'activo', false);
  end if;
  -- Ley 2300: sin mercadeo domingos ni festivos; sábados hasta la 1 pm.
  if v_dow = 7 or exists (select 1 from festivos where fecha = hoy) then
    return jsonb_build_object('ok', true, 'activo', true, 'motivo', 'dia_sin_envio');
  end if;
  if v_dow = 6 then v_fin := least(v_fin, time '13:00'); end if;
  if ahora::time < v_ini or ahora::time >= v_fin then
    return jsonb_build_object('ok', true, 'activo', true, 'motivo', 'fuera_de_ventana');
  end if;

  select count(*) into v_hoy from ventas_chats where (abierta_at at time zone 'America/Bogota')::date = hoy;
  if v_hoy >= v_tope then
    return jsonb_build_object('ok', true, 'activo', true, 'motivo', 'tope_del_dia', 'hoy', v_hoy);
  end if;

  with sel as (
    select * from ventas_candidatos(least(v_por, v_tope - v_hoy))
  ), chat as (
    insert into ventas_chats (telefono, nombre, objetivo, oferta)
    select s.tel, s.nombre, s.objetivo,
           jsonb_build_object('visitas_30d', s.visitas_30d, 'hora_habitual', s.hora_habitual)
      from sel s
    returning telefono, nombre, objetivo, oferta, id
  ), enc as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'ventas:' || c.telefono || ':' || to_char(hoy, 'YYYYMMDD'), 'campana', c.telefono, 'ventas_apertura',
           jsonb_build_array(c.nombre, ventas_gancho(c.objetivo, (c.oferta ->> 'visitas_30d')::int)),
           now() + interval '2 hours'
      from chat c
    on conflict (clave) do nothing
    returning 1
  )
  select count(*) into v_n from enc;

  return jsonb_build_object('ok', true, 'activo', true, 'encolados', v_n, 'hoy', v_hoy + v_n);
exception when others then
  raise warning 'ventas_ronda: %', sqlerrm;
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;
revoke all on function public.ventas_ronda(boolean) from public, anon, authenticated;

-- Lo que el asistente necesita saber de la persona para conversar (solo datos de la base).
create or replace function public.ventas_perfil(p_tel text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  t text := right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 10);
  hoy date := (now() at time zone 'America/Bogota')::date;
  r record; ev jsonb; per jsonb; v_plan jsonb; v_tq jsonb;
begin
  select initcap(split_part(btrim((array_agg(x.nombre order by x.created_at desc))[1]), ' ', 1)) nombre,
         count(*) filter (where x.tipo = 'suelta' and c.fecha_hora >= now() - interval '30 days' and c.fecha_hora < now()) v30,
         count(*) filter (where c.fecha_hora < now()) total,
         (max(c.fecha_hora) at time zone 'America/Bogota')::date ultima,
         mode() within group (order by to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'))
           filter (where c.fecha_hora >= now() - interval '60 days') hh
    into r
    from reservas x join clases c on c.id = x.clase_id
   where x.estado = 'confirmada' and right(regexp_replace(x.telefono, '\D', '', 'g'), 10) = t;

  ev := premium_evaluar(t);
  per := ev -> 'personas' -> 0;

  select jsonb_build_object('horario', m.hora, 'vence', m.fin) into v_plan
    from membresias m where right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10) = t and m.fin + 3 >= hoy
   order by m.fin desc limit 1;
  select jsonb_build_object('clases_restantes', tq.clases_totales - tq.clases_usadas, 'vence', tq.vence_el) into v_tq
    from tiqueteras tq where right(regexp_replace(tq.telefono, '\D', '', 'g'), 10) = t
     and tq.pagado_en is not null and tq.vence_el >= hoy and tq.clases_usadas < tq.clases_totales
   order by tq.vence_el desc limit 1;

  return jsonb_build_object(
    'nombre', r.nombre, 'visitas_30d', coalesce(r.v30, 0), 'visitas_en_total', coalesce(r.total, 0),
    'ultima_clase', r.ultima, 'horario_habitual', r.hh,
    'plan_vigente', v_plan, 'tiquetera_vigente', v_tq,
    'aplica_mensualidad', coalesce(per ->> 'veredicto', 'sin_historial') = 'aplica',
    'cupos_mensualidad', ventas_cupos(),
    'valor_mensualidad', coalesce(nullif((select valor from ajustes where clave = 'mensualidad_valor_cop'), '')::int, 125000),
    'precio_suelta', 15000,
    'paquetes_tiquetera', tiquetera_paquetes());
end;
$$;
revoke all on function public.ventas_perfil(text) from public, anon, authenticated;

-- El Worker toma el mensaje entrante y la conversación completa de esa venta.
create or replace function public.wa_tomar_ventas(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare m wa_mensajes; c ventas_chats; v_his jsonb;
begin
  update wa_mensajes set estado = 'procesando'
   where id = p_id and estado = 'recibido' and direccion = 'entrante'
  returning * into m;
  if m.id is null or wa_es_dueno(m.telefono) then return null; end if;
  if exists (select 1 from wa_bajas b where b.telefono = right(m.telefono, 10)) then
    update wa_mensajes set estado = 'ignorado' where id = m.id;
    return null;
  end if;
  select * into c from ventas_chats where id = ventas_viva(m.telefono);
  if c.id is null then
    update wa_mensajes set estado = 'ignorado' where id = m.id;
    return null;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('direccion', h.direccion, 'texto', h.texto) order by h.id), '[]'::jsonb)
    into v_his
    from (select id, direccion, texto from wa_mensajes
           where right(telefono, 10) = c.telefono and id < m.id and texto is not null
             and creado_at >= c.abierta_at
           order by id desc limit 20) h;
  return jsonb_build_object('id', m.id, 'telefono', m.telefono, 'wa_msg_id', m.wa_msg_id,
    'tipo', m.tipo, 'texto', m.texto, 'historial', v_his,
    'chat', jsonb_build_object('id', c.id, 'nombre', c.nombre, 'objetivo', c.objetivo,
                               'estado', c.estado, 'turnos', c.turnos),
    'perfil', ventas_perfil(m.telefono),
    'apertura', coalesce((select a.variables ->> 1 from wa_avisos a
                           where a.telefono = c.telefono and a.plantilla = 'ventas_apertura'
                           order by a.id desc limit 1), ''));
end;
$$;
revoke all on function public.wa_tomar_ventas(bigint) from public, anon, authenticated;

-- El Worker anota el resultado de cada turno.
create or replace function public.ventas_turno(p_chat bigint, p_mensaje bigint, p_texto_entrante text,
                                               p_cerrar boolean, p_resultado text, p_interes text, p_resumen text)
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
  update ventas_chats
     set turnos = turnos + 1,
         ultima_at = now(),
         estado = case when p_cerrar then 'cerrada' else 'conversando' end,
         cerrada_at = case when p_cerrar and cerrada_at is null then now() else cerrada_at end,
         interes = coalesce(nullif(btrim(coalesce(p_interes, '')), ''), interes),
         resumen = coalesce(nullif(btrim(coalesce(p_resumen, '')), ''), resumen),
         resultado = coalesce(nullif(btrim(coalesce(p_resultado, '')), ''), resultado)
   where id = p_chat;
end;
$$;
revoke all on function public.ventas_turno(bigint, bigint, text, boolean, text, text, text) from public, anon, authenticated;

-- Quien responde a una apertura de ventas se atiende en /wa/ventas, no con el «no revisamos mensajes».
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
    'ventas', (not wa_es_dueno(p_tel)) and wa_opinion_viva(p_tel) is null and ventas_viva(p_tel) is not null,
    'responder', coalesce((select valor from ajustes where clave = 'wa_respuesta_auto'), 'apagado') = 'encendido');
end;
$$;

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
  elsif ventas_viva(new.telefono) is not null then
    select valor into v_url from ajustes where clave = 'wa_ventas_url';
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

-- Medir: aperturas, respuestas, interés y compras de quienes entraron al embudo.
create or replace function public.ventas_resultados(p_dias int default 14)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with c as (select * from ventas_chats where abierta_at > now() - make_interval(days => greatest(p_dias, 1))),
  t as (select c.id, exists (select 1 from tiqueteras q
                              where right(regexp_replace(q.telefono, '\D', '', 'g'), 10) = c.telefono
                                and q.pagado_en is not null and q.pagado_en >= c.abierta_at) compro_tiquetera,
                     exists (select 1 from membresias m
                              where right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10) = c.telefono
                                and m.inicio >= (c.abierta_at at time zone 'America/Bogota')::date) compro_mensualidad
          from c)
  select jsonb_build_object(
    'aperturas', (select count(*) from c),
    'respondieron', (select count(*) from c where turnos > 0),
    'interes_alto', (select count(*) from c where interes = 'alto'),
    'no_interesados', (select count(*) from c where resultado = 'no_interesado'),
    'pasados_a_recepcion', (select count(*) from c where resultado = 'recepcion'),
    'compraron_tiquetera', (select count(*) from t where compro_tiquetera),
    'compraron_mensualidad', (select count(*) from t where compro_mensualidad),
    'por_objetivo', (select coalesce(jsonb_object_agg(objetivo, n), '{}'::jsonb) from (select objetivo, count(*) n from c group by 1) z));
$$;
revoke all on function public.ventas_resultados(int) from public, anon, authenticated;

-- Cada 10 minutos. Con wa_ventas apagado no hace nada.
do $cron$
begin
  perform cron.unschedule('tumbao-ventas');
exception when others then null;
end
$cron$;
select cron.schedule('tumbao-ventas', '*/10 * * * *', 'select public.ventas_ronda(true)');
