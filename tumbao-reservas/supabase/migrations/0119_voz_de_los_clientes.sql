-- 0119 · Lo que los clientes le escriben al WhatsApp de Tumbao, para el
--        debrief del lunes.
--
-- Damián, 29 sep: «El reporte de Tumbao Opina debería enviarse con el
-- reporte de la mañana de los lunes, algo corto que no genere tanto ruido,
-- y poder ver lo que nos comparten los usuarios en WhatsApp.»
--
-- Solo lectura. Por persona: nombre de pila (de su reserva o mensualidad),
-- a qué le estaba respondiendo (el último aviso que le mandamos antes) y
-- sus mensajes de la semana, recortados. Sin celulares completos: el
-- informe sale por WhatsApp.

create or replace function public.mensajes_clientes_semana()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with m as (
    select right(regexp_replace(telefono, '\D', '', 'g'), 10) tel, texto, creado_at
      from wa_mensajes
     where direccion = 'entrante'
       and creado_at > now() - interval '7 days'
       and not wa_es_dueno(telefono)
       and coalesce(btrim(texto), '') <> ''),
  p as (
    select tel,
           count(*) mensajes,
           string_agg(left(texto, 160), ' / ' order by creado_at) textos,
           min(creado_at) primero
      from m group by tel)
  select coalesce(jsonb_agg(jsonb_build_object(
           'nombre', coalesce(
              (select initcap(split_part(btrim(x.nombre), ' ', 1)) from reservas x
                where right(regexp_replace(x.telefono, '\D', '', 'g'), 10) = p.tel
                order by x.created_at desc limit 1),
              (select initcap(split_part(btrim(mm.afiliado), ' ', 1)) from membresias mm
                where right(regexp_replace(coalesce(mm.celular, ''), '\D', '', 'g'), 10) = p.tel
                order by mm.fin desc limit 1)),
           'tel_final', right(p.tel, 4),
           'respondia_a', (select a.plantilla from wa_avisos a
                            where a.telefono = p.tel and a.estado = 'enviado'
                              and a.enviado_at < p.primero
                            order by a.enviado_at desc limit 1),
           'mensajes', p.mensajes,
           'texto', left(p.textos, 400))
         order by p.primero), '[]'::jsonb)
    from p;
$$;
revoke all on function public.mensajes_clientes_semana() from public, anon, authenticated;
