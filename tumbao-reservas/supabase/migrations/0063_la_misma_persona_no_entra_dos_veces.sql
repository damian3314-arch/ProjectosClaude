-- 0063 — La misma persona no entra dos veces a la misma clase
--
-- QUÉ PASÓ, EL 31 DE AGOSTO
-- Eliana Pulgarín reservó dos veces para la clase de las 19:00, con
-- cuatro minutos de diferencia (T5PKQ5 a las 12:16 y ABKXMH a las
-- 12:20, hora Bogotá). La primera se concilió sola contra su depósito
-- de $15.000. La segunda se confirmó A MANO desde el panel, a las
-- 13:54, con la referencia "018000931987".
--
-- Ese número no es una referencia de pago: es el teléfono de atención
-- de Bancolombia, el que sale al pie de todas las alertas ("Dudas al
-- 018000931987"). Quien confirmó copió el número equivocado de lo que
-- tenía delante.
--
-- Resultado: dos entradas confirmadas, un solo pago de $15.000, y el
-- cierre del día contando 6 clases sueltas cuando entraron 5.
--
-- POR QUÉ EL FRENO DE LA 0056 NO LO EVITÓ
-- La 0056 exige teclear una referencia para poder confirmar a mano, y
-- la idea era que copiar algo obligara a mirar el comprobante. No es
-- así: obliga a teclear cuatro caracteres, y cualquier número los
-- cumple. Y sobre todo, ese freno vigila la cosa equivocada. El daño
-- no lo hizo la referencia mala — lo hizo dejar confirmar DOS VECES a
-- la misma persona para la misma clase.
--
-- Validar la forma de la referencia no sirve: las dos legítimas de ese
-- mismo día fueron "M18066236" y
-- "50906185520310483634953761565881950". No hay un formato común que
-- se pueda exigir sin rechazar pagos buenos.
--
-- LO QUE SÍ SE PUEDE COMPROBAR
-- Que no haya ya una confirmada, en esa misma clase, con el mismo
-- teléfono y el mismo nombre.
--
-- Los dos datos, no uno:
--   · solo el teléfono rompería los grupos. Ese mismo día Andrea
--     Ospino y Elayne Jiménez entraron juntas con un depósito de
--     $30.000 desde un mismo teléfono, y son dos personas de verdad.
--   · solo el nombre chocaría con dos tocayas que no se conocen.
--
-- Y se exceptúa al propio grupo, que se confirma de una y comparte
-- depósito a propósito.
--
-- SI DE VERDAD SON DOS
-- Si alguien reserva dos cupos para venir con una amiga, el camino es
-- poner el nombre de la amiga en el segundo, o usar la reserva de
-- grupo. El mensaje del error lo dice, porque quien lo va a leer está
-- en recepción con la persona delante.

do $$
declare
  def   text;
  ini   int;
  nuevo text;
begin
  select pg_get_functiondef(p.oid) into def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_confirmar'
     and pg_get_function_identity_arguments(p.oid)
         = 'p_token text, p_codigo text, p_pago_id uuid, p_referencia text';

  if def is null then
    raise exception 'no está admin_confirmar(text,text,uuid,text); ¿falta la 0056?';
  end if;

  if position('0063:' in def) > 0 then
    raise notice '0063 ya estaba puesta, no se toca';
    return;
  end if;

  -- Va justo antes de amarrar el depósito: si la persona ya entró, no
  -- hay que gastar el pago de nadie averiguándolo.
  ini := position('  if p_pago_id is not null then' in def);
  if ini = 0 then
    raise exception 'no se encontró dónde injertar el freno en admin_confirmar';
  end if;

  nuevo :=
    '  -- 0063: la misma persona no entra dos veces a la misma clase.' || E'\n' ||
    '  -- Se miran teléfono Y nombre: solo el teléfono rompería los' || E'\n' ||
    '  -- grupos (dos personas de verdad reservando desde un móvil), y' || E'\n' ||
    '  -- solo el nombre chocaría con dos tocayas. El propio grupo se' || E'\n' ||
    '  -- exceptúa: se confirma de una y comparte depósito a propósito.' || E'\n' ||
    '  if exists (select 1 from reservas otra' || E'\n' ||
    '              where otra.clase_id = v_reserva.clase_id' || E'\n' ||
    '                and otra.estado = ''confirmada''' || E'\n' ||
    '                and coalesce(otra.grupo_id, otra.id) <> v_grupo' || E'\n' ||
    '                and otra.telefono is not distinct from v_reserva.telefono' || E'\n' ||
    '                and lower(unaccent(btrim(coalesce(otra.nombre, ''''))))' || E'\n' ||
    '                  = lower(unaccent(btrim(coalesce(v_reserva.nombre, ''''))))) then' || E'\n' ||
    '    return jsonb_build_object(''ok'', false, ''error'', ''YA_ENTRO'',' || E'\n' ||
    '      ''mensaje'', ''Esa persona ya tiene una reserva confirmada en esta ''' || E'\n' ||
    '                || ''misma clase. Si de verdad son dos, pon el nombre de la ''' || E'\n' ||
    '                || ''otra persona en esta reserva o hazla como grupo.'');' || E'\n' ||
    '  end if;' || E'\n' || E'\n';

  execute left(def, ini - 1) || nuevo || substr(def, ini);
end $$;

-- Los permisos no viajan con CREATE OR REPLACE, pero tampoco se
-- pierden: la firma no cambia. Se reafirman por si acaso, que es lo
-- que se echó de menos en la 0056.
revoke execute on function admin_confirmar(text, text, uuid, text)
  from public, anon, authenticated;
grant  execute on function admin_confirmar(text, text, uuid, text)
  to service_role;
