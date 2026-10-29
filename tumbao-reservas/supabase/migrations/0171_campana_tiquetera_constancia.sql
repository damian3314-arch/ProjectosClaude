-- 0171 · La campaña de la tiquetera por constancia (plantilla tiquetera_constancia)
--
-- Damián (11 oct): escogió el texto «los objetivos no se cumplen con ganas, se cumplen con constancia… siempre llegan cosas
-- buenas» (lenguaje neutro) y pidió: «envíala apenas esté aprobada, solo por esta vez; el resto en los horarios permitidos».
--
-- Cómo queda:
--   · campana_tiquetera_constancia(p_ejecutar) escoge a los clientes frecuentes de suelta (2 o más clases confirmadas en los
--     últimos 30 días) sin mensualidad vigente, sin tiquetera vigente, sin baja, que no sean dueños, con menos de 2 campañas en
--     14 días y que NUNCA hayan recibido una plantilla de tiquetera (tiquetera_semana, tiquetera_frecuentes ni esta). A cada
--     uno, UNA sola vez en la vida (clave 'tiqconst:<celular>').
--   · Con p_ejecutar = false solo cuenta (no encola nada).
--   · El aviso es tipo 'campana': la cola (wa_tomar_avisos) solo lo manda en horario de mercadeo (wa_horario_mercadeo: lun-vie
--     9:00-19:00, sáb 9:00-13:00, nunca domingos ni festivos). Vence a los 4 días para sobrevivir un puente festivo.
--   · Quién la llama: el Worker (/wa/campana-tiquetera), y SOLO si Meta ya aprobó la plantilla. Un cron cada hora llama esa ruta:
--     la primera vez que la encuentre aprobada encola a todos los pendientes («apenas esté aprobada»); después, cada hora, solo
--     entra quien se vuelve frecuente (el resto, en los horarios permitidos).
-- Nada destructivo: una función nueva, un ajuste y un cron.

create or replace function public.campana_tiquetera_constancia(p_ejecutar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  hoy date := (now() at time zone 'America/Bogota')::date;
  v_total int := 0; v_n int := 0;
begin
  with vig as (
    select distinct right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) tel
      from membresias
     where fin + coalesce(nullif((select valor from ajustes where clave = 'mensualidad_gracia_dias'), '')::int, 3) >= hoy),
  r as (
    select right(regexp_replace(x.telefono, '\D', '', 'g'), 10) tel,
           (array_agg(initcap(split_part(trim(x.nombre), ' ', 1)) order by x.created_at desc))[1] nombre,
           count(*) filter (where x.tipo = 'suelta' and c.fecha_hora >= now() - interval '30 days' and c.fecha_hora < now()) veces
      from reservas x join clases c on c.id = x.clase_id
     where x.estado = 'confirmada' group by 1),
  cand as (
    select r.tel, r.nombre, r.veces::int veces from r
     where r.veces >= 2 and r.tel ~ '^3[0-9]{9}$'
       and r.tel not in (select tel from vig)
       and not wa_es_dueno(r.tel)
       and not exists (select 1 from wa_bajas b where b.telefono = r.tel)
       and not exists (select 1 from wa_avisos a where a.telefono = r.tel
                         and a.plantilla in ('tiquetera_semana', 'tiquetera_frecuentes', 'tiquetera_constancia')
                         and a.estado in ('enviando', 'enviado', 'pendiente'))
       and not exists (select 1 from wa_avisos a where a.clave = 'tiqconst:' || r.tel)
       and (select count(*) from wa_avisos a where a.telefono = r.tel and a.tipo = 'campana'
              and a.estado in ('enviando', 'enviado', 'pendiente') and a.creado_at > now() - interval '14 days') < 2
       and not exists (select 1 from tiqueteras t where right(regexp_replace(t.telefono, '\D', '', 'g'), 10) = r.tel
                         and t.pagado_en is not null and t.vence_el >= hoy)),
  ins as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'tiqconst:' || c.tel, 'campana', c.tel, 'tiquetera_constancia',
           jsonb_build_array(coalesce(nullif(c.nombre, ''), 'amigo(a)'), c.veces::text),
           now() + interval '4 days'
      from cand c
     where p_ejecutar
    on conflict (clave) do nothing
    returning 1)
  select (select count(*) from cand), (select count(*) from ins) into v_total, v_n;

  return jsonb_build_object('candidatos', v_total, 'encolados', v_n, 'ejecutado', p_ejecutar);
end;
$$;
revoke all on function public.campana_tiquetera_constancia(boolean) from public, anon, authenticated;
grant execute on function public.campana_tiquetera_constancia(boolean) to service_role;

insert into ajustes (clave, valor, nota) values
  ('wa_campana_tiquetera_url', 'https://tumbao-caja.damian3314.workers.dev/wa/campana-tiquetera',
   'Ruta del Worker que encola la campaña tiquetera_constancia si Meta ya la aprobó (la llama el cron cada hora). 0171.')
on conflict (clave) do update set valor = excluded.valor;

select cron.schedule('tumbao-tiquetera-constancia', '5 * * * *',
  $c$select net.http_post(url := (select valor from ajustes where clave = 'wa_campana_tiquetera_url'), body := '{}'::jsonb, headers := '{"Content-Type": "application/json"}'::jsonb, timeout_milliseconds := 60000)$c$);
