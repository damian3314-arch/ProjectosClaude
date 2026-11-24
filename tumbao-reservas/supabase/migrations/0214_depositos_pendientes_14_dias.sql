-- 0214 · Los depósitos del banco que nadie ha reclamado se ven 14 días, no 3 (24 nov, aviso de Damián)
--
-- Pasó que la pestaña Pendientes y la lista para escoger depósito en Caja solo miraban los últimos 3 días. Un depósito sin
-- reclamar del 18 o 19 de noviembre ($141.000 en 4 depósitos) desaparecía de la pantalla aunque seguía sin dueño en el banco.
-- Ahora se ven 14 días atrás. Solo cambia qué tan atrás se mira; no toca ningún dato ni ningún cálculo del cierre.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.admin_pendientes(text)'::regprocedure);
  d := replace(d, 'greatest(v_desde, now() - interval ''3 days'')', 'greatest(v_desde, now() - interval ''14 days'')');
  if d !~ '14 days' then raise exception 'parche de admin_pendientes no aplicó'; end if;
  execute d;

  d := pg_get_functiondef('public.caja_del_dia(text,date)'::regprocedure);
  d := replace(d, 'c_dias_lista constant int := 3;', 'c_dias_lista constant int := 14;');
  if d !~ 'c_dias_lista constant int := 14' then raise exception 'parche de caja_del_dia no aplicó'; end if;
  execute d;
end $do$;
