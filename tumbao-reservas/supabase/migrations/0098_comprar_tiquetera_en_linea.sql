-- 0098 · Comprar la tiquetera en línea, con el mismo motor de pagos
-- que ya confirma una clase suelta.
--
-- Damián, 24 de septiembre: «el pago se confirma automático porque
-- quedaría como cuando compran clase suelta; si no se puede confirmar
-- en automático, pues se activa que nos contacte por WhatsApp».
--
-- LO QUE YA EXISTÍA (0097) Y SIGUE IGUAL
-- Una tiquetera vendida en el mostrador por recepción (admin_tiquetera_
-- crear) nace ya `confirmada`: el dinero ya lo tiene la cajera en la
-- mano o en la cuenta, no hay nada que esperar.
--
-- LO NUEVO
-- Una tiquetera comprada SOLA desde la página nace `pendiente_pago`, con
-- el mismo QR y la misma espera de siempre, y se activa exactamente por
-- el mismo camino que confirma una clase suelta:
--
--   1. Llega el correo del banco → registrar_pago_y_conciliar() busca
--      entre las reservas pendientes Y ahora también entre las
--      tiqueteras pendientes, y confirma la que calce por valor, hora y
--      nombre de quien transfiere.
--   2. La clienta pregunta "¿ya?" (la página consulta sola) →
--      conciliar_tiquetera()/cruzar_tiquetera()/buscar_deposito_
--      tiquetera() hacen la misma pregunta al revés: ¿ya llegó una plata
--      que nadie reclamó y que le calza a ESTA tiquetera? — mismo
--      mecanismo que cruzar_reserva()/buscar_deposito_libre() para
--      sueltas, sin el concepto de "grupo" porque una tiquetera siempre
--      es de una sola persona.
--
-- Si ninguno de los dos cruza a tiempo, la página la manda a
-- `pendiente_validacion` — la misma invitación a escribir por WhatsApp
-- con el comprobante que ya existe para una suelta, y de ahí en adelante
-- recepción la activa a mano desde "Vender una tiquetera" (0097), como
-- ya lo hace hoy con cualquier venta de mostrador. No se construye una
-- bandeja nueva para esto: la plata sin dueño ya se ve en "Por validar".
--
-- LOS PAQUETES SON UN AJUSTE, NO UN NÚMERO QUE MANDE EL NAVEGADOR
-- El precio y las clases de cada paquete viven en el ajuste
-- `tiquetera_paquetes` — el navegador solo manda la CLAVE del paquete
-- ('4' u '8'), nunca el precio. Si el precio lo mandara el cliente,
-- cualquiera podría comprar 8 clases por $1.
--
-- Se parchea EN SITIO sobre pg_get_functiondef solo donde hay que tocar
-- una función que YA EXISTE y YA CORRE en producción
-- (registrar_pago_y_conciliar, tomar_cupo): las demás son funciones
-- nuevas, así que se crean directo.

-- ── 1. la tabla aprende el ciclo de vida del pago ────────────────────
alter table tiqueteras
  add column if not exists estado      text not null default 'confirmada',
  add column if not exists pago_id     uuid references pagos(id),
  add column if not exists pagado_en   timestamptz,
  add column if not exists referencia  text,
  add column if not exists expira_en   timestamptz;

do $mig$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'tiqueteras_estado_ck'
  ) then
    alter table tiqueteras add constraint tiqueteras_estado_ck
      check (estado in ('pendiente_pago', 'pendiente_validacion', 'confirmada'));
  end if;
end
$mig$;

create index if not exists tiqueteras_pendientes
  on tiqueteras (creada_en) where estado in ('pendiente_pago', 'pendiente_validacion');

-- ── 2. el catálogo de paquetes, editable sin migración ───────────────
insert into ajustes (clave, valor, nota) values (
  'tiquetera_paquetes',
  '[{"clave":"4","clases":4,"precio_cop":52000,"vigencia_dias":45},{"clave":"8","clases":8,"precio_cop":96000,"vigencia_dias":90}]',
  'Paquetes de tiquetera que se venden en línea: clave, clases, precio y '
  || 'vigencia. El navegador solo manda la clave -- el precio real sale '
  || 'siempre de aquí, nunca de lo que mande el cliente. Editable a mano, '
  || 'sin tocar código. 0098.'
) on conflict (clave) do nothing;

