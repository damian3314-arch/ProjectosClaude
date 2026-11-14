-- 0207 · La promo «2 por $24.000» (Día de invitados) se ve en el cierre y en /admin, y el cierre cuenta lo que SÍ se cobró.
-- Antes: caja_del_dia / ventas_entre sumaban clases.precio_cop por persona ($15.000 × 2 = $30.000) aunque el grupo pagó $24.000,
--        así que el cierre del 13 nov sobraba $6.000 por cada pareja con la promo.
-- Ahora: valor_reserva(id) = lo que de verdad vale esa reserva (precio_del_grupo ÷ personas del grupo; sin promo = precio de la clase).
--        promo_del_dia(dia) lista los grupos con la promo (quién, a qué hora, pagó o no, repetidos) y caja_del_dia lo devuelve en 'promo'.
-- No toca datos: solo funciones. Sin DROP/DELETE.

create or replace function public.valor_reserva(p_id uuid)
returns integer language sql stable security definer set search_path to 'public','pg_temp' as $$
  select coalesce(
    (select (precio_del_grupo(r.id) /
             greatest(1, (select count(*) from reservas x
                           where coalesce(x.grupo_id, x.id) = coalesce(r.grupo_id, r.id)
                             and x.estado not in ('rechazada','expirada'))))::int
       from reservas r where r.id = p_id),
    (select c.precio_cop from reservas r join clases c on c.id = r.clase_id where r.id = p_id), 0)
$$;

create or replace function public.promo_del_dia(p_dia date)
returns jsonb language sql stable security definer set search_path to 'public','pg_temp' as $$
  with g as (
    select coalesce(r.grupo_id, r.id) gid,
           count(*) n,
           min(c.fecha_hora) fecha_hora,
           max(c.precio_cop) unit,
           string_agg(r.nombre, ' + ' order by r.nombre) nombres,
           min(r.telefono) telefono,
           bool_and(r.estado = 'confirmada') confirmada,
           bool_or(r.pago_id is not null) pagada,
           min(r.estado::text) estado,
           min(r.created_at) creada,
           (array_agg(r.pago_id) filter (where r.pago_id is not null))[1] pago_id,
           count(*) filter (where r.no_vino_at is not null) no_vinieron
      from reservas r join clases c on c.id = r.clase_id
     where r.tipo = 'suelta' and r.estado not in ('rechazada','expirada')
       and (c.fecha_hora at time zone 'America/Bogota')::date = p_dia
     group by 1),
  p as (
    select g.*, promo_total_cupos(g.n::int, g.unit, g.fecha_hora) total
      from g)
  select jsonb_build_object(
    'dia', p_dia,
    'grupos_pagados',   coalesce(count(*) filter (where total < unit * n and pagada), 0),
    'personas_pagadas', coalesce(sum(n) filter (where total < unit * n and pagada), 0),
    'cop_pagado',       coalesce(sum(total) filter (where total < unit * n and pagada), 0),
    'grupos_sin_pagar', coalesce(count(*) filter (where total < unit * n and not pagada), 0),
    'descuento_cop',    coalesce(sum(unit * n - total) filter (where total < unit * n and pagada), 0),
    'lista', coalesce(jsonb_agg(jsonb_build_object(
        'hora', to_char(fecha_hora at time zone 'America/Bogota','HH24:MI'),
        'personas', n, 'quienes', nombres, 'telefono', telefono,
        'cop', total, 'pagada', pagada, 'estado', estado,
        'no_vinieron', no_vinieron,
        'remitente', (select pg.remitente from pagos pg where pg.id = p.pago_id),
        'cuando', to_char(creada at time zone 'America/Bogota','HH24:MI'),
        -- Misma gente en dos compras de la promo el mismo día: se marca para revisar (¿pagó dos veces?).
        'repetida', exists (select 1 from p q where q.gid <> p.gid and q.total < q.unit * q.n
                             and q.nombres = p.nombres))
      order by fecha_hora, creada) filter (where total < unit * n), '[]'::jsonb))
  from p
$$;

create or replace function public.admin_promo_dia(p_token text, p_dia date default null)
returns jsonb language plpgsql stable security definer set search_path to 'public','extensions','pg_temp' as $$
begin
  if verificar_token_admin(p_token) is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  return jsonb_build_object('ok', true) || promo_del_dia(coalesce(p_dia, (now() at time zone 'America/Bogota')::date));
end $$;

revoke all on function public.valor_reserva(uuid), public.promo_del_dia(date) from public, anon, authenticated;
revoke all on function public.admin_promo_dia(text, date) from public, anon;
grant execute on function public.admin_promo_dia(text, date) to anon, authenticated, service_role;
grant execute on function public.valor_reserva(uuid), public.promo_del_dia(date) to service_role;

-- caja_del_dia y ventas_entre: cada reserva vale lo que se cobró, y el cierre trae la sección 'promo'.
do $$
declare d text; n int := 0;
begin
  d := pg_get_functiondef('public.caja_del_dia(text,date)'::regprocedure);
  d := replace(d, 'sum(c.precio_cop)',  'sum(valor_reserva(r.id))');
  d := replace(d, 'sum(c2.precio_cop)', 'sum(valor_reserva(r2.id))');
  d := replace(d, 'else c3.precio_cop end', 'else valor_reserva(r3.id) end');
  d := replace(d, 'sum(c4.precio_cop)', 'sum(valor_reserva(r4.id))');
  d := replace(d, 'select r.id, r.nombre, r.pago_id, c.precio_cop', 'select r.id, r.nombre, r.pago_id, valor_reserva(r.id) as precio_cop');
  d := replace(d, E'    ''ok'', true,\n    ''dia'', v_dia,', E'    ''ok'', true,\n    ''promo'', promo_del_dia(v_dia),\n    ''dia'', v_dia,');
  if d !~ 'promo_del_dia' or d ~ 'sum\(c\.precio_cop\)' then raise exception 'parche de caja_del_dia no aplicó'; end if;
  execute d;

  d := pg_get_functiondef('public.ventas_entre(date,date)'::regprocedure);
  d := replace(d, 'select coalesce(sum(c.precio_cop), 0) as cop', 'select coalesce(sum(valor_reserva(r.id)), 0) as cop');
  if d ~ 'sum\(c\.precio_cop\)' then raise exception 'parche de ventas_entre no aplicó'; end if;
  execute d;
end $$;

-- /admin · lista de reservas de una clase: marca la tarifa de cada una.
create or replace function public.admin_reservas_de_clase(p_token text, p_clase_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public','extensions','pg_temp' as $$
declare v_admin uuid; v_out jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO'); end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', r.codigo, 'nombre', r.nombre, 'telefono', r.telefono,
           'tipo', r.tipo, 'estado', r.estado, 'creada_at', r.created_at,
           'valor_cop', valor_reserva(r.id),
           'tarifa', case when r.tipo = 'suelta' and valor_reserva(r.id) < c.precio_cop then 'promo' else 'normal' end,
           'pagada', r.pago_id is not null)
         order by r.created_at), '[]'::jsonb)
    into v_out
    from reservas r join clases c on c.id = r.clase_id
   where r.clase_id = p_clase_id and r.estado not in ('expirada','rechazada');
  return jsonb_build_object('ok', true, 'reservas', v_out);
end $$;
