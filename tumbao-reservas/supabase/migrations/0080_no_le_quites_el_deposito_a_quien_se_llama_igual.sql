-- 0080 · No le quites el depósito a quien se llama igual.
--
-- EL CASO REAL
-- El 11 de septiembre el cierre decía 6 reservas por página y en la web
-- había 7. Al mirarlo apareció esto:
--
--   16:31  Xiomara Hoyos reserva el sábado 9:00 am
--   16:47  Ludys Herazo reserva el viernes 7:00 pm
--   16:49  entra un deposito de LUDYS MARIA HERAZO HERAZO por $15.000
--          → el sistema se lo dio a XIOMARA
--   17:28  la cajera confirma a Ludys a mano, tecleando la referencia
--
-- similitud_nombre('Xiomara Hoyos', 'LUDYS MARIA HERAZO HERAZO') = 0.00
-- similitud_nombre('Ludys Herazo',  'LUDYS MARIA HERAZO HERAZO') = 1.00
--
-- El depósito se lo llevó la reserva con parecido CERO mientras la
-- coincidencia perfecta esperaba.
--
-- LOS DOS DEFECTOS QUE LO PERMITEN
--
--   1. `buscar_deposito_libre` acepta el candidato sin mirar el nombre
--      cuando es el único (`n = 1`). Un parecido de 0.00 pasa igual que
--      uno de 1.00.
--   2. `conciliar_pendientes` recorre las reservas POR ORDEN DE LLEGADA,
--      así que la más vieja se lleva el depósito aunque otra le calce
--      perfecto. Es codicioso: el primero que pasa, agarra.
--
-- CUÁNTO PESA, MEDIDO CONTRA PRODUCCIÓN
--   316 reservas enlazadas solas desde el arranque
--   104 con parecido CERO (33%)
--    13 de esas tenían OTRA reserva viva que sí le calzaba al remitente
--
-- Esas 13 son el error de verdad. Las otras 91 son legítimas: paga la
-- mamá, la pareja, una amiga. Por eso NO se puede exigir que el nombre
-- cuadre siempre — eso mandaría un tercio de las reservas a confirmación
-- manual y ahogaría a la cajera, que es lo contrario de lo que se busca.
--
-- LA REGLA QUE SE AÑADE, UNA SOLA
--
--   Un depósito no se lo lleva una reserva si OTRA reserva viva, que
--   también lo está esperando, le calza claramente mejor por nombre.
--
-- «Claramente mejor» es: la otra saca al menos 0.5 y saca más que esta.
-- Con eso el caso del 11 se arregla solo —Ludys 1.00 le gana a Xiomara
-- 0.00— y el caso de la mamá que paga no se toca: si nadie más le calza
-- al remitente, no hay a quién cederle nada y el enlace se hace igual.
--
-- Y SE CURA SOLO. El bloqueo dura mientras la otra reserva siga viva. Si
-- esa otra nunca paga y vence, el depósito queda libre otra vez y la
-- primera lo toma en la siguiente pasada. No hay forma de quedarse
-- trabado esperando a alguien que no llegó.
--
-- NO SE TOCA EL GRUPO PROPIO. Tres amigas que reservan juntas son varias
-- filas del mismo grupo y comparten un depósito: si contaran como «otra
-- reserva», se bloquearían entre ellas y ninguna cobraría nunca.
--
-- Se parchea EN SITIO sobre la definición viva, no se reescribe:
-- producción trae arreglos que no están en este repo.

do $mig$
declare
  v_src   text;
  v_new   text;
  v_ancla text;