create or replace function public.tiquetera_paquetes()
returns jsonb
language sql stable
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
  select coalesce((select valor::jsonb from ajustes where clave = 'tiquetera_paquetes'), '[]'::jsonb);
$function$;

revoke all on function public.tiquetera_paquetes() from public, anon, authenticated;
grant execute on function public.tiquetera_paquetes() to service_role;

-- ── 3. iniciar la compra ──────────────────────────────────────────────
create or replace function public.iniciar_compra_tiquetera(
  p_nombre text, p_telefono text, p_paquete text
) returns jsonb
language plpgsql security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_nombre   text := trim(coalesce(p_nombre, ''));
  v_tel      text := solo_digitos(coalesce(p_telefono, ''));
  v_paq      jsonb;
  v_codigo   text;
  v_intentos int := 0;
  v_id       bigint;
  v_vence    date;
begin
  if length(v_nombre) < 2 then
    return jsonb_build_object('ok', false, 'error', 'NOMBRE_INVALIDO',
      'mensaje', 'Escribe tu nombre completo.');
  end if;
  if length(v_tel) <> 10 then
    return jsonb_build_object('ok', false, 'error', 'CELULAR_INVALIDO',
      'mensaje', 'El celular debe tener 10 dígitos.');
  end if;

  select x into v_paq
    from jsonb_array_elements(tiquetera_paquetes()) x
   where x->>'clave' = p_paquete;
  if v_paq is null then
    return jsonb_build_object('ok', false, 'error', 'PAQUETE_INVALIDO',
      'mensaje', 'Ese paquete no existe. Elige uno de la lista.');
  end if;

  v_vence := (now() at time zone 'America/Bogota')::date + (v_paq->>'vigencia_dias')::int;

  loop
    v_intentos := v_intentos + 1;
    v_codigo := generar_codigo_reserva();
    begin
      insert into tiqueteras (codigo, nombre, telefono, clases_totales,
                              precio_cop, vence_el, estado, expira_en)
      values (v_codigo, v_nombre, v_tel, (v_paq->>'clases')::int,
              (v_paq->>'precio_cop')::int, v_vence, 'pendiente_pago',
              now() + interval '30 minutes')
      returning id into v_id;
      exit;
    exception when unique_violation then
      if v_intentos >= 5 then raise; end if;
    end;
  end loop;

  return jsonb_build_object('ok', true, 'id', v_id, 'codigo', v_codigo,
    'precio_cop', (v_paq->>'precio_cop')::int, 'clases', (v_paq->>'clases')::int,
    'vence_el', v_vence);
end;
$function$;

revoke all on function public.iniciar_compra_tiquetera(text, text, text)
  from public, anon, authenticated;
grant execute on function public.iniciar_compra_tiquetera(text, text, text)
  to service_role;

