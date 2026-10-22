-- 0114 · Meta rechazó también 'tiquetera_codigo' (28 sep). El aviso usa
-- 'tiquetera_lista' y la tercera variable lleva «Código: X» completa,
-- igual que reserva_confirmada, que sí está aprobada.
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.wa_encolar_tiquetera()'::regprocedure) into v_src;
  if position('''tiquetera_lista''' in v_src) > 0 then return; end if;
  v_new := replace(v_src, 'v_tel, ''tiquetera_codigo'',', 'v_tel, ''tiquetera_lista'',');
  v_new := replace(v_new, 'new.clases_totales::text, new.codigo,', 'new.clases_totales::text, ''Código: '' || new.codigo,');
  if position('''tiquetera_lista''' in v_new) = 0 or position('''Código: '' || new.codigo' in v_new) = 0 then
    raise exception '0114: no se aplicó';
  end if;
  execute v_new;
end
$mig$;
