-- 0218 · Ingresos por validar: de un día para otro solo pasan los de mensualidad y tiquetera (25 nov, Damián)
--
-- «Los de clase suelta no los dejes pasar: son pagos que se usan ese día. Si pagan en la página se cruza solo; si llegan a
-- recepción, la plata entra de inmediato y se toma para el registro. La recepcionista debe usar los del día que va corriendo.»
--
-- · Los depósitos sin asignar de HOY se ven siempre.
-- · Los de días anteriores se ven solo si su valor es el de una mensualidad o el de una tiquetera (precios de ajustes), hasta 14 días atrás.
--   Los demás (clase suelta, de 1, 2, 3… personas) no vuelven a pedir turno.
-- Afecta la pestaña Pendientes (admin_pendientes) y la lista para escoger depósito en Caja (caja_del_dia). El cierre y sus cifras no cambian.
-- No borra nada: los pagos siguen en la base, solo dejan de mostrarse.

create or replace function public.valores_de_plan()
returns int[] language sql stable set search_path to 'public', 'pg_temp' as $$
  select coalesce(array_remove(
           array[nullif((select valor from ajustes where clave = 'mensualidad_valor_cop'), '')::int]
           || coalesce((select array_agg((e->>'precio_cop')::int) from jsonb_array_elements(tiquetera_paquetes()) e), '{}'::int[]),
           null), '{}'::int[])
$$;

do $do$
declare d text;
begin
  d := pg_get_functiondef('public.admin_pendientes(text)'::regprocedure);
  d := replace(d, 'where p.fecha_pago >= greatest(v_desde, now() - interval ''14 days'')',
'where p.fecha_pago >= greatest(v_desde, now() - interval ''14 days'')
       and ((p.fecha_pago at time zone ''America/Bogota'')::date >= (now() at time zone ''America/Bogota'')::date
            or p.valor_cop = any (valores_de_plan()))');
  if d !~ 'valores_de_plan' then raise exception 'parche de admin_pendientes no aplicó'; end if;
  execute d;

  d := pg_get_functiondef('public.caja_del_dia(text,date)'::regprocedure);
  d := replace(d, 'where p.fecha_pago >= v_corte_lista and p.fecha_pago < v_hasta',
'where p.fecha_pago >= v_corte_lista and p.fecha_pago < v_hasta
         and ((p.fecha_pago at time zone ''America/Bogota'')::date >= v_dia
              or p.valor_cop = any (valores_de_plan()))');
  if d !~ 'valores_de_plan' then raise exception 'parche de caja_del_dia no aplicó'; end if;
  execute d;
end $do$;