-- ── 4. «ya pagué»: guarda la hora y la referencia, como una suelta ───
create or replace function public.tiquetera_reportar_pago(
  p_codigo text, p_referencia text default null
) returns jsonb
language plpgsql security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_t tiqueteras%rowtype;
begin
  select * into v_t from tiqueteras
   where upper(btrim(codigo)) = upper(btrim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_encontrada');
  end if;
  if v_t.estado <> 'pendiente_pago' then
    return jsonb_build_object('ok', true, 'estado', v_t.estado, 'ya_estaba', true);
  end if;

  update tiqueteras
     set pagado_en  = now(),
         referencia = nullif(btrim(coalesce(p_referencia, '')), '')
   where id = v_t.id;

  return jsonb_build_object('ok', true, 'estado', 'pendiente_pago', 'ya_estaba', false);
end;
$function$;

revoke all on function public.tiquetera_reportar_pago(text, text)
  from public, anon, authenticated;
grant execute on function public.tiquetera_reportar_pago(text, text)
  to service_role;

-- ── 5. buscar un depósito que ya llegó y a nadie le calza todavía ────
-- Espejo de buscar_deposito_libre(), sin el concepto de "grupo": una
-- tiquetera siempre es de una sola persona.
create or replace function public.buscar_deposito_tiquetera(p_tiquetera_id bigint)
returns uuid
language plpgsql stable security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_t      tiqueteras%rowtype;
  v_corte  timestamptz;
  v_id     uuid;
  v_desde  timestamptz;
  v_hasta  timestamptz;
  v_pasada int;
begin
  select * into v_t from tiqueteras where id = p_tiquetera_id;
  if not found or v_t.pago_id is not null then return null; end if;
  if v_t.estado <> 'pendiente_pago' then return null; end if;
  if v_t.expira_en is not null and v_t.expira_en <= now() then return null; end if;
  if v_t.precio_cop is null or v_t.precio_cop <= 0 then return null; end if;

  v_corte := inicio_produccion()::timestamp at time zone 'America/Bogota';

  for v_pasada in 1..2 loop
    if v_pasada = 1 then
      v_desde := coalesce(v_t.pagado_en, v_t.creada_en) - interval '30 minutes';
      v_hasta := coalesce(v_t.pagado_en, v_t.creada_en) + interval '30 minutes';
    else
      v_desde := v_t.creada_en - interval '15 minutes';
      v_hasta := v_t.creada_en + interval '3 hours';
    end if;

    with cand as (
      select p.id, similitud_nombre(v_t.nombre, p.remitente) as pt,
             -- No se le puede quitar el depósito a una RESERVA de suelta
             -- que también lo esté esperando y le calce mejor.
             coalesce((
               select max(similitud_nombre(coalesce(q.pagador_nombre, q.nombre), p.remitente))
                 from reservas q
                 join clases c on c.id = q.clase_id
                where q.pago_id is null
                  and q.estado in ('pendiente_pago', 'verificando', 'pendiente_validacion')
                  and (q.estado <> 'pendiente_pago'
                       or q.expira_en is null or q.expira_en > now())
                  and c.precio_cop = v_t.precio_cop
                  and p.fecha_pago between coalesce(q.pagado_en, q.created_at) - interval '30 minutes'
                                        and coalesce(q.pagado_en, q.created_at) + interval '3 hours'
             ), -1) as pt_reserva,
             -- Ni a OTRA tiquetera pendiente del mismo valor.
             coalesce((
               select max(similitud_nombre(w.nombre, p.remitente))
                 from tiqueteras w
                where w.id <> v_t.id and w.pago_id is null
                  and w.estado = 'pendiente_pago'
                  and w.precio_cop = v_t.precio_cop
                  and (w.expira_en is null or w.expira_en > now())
                  and p.fecha_pago between coalesce(w.pagado_en, w.creada_en) - interval '30 minutes'
                                        and coalesce(w.pagado_en, w.creada_en) + interval '3 hours'
             ), -1) as pt_otra
        from pagos p
       where not p.consumido
         and p.valor_cop = v_t.precio_cop
         and p.fecha_pago >= v_corte
         and p.fecha_pago between v_desde and v_hasta
    ), orden as (
      select id, pt,
             count(*) over ()                     as n,
             row_number() over (order by pt desc) as rn,
             lead(pt)     over (order by pt desc) as segundo
        from cand
       where not (pt_reserva >= 0.5 and pt_reserva > pt)
         and not (pt_otra    >= 0.5 and pt_otra    > pt)
    )
    select id into v_id from orden
     where rn = 1
       and (n = 1 or (pt >= 0.5 and pt > coalesce(segundo, -1)));

    if v_id is not null then return v_id; end if;
  end loop;

  return null;
end;
$function$;

revoke all on function public.buscar_deposito_tiquetera(bigint)
  from public, anon, authenticated;
grant execute on function public.buscar_deposito_tiquetera(bigint) to service_role;

-- ── 6. cruzarla, y preguntarle desde afuera (poll de la página) ─────
create or replace function public.cruzar_tiquetera(p_tiquetera_id bigint)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_pago uuid; v_t tiqueteras%rowtype;
begin
  v_pago := buscar_deposito_tiquetera(p_tiquetera_id);
  if v_pago is null then
    return jsonb_build_object('ok', true, 'cruzada', false);
  end if;

  perform 1 from pagos where id = v_pago and not consumido for update;
  if not found then
    return jsonb_build_object('ok', true, 'cruzada', false, 'motivo', 'lo_tomaron');
  end if;

  update tiqueteras
     set estado = 'confirmada', pago_id = v_pago
   where id = p_tiquetera_id and pago_id is null and estado = 'pendiente_pago'
   returning * into v_t;

  if not found then
    return jsonb_build_object('ok', true, 'cruzada', false, 'motivo', 'ya_no_aplica');
  end if;

  update pagos set consumido = true where id = v_pago;

  return jsonb_build_object('ok', true, 'cruzada', true, 'pago_id', v_pago, 'codigo', v_t.codigo);
end;
$function$;

revoke all on function public.cruzar_tiquetera(bigint) from public, anon, authenticated;
grant execute on function public.cruzar_tiquetera(bigint) to service_role;

create or replace function public.conciliar_tiquetera(p_codigo text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_t tiqueteras%rowtype; v_cruce jsonb;
begin
  select * into v_t from tiqueteras
   where upper(btrim(codigo)) = upper(btrim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_encontrada');
  end if;

  if v_t.estado <> 'pendiente_pago' then
    return jsonb_build_object('ok', true, 'estado', v_t.estado, 'codigo', v_t.codigo,
      'clases', v_t.clases_totales,
      'tiquetera_saldo', v_t.clases_totales - v_t.clases_usadas);
  end if;

  if v_t.expira_en is not null and v_t.expira_en <= now() then
    return jsonb_build_object('ok', true, 'estado', 'expirada', 'codigo', v_t.codigo);
  end if;

  v_cruce := cruzar_tiquetera(v_t.id);

  if (v_cruce->>'cruzada')::boolean then
    return jsonb_build_object('ok', true, 'estado', 'confirmada', 'codigo', v_t.codigo,
      'clases', v_t.clases_totales,
      'tiquetera_saldo', v_t.clases_totales - v_t.clases_usadas);
  end if;

  return jsonb_build_object('ok', true, 'estado', 'pendiente_pago', 'codigo', v_t.codigo);
end;
$function$;

revoke all on function public.conciliar_tiquetera(text) from public, anon, authenticated;
grant execute on function public.conciliar_tiquetera(text) to service_role;

-- Se acabaron los minutos de espera: a validación humana, igual que a
-- una suelta. De ahí en adelante recepción la activa a mano si la plata
-- de verdad llegó (0097, "Vender una tiquetera" también sirve para
-- activar una que ya existe -- ver LEEME de despliegue para el detalle).
create or replace function public.marcar_tiquetera_pendiente_validacion(p_codigo text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_t tiqueteras%rowtype;
begin
  update tiqueteras
     set estado = 'pendiente_validacion'
   where upper(btrim(codigo)) = upper(btrim(p_codigo))
     and estado = 'pendiente_pago'
   returning * into v_t;

  if not found then
    select * into v_t from tiqueteras where upper(btrim(codigo)) = upper(btrim(p_codigo));
    if not found then
      return jsonb_build_object('ok', false, 'error', 'no_encontrada');
    end if;
  end if;

  return jsonb_build_object('ok', true, 'estado', v_t.estado, 'codigo', v_t.codigo);
end;
$function$;

revoke all on function public.marcar_tiquetera_pendiente_validacion(text)
  from public, anon, authenticated;
grant execute on function public.marcar_tiquetera_pendiente_validacion(text)
  to service_role;

-- ── 7. recuperar el código por celular ───────────────────────────────
create or replace function public.tiquetera_recuperar(p_telefono text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_tel   text := solo_digitos(coalesce(p_telefono, ''));
  v_hoy   date := (now() at time zone 'America/Bogota')::date;
  v_lista jsonb;
begin
  if length(v_tel) <> 10 then
    return jsonb_build_object('ok', false, 'error', 'CELULAR_INVALIDO',
      'mensaje', 'Escribe tu celular a 10 dígitos.');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', t.codigo,
           'clases_restantes', t.clases_totales - t.clases_usadas,
           'vence_el', t.vence_el
         ) order by t.creada_en desc), '[]'::jsonb)
    into v_lista
    from tiqueteras t
   where solo_digitos(t.telefono) = v_tel
     and t.activa and t.estado = 'confirmada'
     and t.vence_el >= v_hoy
     and t.clases_usadas < t.clases_totales;

  if jsonb_array_length(v_lista) = 0 then
    return jsonb_build_object('ok', false, 'error', 'SIN_TIQUETERA',
      'mensaje', 'No encontramos una tiquetera activa con ese celular. '
              || 'Si crees que es un error, escríbenos por WhatsApp.');
  end if;

  return jsonb_build_object('ok', true, 'tiqueteras', v_lista);
end;
$function$;

revoke all on function public.tiquetera_recuperar(text) from public, anon, authenticated;
grant execute on function public.tiquetera_recuperar(text) to service_role;

-- ── 8. tomar_cupo: solo una tiquetera YA PAGADA reserva clase ────────
do $mig$
declare
  v_src text;
  v_a constant text := E'  if p_tipo = ''tiquetera'' then\n    select * into v_tiquetera from tiqueteras\n     where codigo = upper(trim(coalesce(p_codigo_tiquetera, '''')))\n       and activa\n       and vence_el >= v_fecha\n       and clases_usadas < clases_totales\n     for update;';
  v_n constant text := E'  if p_tipo = ''tiquetera'' then\n    -- 0098: una tiquetera comprada en linea que sigue pendiente_pago no\n    -- reserva nada -- ese sería el hueco perfecto para colar una clase\n    -- gratis con un pago que nunca llegó.\n    select * into v_tiquetera from tiqueteras\n     where codigo = upper(trim(coalesce(p_codigo_tiquetera, '''')))\n       and activa\n       and estado = ''confirmada''\n       and vence_el >= v_fecha\n       and clases_usadas < clases_totales\n     for update;';
begin
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'tomar_cupo' and p.prokind = 'f';
  if v_src is null then raise exception '0098: no existe public.tomar_cupo'; end if;

  if position('0098:' in v_src) > 0 then
    raise notice '0098: tomar_cupo ya aplicado, no se toca';
  else
    if position(v_a in v_src) = 0 then raise exception '0098: falta el anchor de tomar_cupo'; end if;
    execute replace(v_src, v_a, v_n);
  end if;
end
$mig$;

-- ── 9. registrar_pago_y_conciliar aprende el segundo tipo de candidato
-- Se reescribe con el mismo mecanismo de siempre: splice sobre la
-- definición viva, con anclajes verificados por posición antes de
-- escribir esta migración. Es la función MÁS delicada de todo Tumbao
-- -- confirma la plata real de hoy -- así que el resto de reservas
-- queda BYTE POR BYTE igual; lo único que cambia es que ahora hay dos
-- tipos de candidato en la misma bolsa en vez de uno.
do $mig$
declare
  v_src text;
  v_a1 constant text := E'  v_pago       pagos%rowtype;\n  v_reserva    reservas%rowtype;\n  v_candidatos int;\n  v_con_nombre int;\n  v_metodo     text := ''monto_unico'';\nbegin';
  v_n1 constant text := E'  v_pago       pagos%rowtype;\n  v_reserva    reservas%rowtype;\n  -- 0098: la tiquetera comprada en linea se paga igual que una suelta,\n  -- así que juega en la misma bolsa de candidatos.\n  v_tiquetera  tiqueteras%rowtype;\n  v_tipo       text;\n  v_id_ganador uuid;\n  v_candidatos int;\n  v_con_nombre int;\n  v_metodo     text := ''monto_unico'';\nbegin';

  v_a2 constant text := E'  create temp table if not exists _cand (id uuid, puntaje numeric) on commit drop;';
  v_n2 constant text := E'  create temp table if not exists _cand (id uuid, tipo text, puntaje numeric) on commit drop;';

  v_a3 constant text := E'  insert into _cand (id, puntaje)\n  -- Se compara contra quien PAGA, no contra quien reserva. Cuando paga\n  -- la mama o la pareja son personas distintas, y comparar contra quien\n  -- reserva daria cero justo cuando hace falta desempatar.\n  select r.id, similitud_nombre(coalesce(r.pagador_nombre, r.nombre), p_remitente)\n    from reservas r\n    join clases c on c.id = r.clase_id\n   where r.estado in (''pendiente_pago'', ''verificando'', ''pendiente_validacion'')\n     and r.pago_id is null\n     -- 0055: las pendiente_pago, solo mientras sigan vivas.\n     and (r.estado <> ''pendiente_pago''\n          or r.expira_en is null or r.expira_en > now())\n     and c.precio_cop = p_valor_cop\n     and case\n           when r.pagado_en is not null then\n             p_fecha_pago between r.pagado_en - interval ''15 minutes''\n                              and r.pagado_en + interval ''15 minutes''\n           else\n             p_fecha_pago between r.created_at - interval ''15 minutes''\n                              and r.created_at + interval ''3 hours''\n         end;';
  v_n3 constant text := E'  insert into _cand (id, tipo, puntaje)\n  -- Se compara contra quien PAGA, no contra quien reserva. Cuando paga\n  -- la mama o la pareja son personas distintas, y comparar contra quien\n  -- reserva daria cero justo cuando hace falta desempatar.\n  select r.id, ''reserva'', similitud_nombre(coalesce(r.pagador_nombre, r.nombre), p_remitente)\n    from reservas r\n    join clases c on c.id = r.clase_id\n   where r.estado in (''pendiente_pago'', ''verificando'', ''pendiente_validacion'')\n     and r.pago_id is null\n     -- 0055: las pendiente_pago, solo mientras sigan vivas.\n     and (r.estado <> ''pendiente_pago''\n          or r.expira_en is null or r.expira_en > now())\n     and c.precio_cop = p_valor_cop\n     and case\n           when r.pagado_en is not null then\n             p_fecha_pago between r.pagado_en - interval ''15 minutes''\n                              and r.pagado_en + interval ''15 minutes''\n           else\n             p_fecha_pago between r.created_at - interval ''15 minutes''\n                              and r.created_at + interval ''3 hours''\n         end\n  union all\n  -- 0098: la tiquetera comprada en linea, mismo criterio, sin grupo.\n  select t.id, ''tiquetera'', similitud_nombre(t.nombre, p_remitente)\n    from tiqueteras t\n   where t.estado = ''pendiente_pago''\n     and t.pago_id is null\n     and (t.expira_en is null or t.expira_en > now())\n     and t.precio_cop = p_valor_cop\n     and case\n           when t.pagado_en is not null then\n             p_fecha_pago between t.pagado_en - interval ''15 minutes''\n                              and t.pagado_en + interval ''15 minutes''\n           else\n             p_fecha_pago between t.creada_en - interval ''15 minutes''\n                              and t.creada_en + interval ''3 hours''\n         end;';

  v_a4 constant text := E'  if v_candidatos = 1 then\n    -- Un solo candidato: se confirma sin mirar el nombre. Es el caso de\n    -- \"pago la mama\": el nombre no coincide y da igual, no hay con quien\n    -- confundirlo.\n    select r.* into v_reserva from reservas r\n     where r.id = (select id from _cand limit 1)\n       for update skip locked;\n  else\n    select count(*) into v_con_nombre from _cand where puntaje >= 0.5;\n\n    if v_con_nombre <> 1 then\n      return jsonb_build_object(''ok'', true, ''duplicado'', false,\n        ''pago_id'', v_pago.id, ''accion'', ''ambiguo'',\n        ''candidatos'', v_candidatos,\n        ''con_nombre_parecido'', v_con_nombre,\n        ''remitente'', p_remitente);\n    end if;\n\n    v_metodo := ''nombre_remitente'';\n    select r.* into v_reserva from reservas r\n     where r.id = (select id from _cand where puntaje >= 0.5 limit 1)\n       for update skip locked;\n  end if;\n\n  if not found then\n    return jsonb_build_object(''ok'', true, ''duplicado'', false,\n      ''pago_id'', v_pago.id, ''accion'', ''sin_reserva_que_casar'');\n  end if;\n\n  update reservas\n     set estado = ''confirmada'', pago_id = v_pago.id, updated_at = now()\n   where id = v_reserva.id;\n\n  update pagos set consumido = true where id = v_pago.id;\n\n  return jsonb_build_object(''ok'', true, ''duplicado'', false,\n    ''pago_id'', v_pago.id, ''accion'', ''reserva_confirmada'',\n    ''metodo'', v_metodo, ''candidatos'', v_candidatos,\n    ''reserva_id'', v_reserva.id, ''codigo'', v_reserva.codigo,\n    ''nombre'', v_reserva.nombre, ''telefono'', v_reserva.telefono);\nend;';
  v_n4 constant text := E'  -- 0098: primero se decide QUIEN gana (una reserva o una tiquetera);\n  -- despues se actua segun ese tipo. La logica de desempate es\n  -- exactamente la misma de siempre, sobre la bolsa combinada.\n  if v_candidatos = 1 then\n    select id, tipo into v_id_ganador, v_tipo from _cand limit 1;\n  else\n    select count(*) into v_con_nombre from _cand where puntaje >= 0.5;\n\n    if v_con_nombre <> 1 then\n      return jsonb_build_object(''ok'', true, ''duplicado'', false,\n        ''pago_id'', v_pago.id, ''accion'', ''ambiguo'',\n        ''candidatos'', v_candidatos,\n        ''con_nombre_parecido'', v_con_nombre,\n        ''remitente'', p_remitente);\n    end if;\n\n    v_metodo := ''nombre_remitente'';\n    select id, tipo into v_id_ganador, v_tipo from _cand where puntaje >= 0.5 limit 1;\n  end if;\n\n  if v_tipo = ''reserva'' then\n    select r.* into v_reserva from reservas r\n     where r.id = v_id_ganador for update skip locked;\n\n    if not found then\n      return jsonb_build_object(''ok'', true, ''duplicado'', false,\n        ''pago_id'', v_pago.id, ''accion'', ''sin_reserva_que_casar'');\n    end if;\n\n    update reservas\n       set estado = ''confirmada'', pago_id = v_pago.id, updated_at = now()\n     where id = v_reserva.id;\n\n    update pagos set consumido = true where id = v_pago.id;\n\n    return jsonb_build_object(''ok'', true, ''duplicado'', false,\n      ''pago_id'', v_pago.id, ''accion'', ''reserva_confirmada'',\n      ''metodo'', v_metodo, ''candidatos'', v_candidatos,\n      ''reserva_id'', v_reserva.id, ''codigo'', v_reserva.codigo,\n      ''nombre'', v_reserva.nombre, ''telefono'', v_reserva.telefono);\n  else\n    -- 0098: mismo cruce, para una tiquetera comprada en linea -- no hay\n    -- clase que confirmar, hay un saldo que activar.\n    select t.* into v_tiquetera from tiqueteras t\n     where t.id = v_id_ganador for update skip locked;\n\n    if not found then\n      return jsonb_build_object(''ok'', true, ''duplicado'', false,\n        ''pago_id'', v_pago.id, ''accion'', ''sin_reserva_que_casar'');\n    end if;\n\n    update tiqueteras\n       set estado = ''confirmada'', pago_id = v_pago.id\n     where id = v_tiquetera.id;\n\n    update pagos set consumido = true where id = v_pago.id;\n\n    return jsonb_build_object(''ok'', true, ''duplicado'', false,\n      ''pago_id'', v_pago.id, ''accion'', ''tiquetera_confirmada'',\n      ''metodo'', v_metodo, ''candidatos'', v_candidatos,\n      ''tiquetera_id'', v_tiquetera.id, ''codigo'', v_tiquetera.codigo,\n      ''nombre'', v_tiquetera.nombre, ''telefono'', v_tiquetera.telefono,\n      ''clases'', v_tiquetera.clases_totales);\n  end if;\nend;';
begin
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'registrar_pago_y_conciliar' and p.prokind = 'f';
  if v_src is null then raise exception '0098: no existe public.registrar_pago_y_conciliar'; end if;

  if position('0098:' in v_src) > 0 then
    raise notice '0098: registrar_pago_y_conciliar ya aplicado, no se toca';
  else
    if position(v_a1 in v_src) = 0 then raise exception '0098: falta anchor 1 (declare)'; end if;
    v_src := replace(v_src, v_a1, v_n1);
    if position(v_a2 in v_src) = 0 then raise exception '0098: falta anchor 2 (temp table)'; end if;
    v_src := replace(v_src, v_a2, v_n2);
    if position(v_a3 in v_src) = 0 then raise exception '0098: falta anchor 3 (insert _cand)'; end if;
    v_src := replace(v_src, v_a3, v_n3);
    if position(v_a4 in v_src) = 0 then raise exception '0098: falta anchor 4 (cola completa)'; end if;
    v_src := replace(v_src, v_a4, v_n4);
    execute v_src;
  end if;
end
$mig$;
