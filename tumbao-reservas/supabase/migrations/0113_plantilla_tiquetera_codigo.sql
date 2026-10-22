-- 0113 · Meta rechazó al instante la plantilla 'tiquetera_activa' (28 sep):
-- el aviso con el código usa 'tiquetera_codigo', más sobria. (El archivo
-- 0112 ya quedó con el nombre nuevo; esto corrige lo que se aplicó.)
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.wa_encolar_tiquetera()'::regprocedure) into v_src;
  if position('''tiquetera_codigo''' in v_src) > 0 then return; end if;
  v_new := replace(v_src, 'v_tel, ''tiquetera_activa'',', 'v_tel, ''tiquetera_codigo'',');
  if v_new = v_src then raise exception '0113: no se aplicó'; end if;
  execute v_new;
end
$mig$;
