-- 0216 · La clase adicional por constancia solo para tiqueteras compradas hasta el 30 de noviembre de 2026 (24 nov, Damián)
--
-- «1 clase más en la tiquetera de 4 y 2 clases más en la de 8 al completarla» no convive con la promoción de fin de año
-- (45 días de vigencia, compras desde el 24 de nov). Se acuerda: la constancia vale para tiqueteras compradas hasta el
-- 30 de noviembre; las compradas desde el 1 de diciembre no la tienen. Las ya compradas la conservan aunque terminen después.
--
-- La fecha se lee de ajustes.pase_constancia_hasta (vacía = sin límite). Se compara con el día del pago (pagado_en) y,
-- si no hay, con el de creación. pases_por_constancia() sigue igual en todo lo demás. No borra nada.

insert into ajustes (clave, valor) values ('pase_constancia_hasta', '2026-11-30')
on conflict (clave) do nothing;

do $do$
declare d text;
begin
  d := pg_get_functiondef('public.pases_por_constancia()'::regprocedure);
  d := replace(d, '       and t.premio_de is null
       and not exists (select 1 from tiqueteras p where p.premio_de = t.id)',
'       and t.premio_de is null
       and (coalesce(nullif((select valor from ajustes where clave = ''pase_constancia_hasta''), ''''), ''9999-12-31'')::date
              >= (coalesce(t.pagado_en, t.creada_en) at time zone ''America/Bogota'')::date)
       and not exists (select 1 from tiqueteras p where p.premio_de = t.id)');
  if d !~ 'pase_constancia_hasta' then raise exception 'parche de pases_por_constancia no aplicó'; end if;
  execute d;
end $do$;
