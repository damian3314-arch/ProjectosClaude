-- 0130 · El cupo sin pago dura 15 minutos y se libera solo; un cambio de horario libera su puesto de origen
--
-- Damián (30 sep):
--  1) «Esa gente que nunca dijo que pagó nos está inflando las reservas: solo es
--     guardarle 15 min el cupo y luego liberarlo.»
--  2) «Los de plan mensualidad solo pueden reservar entre 3 y 4 cupos de cambio
--     de horario, para no tener problemas de aforo; y si se mueve, se libera el
--     puesto para la clase suelta del horario en el que está inscrito.»
--
-- 1 · POR QUÉ SE INFLABA
--   · El cupo sin pago duraba 30 minutos (default de reservas.expira_en).
--   · Y nada lo soltaba a tiempo: los cron de Cloudflare no corren en esta
--     cuenta, así que solo se liberaba cuando alguien más miraba esa clase. Las
--     reservas expiradas esperaban ~94 minutos en promedio.
--   · Y la protección «si hay una plata sin consumir cerca, no se vence»
--     miraba CUALQUIER pago cercano (p. ej. una transferencia de mensualidad),
--     sin comparar monto ni nombre: bastaba una para que varias quedaran vivas.
--   Ahora: 15 minutos (ajustes.minutos_cupo_sin_pago), un pg_cron por minuto que
--   suelta lo vencido, y la protección solo vale si hay un pago sin consumir que
--   alcance para esa clase y cuyo remitente se parezca a quien reservó (o no
--   traiga nombre).
--   «Ya pagué» no cambia: esa reserva pasa a 'verificando' y no expira sola.
--
-- 2 · EL CAMBIO DE HORARIO
--   El tope por clase de destino ya existe (0095, cambios_tope_por_clase = 4;
--   Damián dijo entre 3 y 4). Lo nuevo: cuando un afiliado reserva un cambio, el
--   puesto que deja en SU clase de ese día (la de su mensualidad) queda libre
--   para clase suelta: cupo_total de la clase de origen sube 1 mientras el cambio
--   esté confirmado, y vuelve a bajar si se cancela, se rechaza o expira.
--   recalcular_cupos() lo respeta (si no, la noche siguiente lo borraría).

-- ── 1 · cupo sin pago ─────────────────────────────────────────────────
insert into ajustes (clave, valor, nota) values
  ('minutos_cupo_sin_pago', '15',
   'Cuántos minutos se le guarda el cupo a quien reservó y todavía no avisó que pagó. Pasado ese tiempo se libera. 0130.')
on conflict (clave) do nothing;

create or replace function public.minutos_cupo_sin_pago()
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(nullif((select valor from ajustes where clave = 'minutos_cupo_sin_pago'), '')::int, 15)
$$;

alter table reservas alter column expira_en
  set default (now() + make_interval(mins => public.minutos_cupo_sin_pago()));

