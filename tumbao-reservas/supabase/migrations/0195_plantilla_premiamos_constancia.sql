-- 0195 · Aviso «premiamos tu constancia» (2 nov, Damián). Reemplaza a pase_constancia y pase_constancia_2 («clase de regalo»).
-- La plantilla nueva (premiamos_constancia) se crea en Meta desde el Worker (GET /wa/plantillas). Hasta que Meta la apruebe todo sigue como estaba.
-- Cuando esté APPROVED:  update ajustes set valor = 'premiamos_constancia' where clave = 'wa_pase_plantilla_nueva';
-- Con eso, pases_por_constancia() usa la plantilla nueva para las dos tiqueteras (4 → «1 clase más», 8 → «2 clases más»).
-- Aplicada en vivo.

insert into ajustes (clave, valor, nota)
values ('wa_pase_plantilla_nueva', '', 'Plantilla del aviso de constancia. Vacío = las antiguas. «premiamos_constancia» = la nueva (0195).')
on conflict (clave) do nothing;

do $b$ declare d text; viejo text; nuevo text; begin
 d := pg_get_functiondef('public.pases_por_constancia()'::regprocedure);
 viejo := E'      if not v_baja then\n        insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)\n        values (''pase_constancia:''';
 if position(viejo in d) = 0 then raise exception 'no encontrado'; end if;
 nuevo := E'      if coalesce((select valor from ajustes where clave = ''wa_pase_plantilla_nueva''), '''') = ''premiamos_constancia'' then\n'
       || E'        v_plant := ''premiamos_constancia'';\n'
       || E'        v_vars := jsonb_build_array(v_nom, r.clases_totales::text, case when v_extra = 1 then ''1 clase más'' else v_extra::text || '' clases más'' end,\n'
       || E'                                    ''Código: '' || v_cod, wa_fecha_texto(v_vence));\n'
       || E'        v_baja := v_tel !~ ''^3[0-9]{9}$'' or exists (select 1 from wa_bajas b where b.telefono = v_tel);\n'
       || E'      end if;\n' || viejo;
 d := replace(d, viejo, nuevo);
 execute d; end $b$;
