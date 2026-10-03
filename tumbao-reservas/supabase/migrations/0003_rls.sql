-- =====================================================================
-- Tumbao Reservas — Row Level Security
--
-- RLS activo en todas las tablas. El servidor usa service_role y las
-- omite; el navegador solo puede leer lo que es explícitamente público.
-- =====================================================================

alter table clases      enable row level security;
alter table reservas    enable row level security;
alter table pagos       enable row level security;
alter table admin_users enable row level security;

-- Cualquiera ve las clases activas y futuras (para el selector).
create policy clases_publicas on clases for select
  using (activa and fecha_hora > now());

-- reservas y pagos: sin políticas para el rol anon.
-- Toda lectura/escritura pasa por el servidor con service_role.
-- pagos NUNCA se expone al navegador: contiene datos bancarios de
-- terceros.

-- admin_users tampoco tiene política pública. El guard de /admin lee
-- esta tabla desde el servidor.

-- ---------------------------------------------------------------------
-- Cierre de permisos sobre las funciones
--
-- tomar_cupo() es SECURITY DEFINER: corre con los privilegios de su
-- dueño y se salta RLS por diseño. Por defecto Postgres da EXECUTE a
-- PUBLIC en toda función nueva, así que el rol anon podría llamarla
-- directamente desde el navegador vía PostgREST y crear reservas
-- saltándose la API. Se revoca y solo se concede al servidor.
revoke execute on function tomar_cupo(uuid, text, text, text, text) from public;
revoke execute on function liberar_cupos_expirados()                from public;
revoke execute on function generar_codigo_reserva()                 from public;

grant execute on function tomar_cupo(uuid, text, text, text, text) to service_role;
grant execute on function liberar_cupos_expirados()                to service_role;
