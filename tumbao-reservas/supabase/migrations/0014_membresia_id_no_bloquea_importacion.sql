-- =====================================================================
-- La reserva de un miembro rompía la importación de la noche
--
-- EL BUG
-- `reservas.membresia_id` apunta a `membresias`. Y `membresias` se BORRA
-- ENTERA cada noche para recargarla desde el reporte de AdminGym.
--
-- Mientras nadie con plan reservara, no pasaba nada. Pero reservar el
-- sábado es justo lo que los miembros tienen que hacer, y esa reserva
-- guarda el membresia_id. Desde ese momento:
--
--     ERROR: update or delete on table "membresias" violates foreign
--     key constraint "reservas_membresia_id_fkey" on table "reservas"
--
-- La importación abortaba entera. Los cupos se quedaban congelados en
-- los del último día bueno, sin que nadie se enterara — y ya sabemos a
-- dónde lleva eso: se venden cupos que no existen.
--
-- LA CORRECCIÓN
-- `on delete set null`. La membresía es una réplica que se reemplaza
-- cada noche; la reserva no. La reserva ya guarda nombre y celular por
-- su cuenta, así que perder el vínculo no le quita nada: solo deja de
-- apuntar a una fila que dejó de existir.
--
-- Lo salió probando el caso completo del sábado: un miembro reserva, y
-- después corre la importación.
-- =====================================================================

alter table reservas
  drop constraint if exists reservas_membresia_id_fkey;

alter table reservas
  add constraint reservas_membresia_id_fkey
  foreign key (membresia_id) references membresias(id)
  on delete set null;

comment on column reservas.membresia_id is
  'Membresia con la que se reservo. Se pone en null cuando la importacion nocturna reemplaza la tabla: es una replica, la reserva no.';
