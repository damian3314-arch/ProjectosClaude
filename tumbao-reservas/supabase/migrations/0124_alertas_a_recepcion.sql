-- 0124 · El bot le escribe a recepción cuando algo pide una persona
--
-- Damián (29 sep): «muchos pagos sin procesar, no sé qué está pasando. En esos
-- casos que el bot envíe un mensaje al número de recepción 3017833550,
-- diciendo qué se debe validar o hacer, o qué cliente quedó pendiente».
--
-- QUÉ ENCONTRÓ LA REVISIÓN (29 sep)
--   · 113 depósitos «sin asignar» ($4,8M), pero 106 tienen más de 14 días: es
--     un rezago viejo. Lo que de verdad espera a una persona son 4 o 5
--     depósitos de la última semana: casi todos mensualidades de $125.000
--     pagadas por transferencia. El sistema casa solo las clases sueltas y
--     las tiqueteras; una mensualidad hay que pasarla a mano y nadie se
--     entera de que llegó hasta que abre «Por validar».
--   · 8 reservas «rechazadas» en 14 días: casi todas son la MISMA persona
--     reservando dos veces la misma clase. La primera se confirmó sola con su
--     pago y la segunda se quedó en la cola hasta que alguien la rechazó a
--     mano (30 horas de promedio). Ruido, no plata perdida.
--
-- QUÉ HACE `alertas_recepcion()`  (cada 10 minutos, lun-sáb 7 am a 9 pm)
--   Junta, sin repetir, lo que NUEVO pide una persona y manda UN solo mensaje
--   agrupado a ajustes.wa_recepcion_para:
--     1. Pagos que llegaron al banco (últimas 48 h, hace más de 10 minutos, de
--        $10.000 o más) y no están asignados a nadie. Si el nombre de quien
--        pagó coincide con una mensualidad que vence pronto, lo dice.
--     2. Reservas donde dijeron «ya pagué» hace más de 15 minutos y el pago no
--        aparece. Las repetidas (la misma persona ya tiene esa clase
--        confirmada) NO se avisan: no hay nada que hacer.
--     3. Tiqueteras por validar.
--     4. Mensualidades pagadas que todavía no se pasan a AdminGym (1 hora).
--   Cada cosa se avisa UNA vez (recepcion_alertas). Mínimo 20 minutos entre
--   mensajes. Nada de domingos ni festivos.
--
-- Cómo llega: el mismo camino que las notas del asistente a Damián. Si el
-- número habló con el de avisos en las últimas 23 h, el texto directo; si no,
-- la plantilla aprobada «Tu reporte del asistente está listo» y al tocar
-- «Ver resumen» llega el mensaje.

insert into ajustes (clave, valor, nota) values
  ('wa_recepcion_para', '3017833550',
   'A quién le escribe el bot cuando algo pide a una persona de recepción: pagos sin asignar, ya pagué sin pago, tiqueteras por validar (celulares separados por coma). 0124.'),
  ('wa_alertas_recepcion', 'encendido',
   'Alertas del bot a recepción. Poner apagado para detenerlas. 0124.')
on conflict (clave) do nothing;

create table if not exists public.recepcion_alertas (
  clave     text primary key,
  tipo      text not null,
  creada_at timestamptz not null default now()
);
alter table public.recepcion_alertas enable row level security;
revoke all on table public.recepcion_alertas from public, anon, authenticated;

-- Un nombre sin tildes ni mayúsculas, para compararlo con otro.
create or replace function public.norm_nombre(p text)
returns text
language sql
immutable
as $$
  select lower(translate(coalesce(p, ''), 'ÁÉÍÓÚÜáéíóúüÑñ', 'AEIOUUaeiouuNn'));
$$;

-- Como nota_asistente(), pero para otra lista de destinatarios.
create or replace function public.nota_recepcion(p_titulo text, p_texto text, p_clave text default null)
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
      from unnest(string_to_array(coalesce((select valor from ajustes where clave = 'wa_recepcion_para'), ''), ',')) t
     where trim(t) ~ '^3[0-9]{9}$'
  loop
    insert into wa_notas (clave, telefono, titulo, texto)
    values (case when p_clave is null then null else p_clave || ':' || v_tel end,
            v_tel, left(coalesce(nullif(btrim(p_titulo), ''), 'Pendientes'), 80), left(p_texto, 3500))
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
revoke all on function public.nota_recepcion(text, text, text) from public, anon, authenticated;

