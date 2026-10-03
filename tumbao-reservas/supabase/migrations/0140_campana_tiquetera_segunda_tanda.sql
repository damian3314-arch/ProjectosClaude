-- 0140 · Segunda tanda de la campaña de tiquetera (lista, SIN programar ni enviar)
--
-- La primera tanda (28 sep, plantilla 'tiquetera_semana') fue a 40 clientes con 3 o más
-- clases sueltas en 30 días: 15 reservaron después (38 %) y 2 compraron tiquetera (5 %).
-- Ojo con la lectura: de los 6 clientes parecidos a quienes NO se les mandó nada, los 6
-- también reservaron en esos días; los frecuentes reservan igual. Lo medible es la compra.
--
-- Esta función arma la segunda tanda para quienes tienen 2 o más sueltas en 30 días y
-- todavía no recibieron la oferta (43 personas el 2 oct). Reglas que no se saltan:
--   · sin mensualidad vigente (ni en gracia), ni tiquetera pagada y vigente;
--   · nunca a quien ya recibió tiquetera_semana / tiquetera_frecuentes;
--   · nunca a quien pidió SALIR ni a los dueños;
--   · como mucho 2 mensajes de campaña cada 14 días por persona;
--   · el aviso vence a las 3 horas de encolado (no sale tarde).
-- p_ejecutar = false solo cuenta; true encola (clave única 'tiquetera2:<celular>': no repite).
-- La función NO se agenda sola: enviar a clientes reales lo decide Damián.

create or replace function public.campana_tiquetera_frecuentes2(p_ejecutar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  hoy date := (now() at time zone 'America/Bogota')::date;
  v_total int := 0; v_n int := 0;
begin
  with vig as (select distinct right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) tel from membresias where fin + 3 >= hoy),
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
       and not exists (select 1 from wa_avisos a where a.telefono = r.tel and a.plantilla in ('tiquetera_semana', 'tiquetera_frecuentes')
                         and a.estado in ('enviando', 'enviado', 'pendiente'))
       and (select count(*) from wa_avisos a where a.telefono = r.tel and a.tipo = 'campana'
              and a.estado in ('enviando', 'enviado', 'pendiente') and a.creado_at > now() - interval '14 days') < 2
       and not exists (select 1 from tiqueteras t where right(regexp_replace(t.telefono, '\D', '', 'g'), 10) = r.tel
                         and t.pagado_en is not null and t.vence_el >= hoy)),
  ins as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'tiquetera2:' || c.tel, 'campana', c.tel, 'tiquetera_semana',
           jsonb_build_array(coalesce(nullif(c.nombre, ''), 'amigo(a)'), c.veces::text),
           now() + interval '3 hours'
      from cand c
     where p_ejecutar
    on conflict (clave) do nothing
    returning 1)
  select (select count(*) from cand), (select count(*) from ins) into v_total, v_n;

  return jsonb_build_object('candidatos', v_total, 'encolados', v_n, 'ejecutado', p_ejecutar);
end;
$$;
revoke all on function public.campana_tiquetera_frecuentes2(boolean) from public, anon, authenticated;
