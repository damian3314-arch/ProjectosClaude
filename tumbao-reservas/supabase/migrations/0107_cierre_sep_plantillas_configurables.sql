-- 0107 · Cierre de septiembre: el recordatorio del miércoles y las
--        plantillas "para la semana".
--
-- LO QUE PIDIÓ DAMIÁN (27 sep, 10 pm)
-- «La de invitar a renovar solo debemos enviarla el lunes, y recordar de
--  nuevo el miércoles, pero sin sonar acosador, solo recordando el
--  vencimiento, con un lenguaje muy de Tumbao… invitar a la gente que
--  compre su tiquetera y se programe para la semana es lo mejor.»
--
-- ── QUÉ CAMBIA ──────────────────────────────────────────────────────
--   renovacion (lun)         mensualidad_vencimiento   (igual, ya aprobada)
--   renovacion_ultimo (mié)  mensualidad_recordatorio  (nueva, suave:
--                            "Pasamos con cariño a recordarte…"). Cubre
--                            hasta el 2 oct, lo mismo que el lunes: si ya
--                            renovó, su fin cambió y no le llega.
--   tiquetera (lun)          tiquetera_semana          (nueva)
--   regreso (mar y mié)      te_extranamos_semana      (nueva, con botón
--                            "Reservar una clase")
--
-- ── SI META NO APRUEBA A TIEMPO ─────────────────────────────────────
-- Las plantillas se leen de ajustes.cierre_sep_plantillas. La revisión
-- previa a cada lanzamiento consulta /wa/plantillas; si la nueva no está
-- APPROVED, cambia ese grupo a la anterior aprobada (tiquetera_frecuentes,
-- te_extranamos, mensualidad_vencimiento) y la campaña sale igual.

insert into public.ajustes (clave, valor, nota) values
  ('cierre_sep_plantillas',
   '{"renovacion":"mensualidad_vencimiento","renovacion_ultimo":"mensualidad_recordatorio","tiquetera":"tiquetera_semana","regreso":"te_extranamos_semana"}',
   'Qué plantilla usa cada grupo del cierre de septiembre. Si Meta no aprobó la nueva a tiempo, se cambia aquí por la anterior aprobada (mensualidad_vencimiento, tiquetera_frecuentes, te_extranamos). 0107.')
on conflict (clave) do update set valor = excluded.valor, nota = excluded.nota, updated_at = now();

do $mig$
declare v_src text; v_new text;
  cfg text := '(select valor::jsonb->>%L from ajustes where clave = ''cierre_sep_plantillas'')';
begin
  select pg_get_functiondef('public.campana_cierre_sep(text)'::regprocedure) into v_src;
  v_new := v_src;
  v_new := replace(v_new, 'm.tel, ''mensualidad_vencimiento'',',
    'm.tel, case when p_grupo = ''renovacion_ultimo'' then coalesce(' || format(cfg, 'renovacion_ultimo') ||
    ', ''mensualidad_recordatorio'') else coalesce(' || format(cfg, 'renovacion') || ', ''mensualidad_vencimiento'') end,');
  v_new := replace(v_new, 'r.tel, ''tiquetera_frecuentes'',',
    'r.tel, coalesce(' || format(cfg, 'tiquetera') || ', ''tiquetera_semana''),');
  v_new := replace(v_new, 'tel, ''te_extranamos'',',
    'tel, coalesce(' || format(cfg, 'regreso') || ', ''te_extranamos_semana''),');
  v_new := replace(v_new, 'else m.fin between date ''2026-09-25'' and date ''2026-09-30''',
                          'else m.fin between date ''2026-09-25'' and date ''2026-10-02''');
  if v_new = v_src
     or position('''renovacion_ultimo'' then coalesce' in v_new) = 0
     or position('''tiquetera_semana''' in v_new) = 0
     or position('''te_extranamos_semana''' in v_new) = 0
     or position('date ''2026-09-30''' in v_new) > 0 then
    raise exception '0107: no se aplicaron todos los cambios';
  end if;
  execute v_new;
end
$mig$;

-- Simulacro del 27 sep (transacción revertida): renovación 26,
-- recordatorio 26, tiquetera 44, regreso 76; 146 personas, máximo 2
-- mensajes por persona.