create or replace function public.alertas_recepcion()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  -- `tumbao.dia` y `tumbao.sin_horario` solo los usan las pruebas.
  hoy   date := coalesce(nullif(current_setting('tumbao.dia', true), '')::date,
                         (now() at time zone 'America/Bogota')::date);
  hora  int  := extract(hour from (now() at time zone 'America/Bogota'))::int;
  lineas_pago text[] := '{}';
  lineas_res  text[] := '{}';
  lineas_tiq  text[] := '{}';
  lineas_mens text[] := '{}';
  n_total int := 0;
  r record;
  v_texto text;
  v_dinero text;
begin
  if coalesce((select valor from ajustes where clave = 'wa_alertas_recepcion'), 'encendido') <> 'encendido' then
    return 0;
  end if;
  if extract(isodow from hoy) = 7 or exists (select 1 from festivos where fecha = hoy) then
    return 0;
  end if;
  if current_setting('tumbao.sin_horario', true) is distinct from 'si' and (hora < 7 or hora >= 21) then
    return 0;
  end if;
  -- Como mucho un mensaje cada 20 minutos: lo nuevo espera a la siguiente vuelta.
  if exists (select 1 from wa_notas where clave like 'recep:%'
              and creado_at > now() - interval '20 minutes') then
    return 0;
  end if;

  -- 1 · pagos que llegaron y no están asignados a nadie
  for r in
    select p.id, p.valor_cop - coalesce(p.usado_cop, 0) saldo, p.remitente, p.fecha_pago,
           (select initcap(m.afiliado) || ' (vence ' || to_char(m.fin, 'DD/MM') || ')'
              from membresias m
             where m.fin >= hoy - 5
               and cardinality(array(
                     select t from unnest(string_to_array(norm_nombre(p.remitente), ' ')) t where length(t) >= 3
                     intersect
                     select t from unnest(string_to_array(norm_nombre(m.afiliado), ' ')) t where length(t) >= 3)) >= 2
             order by m.fin limit 1) parece
      from pagos_sin_asignar p
     where p.fecha_pago between now() - interval '48 hours' and now() - interval '10 minutes'
       and p.valor_cop - coalesce(p.usado_cop, 0) >= 10000
       and not exists (select 1 from recepcion_alertas a where a.clave = 'pago:' || p.id)
     order by p.fecha_pago
  loop
    v_dinero := '$' || replace(to_char(r.saldo, 'FM999,999,999'), ',', '.');
    lineas_pago := lineas_pago || ('• ' || v_dinero || ' de ' || initcap(coalesce(nullif(btrim(r.remitente), ''), 'alguien sin nombre'))
      || ' (' || lower(to_char(r.fecha_pago at time zone 'America/Bogota', 'FMHH12:MI am')) || ')'
      || case when r.parece is not null then E'\n   Parece la renovación de ' || r.parece else '' end);
    insert into recepcion_alertas (clave, tipo) values ('pago:' || r.id, 'pago');
    n_total := n_total + 1;
  end loop;

  -- 2 · dijeron «ya pagué» y el pago no aparece (sin contar las repetidas)
  for r in
    select x.id, x.nombre, x.telefono, x.referencia_pago, c.precio_cop,
           lower(to_char(c.fecha_hora at time zone 'America/Bogota', 'FMHH12:MI am')) hora_clase
      from reservas x join clases c on c.id = x.clase_id
     where x.estado in ('verificando', 'pendiente_validacion')
       and x.pagado_en is not null and x.pago_id is null
       and x.created_at between now() - interval '48 hours' and now() - interval '15 minutes'
       and not exists (select 1 from reservas h
                        where h.clase_id = x.clase_id and h.telefono = x.telefono and h.id <> x.id
                          and h.estado = 'confirmada'
                          and split_part(norm_nombre(btrim(h.nombre)), ' ', 1) = split_part(norm_nombre(btrim(x.nombre)), ' ', 1))
       and not exists (select 1 from recepcion_alertas a where a.clave = 'reserva:' || x.id)
     order by x.created_at
  loop
    lineas_res := lineas_res || ('• ' || initcap(btrim(r.nombre)) || ' (' || r.telefono || ') · clase de ' || r.hora_clase
      || ' · $' || replace(to_char(coalesce(r.precio_cop, 0), 'FM999,999,999'), ',', '.')
      || case when r.referencia_pago is not null then ' · ref ' || r.referencia_pago else '' end);
    insert into recepcion_alertas (clave, tipo) values ('reserva:' || r.id, 'reserva');
    n_total := n_total + 1;
  end loop;

  -- 3 · tiqueteras por validar
  for r in
    select t.id, t.nombre, t.telefono, t.clases_totales, t.precio_cop
      from tiqueteras t
     where (t.estado = 'pendiente_validacion' or (t.estado = 'pendiente_pago' and t.pagado_en is not null))
       and coalesce(t.pagado_en, t.creada_en) between now() - interval '48 hours' and now() - interval '15 minutes'
       and not exists (select 1 from recepcion_alertas a where a.clave = 'tiq:' || t.id)
     order by t.creada_en
  loop
    lineas_tiq := lineas_tiq || ('• ' || initcap(btrim(r.nombre)) || ' (' || r.telefono || ') · tiquetera de ' || r.clases_totales
      || ' clases · $' || replace(to_char(coalesce(r.precio_cop, 0), 'FM999,999,999'), ',', '.'));
    insert into recepcion_alertas (clave, tipo) values ('tiq:' || r.id, 'tiquetera');
    n_total := n_total + 1;
  end loop;

  -- 4 · mensualidades pagadas que falta pasar a AdminGym
  for r in
    select s.id, s.nombre, s.celular, s.hora
      from mensualidad_solicitudes s
     where s.estado = 'pagada'
       and coalesce(s.pagado_en, s.creado_at) between now() - interval '48 hours' and now() - interval '1 hour'
       and not exists (select 1 from recepcion_alertas a where a.clave = 'mens:' || s.id)
     order by s.creado_at
  loop
    lineas_mens := lineas_mens || ('• ' || initcap(btrim(r.nombre)) || ' (' || r.celular || ') · mensualidad de las '
      || lower(to_char(r.hora::time, 'FMHH12:MI am')));
    insert into recepcion_alertas (clave, tipo) values ('mens:' || r.id, 'mensualidad');
    n_total := n_total + 1;
  end loop;

  if n_total = 0 then return 0; end if;

  v_texto := '';
  if cardinality(lineas_pago) > 0 then
    v_texto := v_texto || '💳 *Llegó plata al banco y no está asignada*' || E'\n' || array_to_string(lineas_pago, E'\n')
      || E'\nSi es una mensualidad, regístrala en Caja y pásala a AdminGym.' || E'\n\n';
  end if;
  if cardinality(lineas_res) > 0 then
    v_texto := v_texto || '🕒 *Dijeron que pagaron y el pago no aparece*' || E'\n' || array_to_string(lineas_res, E'\n')
      || E'\nPídeles el comprobante o revisa «Por validar».' || E'\n\n';
  end if;
  if cardinality(lineas_tiq) > 0 then
    v_texto := v_texto || '🎟 *Tiquetera por validar*' || E'\n' || array_to_string(lineas_tiq, E'\n')
      || E'\nVálidala en Tiqueteras cuando veas el pago.' || E'\n\n';
  end if;
  if cardinality(lineas_mens) > 0 then
    v_texto := v_texto || '📅 *Mensualidad pagada sin pasar a AdminGym*' || E'\n' || array_to_string(lineas_mens, E'\n') || E'\n\n';
  end if;
  v_texto := v_texto || 'Panel: tumbaobaila.com/admin';

  perform nota_recepcion('🔔 Pendientes por revisar (' || n_total || ')', v_texto,
                         'recep:' || to_char(now() at time zone 'America/Bogota', 'YYYYMMDDHH24MI'));
  return n_total;
exception when others then
  raise warning 'alertas_recepcion: %', sqlerrm;
  return 0;
end;
$$;
revoke all on function public.alertas_recepcion() from public, anon, authenticated;

-- Cada 10 minutos. La función se salta sola domingos, festivos y la noche.
do $cron$
begin
  perform cron.unschedule('tumbao-alertas-recepcion');
exception when others then null;
end
$cron$;
select cron.schedule('tumbao-alertas-recepcion', '*/10 * * * *',
                     'select public.alertas_recepcion()');
