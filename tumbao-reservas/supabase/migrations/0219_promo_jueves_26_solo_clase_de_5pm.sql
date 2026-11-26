-- 0219 · Jueves 26 de noviembre: 2 × $24.000 solo en la Rumba de las 5:00 pm (25 nov, Damián)
--
-- «Estamos en aguinaldos… JUEVES · 2 x $24.000 · Rumba Fitness · Principiantes · 5:00 PM». Cada 2 cupos de clase suelta valen
-- $24.000 (4 = $48.000, 6 = $72.000, 8 = $96.000; si sobra uno paga lo normal), pero solo en ESA clase, no en las demás del jueves.
--
-- ajustes.promo_dos_cupos ya tenía `fechas` (días con promo); se le agrega `solo_horas`: {"fecha": ["HH:MM", …]}. Un día que
-- aparece ahí solo da la tarifa a las clases de esas horas; un día que no aparece sigue valiendo para todas (como el 13, 18 y 20).
-- promo_total_cupos() es la única que calcula el precio, así que la página, el cierre y /admin siguen cuadrando. No borra nada.

update ajustes
   set valor = (jsonb_set(
                  jsonb_set(valor::jsonb, '{fechas}', (valor::jsonb->'fechas') || '"2026-11-26"'::jsonb),
                  '{solo_horas}', '{"2026-11-26": ["17:00"]}'::jsonb))::text
 where clave = 'promo_dos_cupos'
   and not (valor::jsonb->'fechas') ? '2026-11-26';

do $do$
declare d text;
begin
  d := pg_get_functiondef('public.promo_total_cupos(integer,integer,timestamp with time zone)'::regprocedure);
  d := replace(d, '  if not ok then return p_precio_unit * p_n; end if;',
'  -- Algunos días la tarifa es solo para ciertas clases (solo_horas: {"AAAA-MM-DD": ["HH:MM"]}).
  if ok and jsonb_typeof(v->''solo_horas'') = ''object'' and (v->''solo_horas'') ? d::text then
    ok := exists (select 1 from jsonb_array_elements_text(v->''solo_horas''->(d::text)) h
                   where h = to_char(p_fecha_clase at time zone ''America/Bogota'', ''HH24:MI''));
  end if;
  if not ok then return p_precio_unit * p_n; end if;');
  if d !~ 'solo_horas' then raise exception 'parche de promo_total_cupos no aplicó'; end if;
  execute d;
end $do$;