begin
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'buscar_deposito_libre';

  if v_src is null then
    raise exception '0080: no existe public.buscar_deposito_libre';
  end if;

  if position('0080:' in v_src) > 0 then
    raise notice '0080: ya aplicado, no se toca';
    return;
  end if;

  v_new := v_src;

  -- Hace falta saber de qué grupo es esta reserva, para no bloquearse
  -- contra sus propias compañeras.
  v_ancla := E'  v_pasada int;\nbegin';
  if position(v_ancla in v_new) = 0 then
    raise exception '0080: no se encontro el declare';
  end if;
  v_new := replace(v_new, v_ancla,
    E'  v_pasada int;\n' ||
    E'  v_grupo  uuid;   -- 0080: para no bloquearse contra su propio grupo\n' ||
    E'begin');

  v_ancla := E'  v_corte := inicio_produccion()::timestamp at time zone ''America/Bogota'';';
  if position(v_ancla in v_new) = 0 then
    raise exception '0080: no se encontro el corte';
  end if;
  v_new := replace(v_new, v_ancla,
    v_ancla || E'\n  v_grupo := grupo_de(p_reserva_id);');

  -- La regla.
  v_ancla :=
    E'    with cand as (\n' ||
    E'      select p.id, similitud_nombre(v_quien, p.remitente) as pt\n' ||
    E'        from pagos p\n' ||
    E'       where not p.consumido\n' ||
    E'         and p.valor_cop = v_precio\n' ||
    E'         and p.fecha_pago >= v_corte\n' ||
    E'         and p.fecha_pago between v_desde and v_hasta\n' ||
    E'    ), orden as (\n' ||
    E'      select id, pt,\n' ||
    E'             count(*) over ()                     as n,\n' ||
    E'             row_number() over (order by pt desc) as rn,\n' ||
    E'             lead(pt)     over (order by pt desc) as segundo\n' ||
    E'        from cand\n' ||
    E'    )';
  if position(v_ancla in v_new) = 0 then
    raise exception '0080: no se encontro el bloque cand/orden';
  end if;

  v_new := replace(v_new, v_ancla,
    E'    with cand as (\n' ||
    E'      select p.id, similitud_nombre(v_quien, p.remitente) as pt,\n' ||
    E'             -- 0080: cuanto le calza ESE MISMO deposito a otra\n' ||
    E'             -- reserva viva que tambien lo esta esperando. Si a\n' ||
    E'             -- otra le calza claramente mejor, este deposito no es\n' ||
    E'             -- de esta reserva: es de aquella.\n' ||
    E'             coalesce((\n' ||
    E'               select max(similitud_nombre(\n' ||
    E'                        coalesce(q.pagador_nombre, q.nombre), p.remitente))\n' ||
    E'                 from reservas q\n' ||
    E'                where coalesce(q.grupo_id, q.id) <> v_grupo\n' ||
    E'                  and q.pago_id is null\n' ||
    E'                  and q.estado in (''pendiente_pago'',''verificando'',''pendiente_validacion'')\n' ||
    E'                  and (q.estado <> ''pendiente_pago''\n' ||
    E'                       or q.expira_en is null or q.expira_en > now())\n' ||
    E'                  and precio_del_grupo(q.id) = v_precio\n' ||
    E'                  -- Solo si ese deposito le cae dentro de SU ventana:\n' ||
    E'                  -- una reserva de ayer no reclama el de hoy.\n' ||
    E'                  and p.fecha_pago between\n' ||
    E'                        coalesce(q.pagado_en, q.created_at) - interval ''30 minutes''\n' ||
    E'                    and coalesce(q.pagado_en, q.created_at) + interval ''3 hours''\n' ||
    E'             ), -1) as pt_ajeno\n' ||
    E'        from pagos p\n' ||
    E'       where not p.consumido\n' ||
    E'         and p.valor_cop = v_precio\n' ||
    E'         and p.fecha_pago >= v_corte\n' ||
    E'         and p.fecha_pago between v_desde and v_hasta\n' ||
    E'    ), orden as (\n' ||
    E'      select id, pt,\n' ||
    E'             count(*) over ()                     as n,\n' ||
    E'             row_number() over (order by pt desc) as rn,\n' ||
    E'             lead(pt)     over (order by pt desc) as segundo\n' ||
    E'        from cand\n' ||
    E'       -- 0080: se cede el deposito a quien le calza mejor. El\n' ||
    E'       -- bloqueo dura solo mientras esa otra siga viva: si vence\n' ||
    E'       -- sin pagar, el deposito vuelve a quedar disponible.\n' ||
    E'       where not (pt_ajeno >= 0.5 and pt_ajeno > pt)\n' ||
    E'    )');

  v_new := replace(v_new, E'AS $function$\ndeclare',
    E'AS $function$\n-- 0080: un deposito no se lo lleva quien no se llama asi si otra\n' ||
    E'-- reserva viva le calza mejor.\ndeclare');

  execute v_new;
end
$mig$;
