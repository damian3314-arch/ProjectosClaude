-- 0209 · Aguinaldos: la promo de $24.000 por cada 2 personas vale para grupos grandes (4, 6, 8…), no solo para 2. Pedido de Damián (17 nov).
-- · Cada pareja (cupos = 2) cuesta precio_cop ($24.000): 4 personas = $48.000, 6 = $72.000, 8 = $96.000.
-- · Si sobra una persona (3, 5, 7), esa paga el precio normal de la clase. Nunca cuesta más que sin promo (least).
-- · Los días de la promo siguen siendo los de ajustes.promo_dos_cupos.fechas. precio_del_grupo / tomar_cupos / valor_reserva / cierre la usan sin cambios.
create or replace function public.promo_total_cupos(p_n integer, p_precio_unit integer, p_fecha_clase timestamp with time zone)
returns integer language plpgsql stable security definer set search_path to 'public','pg_temp' as $$
declare v jsonb; d date; ok boolean; k int; pares int;
begin
  begin v := (select valor::jsonb from ajustes where clave = 'promo_dos_cupos'); exception when others then v := null; end;
  if v is null or coalesce((v->>'activa')::boolean, false) is not true then
    return p_precio_unit * p_n;
  end if;
  k := (v->>'cupos')::int;
  if k is null or k < 1 or p_n < k then
    return p_precio_unit * p_n;
  end if;
  d := (p_fecha_clase at time zone 'America/Bogota')::date;
  if jsonb_typeof(v->'fechas') = 'array' then
    ok := exists (select 1 from jsonb_array_elements_text(v->'fechas') f where f::date = d);
  else
    ok := d between (v->>'clases_desde')::date and (v->>'clases_hasta')::date;
  end if;
  if not ok then return p_precio_unit * p_n; end if;
  pares := p_n / k;
  return least(pares * (v->>'precio_cop')::int + (p_n - pares * k) * p_precio_unit, p_precio_unit * p_n);
end $$;
