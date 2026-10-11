-- 0142 · ventas_ronda(p_ejecutar, p_ahora): la hora se puede simular en las pruebas
--
-- Igual que 0141, pero la ronda recibe «qué hora es» (por defecto now()). Así se prueba la
-- ventana (lun–vie 10–13, sábado hasta la 1 pm, nunca domingo ni festivo) y el tope diario sin
-- esperar al lunes. La conversación se abre con esa misma hora (abierta_at = p_ahora).
--
-- Sin DROP a propósito (borrar una función necesita autorización de Damián): la versión de
-- un solo argumento queda como envoltorio de la nueva, y el cron llama a la nueva con la hora
-- explícita para que no haya ambigüedad entre las dos.

create or replace function public.ventas_ronda(p_ejecutar boolean, p_ahora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  ahora timestamp := p_ahora at time zone 'America/Bogota';
  hoy date := ahora::date;
  v_dow int := extract(isodow from ahora)::int;
  v_ini time := ventas_ajuste('ventas_hora_ini', '10:00')::time;
  v_fin time := ventas_ajuste('ventas_hora_fin', '13:00')::time;
  v_por int := ventas_ajuste('ventas_por_ronda', '3')::int;
  v_tope int := ventas_ajuste('ventas_tope_dia', '45')::int;
  v_hoy int; v_n int := 0; v_prev jsonb;
begin
  if not p_ejecutar then
    select coalesce(jsonb_agg(jsonb_build_object('tel', right(c.tel, 4), 'nombre', c.nombre, 'objetivo', c.objetivo,
                                                  'visitas_30d', c.visitas_30d, 'hora_habitual', c.hora_habitual)), '[]'::jsonb)
      into v_prev from ventas_candidatos(50) c;
    return jsonb_build_object('ejecutado', false, 'candidatos', v_prev, 'cupos', ventas_cupos());
  end if;

  if ventas_ajuste('wa_ventas', 'apagado') <> 'encendido' then
    return jsonb_build_object('ok', true, 'activo', false);
  end if;
  -- Ley 2300: sin mercadeo domingos ni festivos; sábados hasta la 1 pm.
  if v_dow = 7 or exists (select 1 from festivos where fecha = hoy) then
    return jsonb_build_object('ok', true, 'activo', true, 'motivo', 'dia_sin_envio');
  end if;
  if v_dow = 6 then v_fin := least(v_fin, time '13:00'); end if;
  if ahora::time < v_ini or ahora::time >= v_fin then
    return jsonb_build_object('ok', true, 'activo', true, 'motivo', 'fuera_de_ventana');
  end if;

  select count(*) into v_hoy from ventas_chats where (abierta_at at time zone 'America/Bogota')::date = hoy;
  if v_hoy >= v_tope then
    return jsonb_build_object('ok', true, 'activo', true, 'motivo', 'tope_del_dia', 'hoy', v_hoy);
  end if;

  with sel as (
    select * from ventas_candidatos(least(v_por, v_tope - v_hoy))
  ), chat as (
    insert into ventas_chats (telefono, nombre, objetivo, oferta, abierta_at)
    select s.tel, s.nombre, s.objetivo,
           jsonb_build_object('visitas_30d', s.visitas_30d, 'hora_habitual', s.hora_habitual), p_ahora
      from sel s
    returning telefono, nombre, objetivo, oferta, id
  ), enc as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'ventas:' || c.telefono || ':' || to_char(hoy, 'YYYYMMDD'), 'campana', c.telefono, 'ventas_apertura',
           jsonb_build_array(c.nombre, ventas_gancho(c.objetivo, (c.oferta ->> 'visitas_30d')::int)),
           now() + interval '2 hours'
      from chat c
    on conflict (clave) do nothing
    returning 1
  )
  select count(*) into v_n from enc;

  return jsonb_build_object('ok', true, 'activo', true, 'encolados', v_n, 'hoy', v_hoy + v_n);
exception when others then
  raise warning 'ventas_ronda: %', sqlerrm;
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;
revoke all on function public.ventas_ronda(boolean, timestamptz) from public, anon, authenticated;

create or replace function public.ventas_ronda(p_ejecutar boolean default true)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$ select public.ventas_ronda($1, now()) $$;
revoke all on function public.ventas_ronda(boolean) from public, anon, authenticated;

select cron.alter_job((select jobid from cron.job where jobname = 'tumbao-ventas'),
                      command := 'select public.ventas_ronda(true, now())');
