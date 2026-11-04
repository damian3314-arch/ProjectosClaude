-- 0079 · La regla de cupos manda desde hoy, no desde el 15.
--
-- Damián: «que esto aplique también para la página de reserva de clase
-- suelta».
--
-- La regla YA gobernaba esa página: `cupo_total` de cada clase es
-- exactamente lo que la página vende, y desde la 0076 sale de
-- `cupo_suelta_de`. Lo que pasaba es que arrancaba el 15 de septiembre
-- —la fecha que él mismo puso el 8— y hoy es 10. Esta semana seguía
-- funcionando con lo de antes.
--
-- Y se notaba. Alguien estaba aplicando la regla A MANO, clase por
-- clase, poniendo `cupo_manual`:
--
--   10/09 19:00  cupo_manual 11   ← puesto a mano
--   11/09 07:00  cupo_manual  5   ← puesto a mano
--   11/09 19:00  cupo_manual 11   ← puesto a mano
--   11/09 18:00  cupo_manual null → 35 − 23 afiliadas = 12  ← SE ESCAPÓ
--
-- Ese 12 es justo el fallo que se evita teniendo la regla: la clase del
-- viernes a las 6pm estaba vendiendo un cupo por encima de los 11 que
-- fijó el dueño, porque a esa nadie le escribió el número encima.
--
-- Adelantar el corte a hoy arregla ese caso y quita el trabajo manual.
--
-- COMPROBADO ANTES DE APLICARLO, clase por clase: el único cupo que
-- cambia es el del viernes 6pm, de 12 a 11, y esa clase tiene CERO
-- reservas. Nadie pierde un cupo que ya tenía. El resto ya estaba en el
-- número de la regla, y los sábados no los toca (la regla no los
-- nombra, y siguen en 35 por su cupo manual).
--
-- CONSECUENCIA QUE HAY QUE TENER PRESENTE: desde la 0076 la regla manda
-- SOBRE `cupo_manual` en las tres horas que nombra. O sea que escribir
-- un cupo a mano en la rejilla de la semana para 07:00, 18:00 o 19:00 ya
-- no hace nada. Es deliberado —la política no puede depender de que
-- alguien la teclee cada semana— pero significa que una excepción para
-- una clase suelta hay que pedirla, no teclearla.

update ajustes
   set valor = to_char((now() at time zone 'America/Bogota')::date, 'YYYY-MM-DD')
 where clave = 'suelta_cupos_desde';

-- Lo aplica a las clases que ya existen. `recalcular_cupos` nunca baja
-- de `cupo_tomado`, así que aunque un cupo nuevo fuera menor que lo ya
-- reservado, la reserva se respeta.
select recalcular_cupos();
