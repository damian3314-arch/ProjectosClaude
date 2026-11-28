-- ---------------------------------------------------------------------
-- 0055 — Cruzar también la reserva que no alcanzó a avisar el pago
--
-- EL PROBLEMA
-- La conciliación solo miraba reservas en 'verificando' o
-- 'pendiente_validacion'. Las dos exigen lo mismo: que la persona haya
-- alcanzado a pulsar "ya pagué". Quien reserva, se le sale la página y
-- transfiere igual se queda en 'pendiente_pago', y ahí es invisible: su
-- plata puede estar en el banco, con su nombre y su monto exacto, y
-- nadie la mira. A los treinta minutos la reserva expira.
--
-- Pasó hoy, y el chat lo dice con todas las letras: "reservé dos cupos
-- para las 8 am / pero se me salió de la página / y no pude terminar".
-- Duvis y Laury reservaron a las 15:52, transfirieron $30.000 a las
-- 15:58 —dentro de su ventana, que vencía 16:22— y hubo que confirmarlas
-- a mano a las 16:13.
--
-- CUÁNTO PESA
-- Medido sobre 21 días, aplicando el MISMO criterio de seguridad que ya
-- usa el sistema (monto exacto del grupo, ventana de tiempo, y el nombre
-- del remitente desempatando cuando hay varios candidatos):
--
--   49 grupos se quedaron en pendiente_pago o expiraron
--   27 de ellos tenían un depósito que casa sin ambigüedad
--   25 de esos 27 lo tenían ANTES de expirar  -> 26 personas, $390.000
--
-- LO QUE HACE
-- Añade 'pendiente_pago' a los estados que la conciliación considera. No
-- cambia ni una regla de decisión: el monto, la ventana y el desempate
-- por nombre siguen siendo los mismos. Solo deja de exigir que la
-- persona haya avisado.
--
-- POR QUÉ NO HAY SOBREVENTA
-- Solo se cruzan reservas VIVAS. Una en 'pendiente_pago' ya tiene su
-- cupo apartado, así que confirmarla no consume uno nuevo. Las expiradas
-- se quedan fuera a propósito: ahí el cupo ya se soltó y pudo venderse a
-- otra persona. Se añade además una guarda explícita por si el barrido
-- de vencidos todavía no ha pasado y la fila sigue en pendiente_pago con
-- la hora ya cumplida.
--
-- LO QUE NO ARREGLA
-- Los 2 casos de 21 días donde la plata llegó DESPUÉS de expirar siguen
-- yendo a mano, y los 13 ambiguos también. Eso es correcto: adivinar ahí
-- es peor que preguntar.
-- ---------------------------------------------------------------------
do $$
declare
  v_fn   text;
  v_def  text;
  v_a    text := '''verificando'', ''pendiente_validacion''';
  v_b    text := '''pendiente_pago'', ''verificando'', ''pendiente_validacion''';
  v_n    int;
begin
  foreach v_fn in array array['buscar_deposito_libre', 'conciliar_pendientes',
                              'cruzar_reserva', 'registrar_pago_y_conciliar']
  loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;
    if v_def is null then
      raise exception 'no existe la funcion %', v_fn;
    end if;

    if position('0055:' in v_def) > 0 then
      raise notice '% ya estaba aplicada', v_fn;
      continue;
    end if;

    v_n := (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a);
    if v_n <> 1 then
      raise exception 'en % se esperaba la lista de estados una vez, hay %', v_fn, v_n;
    end if;
    v_def := replace(v_def, v_a, v_b);

    -- La guarda de vida. Va donde se decide por una reserva concreta: si
    -- su hora ya pasó, el cupo pudo soltarse y venderse a otra persona.
    if v_fn = 'buscar_deposito_libre' then
      v_def := replace(v_def,
        '  v_precio := precio_del_grupo(p_reserva_id);',
        '  -- 0055: una pendiente_pago solo cuenta mientras siga viva. El' || E'\n' ||
        '  -- barrido de vencidos corre cada pocos minutos, asi que puede' || E'\n' ||
        '  -- haber filas con la hora cumplida y el estado sin cambiar.' || E'\n' ||
        '  if v_r.estado = ''pendiente_pago''' || E'\n' ||
        '     and v_r.expira_en is not null and v_r.expira_en <= now() then' || E'\n' ||
        '    return null;' || E'\n' ||
        '  end if;' || E'\n\n' ||
        '  v_precio := precio_del_grupo(p_reserva_id);');
    end if;

    if v_fn = 'conciliar_pendientes' then
      v_def := replace(v_def,
        '       and r.pago_id is null',
        '       and r.pago_id is null' || E'\n' ||
        '       -- 0055: las pendiente_pago, solo mientras sigan vivas.' || E'\n' ||
        '       and (r.estado <> ''pendiente_pago''' || E'\n' ||
        '            or r.expira_en is null or r.expira_en > now())');
    end if;

    if v_fn = 'cruzar_reserva' then
      v_def := replace(v_def,
        '       and pago_id is null',
        '       and pago_id is null' || E'\n' ||
        '       -- 0055: no revivir una fila que ya vencio.' || E'\n' ||
        '       and (estado <> ''pendiente_pago''' || E'\n' ||
        '            or expira_en is null or expira_en > now())');
    end if;

    if v_fn = 'registrar_pago_y_conciliar' then
      v_def := replace(v_def,
        '     and r.pago_id is null',
        '     and r.pago_id is null' || E'\n' ||
        '     -- 0055: las pendiente_pago, solo mientras sigan vivas.' || E'\n' ||
        '     and (r.estado <> ''pendiente_pago''' || E'\n' ||
        '          or r.expira_en is null or r.expira_en > now())');
    end if;

    execute v_def;
  end loop;
end $$;
