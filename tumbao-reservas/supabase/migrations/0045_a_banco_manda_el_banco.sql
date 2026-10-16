-- ---------------------------------------------------------------------
-- 0045 — El total a banco lo pone el banco, no una suma a mano
--
-- LO QUE PASÓ EL 20 DE AGOSTO
-- El cierre decía que a banco habían entrado 490.000. Al banco entraron
-- 475.000. Y la cajera, en su reporte a mano, decía 445.000.
--
-- Tres números para la misma cosa, y ninguno de los tres coincidía con
-- otro. Ese número se copia después en AdminGym, así que el error no se
-- quedaba en la pantalla: viajaba.
--
-- DE DÓNDE SALÍA CADA UNO
--   475.000  el banco, sumando sus 16 depósitos del día
--   490.000  el cierre: transferencias del mostrador + reservas cobradas
--   445.000  la cajera, que sumó a ojo y se saltó un depósito de 30.000
--
-- Los 15.000 que le sobraban al cierre eran un movimiento registrado a
-- mano SIN depósito detrás: la misma plata apuntada dos veces. Y cuadra
-- exacto por el otro lado — 355.000 de movimientos enlazados a un
-- depósito + 120.000 de reservas que entraron solas = 475.000 clavados.
--
-- EL ARREGLO
-- `ingresos_a_banco` pasa a ser `v_recibido`, que es lo que el banco
-- reporta. No hay que sumarlo, no se puede equivocar, y es el único de
-- los tres que describe la realidad.
--
-- Lo registrado a mano deja de sumar aquí y pasa a ser lo que siempre
-- debió ser: una comprobación. Lo que se apuntó a mano y el banco NO ha
-- reportado ya salía aparte en `sin_respaldo_cop`; ahora la pantalla lo
-- dice fuerte en vez de sumarlo en silencio.
--
-- POR QUÉ NO SE SUMA sin_respaldo
-- Tentaba hacer `v_recibido + v_sin_resp` para cubrir el depósito que
-- todavía no ha llegado por correo. No: no se puede distinguir "va a
-- llegar" de "está apuntado de más", y el 20 de agosto era lo segundo.
-- Sumar a ciegas sería volver a inflar el total. Se enseña aparte y lo
-- decide una persona, que es quien sabe si el aviso viene en camino.
--
-- Se parchea sobre pg_get_functiondef: caja_del_dia es larga y ya la
-- han tocado la 0030, la 0031, la 0038 y la 0039.
-- ---------------------------------------------------------------------
do $$
declare
  v_def   text;
  v_viejo text;
  v_nuevo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';

  v_viejo := '''ingresos_a_banco'', v_ing_tr + v_reservas,';
  v_nuevo := '''ingresos_a_banco'', v_recibido,';

  if v_def is null then
    raise exception 'no existe caja_del_dia';
  end if;
  -- Si ya está aplicada, no hay nada que hacer: así se puede volver a
  -- pegar sin miedo.
  if position(v_nuevo in v_def) > 0 then
    raise notice 'ya estaba aplicada';
    return;
  end if;
  if (length(v_def) - length(replace(v_def, v_viejo, ''))) / length(v_viejo) <> 1 then
    raise exception 'el trozo a parchear no aparece exactamente una vez en caja_del_dia';
  end if;

  execute replace(v_def, v_viejo, v_nuevo);
end $$;
