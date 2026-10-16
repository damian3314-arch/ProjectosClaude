-- ---------------------------------------------------------------------
-- 0051 — Entradas: efectivo de clase suelta, y transferencia por
-- recepción y por página
--
-- EL PROBLEMA
-- Tania cruza la tirilla contra su propio conteo de la puerta: por cada
-- clase anota cuántas personas de clase suelta entraron. Hoy la tirilla
-- no responde eso. "Efectivo" mezcla clase suelta con mensualidades y
-- cumpleaños, y "Transferencia" es lo que confirmó el banco ESE día sin
-- importar de qué clase es (incluye anticipos de otro día). Ninguna de
-- las dos contesta "cuánto de clase suelta entró hoy, y por dónde".
--
-- POR QUÉ NO SON CUATRO CASILLAS
-- El primer diseño cruzaba origen (recepción/página) × medio
-- (efectivo/transferencia). Se descartó: en Caja hay un botón genérico
-- "Clase suelta $15.000" que registra el efectivo SIN crear una
-- reserva —confirmado que se usa de verdad, a veces—, así que un cobro
-- en efectivo puede no tener ninguna fila en `reservas` de la que leer
-- el origen. Cruzarlo igual habría significado inventar un origen para
-- esa plata. Página, en cambio, nunca cobra en efectivo —no es una
-- opción en el formulario—, así que ahí "efectivo" siempre iba a ser
-- cero: la cuarta casilla no aportaba nada, solo un cero fijo.
--
-- LO QUE HACE
-- Tres números, cada uno con una sola fuente confiable:
--
--   Efectivo (clase suelta)      -> caja_movimientos, concepto
--                                    'clase_suelta', medio 'efectivo',
--                                    del día. Da igual si el cobro vino
--                                    de apuntar a mano, de "paga al
--                                    llegar" o del botón genérico: los
--                                    tres pasan por ahí.
--   Transferencia por recepción  -> reservas confirmadas, suelta, con
--   Transferencia por página        pago_id (ya cruzada con el banco),
--                                    de una clase de HOY, agrupadas por
--                                    si el origen es 'recepcion' o no.
--                                    Una transferencia SIEMPRE deja
--                                    fila en reservas —es lo único que
--                                    la cruza con el depósito—, así que
--                                    aquí sí hay de dónde leer el origen.
-- ---------------------------------------------------------------------
do $$
declare
  v_def text;
  v_a   text;
  v_b   text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if v_def is null then
    raise exception 'no existe caja_del_dia';
  end if;
  if position('v_entra_ef' in v_def) > 0 then
    raise notice 'ya estaba aplicada';
    return;
  end if;

  -- 1. Declarar las variables nuevas.
  v_a := '  v_res_dictadas int; v_res_dictadas_n int;';
  v_b := v_a || E'\n' ||
    '  v_entra_ef        int; v_entra_ef_n        int;' || E'\n' ||
    '  v_entra_recep_tr  int; v_entra_recep_tr_n  int;' || E'\n' ||
    '  v_entra_pag_tr    int; v_entra_pag_tr_n    int;';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro la declaracion de v_res_dictadas exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  -- 2. Las consultas. La de efectivo reusa el mismo filtro de dia que
  -- ya usa v_ing_ef, solo que acotada al concepto de clase suelta. La
  -- de transferencia reusa el mismo filtro de reservas_dictadas —
  -- confirmada, suelta, clase de HOY— pero exigiendo pago_id (si no
  -- tiene, esa plata no es transferencia: es la de arriba) y separando
  -- por origen.
  v_a := '  select coalesce(sum(c.precio_cop), 0), count(*)
    into v_res_dictadas, v_res_dictadas_n
    from reservas r join clases c on c.id = r.clase_id
   where r.estado = ''confirmada'' and r.tipo = ''suelta''
     and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia;';
  v_b := v_a || E'\n\n' ||
    '  select coalesce(sum(valor_cop), 0), count(*)' || E'\n' ||
    '    into v_entra_ef, v_entra_ef_n' || E'\n' ||
    '    from caja_movimientos' || E'\n' ||
    '   where dia = v_dia and not anulado' || E'\n' ||
    '     and sentido = ''ingreso'' and medio = ''efectivo''' || E'\n' ||
    '     and concepto = ''clase_suelta'';' || E'\n\n' ||
    '  -- Una transferencia siempre queda cruzada con una fila en' || E'\n' ||
    '  -- reservas (es lo que la liga al deposito), asi que aqui si hay' || E'\n' ||
    '  -- de donde leer si vino de recepcion o de la pagina.' || E'\n' ||
    '  select' || E'\n' ||
    '    coalesce(sum(c.precio_cop) filter (where r.origen = ''recepcion''), 0),' || E'\n' ||
    '    count(*) filter (where r.origen = ''recepcion''),' || E'\n' ||
    '    coalesce(sum(c.precio_cop) filter (where r.origen <> ''recepcion''), 0),' || E'\n' ||
    '    count(*) filter (where r.origen <> ''recepcion'')' || E'\n' ||
    '    into v_entra_recep_tr, v_entra_recep_tr_n, v_entra_pag_tr, v_entra_pag_tr_n' || E'\n' ||
    '    from reservas r join clases c on c.id = r.clase_id' || E'\n' ||
    '   where r.estado = ''confirmada'' and r.tipo = ''suelta'' and r.pago_id is not null' || E'\n' ||
    '     and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia;';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro la consulta de reservas_dictadas exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  -- 3. Sacarlas en la respuesta, agrupadas: 'entradas' -> efectivo_cop/n,
  -- recepcion_transferencia_cop/n, pagina_transferencia_cop/n.
  v_a := '    ''reservas_dictadas_cop'', v_res_dictadas,
    ''reservas_dictadas_n'',   v_res_dictadas_n,';
  v_b := v_a || E'\n' ||
    '    ''entradas'', jsonb_build_object(' || E'\n' ||
    '      ''efectivo_cop'', v_entra_ef, ''efectivo_n'', v_entra_ef_n,' || E'\n' ||
    '      ''recepcion_transferencia_cop'', v_entra_recep_tr,' || E'\n' ||
    '      ''recepcion_transferencia_n'',   v_entra_recep_tr_n,' || E'\n' ||
    '      ''pagina_transferencia_cop'', v_entra_pag_tr,' || E'\n' ||
    '      ''pagina_transferencia_n'',   v_entra_pag_tr_n' || E'\n' ||
    '    ),';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro reservas_dictadas_n en la respuesta exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  execute v_def;
end $$;
