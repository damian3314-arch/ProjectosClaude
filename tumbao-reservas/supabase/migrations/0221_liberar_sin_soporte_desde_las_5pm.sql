-- 0221 · Reservas sin comprobante de WhatsApp: se liberan desde las 5:00 pm (hora Bogotá).
-- La recepcionista llega a las 4:30 pm y tiene esa media hora para revisar comprobantes y aprobar
-- en "por validar". Antes de las 5:00 pm no se libera nada; desde las 5:00 pm rige el margen de siempre
-- (validacion_max_min, 30 min por defecto) para que lo reservado entre 4:30 y 5:00 también tenga su tiempo.
do $$
declare
  d text := pg_get_functiondef('public.liberar_cupos_expirados'::regproc);
  n text;
begin
  if d like '%liberar_sin_soporte_desde%' then return; end if;
  n := replace(d, 'v_n2  int := 0;',
    E'v_n2  int := 0;\n  v_desde time := coalesce(nullif((select valor from ajustes where clave = ''liberar_sin_soporte_desde''), '''')::time, time ''17:00'');');
  n := replace(n, E'where r.estado in (''verificando'', ''pendiente_validacion'')\n',
    E'where r.estado in (''verificando'', ''pendiente_validacion'')\n       and (now() at time zone ''America/Bogota'')::time >= v_desde\n');
  if n = d or n not like '%v_desde time%' or n not like '%>= v_desde%' then raise exception 'parche 0221 no aplicó'; end if;
  execute n;
end $$;
insert into ajustes (clave, valor) values ('liberar_sin_soporte_desde', '17:00')
on conflict (clave) do nothing;
