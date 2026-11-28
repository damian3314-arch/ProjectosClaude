-- 0224 · Lo que la persona dice que pagó se queda en «Por validar» (no se libera a los 30 min) + Timba pide el comprobante
--        + seguimiento del correo del banco.
--
-- Damián (27 nov): el banco está fallando (a veces no llega el correo del depósito) y varias usuarias dijeron «ya pagué»,
-- no vieron su reserva en «Por validar» y se les liberó el cupo a los 30 minutos. Eso no se puede hacer.
--
-- 1) liberar_cupos_expirados: las reservas en verificando / pendiente_validacion SIN pago ya NO se liberan por falta de
--    soporte mientras la clase no haya terminado. Siguen en «Por validar» para que recepción les ponga la referencia del
--    comprobante (como siempre). Lo que nunca marcó «ya pagué» (pendiente_pago) sí vence como siempre.
-- 2) reserva_recordar_comprobante(): a quien dijo que pagó y sigue sin depósito, Timba le escribe (plantilla de UTILIDAD
--    reserva_comprobante_pendiente) a los ~8 min y otra vez a los ~90 min: «tu clase está en espera de validación, envía el
--    comprobante a recepción (301 783 3550); si ya lo enviaste, respóndeme y lo verifico». Nace en 'esperando_plantilla':
--    el Worker lo enciende cuando Meta aprueba la plantilla. Sin cambios en dinero ni reservas.
-- 3) banco_correo_log + banco_correo_revisar(): cada 10 min deja una fila (último depósito recibido, depósitos de hoy,
--    cuántas reservas esperan, desde hace cuánto) y, si hay gente esperando y el banco lleva rato sin avisar, una nota a
--    Damián (máx. una por hora). Es el seguimiento de si está llegando el correo del banco.

-- ── 1) Sin soporte: solo después de que termine la clase ─────────────────────────────────────────────────────────
do $$
declare d text := pg_get_functiondef('public.liberar_cupos_expirados'::regproc); n text;
begin
  if d like '%0224%' then return; end if;
  n := replace(d, E'       and r.tipo = ''suelta''\n       and r.updated_at < now() - make_interval(mins => v_min)\n',
    E'       and r.tipo = ''suelta''\n       -- 0224: mientras la clase no termine se queda en «Por validar» (el banco falla; recepción lo valida)\n       and exists (select 1 from clases cl where cl.id = r.clase_id\n                    and cl.fecha_hora + make_interval(mins => coalesce(cl.duracion_min, 60)) < now())\n       and r.updated_at < now() - make_interval(mins => v_min)\n');
  if n = d then raise exception '0224: parche de liberar_cupos_expirados no aplicó'; end if;
  execute n;
end $$;

-- ── 2) Timba pide el comprobante ──────────────────────────────────────────────────────────────────────────────────
insert into ajustes (clave, valor, nota) values
  ('wa_recordar_comprobante', 'esperando_plantilla',
   'Aviso por WhatsApp a quien dijo que pagó una clase suelta y sigue sin depósito: pide el comprobante (8 min y 90 min). esperando_plantilla → el Worker lo enciende al aprobar Meta reserva_comprobante_pendiente. 0224.')
on conflict (clave) do nothing;

create or replace function public.wa_recordar_comprobante_activar(p_aprobada boolean default false)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v text;
begin
  if p_aprobada then
    update ajustes set valor = 'encendido' where clave = 'wa_recordar_comprobante' and valor = 'esperando_plantilla';
  end if;
  select valor into v from ajustes where clave = 'wa_recordar_comprobante';
  return jsonb_build_object('estado', coalesce(v, 'apagado'));
end $$;
revoke all on function public.wa_recordar_comprobante_activar(boolean) from public, anon, authenticated;
grant execute on function public.wa_recordar_comprobante_activar(boolean) to service_role;

create or replace function public.reserva_recordar_comprobante(p_ejecutar boolean default true)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare n int := 0; cand int := 0;
begin
  if coalesce((select valor from ajustes where clave = 'wa_recordar_comprobante'), 'apagado') <> 'encendido' then
    return jsonb_build_object('whatsapp', 'apagado', 'avisos', 0);
  end if;
  with c as (
    select r.id, r.clase_id, cl.fecha_hora,
           right(regexp_replace(coalesce(r.telefono, ''), '\D', '', 'g'), 10) tel,
           initcap(split_part(btrim(r.nombre), ' ', 1)) primer,
           case when r.updated_at <= now() - interval '90 minutes'
                  and cl.fecha_hora > now() + interval '15 minutes' then 2
                when r.updated_at <= now() - interval '8 minutes' then 1 end as paso
      from reservas r join clases cl on cl.id = r.clase_id
     where r.estado in ('verificando', 'pendiente_validacion') and r.tipo = 'suelta' and r.pago_id is null
       and r.updated_at >= now() - interval '6 hours'
       and cl.fecha_hora + make_interval(mins => coalesce(cl.duracion_min, 60)) > now()
  ), e as (
    select distinct on (c.tel) c.*
      from c
     where c.paso is not null and c.tel ~ '^3[0-9]{9}$'
       and not wa_es_dueno(c.tel)
       and not exists (select 1 from wa_bajas b where b.telefono = c.tel)
       and not exists (select 1 from wa_avisos a where a.clave = 'recordatorio_comprobante:' || c.id || ':' || c.paso)
       and not exists (select 1 from wa_avisos a where a.telefono = c.tel and a.tipo = 'recordatorio_comprobante'
                        and a.creado_at > now() - interval '60 minutes')
     order by c.tel, c.fecha_hora
  ), ins as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, datos, vence_at)
    select 'recordatorio_comprobante:' || e.id || ':' || e.paso, 'recordatorio_comprobante', e.tel, 'reserva_comprobante_pendiente',
           jsonb_build_array(coalesce(nullif(e.primer, ''), 'amigo(a)'),
             'el ' || wa_fecha_texto((e.fecha_hora at time zone 'America/Bogota')::date) || ' a las '
                   || wa_hora_texto((e.fecha_hora at time zone 'America/Bogota')::time)),
           jsonb_build_object('reserva_id', e.id, 'paso', e.paso),
           least(now() + interval '2 hours', e.fecha_hora)
      from e where p_ejecutar
    on conflict (clave) do nothing
    returning 1)
  select count(*) into n from ins;
  select count(*) into cand from c where paso is not null;
  return jsonb_build_object('whatsapp', 'encendido', 'candidatos', cand, 'avisos', n);
