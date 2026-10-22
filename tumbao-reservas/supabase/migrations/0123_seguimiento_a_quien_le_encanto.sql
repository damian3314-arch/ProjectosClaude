-- 0123 · Seguimiento a quien contestó «Me encantó»
--
-- Damián (29 sep): quienes contestan «Me encantó» en «¿cómo te fue?» son las
-- mejores candidatas a comprar una tiquetera; dejar programado escribirles de
-- nuevo. Y por ahora NADA de decir que hay un pase gratis por completar las
-- 4 clases: eso es interno, para medir qué efecto tiene en la gente.
--
-- Qué hace `opinion_seguimiento()` (todos los días a las 10:15 am, lun-sáb):
--   Escribe UNA vez a cada persona que contestó con elogio, cuando pasaron
--   de 4 a 10 días desde su respuesta (la segunda visita llega a los 7 días
--   de mediana, a los 14 el 80%), y que TODAVÍA:
--     · no reservó ninguna clase después de contestar,
--     · no compró una tiquetera desde que la invitamos,
--     · no tiene una mensualidad vigente.
--   El mensaje (plantilla 'seguimiento_encanto') invita a reservar la segunda
--   clase y dice el precio real de la tiquetera de 4 clases, que sale de
--   tiquetera_paquetes(). No dice nada del pase de regalo.
--
-- Cuidados: ni domingos ni festivos (Ley 2300); sin la dueña ni quienes
-- pidieron SALIR; una sola vez por persona (clave 'seguimiento_opinion:<id>').
-- Nace APAGADO (ajustes.wa_opinion_seguimiento) hasta que Meta apruebe la
-- plantilla. Si se aprueba tarde, alcanza a quien siga dentro de la ventana.

insert into ajustes (clave, valor, nota)
values ('wa_opinion_seguimiento', 'apagado',
        'Seguimiento a quien contestó «Me encantó»: día 4 a 10, si no volvió ni compró. Se enciende cuando Meta apruebe seguimiento_encanto (0123).')
on conflict (clave) do nothing;

create or replace function public.opinion_seguimiento()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  -- `tumbao.dia` solo lo usan las pruebas para simular otro día.
  hoy date := coalesce(nullif(current_setting('tumbao.dia', true), '')::date,
                       (now() at time zone 'America/Bogota')::date);
  n int := 0;
  v_clases text;
  v_precio text;
begin
  if coalesce((select valor from ajustes where clave = 'wa_opinion_seguimiento'), 'apagado')
     <> 'encendido' then
    return 0;
  end if;
  -- Ley 2300: nada de mensajes de mercadeo domingos ni festivos.
  if extract(isodow from hoy) = 7 or exists (select 1 from festivos where fecha = hoy) then
    return 0;
  end if;

  -- El paquete chico de tiquetera, con su precio de verdad.
  select (p->>'clases'), '$' || replace(to_char((p->>'precio_cop')::numeric, 'FM999,999,999'), ',', '.')
    into v_clases, v_precio
    from jsonb_array_elements(coalesce(tiquetera_paquetes(), '[]'::jsonb)) p
   where coalesce((p->>'clases')::int, 0) > 0 and coalesce((p->>'precio_cop')::int, 0) > 0
   order by (p->>'clases')::int
   limit 1;
  if v_clases is null then return 0; end if;

  with elegidos as (
    select o.id, o.telefono, o.nombre
      from wa_opiniones o
     where o.estado = 'cerrada'
       and o.tipo = 'elogio'
       and coalesce(o.urgente, false) = false
       and o.cerrada_at is not null
       and (hoy - (o.cerrada_at at time zone 'America/Bogota')::date) between 4 and 10
       and o.telefono ~ '^3[0-9]{9}$'
       and not wa_es_dueno(o.telefono)
       and not exists (select 1 from wa_bajas b where b.telefono = o.telefono)
       -- No reservó nada después de contestar.
       and not exists (select 1 from reservas r
                        where right(regexp_replace(coalesce(r.telefono, ''), '\D', '', 'g'), 10) = o.telefono
                          and r.estado = 'confirmada' and r.created_at > o.cerrada_at)
       -- No compró tiquetera desde que la invitamos.
       and not exists (select 1 from tiqueteras t
                        where right(regexp_replace(coalesce(t.telefono, ''), '\D', '', 'g'), 10) = o.telefono
                          and t.premio_de is null and t.estado <> 'descartada'
                          and t.creada_en > o.invitada_at)
       -- Ni tiene ya una mensualidad.
       and not exists (select 1 from membresias m
                        where right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10) = o.telefono
                          and m.fin >= hoy))
  insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
  select 'seguimiento_opinion:' || e.id, 'seguimiento_opinion', e.telefono, 'seguimiento_encanto',
         jsonb_build_array(coalesce(nullif(initcap(split_part(btrim(coalesce(e.nombre, '')), ' ', 1)), ''), 'hola'),
                           v_clases, v_precio),
         now() + interval '10 hours'
    from elegidos e
  on conflict (clave) do nothing;
  get diagnostics n = row_count;
  return n;
exception when others then
  raise warning 'opinion_seguimiento: %', sqlerrm;
  return n;
end;
$$;
revoke all on function public.opinion_seguimiento() from public, anon, authenticated;

-- 10:15 am de Bogotá = 15:15 UTC, lunes a sábado (después de las invitaciones
-- de las 10:00 y antes del pase de las 10:30).
do $cron$
begin
  perform cron.unschedule('tumbao-opinion-seguimiento');
exception when others then null;
end
$cron$;
select cron.schedule('tumbao-opinion-seguimiento', '15 15 * * 1-6',
                     'select public.opinion_seguimiento()');
