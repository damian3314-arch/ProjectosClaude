-- 0118 · El centinela solo avisa de tiqueteras realmente por validar; las
-- descartadas (0117) ya no cuentan.
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.centinela_datos()'::regprocedure) into v_src;
  if position('''pendiente_validacion''' in v_src) > 0 then return; end if;
  v_new := replace(v_src, 'where estado <> ''confirmada'' and pagado_en is not null',
    'where estado in (''pendiente_pago'', ''pendiente_validacion'') and pagado_en is not null');
  if v_new = v_src then raise exception '0118: no se aplicó'; end if;
  execute v_new;
end
$mig$;
