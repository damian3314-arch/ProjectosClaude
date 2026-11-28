-- 0215 · Promoción de fin de año: 45 días de vigencia (24 nov – 31 dic 2026) y días de cierre
--
-- La idea es de la dueña y la comunicó Damián el 24 de noviembre:
--  · Compras del 24 de noviembre al 31 de diciembre de 2026 (inclusive, hora de Bogotá).
--  · Mensualidades y tiqueteras: 45 días calendario desde la fecha de compra (con el mismo precio).
--  · No hay clases: 8, 25, 26 y 31 de diciembre; receso del 1 al 5 de enero; regresan el miércoles 6 de enero.
--
-- Aquí queda lo que depende de este sistema:
--  1. tiquetera_paquetes() devuelve 45 días mientras dure la promo (la página, la compra en línea y los precios oficiales leen de ahí).
--     Fuera de las fechas vuelve sola a lo que diga ajustes.tiquetera_paquetes (30 días).
--  2. Los días de cierre entran en la tabla de festivos: así abrir_semana() no abre clases esos días.
--  3. La Rumba básica del 31 de diciembre (sin reservas) se desactiva.
-- La vigencia de la MENSUALIDAD no vive aquí: viene de AdminGym (importar_membresias); recepción debe activarla con 45 días.
-- No borra nada.

insert into ajustes (clave, valor)
values ('promo_vigencia_fin_anio', '{"desde":"2026-11-24","hasta":"2026-12-31","vigencia_dias":45}')
on conflict (clave) do nothing;

create or replace function public.tiquetera_paquetes()
returns jsonb language sql stable set search_path to 'public', 'extensions', 'pg_temp' as $$
  with base as (
    select coalesce((select valor::jsonb from ajustes where clave = 'tiquetera_paquetes'), '[]'::jsonb) as v
  ), promo as (
    select (a.valor::jsonb->>'vigencia_dias')::int as dias,
           (now() at time zone 'America/Bogota')::date
             between (a.valor::jsonb->>'desde')::date and (a.valor::jsonb->>'hasta')::date as activa
      from ajustes a where a.clave = 'promo_vigencia_fin_anio'
  )
  select coalesce(
    (select jsonb_agg(
              case when coalesce((select p.activa from promo p), false)
                   then jsonb_set(e.paq, '{vigencia_dias}',
                                  to_jsonb(greatest((e.paq->>'vigencia_dias')::int, (select p.dias from promo p))))
                   else e.paq end
              order by e.ord)
       from base b, jsonb_array_elements(b.v) with ordinality as e(paq, ord)),
    '[]'::jsonb)
$$;

insert into festivos (fecha, nombre, origen) values
  ('2026-12-26', 'Cierre de fin de año', 'manual'),
  ('2026-12-31', 'Cierre de fin de año', 'manual'),
  ('2027-01-02', 'Receso de inicio de año', 'manual'),
  ('2027-01-03', 'Receso de inicio de año', 'manual'),
  ('2027-01-04', 'Receso de inicio de año', 'manual'),
  ('2027-01-05', 'Receso de inicio de año', 'manual')
on conflict (fecha) do nothing;

update clases set activa = false
 where (fecha_hora at time zone 'America/Bogota')::date = '2026-12-31'
   and activa
   and not exists (select 1 from reservas r
                    where r.clase_id = clases.id
                      and r.estado in ('confirmada', 'pendiente_pago', 'verificando', 'pendiente_validacion'));
