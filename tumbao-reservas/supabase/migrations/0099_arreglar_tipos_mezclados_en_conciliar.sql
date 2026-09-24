-- 0099 · Arreglar uuid contra bigint en registrar_pago_y_conciliar.
--
-- La 0098 metió reservas (id uuid) y tiqueteras (id bigint) en la misma
-- tabla temporal `_cand (id uuid, ...)`, y el `union all` entre
-- `select r.id, ...` y `select t.id, ...` truena en seco:
--
--   ERROR: UNION types uuid and bigint cannot be matched
--
-- Esto se detectó DENTRO de la misma sesión que aplicó la 0098, con el
-- propio ensayo de verificación -- antes de que ningún correo real del
-- banco pasara por ahí, pero después de que la función ya estaba viva en
-- producción unos minutos. Mientras estuvo así, CUALQUIER pago -- de una
-- suelta o de una tiquetera -- habría fallado al querer conciliarse.
--
-- EL ARREGLO
-- `_cand.id` pasa a `text` (guarda el uuid y el bigint como texto), y se
-- vuelve a convertir al tipo real de cada lado al usarlo:
--
--   reserva.id = v_id_ganador::uuid
--   tiquetera.id = v_id_ganador::bigint
--
-- Se aplica EN SITIO, como siempre, con anclajes verificados por
-- posición contra la definición viva antes de escribir esta migración
-- (en este caso, contra la propia 0098 recién aplicada).

do $$
declare
  v_src text;
begin
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'registrar_pago_y_conciliar' and p.prokind = 'f';

  if position('  v_id_ganador text;' in v_src) > 0 then
    raise notice '0099: ya aplicado, no se toca';
    return;
  end if;

  if position('  v_id_ganador uuid;' in v_src) = 0 then raise exception '0099: falta anchor 1'; end if;
  v_src := replace(v_src, '  v_id_ganador uuid;', '  v_id_ganador text;');

  if position('create temp table if not exists _cand (id uuid, tipo text, puntaje numeric) on commit drop;' in v_src) = 0 then
    raise exception '0099: falta anchor 2';
  end if;
  v_src := replace(v_src,
    'create temp table if not exists _cand (id uuid, tipo text, puntaje numeric) on commit drop;',
    'create temp table if not exists _cand (id text, tipo text, puntaje numeric) on commit drop;');

  if position(E'select r.id, \'reserva\', similitud_nombre(coalesce(r.pagador_nombre, r.nombre), p_remitente)' in v_src) = 0 then
    raise exception '0099: falta anchor 3';
  end if;
  v_src := replace(v_src,
    E'select r.id, \'reserva\', similitud_nombre(coalesce(r.pagador_nombre, r.nombre), p_remitente)',
    E'select r.id::text, \'reserva\', similitud_nombre(coalesce(r.pagador_nombre, r.nombre), p_remitente)');

  if position(E'select t.id, \'tiquetera\', similitud_nombre(t.nombre, p_remitente)' in v_src) = 0 then
    raise exception '0099: falta anchor 4';
  end if;
  v_src := replace(v_src,
    E'select t.id, \'tiquetera\', similitud_nombre(t.nombre, p_remitente)',
    E'select t.id::text, \'tiquetera\', similitud_nombre(t.nombre, p_remitente)');

  if position(E'    where r.id = v_id_ganador for update skip locked;' in v_src) = 0 then
    raise exception '0099: falta anchor 5';
  end if;
  v_src := replace(v_src,
    E'    where r.id = v_id_ganador for update skip locked;',
    E'    where r.id = v_id_ganador::uuid for update skip locked;');

  if position(E'     where t.id = v_id_ganador for update skip locked;' in v_src) = 0 then
    raise exception '0099: falta anchor 6';
  end if;
  v_src := replace(v_src,
    E'     where t.id = v_id_ganador for update skip locked;',
    E'     where t.id = v_id_ganador::bigint for update skip locked;');

  execute v_src;
end $$;
