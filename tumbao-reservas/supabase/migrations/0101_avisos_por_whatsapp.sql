-- 0101 · Avisos por WhatsApp: la cola, el registro y las bajas.
--
-- LO QUE PIDIÓ DAMIÁN (27-28 de septiembre)
-- «Enviar mensajes reales a los clientes, tipo "tu reserva quedó
--  efectiva"… lo más importante es que no me vayan a bannear el número.»
-- Autorizó: crear esto en la base, mandar la plantilla a Meta y UNA
-- prueba a su número. Prender los avisos para clientes de verdad es una
-- pregunta aparte (el ajuste `wa_avisos_reserva`, que nace apagado).
--
-- ── LO QUE APRENDIMOS LA NOCHE ANTERIOR ─────────────────────────────
-- Una ruta de prueba mandó ~20 mensajes al mismo número porque algo la
-- llamó en bucle. De ahí salen las reglas de esta cola, que no dependen
-- de que quien la llame se porte bien:
--
--   · `clave` es ÚNICA. Un aviso es «reserva_confirmada:<clase>:<cel>»:
--     una persona recibe UN aviso por clase, aunque reserve cuatro cupos
--     o aunque la reserva pase dos veces por confirmada.
--   · Se toma con FOR UPDATE SKIP LOCKED y se marca `enviando` en la
--     misma sentencia: dos despachos a la vez nunca toman el mismo.
--   · NUNCA se reintenta solo. Si Meta falla o no contesta, queda en
--     `fallido`. Un mensaje de más quema el número; uno de menos no.
--   · Tope diario total y tope de 3 por persona en 24 horas.
--
-- ── POR QUÉ UN DISPARADOR Y NO CÓDIGO EN CADA SITIO ─────────────────
-- Una reserva queda confirmada desde muchos lados: el pago en línea, el
-- cruce con el banco, las mensualidades, las tiqueteras, la reserva a
-- mano. Un solo disparador en `reservas` los cubre a todos, hoy y los
-- que vengan.
--
-- ── CÓMO LLEGA AL WORKER ────────────────────────────────────────────
-- Los cron de Cloudflare no disparan en esta cuenta (ver wrangler.jsonc).
-- Así que al entrar un aviso, la base misma le toca la puerta al Worker
-- con pg_net (asíncrono: sale después del commit, nunca frena la
-- reserva). La ruta /wa/despachar no necesita secreto: solo manda lo que
-- YA está en la cola, cada cosa una vez.

create extension if not exists pg_net with schema extensions;

-- ── la cola, que es también el registro ─────────────────────────────
create table if not exists public.wa_avisos (
  id          bigint generated always as identity primary key,
  clave       text not null unique,
  tipo        text not null,
  telefono    text not null check (telefono ~ '^3[0-9]{9}$'),
  plantilla   text not null,
  idioma      text not null default 'es',
  datos       jsonb not null default '{}'::jsonb,
  variables   jsonb,
  vence_at    timestamptz,
  estado      text not null default 'pendiente'
              check (estado in ('pendiente', 'enviando', 'enviado', 'fallido', 'omitido')),
  motivo      text,
  wa_id       text,
  creado_at   timestamptz not null default now(),
  tomado_at   timestamptz,
  enviado_at  timestamptz
);
create index if not exists wa_avisos_pendientes on public.wa_avisos (id) where estado = 'pendiente';
create index if not exists wa_avisos_por_telefono on public.wa_avisos (telefono, tomado_at);
alter table public.wa_avisos enable row level security;
comment on table public.wa_avisos is
  '0101: cola y registro de avisos por WhatsApp. clave única = un aviso por evento. '
  'Nunca se reintenta solo: fallido se queda fallido.';

-- ── quien no quiere más mensajes ────────────────────────────────────
create table if not exists public.wa_bajas (
  telefono   text primary key check (telefono ~ '^3[0-9]{9}$'),
  motivo     text,
  creado_at  timestamptz not null default now()
);
alter table public.wa_bajas enable row level security;
comment on table public.wa_bajas is
  '0101: celulares que no quieren mensajes de Tumbao. Nunca se les escribe.';

-- ── los mandos ──────────────────────────────────────────────────────
insert into public.ajustes (clave, valor, nota) values
  ('wa_avisos_reserva', 'apagado',
   'encendido = cada reserva confirmada le manda un aviso por WhatsApp al cliente. '
   'Nace apagado: prenderlo es decisión de Damián. 0101.'),
  ('wa_tope_diario', '200',
   'Máximo de mensajes de WhatsApp en 24 horas, sumando todo. Freno de mano. 0101.'),
  ('wa_despachar_url', 'https://tumbao-caja.damian3314.workers.dev/wa/despachar',
   'A dónde toca la base cuando entra un aviso a la cola. 0101.')