-- Suelta lo vencido de UNA clase. Se conserva la regla de no perder una reserva
-- con plata real, pero afinada: el pago sin consumir tiene que alcanzar para la
-- clase y parecerse a quien reservó.
create or replace function public.liberar_cupos_de_clase(p_clase_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_n int;
begin
  with liberadas as (
    update reservas r set estado = 'expirada', updated_at = now()
     where r.clase_id = p_clase_id
       and r.estado = 'pendiente_pago'
       and r.expira_en < now()
       and not exists (
         select 1 from pagos p
          where not p.consumido
            and p.valor_cop - coalesce(p.usado_cop, 0) >=
                coalesce((select c.precio_cop from clases c where c.id = r.clase_id), 0)
            and p.fecha_pago between r.created_at - interval '2 hours' and r.created_at + interval '3 hours'
            and (coalesce(btrim(p.remitente), '') = ''
                 or exists (
                   select 1
                     from unnest(string_to_array(norm_nombre(p.remitente), ' ')) a
                     join unnest(string_to_array(norm_nombre(r.nombre), ' ')) b on a = b
                    where length(a) >= 3))
       )
    returning 1
  )
  select count(*)::int into v_n from liberadas;

  if v_n > 0 then
    update clases set cupo_tomado = greatest(0, cupo_tomado - v_n) where id = p_clase_id;
  end if;
  return v_n;
end;
$$;

-- Lo que corre cada minuto: todas las clases con algo vencido.
create or replace function public.liberar_cupos_vencidos()
returns integer
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_total int := 0; r record;
begin
  for r in select distinct clase_id from reservas where estado = 'pendiente_pago' and expira_en < now() loop
    v_total := v_total + liberar_cupos_de_clase(r.clase_id);
  end loop;
  return v_total;
end;
$$;
revoke all on function public.liberar_cupos_vencidos(), public.liberar_cupos_de_clase(uuid)
  from public, anon, authenticated;

do $cron$
begin
  perform cron.unschedule('tumbao-liberar-cupos');
exception when others then null;
end
$cron$;
select cron.schedule('tumbao-liberar-cupos', '* * * * *', 'select public.liberar_cupos_vencidos()');

-- ── 2 · el cambio libera su puesto de origen ─────────────────────────
alter table reservas add column if not exists clase_origen_id uuid references clases (id);
alter table reservas add column if not exists origen_liberado boolean not null default false;

-- Al nacer un cambio, se anota de qué clase sale: la del día con la hora de su plan.
create or replace function public.reservas_cambio_anota_origen()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_dia date; v_tel text; v_hora time;
begin
  if new.tipo::text <> 'cambio' or new.clase_origen_id is not null then return new; end if;
  select (c.fecha_hora at time zone 'America/Bogota')::date into v_dia from clases c where c.id = new.clase_id;
  v_tel := right(regexp_replace(coalesce(new.telefono, ''), '\D', '', 'g'), 10);
  select m.hora into v_hora
    from membresias m
   where v_dia between m.inicio and m.fin
     and right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10) = v_tel
   order by m.fin desc limit 1;
  if v_hora is not null then
    select c.id into new.clase_origen_id
      from clases c
     where (c.fecha_hora at time zone 'America/Bogota')::date = v_dia
       and (c.fecha_hora at time zone 'America/Bogota')::time = v_hora
       and c.id <> new.clase_id
     limit 1;
  end if;
  return new;
end;
$$;

-- Mientras el cambio esté confirmado, el puesto de origen se ofrece a sueltas.
create or replace function public.reservas_cambio_libera_origen()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.tipo::text <> 'cambio' or new.clase_origen_id is null then return new; end if;
  if new.estado = 'confirmada' and not new.origen_liberado then
    update clases set cupo_total = cupo_total + 1
     where id = new.clase_origen_id and fecha_hora > now() - interval '1 day';
    update reservas set origen_liberado = true where id = new.id;
  elsif new.estado <> 'confirmada' and new.origen_liberado then
    update clases set cupo_total = greatest(cupo_total - 1, cupo_tomado) where id = new.clase_origen_id;
    update reservas set origen_liberado = false where id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists reservas_cambio_anota_origen on reservas;
create trigger reservas_cambio_anota_origen
  before insert on reservas
  for each row execute function public.reservas_cambio_anota_origen();

drop trigger if exists reservas_cambio_libera_origen on reservas;
create trigger reservas_cambio_libera_origen
  after insert or update of estado on reservas
  for each row execute function public.reservas_cambio_libera_origen();

revoke all on function public.reservas_cambio_anota_origen(), public.reservas_cambio_libera_origen()
  from public, anon, authenticated;

-- El recálculo nocturno no puede borrar lo liberado por cambios confirmados.
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.recalcular_cupos()'::regprocedure) into v_src;
  if position('liberados' in v_src) > 0 then return; end if;
  v_new := replace(v_src,
    '           c.cupo_manual,
',
    '           c.cupo_manual,
           (select count(*) from reservas r
             where r.clase_origen_id = c.id and r.origen_liberado)::int as liberados,
');
  if v_new = v_src then raise exception '0130: no encontré cupo_manual en recalcular_cupos'; end if;
  v_src := v_new;
  v_new := replace(v_src,
    'greatest(k.aforo - k.activos, 0))
           ) as meta',
    'greatest(k.aforo - k.activos, 0))
           ) + k.liberados as meta');
  if v_new = v_src then raise exception '0130: no encontré la meta en recalcular_cupos'; end if;
  execute v_new;
end
$mig$;
