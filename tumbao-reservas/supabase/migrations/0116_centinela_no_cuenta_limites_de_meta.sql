-- 0116 · El centinela no cuenta como "fallido" lo que Meta retiene por sus
-- propios límites de marketing (131049: "healthy ecosystem engagement",
-- 130472: número en experimento de Meta) ni números sin WhatsApp (131026).
-- El 28 sep dio una falsa alarma por 4 de esos en la campaña de tiquetera.
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.centinela_datos()'::regprocedure) into v_src;
  if position('131049' in v_src) > 0 then return; end if;
  v_new := replace(v_src, 'and coalesce(entrega_error, '''') not like ''131026%''',
    'and coalesce(entrega_error, '''') !~ ''^(131026|131049|130472)''');
  if v_new = v_src then raise exception '0116: no se aplicó'; end if;
  execute v_new;
end
$mig$;
