-- 0150 · Precios oficiales y renovaciones en juego, calculados en la base (no por el modelo)
--
-- Damián (5-6 oct): «el modelo de IA del bot de reportes cambia el valor de la mensualidad; OpenAI no es bueno en
-- los cálculos». La causa: el informe recibía «valor típico de la mensualidad» = lo recaudado en el mes ÷ número de
-- mensualidades ($118.333, mezcla de planes completos y medias) y el modelo lo tomó por el precio y lo multiplicó por
-- 23 de cabeza ($2.722.000). Lo correcto: 21 planes completos × $125.000 = $2.625.000.
--
--   precios_oficiales()        mensualidad (ajustes.mensualidad_valor_cop), clase suelta y tiqueteras.
--   renovaciones_en_juego(d)   planes completos y medias que vencen en d días, y el valor en plata de los completos.
--
-- El Worker se los pasa al modelo como «datos fijos» y «cálculos hechos» (src/cifras.js), y revisa cada monto del
-- texto contra los datos. (Se aplicó con las instrucciones SQL de esta conversación; este archivo es el registro.)

create or replace function public.precios_oficiales()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'mensualidad_plan_completo_cop', coalesce(nullif((select valor from ajustes where clave = 'mensualidad_valor_cop'), '')::int, 125000),
    'clase_suelta_cop', coalesce((select precio_cop from clases where activa and fecha_hora >= now() order by fecha_hora limit 1), 15000),
    'tiquetera_paquetes', tiquetera_paquetes(),
    'nota', 'El precio de la mensualidad es el de plan_completo. «Media mensualidad» se cobra por un monto variable; el promedio de lo cobrado en el mes NO es el precio.')
$$;
revoke all on function public.precios_oficiales() from public, anon, authenticated;

create or replace function public.renovaciones_en_juego(p_dias int default 7)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with d as (select (now() at time zone 'America/Bogota')::date hoy),
  r as (select m.tipo, count(*) n from membresias m, d where m.fin between d.hoy and d.hoy + p_dias group by 1),
  p as (select (precios_oficiales() ->> 'mensualidad_plan_completo_cop')::int precio)
  select jsonb_build_object(
    'dias', p_dias,
    'planes_completos_n', coalesce((select n from r where tipo = 'plan'), 0),
    'medias_mensualidades_n', coalesce((select n from r where tipo = 'media'), 0),
    'otros_n', coalesce((select sum(n) from r where tipo not in ('plan', 'media')), 0),
    'personas_total', coalesce((select sum(n) from r), 0),
    'valor_planes_completos_cop', coalesce((select n from r where tipo = 'plan'), 0) * (select precio from p),
    'nota', 'valor_planes_completos_cop = planes completos x precio oficial; las medias mensualidades se cobran por un monto menor y variable y no se suman.')
$$;
revoke all on function public.renovaciones_en_juego(int) from public, anon, authenticated;
