-- =====================================================================
-- Cerrar la ejecución de las funciones a anon y authenticated
--
-- `REVOKE EXECUTE ... FROM PUBLIC` (migración 0003) NO alcanza.
--
-- Supabase concede EXECUTE explícito a los roles `anon` y
-- `authenticated` sobre las funciones del esquema `public`, y esas
-- concesiones son independientes del pseudo-rol PUBLIC: revocar de
-- PUBLIC no las toca.
--
-- El resultado era que el advisor de seguridad marcaba las seis
-- funciones como ejecutables sin autenticación vía
-- /rest/v1/rpc/<nombre>. La anon key es pública por definición en una
-- web, así que cualquiera podía llamar
--     POST /rest/v1/rpc/registrar_pago_y_conciliar
-- con el monto de una clase y confirmarse la reserva sin haber pagado
-- un peso.
--
-- Verificado después de aplicar: has_function_privilege devuelve false
-- para anon y authenticated en las seis, y true para service_role.
-- =====================================================================

revoke execute on function tomar_cupo(uuid, text, text, text, text)          from anon, authenticated;
revoke execute on function liberar_cupos_expirados()                          from anon, authenticated;
revoke execute on function generar_codigo_reserva()                           from anon, authenticated;
revoke execute on function conciliar_reserva(text)                            from anon, authenticated;
revoke execute on function marcar_pendiente_validacion(text)                  from anon, authenticated;
revoke execute on function registrar_pago_y_conciliar(text,int,timestamptz,text,text,text,numeric,text,text)
  from anon, authenticated;

-- Que las funciones futuras tampoco nazcan abiertas.
alter default privileges in schema public
  revoke execute on functions from anon, authenticated;