on conflict (clave) do nothing;

-- ── el texto de un aviso de reserva ─────────────────────────────────
-- Se arma al MANDAR, no al encolar: si la persona reservó varios cupos
-- y se confirmaron en la misma pasada, salen todos los códigos juntos.
-- Devuelve null si ya no hay nada confirmado (se canceló entre medias).
create or replace function public.wa_variables_reserva(p_clase uuid, p_tel text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_fecha   timestamptz;
  v_nomcla  text;
  v_local   timestamp;
  v_codigos text[];
  v_nombre  text;
  v_hora    text;
  v_dias    text[] := array['domingo','lunes','martes','miércoles','jueves','viernes','sábado'];
  v_meses   text[] := array['enero','febrero','marzo','abril','mayo','junio','julio',
                            'agosto','septiembre','octubre','noviembre','diciembre'];
begin
  select c.fecha_hora, c.nombre into v_fecha, v_nomcla from clases c where c.id = p_clase;
  if v_fecha is null then return null; end if;

  select array_agg(r.codigo order by r.created_at),
         (array_agg(r.nombre order by r.created_at))[1]
    into v_codigos, v_nombre
    from reservas r
   where r.clase_id = p_clase
     and r.estado = 'confirmada'
     and right(regexp_replace(r.telefono, '\D', '', 'g'), 10) = p_tel;
  if v_codigos is null then return null; end if;

  v_local  := v_fecha at time zone 'America/Bogota';
  v_nombre := initcap(split_part(trim(coalesce(v_nombre, '')), ' ', 1));
  if v_nombre = '' then v_nombre := 'amigo(a)'; end if;

  v_hora := to_char(v_local, 'FMHH12:MI') ||
            case when extract(hour from v_local) < 12 then ' am' else ' pm' end;
  -- «Clase 6:00 pm» al lado de la hora no dice nada; «Rumba básica» sí.
  if v_nomcla is not null and v_nomcla !~* '^clase ' then
    v_hora := v_hora || ' · ' || v_nomcla;
  end if;

  return jsonb_build_array(
    v_nombre,
    v_dias[extract(dow from v_local)::int + 1] || ' ' ||
      extract(day from v_local)::int || ' de ' || v_meses[extract(month from v_local)::int],
    v_hora,
    case when cardinality(v_codigos) = 1
         then 'Código: ' || v_codigos[1]
         else 'Códigos: ' || array_to_string(v_codigos, ', ') ||
              ' (' || cardinality(v_codigos) || ' cupos)'
    end);
end;
$$;

-- ── encolar: el disparador de reservas ──────────────────────────────
create or replace function public.wa_encolar_reserva()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tel   text;
  v_fecha timestamptz;
begin
  if new.estado <> 'confirmada' then return new; end if;
  if tg_op = 'UPDATE' and old.estado = 'confirmada' then return new; end if;
  if coalesce((select valor from ajustes where clave = 'wa_avisos_reserva'), 'apagado')
     <> 'encendido' then
    return new;
  end if;

  v_tel := right(regexp_replace(coalesce(new.telefono, ''), '\D', '', 'g'), 10);
  if v_tel !~ '^3[0-9]{9}$' then return new; end if;          -- solo celulares de Colombia

  select fecha_hora into v_fecha from clases where id = new.clase_id;
  if v_fecha is null or v_fecha < now() then return new; end if;  -- clase ya pasó

  insert into wa_avisos (clave, tipo, telefono, plantilla, datos, vence_at)
  values ('reserva_confirmada:' || new.clase_id || ':' || v_tel,
          'reserva_confirmada', v_tel, 'reserva_confirmada',
          jsonb_build_object('clase_id', new.clase_id, 'reserva_id', new.id),
          v_fecha)
  on conflict (clave) do nothing;
  return new;
exception when others then
  -- Un aviso NUNCA puede tumbar una reserva.
  raise warning 'wa_encolar_reserva: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists wa_aviso_reserva on public.reservas;
create trigger wa_aviso_reserva
  after insert or update of estado on public.reservas
  for each row execute function public.wa_encolar_reserva();

-- ── tocarle la puerta al Worker ─────────────────────────────────────
create or replace function public.wa_avisar_worker()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_url text;
begin
  select valor into v_url from ajustes where clave = 'wa_despachar_url';
  if coalesce(v_url, '') <> '' then
    perform net.http_post(url := v_url, body := '{}'::jsonb,
                          headers := '{"Content-Type": "application/json"}'::jsonb);
  end if;
  return null;
exception when others then
  raise warning 'wa_avisar_worker: %', sqlerrm;
  return null;
end;
$$;

drop trigger if exists wa_avisar_worker on public.wa_avisos;
create trigger wa_avisar_worker
  after insert on public.wa_avisos
  for each statement execute function public.wa_avisar_worker();

-- ── tomar lo que hay que mandar ─────────────────────────────────────
create or replace function public.wa_tomar_avisos(p_limite int default 10)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tope  int;
  v_usado int;
  v_cupo  int;
  v_vars  jsonb;
  v_out   jsonb := '[]'::jsonb;
  r       record;
begin
  -- Lo que ya no tiene sentido mandar se cierra sin mandar.
  update wa_avisos set estado = 'omitido', motivo = 'vencido'
   where estado = 'pendiente' and vence_at is not null and vence_at < now();
  update wa_avisos a set estado = 'omitido', motivo = 'baja'
   where a.estado = 'pendiente'
     and exists (select 1 from wa_bajas b where b.telefono = a.telefono);
  -- Lo que se quedó a medias NO se reintenta: pudo haber salido.
  update wa_avisos set estado = 'fallido', motivo = 'sin_respuesta_del_worker'
   where estado = 'enviando' and tomado_at < now() - interval '15 minutes';

  v_tope := coalesce(nullif((select valor from ajustes where clave = 'wa_tope_diario'), '')::int, 200);
  select count(*) into v_usado from wa_avisos
   where estado in ('enviando', 'enviado') and tomado_at > now() - interval '24 hours';
  v_cupo := least(greatest(p_limite, 0), greatest(v_tope - v_usado, 0));
  if v_cupo = 0 then return v_out; end if;

  for r in
    update wa_avisos set estado = 'enviando', tomado_at = now()
     where id in (select id from wa_avisos where estado = 'pendiente'
                   order by id limit v_cupo for update skip locked)
    returning *
  loop
    -- Tope por persona: 3 en 24 horas.
    if (select count(*) from wa_avisos x
         where x.telefono = r.telefono and x.id <> r.id
           and x.estado in ('enviando', 'enviado')
           and x.tomado_at > now() - interval '24 hours') >= 3 then
      update wa_avisos set estado = 'omitido', motivo = 'tope_por_persona' where id = r.id;
      continue;
    end if;

    if r.tipo = 'reserva_confirmada' then
      v_vars := wa_variables_reserva((r.datos->>'clase_id')::uuid, r.telefono);
      if v_vars is null then
        update wa_avisos set estado = 'omitido', motivo = 'ya_no_confirmada' where id = r.id;
        continue;
      end if;
      update wa_avisos set variables = v_vars where id = r.id;
    else
      v_vars := r.variables;
    end if;

    v_out := v_out || jsonb_build_object(
      'id', r.id, 'para', '57' || r.telefono, 'plantilla', r.plantilla,
      'idioma', r.idioma, 'variables', coalesce(v_vars, '[]'::jsonb));
  end loop;
  return v_out;
end;
$$;

-- ── anotar cómo le fue ──────────────────────────────────────────────
create or replace function public.wa_marcar_aviso(p_id bigint, p_ok boolean,
                                                  p_wa_id text default null,
                                                  p_error text default null)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update wa_avisos
     set estado     = case when p_ok then 'enviado' else 'fallido' end,
         wa_id      = p_wa_id,
         motivo     = case when p_ok then null else left(p_error, 500) end,
         enviado_at = case when p_ok then now() end
   where id = p_id and estado = 'enviando';
$$;

-- Solo el Worker (service_role) las usa.
revoke all on function public.wa_variables_reserva(uuid, text) from public, anon, authenticated;
revoke all on function public.wa_encolar_reserva() from public, anon, authenticated;
revoke all on function public.wa_avisar_worker() from public, anon, authenticated;
revoke all on function public.wa_tomar_avisos(int) from public, anon, authenticated;
revoke all on function public.wa_marcar_aviso(bigint, boolean, text, text) from public, anon, authenticated;
grant execute on function public.wa_tomar_avisos(int) to service_role;
grant execute on function public.wa_marcar_aviso(bigint, boolean, text, text) to service_role;
