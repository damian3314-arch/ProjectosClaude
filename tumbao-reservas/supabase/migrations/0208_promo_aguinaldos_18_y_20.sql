-- 0208 · Aguinaldos: la promo de 2 cupos por $24.000 vale también el miércoles 18 y el viernes 20 de noviembre de 2026 (NO el jueves 19).
-- · ajustes.promo_dos_cupos gana "fechas": lista de días de CLASE (hora de Bogotá). Si existe, manda sobre clases_desde/clases_hasta.
-- · promo_total_cupos lee "fechas"; sin ella funciona igual que en la 0206. Se conserva el 13 de nov para que el cierre de ese día no cambie.
-- Pedido de Damián (17 nov). Sin DROP/DELETE; la promo se apaga con activa=false (después de revisar el cierre de los días de la promo).
create or replace function public.promo_total_cupos(p_n integer, p_precio_unit integer, p_fecha_clase timestamp with time zone)
returns integer language plpgsql stable security definer set search_path to 'public','pg_temp' as $$
declare v jsonb; d date; ok boolean;
begin
  begin v := (select valor::jsonb from ajustes where clave = 'promo_dos_cupos'); exception when others then v := null; end;
  if v is null or coalesce((v->>'activa')::boolean, false) is not true or p_n is distinct from (v->>'cupos')::int then
    return p_precio_unit * p_n;
  end if;
  d := (p_fecha_clase at time zone 'America/Bogota')::date;
  if jsonb_typeof(v->'fechas') = 'array' then
    ok := exists (select 1 from jsonb_array_elements_text(v->'fechas') f where f::date = d);
  else
    ok := d between (v->>'clases_desde')::date and (v->>'clases_hasta')::date;
  end if;
  if ok then return least((v->>'precio_cop')::int, p_precio_unit * p_n); end if;
  return p_precio_unit * p_n;
end $$;

update ajustes
   set valor = '{"activa":true,"cupos":2,"precio_cop":24000,"clases_desde":"2026-11-13","clases_hasta":"2026-11-20","fechas":["2026-11-13","2026-11-18","2026-11-20"]}'
 where clave = 'promo_dos_cupos';
