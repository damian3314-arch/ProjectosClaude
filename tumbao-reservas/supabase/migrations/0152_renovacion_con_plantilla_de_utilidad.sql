-- 0152 · El aviso de renovación pasa a la plantilla de UTILIDAD
--
-- Meta aprobó mensualidad_vence_aviso como UTILIDAD (≈ $3 por mensaje, contra ≈ $46 de
-- mensualidad_vencimiento / mensualidad_recordatorio, que Meta cobra como marketing).
-- Las dos tienen las mismas tres variables (nombre, horario, fecha), así que basta cambiar el ajuste
-- que lee renovacion_automatica(): el aviso de 3 días antes y el del día del vencimiento.
--
-- Probado en una transacción que se deshizo: una membresía de prueba que vence en 2 días generó un aviso
-- con plantilla mensualidad_vence_aviso y variables ["Prueba", "7:00 pm", "jueves 8 de octubre"].
-- Si Meta la reclasifica a marketing, se vuelve a mensualidad_vencimiento / mensualidad_recordatorio.

update ajustes
   set valor = '{"renovacion":"mensualidad_vence_aviso","renovacion_ultimo":"mensualidad_vence_aviso","tiquetera":"tiquetera_semana","regreso":"te_extranamos_semana"}',
       nota = 'Qué plantilla usa cada grupo. 6 oct: la renovación (3 días antes y día del vencimiento) usa mensualidad_vence_aviso, aprobada por Meta como UTILIDAD (≈ $3 en vez de ≈ $46). Si Meta la reclasifica a marketing, volver a mensualidad_vencimiento / mensualidad_recordatorio.'
 where clave = 'cierre_sep_plantillas';
