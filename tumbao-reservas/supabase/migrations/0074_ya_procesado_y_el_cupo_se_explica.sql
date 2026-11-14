-- 0074 · El botón «ya procesado», y un cupo que se puede explicar.
--
-- EL CASO REAL
-- El 9 de septiembre el panel decía 30 personas a las 7:00 pm y el
-- listado de AdminGym decía 25. Damián: «deja eso bien».
--
-- Ninguno de los dos mentía y los dos estaban incompletos:
--
--   25  membresías activas (lo que ve AdminGym)
--  + 5  mensualidades pagadas por la página el 7 y el 8 de septiembre
--  ---
--   30  que era lo que sumaba el panel
--
-- Pero DOS de esas cinco ya habían sido pasadas a membresías a mano, así
-- que se estaban contando dos veces. El número de verdad era 28.
--
-- Ese doble conteo no es un descuido puntual: es estructural. Mientras
-- una solicitud pagada no tenga forma de decir «ya la pasé a AdminGym»,
-- se cuenta aparte para siempre, y el día que alguien la pase, se cuenta
-- dos veces. Con cinco al mes ya se nota; con veinte, el cupo deja de
-- servir para nada.
--
-- LO QUE SE AÑADE
--
-- 1. `mensualidad_atender` — el botón que pidió Damián. Marca la
--    solicitud como `atendida`, que es un estado que la tabla ya
--    aceptaba desde la 0070 y que nadie podía poner. Sirve igual para
--    una pagada («ya la metí a AdminGym») que para una de lista de
--    espera («ya la llamé»), que es justo lo que pidió.
--
--    `mensualidad_cupos` ya contaba solo `pagada`, así que al marcarla
--    deja de sumarse sola — y para entonces ya está en membresías. El
--    doble conteo se cierra sin restar nada a mano.
--
-- 2. `mensualidad_cupos` explica de dónde sale el número: devuelve
--    `activas` (las de AdminGym) y `por_procesar` (las pagadas que
--    todavía no están allá) aparte del total. Un cupo que no se puede
--    desglosar es un cupo del que se desconfía, y con razón.
--
-- 3. Tope por hora. Hoy `mensualidad_tope_por_hora` es un solo número
--    para las tres horas, y las tres no se parecen: a las 7:00 am se
--    venden 0,5 clases sueltas por sesión y a las 7:00 pm casi ocho. El
--    ajuste opcional `mensualidad_topes` permite escribir
--    «07:00=32,18:00=26,19:00=24». Si no existe, todo funciona
--    exactamente como hoy: no se cambia ningún tope en esta migración,
--    solo se deja el mando puesto.
--
-- Se parchea EN SITIO sobre la definición viva de `mensualidad_cupos`,
-- no se reescribe: producción trae arreglos que no están en este repo.

-- ── 1. El botón ──────────────────────────────────────────────────────
create or replace function public.mensualidad_atender(
  p_token text,
  p_id    uuid,
  p_nota  text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_admin uuid;
  v_fila  mensualidad_solicitudes;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_fila from mensualidad_solicitudes where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE',
      'mensaje', 'Esa solicitud ya no está.');
  end if;

  -- Marcar dos veces no es un error: es que dos personas la miraron. Se
  -- contesta que ya estaba, con quién y cuándo, en vez de fallar.
  if v_fila.estado = 'atendida' then
    return jsonb_build_object('ok', true, 'ya_estaba', true,
      'nombre', v_fila.nombre,
      'atendida_at', v_fila.atendida_at);
  end if;

  -- Una anulada no se «procesa»: se anuló a propósito y volverla a la
  -- vida por el camino de atrás escondería esa decisión.
  if v_fila.estado = 'anulada' then
    return jsonb_build_object('ok', false, 'error', 'ANULADA',
      'mensaje', 'Esa solicitud está anulada. No hay nada que procesar.');
  end if;

  update mensualidad_solicitudes
     set estado       = 'atendida',
         atendida_at  = now(),
         atendida_por = v_admin,
         -- La nota vieja no se pisa: puede traer la referencia del pago.
         nota = case
                  when coalesce(btrim(p_nota), '') = '' then nota
                  when coalesce(btrim(nota), '') = ''   then btrim(p_nota)
                  else nota || ' · ' || btrim(p_nota)
                end
   where id = p_id;

  return jsonb_build_object('ok', true, 'ya_estaba', false,
    'nombre', v_fila.nombre,
    -- El estado de antes viaja de vuelta para que el panel diga «ya
    -- quedó en AdminGym» o «ya la llamaste» según lo que era.
    'estado_antes', v_fila.estado);
