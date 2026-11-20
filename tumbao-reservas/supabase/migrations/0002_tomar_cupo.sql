-- =====================================================================
-- Tumbao Reservas — toma de cupo y expiración
--
-- ESTA FUNCIÓN ES EL CORAZÓN DEL SISTEMA. No reemplazar por lógica en
-- TypeScript: el bloqueo de fila es lo único que impide vender dos veces
-- el último cupo.
--
-- Basada en el blueprint, con cuatro correcciones sobre el original.
-- Cada una está marcada con [FIX] y explicada donde ocurre.
-- =====================================================================

create extension if not exists pgcrypto;


-- ---------------------------------------------------------------------
-- Generador de códigos
--
-- [FIX 1] El original hacía:
--   upper(translate(encode(gen_random_bytes(8),'base64'), '+/=0O1lI',''))
-- translate borra la 'O' y la 'I' mayúsculas, pero deja la 'o' y la 'i'
-- minúsculas — y el upper() posterior las convierte de vuelta en 'O' e
-- 'I'. Medido sobre 5.000 muestras: 19,1% de los códigos contenían
-- justo los caracteres que se querían evitar.
--
-- Aquí se construye desde un alfabeto explícito. Lo que no está en el
-- alfabeto no puede salir.
-- ---------------------------------------------------------------------
create or replace function generar_codigo_reserva() returns text
language plpgsql
as $$
declare
  -- Sin 0/O, 1/I/L: son los que se confunden dictando por teléfono.
  v_alfabeto constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_bytes    bytea := gen_random_bytes(6);
  v_codigo   text := '';
  i          int;
begin
  for i in 0..5 loop
    v_codigo := v_codigo || substr(
      v_alfabeto,
      1 + (get_byte(v_bytes, i) % length(v_alfabeto)),
      1);
  end loop;
  return v_codigo;
end;
$$;


-- ---------------------------------------------------------------------
-- tomar_cupo
-- ---------------------------------------------------------------------
create or replace function tomar_cupo(
  p_clase_id uuid,
  p_nombre   text,
  p_telefono text,
  p_email    text,
  p_origen   text
) returns reservas
language plpgsql
security definer
-- [FIX 2] El original era SECURITY DEFINER sin search_path fijo. Eso es
-- un vector de escalada de privilegios: quien pueda crear objetos en un
-- esquema del search_path puede secuestrar la resolución de nombres
-- dentro de la función. El advisor de Supabase lo marca.
set search_path = public, extensions, pg_temp
as $$
declare
  v_clase    clases%rowtype;
  v_reserva  reservas%rowtype;
  v_codigo   text;
  v_intentos int := 0;
begin
  -- FOR UPDATE bloquea la fila: cualquier otra transacción que quiera
  -- esta misma clase espera aquí hasta que terminemos. Sin esto hay
  -- sobreventa. (Verificado: 20 llamadas simultáneas sobre una clase de
  -- cupo 3 → exactamente 3 reservas y 17 SIN_CUPO.)
  select * into v_clase from clases where id = p_clase_id for update;

  if not found then                              raise exception 'CLASE_NO_EXISTE'; end if;
  if not v_clase.activa then                     raise exception 'CLASE_INACTIVA'; end if;
  if v_clase.fecha_hora < now() then             raise exception 'CLASE_YA_PASO'; end if;
  if v_clase.cupo_tomado >= v_clase.cupo_total then raise exception 'SIN_CUPO';   end if;

  update clases set cupo_tomado = cupo_tomado + 1 where id = p_clase_id;

  -- [FIX 3] El original elegía el código con un `not exists (...)` y
  -- después insertaba. Entre la comprobación y el insert cabe otra
  -- transacción: si ambas escogen el mismo código, la segunda revienta
  -- con unique_violation y aborta la reserva entera. Aquí el insert va
  -- dentro del loop y el conflicto solo cuesta otra vuelta.
  loop
    v_intentos := v_intentos + 1;
    v_codigo := generar_codigo_reserva();
    begin
      insert into reservas (codigo, clase_id, nombre, telefono, email, origen)
      values (v_codigo, p_clase_id, p_nombre, p_telefono, p_email, p_origen)
      returning * into v_reserva;
      exit;
    exception when unique_violation then
      if v_intentos >= 5 then raise; end if;
    end;
  end loop;

  return v_reserva;
end;
$$;


-- ---------------------------------------------------------------------
-- liberar_cupos_expirados
-- Libera cupos de reservas que nunca pagaron. La llama el cron.
-- ---------------------------------------------------------------------
create or replace function liberar_cupos_expirados() returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_n int;
begin
  -- [FIX 4] El original terminaba con `get diagnostics v_n = row_count`,
  -- que cuenta las filas de la ÚLTIMA sentencia — el update sobre
  -- `clases`, no las reservas expiradas. Medido: con 7 reservas vencidas
  -- de una sola clase devolvía 1. Los cupos se liberaban bien, pero el
  -- log del cron mentía. Aquí se suma lo realmente liberado.
  with liberadas as (
    update reservas set estado = 'expirada', updated_at = now()
    where estado = 'pendiente_pago' and expira_en < now()
    returning clase_id
  ),
  por_clase as (
    select clase_id, count(*)::int as n from liberadas group by clase_id
  ),
  ajuste as (
    update clases c set cupo_tomado = greatest(0, c.cupo_tomado - p.n)
    from por_clase p
    where c.id = p.clase_id
    returning p.n
  )
  select coalesce(sum(n), 0)::int into v_n from ajuste;

  return v_n;
end;
$$;