end $$;
revoke all on function public.reserva_recordar_comprobante(boolean) from public, anon, authenticated;
grant execute on function public.reserva_recordar_comprobante(boolean) to service_role;

do $cron$ begin perform cron.unschedule('tumbao-recordar-comprobante'); exception when others then null; end $cron$;
select cron.schedule('tumbao-recordar-comprobante', '*/2 11-23,0-2 * * *', 'select public.reserva_recordar_comprobante()');

create or replace function public.reserva_cancela_recordatorio_comprobante() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update wa_avisos set estado = 'omitido', motivo = 'ya_confirmada'
   where clave like 'recordatorio_comprobante:' || new.id || ':%' and estado = 'pendiente';
  return new;
exception when others then
  raise warning 'reserva_cancela_recordatorio_comprobante: %', sqlerrm; return new;
end $$;
create or replace trigger reserva_cancela_recordatorio_comprobante
  after update of estado on public.reservas
  for each row when (new.estado = 'confirmada' and old.estado is distinct from 'confirmada')
  execute function public.reserva_cancela_recordatorio_comprobante();

-- ── 3) Seguimiento del correo del banco ───────────────────────────────────────────────────────────────────────────
create table if not exists public.banco_correo_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  ultimo_deposito_at timestamptz,
  min_desde_ultimo int,
  depositos_hoy int not null default 0,
  cop_hoy int not null default 0,
  depositos_sin_asignar int not null default 0,
  esperando_n int not null default 0,
  espera_max_min int,
  alerta boolean not null default false
);
alter table public.banco_correo_log enable row level security;
create index if not exists banco_correo_log_at on public.banco_correo_log (at desc);

create or replace function public.banco_correo_revisar()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_ult timestamptz; v_min int; v_hoy int; v_cop int; v_libres int; v_esp int; v_max int; v_alerta boolean;
  v_dia date := (now() at time zone 'America/Bogota')::date; v_hora int := extract(hour from now() at time zone 'America/Bogota');
begin
  select max(created_at) into v_ult from pagos;
  v_min := floor(extract(epoch from now() - v_ult) / 60);
  select count(*), coalesce(sum(valor_cop), 0) into v_hoy, v_cop from pagos where (fecha_pago at time zone 'America/Bogota')::date = v_dia;
  select count(*) into v_libres from pagos_sin_asignar where (fecha_pago at time zone 'America/Bogota')::date = v_dia;
  select count(*), floor(max(extract(epoch from now() - r.updated_at)) / 60)::int into v_esp, v_max
    from reservas r join clases cl on cl.id = r.clase_id
   where r.estado in ('verificando', 'pendiente_validacion') and r.tipo = 'suelta' and r.pago_id is null
     and r.updated_at < now() - interval '10 minutes'
     and cl.fecha_hora + make_interval(mins => coalesce(cl.duracion_min, 60)) > now();
  v_alerta := v_esp > 0 and coalesce(v_min, 9999) >= 25 and v_hora between 6 and 21;
  insert into banco_correo_log (ultimo_deposito_at, min_desde_ultimo, depositos_hoy, cop_hoy, depositos_sin_asignar, esperando_n, espera_max_min, alerta)
  values (v_ult, v_min, v_hoy, v_cop, v_libres, v_esp, v_max, v_alerta);
  if v_alerta then
    perform nota_asistente('Correo del banco: ' || v_esp || ' reserva(s) esperan y no llega depósito',
      v_esp || ' persona(s) dijeron que pagaron y llevan hasta ' || v_max || ' min en «Por validar» sin depósito. El último correo del banco llegó hace '
      || v_min || ' min (' || to_char(v_ult at time zone 'America/Bogota', 'HH24:MI') || '). Hoy van ' || v_hoy || ' depósitos. '
      || 'Si el banco está fallando, recepción las valida con la referencia del comprobante; no se liberan hasta que termine la clase.',
      'banco-sin-correo:' || to_char(now() at time zone 'America/Bogota', 'YYYY-MM-DD-HH24'));
  end if;
  return jsonb_build_object('ultimo_deposito_hace_min', v_min, 'depositos_hoy', v_hoy, 'esperando', v_esp, 'alerta', v_alerta);
end $$;
revoke all on function public.banco_correo_revisar() from public, anon, authenticated;
grant execute on function public.banco_correo_revisar() to service_role;

do $cron$ begin perform cron.unschedule('tumbao-banco-correo'); exception when others then null; end $cron$;
select cron.schedule('tumbao-banco-correo', '*/10 11-23,0-2 * * *', 'select public.banco_correo_revisar()');

insert into ajustes (clave, valor, nota) values
  ('banco_correo_log', 'tabla banco_correo_log', 'Seguimiento cada 10 min del correo del banco: select * from banco_correo_log order by at desc limit 20. 0224.')
on conflict (clave) do nothing;