end;
$function$;

revoke all on function public.mensualidad_atender(text, uuid, text) from public, anon;
grant execute on function public.mensualidad_atender(text, uuid, text) to service_role;

-- ── 2 y 3. El cupo se explica, y admite tope por hora ────────────────
do $mig$
declare
  v_src   text;
  v_new   text;
  v_ancla text;
  v_rep   text;
begin
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'mensualidad_cupos';

  if v_src is null then
    raise exception '0074: no existe public.mensualidad_cupos';
  end if;

  if position('0074:' in v_src) > 0 then
    raise notice '0074: ya aplicado, no se toca';
    return;
  end if;

  v_new := v_src;

  -- 3. El tope por hora, opcional. `v_topes` se lee una vez y se
  --    consulta por hora más abajo; sin el ajuste, queda null y manda
  --    `v_tope` como hasta ahora.
  v_ancla := E'declare v_tope int; v_horas text; v_valor int; v_out jsonb;';
  if position(v_ancla in v_new) = 0 then
    raise exception '0074: no se encontro el declare de mensualidad_cupos';
  end if;
  v_rep :=
    E'-- 0074: el cupo dice de donde sale, y el tope puede ir por hora.\n' ||
    E'declare v_tope int; v_horas text; v_valor int; v_out jsonb;\n' ||
    E'  v_topes text;';
  v_new := replace(v_new, v_ancla, v_rep);

  v_ancla := E'  select coalesce((select valor::int from ajustes where clave=''mensualidad_valor_cop''),125000) into v_valor;';
  if position(v_ancla in v_new) = 0 then
    raise exception '0074: no se encontro la lectura de mensualidad_valor_cop';
  end if;
  v_rep := v_ancla || E'\n' ||
    E'  -- Opcional, con la forma «07:00=32,18:00=26,19:00=24». Si no\n' ||
    E'  -- existe, manda v_tope para todas las horas, como hasta hoy.\n' ||
    E'  select (select valor from ajustes where clave=''mensualidad_topes'') into v_topes;';
  v_new := replace(v_new, v_ancla, v_rep);

  -- El tope de cada hora sale del ajuste por hora si lo hay.
  v_ancla := E'  cuenta as (\n    select h.hora, h.orden,';
  if position(v_ancla in v_new) = 0 then
    raise exception '0074: no se encontro el cuerpo de la cuenta';
  end if;
  v_rep :=
    E'  cuenta as (\n' ||
    E'    select h.hora, h.orden,\n' ||
    E'           coalesce((select btrim(split_part(t, ''='', 2))::int\n' ||
    E'                       from unnest(string_to_array(coalesce(v_topes, ''''), '','')) as t\n' ||
    E'                      where btrim(split_part(t, ''='', 1)) = to_char(h.hora, ''HH24:MI'')\n' ||
    E'                      limit 1), v_tope) as tope_hora,';
  v_new := replace(v_new, v_ancla, v_rep);

  -- 2. El desglose. Los tres sumandos ya estaban calculados; solo no se
  --    enseñaban, y por eso el 30 no se podia explicar.
  v_ancla :=
    E'        ''ocupadas'', c.activas + c.apartadas + c.pagadas,\n' ||
    E'        ''tope'', v_tope,\n' ||
    E'        ''libres'', greatest(v_tope - (c.activas + c.apartadas + c.pagadas), 0)';
  if position(v_ancla in v_new) = 0 then
    raise exception '0074: no se encontro el jsonb de cada hora';
  end if;
  v_rep :=
    E'        ''ocupadas'', c.activas + c.apartadas + c.pagadas,\n' ||
    E'        -- 0074: de donde sale ese numero. `activas` es lo que ve\n' ||
    E'        -- AdminGym; `por_procesar` son las que pagaron por la\n' ||
    E'        -- pagina y todavia no estan alla. Al marcarlas con el\n' ||
    E'        -- boton pasan a `atendida`, dejan de sumar aqui y quedan\n' ||
    E'        -- contadas una sola vez, en membresias.\n' ||
    E'        ''activas'', c.activas,\n' ||
    E'        ''por_procesar'', c.pagadas,\n' ||
    E'        ''apartadas'', c.apartadas,\n' ||
    E'        ''tope'', c.tope_hora,\n' ||
    E'        ''libres'', greatest(c.tope_hora - (c.activas + c.apartadas + c.pagadas), 0)';
  v_new := replace(v_new, v_ancla, v_rep);

  execute v_new;
end
$mig$;
