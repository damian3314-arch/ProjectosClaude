-- 0183 · El tope de mensualidades de 6 pm y de 7 pm pasa de 23 a 25
--
-- 14 oct, Damián: «ajustemos el tope a 25 mensualidades». El 9 de octubre lo había dejado en 23 para que, ahora que se
-- venden las tiqueteras, quedaran más cupos libres en clase suelta; con las mensualidades cayendo y 47 clientes frecuentes
-- de noche sin cupo, sube a 25 (el aforo de la sala sigue siendo 35). El horario de 7 am no cambia (35).
--   · mensualidad_topes: lo que vende la página.
--   · premium_topes: el tope que usan la fidelidad (pausada, 0180) y el aviso a la lista de espera.
-- Cada cambio solo se aplica si el valor sigue siendo el de antes, para no pisar un ajuste hecho a mano después.
-- Para volver atrás: los mismos valores con 23.

update public.ajustes
   set valor = '07:00=35,18:00=25,19:00=25', updated_at = now()
 where clave = 'mensualidad_topes' and valor = '07:00=35,18:00=23,19:00=23';

update public.ajustes
   set valor = '07:00=99,18:00=25,19:00=25', updated_at = now()
 where clave = 'premium_topes' and valor = '07:00=99,18:00=23,19:00=23';
