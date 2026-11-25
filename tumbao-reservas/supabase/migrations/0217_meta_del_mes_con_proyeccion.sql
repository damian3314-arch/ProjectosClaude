-- 0217 · La meta del mes muestra primero lo vendido y trae la proyección (25 nov, Damián)
--
-- «Sale primero lo que falta por vender y luego lo que se lleva. Que muestre primero lo vendido y cuánto hace falta, lo que se
-- necesita por día para completar la meta y hasta cuánto se llega si sigue la tendencia de ventas.»
--
-- admin_meta_mes() ahora también devuelve:
--   ritmo_dia_cop      lo vendido por día de clase en los días ya completos del mes (hasta ayer)
--   proyeccion_cop     lo vendido hasta hoy + ritmo × los días de clase que quedan después de hoy (hoy cuenta solo lo vendido)
--   proyeccion_pct     la proyección como % de la meta
--   falta_proyectada_cop   cuánto faltaría para la meta si todo sigue igual (0 si se llega)
--   dias_pasados       cuántos días de clase completos entran en el ritmo
-- Sin días completos (primer día del mes) no hay proyección: queda en null. Lo demás no cambia. No borra nada.

create or replace function public.admin_meta_mes(p_token text)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions', 'pg_temp' as $$
declare
  v_admin record; v_hoy date; v_ini date; v_fin date; v_mes text;
  v_meta bigint := 0; v_de_mes text; v_vendido bigint; v_ult date; v_dias int; v_falta bigint;
  v_json jsonb;
  v_pasados int := 0; v_dias_sin_hoy int := 0; v_vendido_ayer bigint := 0;
  v_ritmo bigint := null; v_proy bigint := null;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if v_admin.rol = 'cajero' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO',
      'mensaje', 'Esta vista es del propietario y el administrador.');
  end if;

  v_hoy := (now() at time zone 'America/Bogota')::date;
  v_ini := date_trunc('month', v_hoy)::date;
  v_fin := (v_ini + interval '1 month' - interval '1 day')::date;
  v_mes := to_char(v_hoy, 'YYYY-MM');

  begin
    v_json := (select valor::jsonb from ajustes where clave = 'meta_ventas_mes');
  exception when others then v_json := null; end;
  if v_json is not null then
    select k, (v_json ->> k)::bigint into v_de_mes, v_meta
      from jsonb_object_keys(v_json) k
     where k <= v_mes and (v_json ->> k) ~ '^\d+$'
     order by k desc limit 1;
  end if;
  v_meta := coalesce(v_meta, 0);

  v_vendido := coalesce((ventas_entre(v_ini, v_hoy) ->> 'ingreso_cop')::bigint, 0);

  select max((fecha_hora at time zone 'America/Bogota')::date) into v_ult from clases;
  select count(*) into v_dias
    from generate_series(v_hoy, v_fin, interval '1 day') d
   where exists (select 1 from clases c where (c.fecha_hora at time zone 'America/Bogota')::date = d::date)
      or (extract(isodow from d) <> 7 and not exists (select 1 from festivos f where f.fecha = d::date));

  -- Tendencia: días de clase ya completos (hasta ayer) y lo vendido en ellos.
  if v_hoy > v_ini then
    select count(*) into v_pasados
      from generate_series(v_ini, v_hoy - 1, interval '1 day') d
     where exists (select 1 from clases c where (c.fecha_hora at time zone 'America/Bogota')::date = d::date)
        or (extract(isodow from d) <> 7 and not exists (select 1 from festivos f where f.fecha = d::date));
    v_vendido_ayer := coalesce((ventas_entre(v_ini, v_hoy - 1) ->> 'ingreso_cop')::bigint, 0);
  end if;
  if v_hoy < v_fin then
    select count(*) into v_dias_sin_hoy
      from generate_series(v_hoy + 1, v_fin, interval '1 day') d
     where exists (select 1 from clases c where (c.fecha_hora at time zone 'America/Bogota')::date = d::date)
        or (extract(isodow from d) <> 7 and not exists (select 1 from festivos f where f.fecha = d::date));
  end if;
  if v_pasados > 0 then
    v_ritmo := round(v_vendido_ayer::numeric / v_pasados)::bigint;
    v_proy  := v_vendido + v_ritmo * v_dias_sin_hoy;
  end if;

  v_falta := greatest(v_meta - v_vendido, 0);

  return jsonb_build_object(
    'ok', true, 'mes', v_mes, 'hoy', v_hoy,
    'meta_cop', v_meta, 'meta_definida_para', v_de_mes,
    'vendido_cop', v_vendido, 'falta_cop', v_falta,
    'pct', case when v_meta > 0 then round(v_vendido * 100.0 / v_meta)::int else null end,
    'dias_restantes', v_dias,
    'por_dia_cop', case when v_dias > 0 then ceil(v_falta::numeric / v_dias)::bigint else v_falta end,
    'ritmo_dia_cop', v_ritmo,
    'dias_pasados', v_pasados,
    'proyeccion_cop', v_proy,
    'proyeccion_pct', case when v_meta > 0 and v_proy is not null then round(v_proy * 100.0 / v_meta)::int else null end,
    'falta_proyectada_cop', case when v_proy is not null then greatest(v_meta - v_proy, 0) else null end,
    'cumplida', v_meta > 0 and v_vendido >= v_meta,
    'puede_cambiar', v_admin.rol = 'propietario');
end;
$$;
