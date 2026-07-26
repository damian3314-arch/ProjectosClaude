-- =====================================================================
-- Desempate por el nombre de quien envió el dinero
--
-- EL PROBLEMA
-- El QR Bre-B es estático (verificado en su payload EMVCo: tag 01 = 11)
-- y el precio de la clase suelta es fijo. No se puede pedir un monto
-- distinto a cada persona: solo pagan quienes no tienen mensualidad, y
-- el valor es el de la clase.
--
-- Consecuencia: dos personas pagando en la misma ventana producen dos
-- pagos idénticos en monto. Antes eso mandaba las DOS a validación
-- humana, que en hora pico puede ser la mayoría.
--
-- LA SEÑAL QUE SÍ EXISTE
-- El correo del banco trae el nombre de quien envió:
--   "recibiste una transferencia de CAMILA ROJAS DUQUE por $15000.00"
--
-- Se compara contra el nombre que la persona escribió al reservar.
--
-- POR QUÉ NO LA HORA
-- El pago siempre llega después de la reserva, y eso ya se usa como
-- filtro de ventana. Pero dentro de esa ventana dos personas pueden
-- reservar con segundos de diferencia y pagar en cualquier orden, así
-- que el orden temporal no distingue quién es quién. El nombre sí.
-- =====================================================================

create extension if not exists unaccent with schema extensions;


-- Tokens normalizados de un nombre: sin acentos, en mayúsculas, sin
-- palabras de menos de 3 letras (para que "de", "la", "Jo" no cuenten).
create or replace function tokens_nombre(p_nombre text) returns text[]
language sql
immutable
set search_path = public, extensions, pg_temp
as $$
  select coalesce(array_agg(t), array[]::text[])
  from (
    select distinct t
    from regexp_split_to_table(
           upper(extensions.unaccent(coalesce(p_nombre, ''))),
           '[^A-Z]+'
         ) AS t
    where length(t) >= 3
  ) x;
$$;


-- Fracción de los tokens del nombre de la reserva que aparecen en el
-- nombre del remitente.
--   'Camila'       vs 'CAMILA ROJAS DUQUE' -> 1.00
--   'Camila Rojas' vs 'CAMILA GOMEZ'       -> 0.50
--   'Ana'          vs 'CAMILA ROJAS DUQUE' -> 0.00
--   'José'         vs 'JOSE ANDRES MERCADO'-> 1.00  (acentos resueltos)
create or replace function similitud_nombre(p_reserva text, p_remitente text)
returns numeric
language sql
immutable
set search_path = public, extensions, pg_temp
as $$
  select case
    when cardinality(tokens_nombre(p_reserva)) = 0
      or cardinality(tokens_nombre(p_remitente)) = 0
    then 0::numeric
    else (
      select count(*)::numeric / cardinality(tokens_nombre(p_reserva))
      from unnest(tokens_nombre(p_reserva)) tr
      where tr = any (tokens_nombre(p_remitente))
    )
  end;
$$;

revoke execute on function tokens_nombre(text)          from public, anon, authenticated;
revoke execute on function similitud_nombre(text, text) from public, anon, authenticated;
