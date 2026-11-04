-- 0196 · Plantillas con imagen y prueba A/B (2 nov, Damián). Aplicada en vivo.
-- · Plantillas nuevas (se crean en Meta desde el Worker): rumbo_2027_imagen y tiquetera_premio_imagen (encabezado con imagen de la campaña).
-- · ajustes.wa_ab_imagen = 'apagado' hasta que Meta apruebe tiquetera_premio_imagen. Encendido, campana_frecuentes_nov manda esa plantilla a los
--   celulares que terminan en dígito impar y tiquetera_frecuentes (solo texto) a los pares: se compara cuál convierte más.
-- · Cuando alguien responde a una venta, el Worker le comparte una vez la imagen de la campaña que va con su interés (gratis dentro de las 24 h).
insert into ajustes (clave, valor, nota)
values ('wa_ab_imagen', 'apagado', 'Prueba A/B de la campaña a frecuentes (0196): impares con imagen, pares solo texto.')
on conflict (clave) do nothing;

do $b$ declare d text; viejo text; nuevo text; begin
 d := pg_get_functiondef('public.campana_frecuentes_nov(boolean)'::regprocedure);
 viejo := 'select ''frecuentes-nov:''||t,''campana'',t,''tiquetera_frecuentes'',jsonb_build_array(n,v30::text),now()+interval ''4 days'' from cand';
 nuevo := 'select ''frecuentes-nov:''||t,''campana'',t,'
       || 'case when (select valor from ajustes where clave=''wa_ab_imagen'')=''encendido'' and right(t,1)::int % 2 = 1 then ''tiquetera_premio_imagen'' else ''tiquetera_frecuentes'' end,'
       || 'case when (select valor from ajustes where clave=''wa_ab_imagen'')=''encendido'' and right(t,1)::int % 2 = 1 then jsonb_build_array(n) else jsonb_build_array(n,v30::text) end,'
       || 'now()+interval ''4 days'' from cand';
 d := replace(d, viejo, nuevo);
 execute d; end $b$;
