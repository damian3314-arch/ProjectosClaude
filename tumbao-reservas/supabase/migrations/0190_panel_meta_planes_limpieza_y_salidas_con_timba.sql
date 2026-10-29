-- 0190 · Panel más liviano: la meta del mes, los clientes con plan fuera del ranking, la limpieza de pendientes viejos y
--        las salidas del banco que Timba le pregunta a Tania.
--
-- Damián (29 oct): «el panel se volvió una cosa donde todos los días hay pendientes por validar… la lista de clientes
-- frecuentes con mensualidad pagada ya no hace falta… hay un montón de salidas pendientes por clasificar: que Timba le
-- escriba a Tania, le pregunte a qué corresponde y registre la respuesta… la tesorería no me la muestres: solo cuánto
-- falta por vender en el mes para llegar a la meta».
--
-- Todo lo de aquí es ADITIVO: funciones nuevas y dos columnas nuevas. Lo único que cambia datos es la limpieza (cierra las
-- tiqueteras que NUNCA reportaron pago y llevan 3 días sin moverse; ninguna plata se mueve) y queda registrado en la nota
-- de cada tiquetera. Las salidas con Timba nacen APAGADAS (ajustes.salidas_timba = 'apagado'): se encienden cuando
-- Damián confirma el número de Tania.

-- ─── 1 · La meta del mes ─────────────────────────────────────────────────────────────────────────────────────────────
-- ajustes.meta_ventas_mes ya existía: {"2026-10": 16000000}. Si un mes no tiene meta se usa la del último mes que sí la tenga.
create or replace function public.admin_meta_mes(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_admin record; v_hoy date; v_ini date; v_fin date; v_mes text;
  v_meta bigint := 0; v_de_mes text; v_vendido bigint; v_ult date; v_dias int; v_falta bigint;
  v_json jsonb;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if v_admin.rol = 'cajero' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO',
      'mensaje', 'Esta vista es del propietario y el administrador.');
  end if;

  v_hoy := (now() at time zone 'America/Bogota')::date;
  v_ini := date_trunc('month', v_hoy)::date;
  v_fin := (v_ini + interval '1 month' - interval '1 day')::date;
  v_mes := to_char(v_hoy, 'YYYY-MM');

  begin
    v_json := (select valor::jsonb from ajustes where clave = 'meta_ventas_mes');
  exception when others then v_json := null; end;
  if v_json is not null then
    select k, (v_json ->> k)::bigint into v_de_mes, v_meta
      from jsonb_object_keys(v_json) k
     where k <= v_mes and (v_json ->> k) ~ '^\d+$'
     order by k desc limit 1;
  end if;
  v_meta := coalesce(v_meta, 0);

  v_vendido := coalesce((ventas_entre(v_ini, v_hoy) ->> 'ingreso_cop')::bigint, 0);

  -- Días con clase que quedan (hoy incluido): donde ya hay horario se cuentan los días que de verdad tienen clase (no
  -- cuenta domingos ni festivos); donde todavía no se ha creado el horario, lunes a sábado.
  select max((fecha_hora at time zone 'America/Bogota')::date) into v_ult from clases;
  select count(*) into v_dias
    from generate_series(v_hoy, v_fin, interval '1 day') d
   where case when d::date <= coalesce(v_ult, v_hoy)
              then exists (select 1 from clases c where (c.fecha_hora at time zone 'America/Bogota')::date = d::date)
              else extract(isodow from d) <> 7 end;

  v_falta := greatest(v_meta - v_vendido, 0);

  return jsonb_build_object(
    'ok', true, 'mes', v_mes, 'hoy', v_hoy,
    'meta_cop', v_meta, 'meta_definida_para', v_de_mes,
    'vendido_cop', v_vendido, 'falta_cop', v_falta,
    'pct', case when v_meta > 0 then round(v_vendido * 100.0 / v_meta)::int else null end,
    'dias_restantes', v_dias,
    'por_dia_cop', case when v_dias > 0 then ceil(v_falta::numeric / v_dias)::bigint else v_falta end,
    'cumplida', v_meta > 0 and v_vendido >= v_meta,
    'puede_cambiar', v_admin.rol = 'propietario');
end;
$function$;

create or replace function public.admin_meta_fijar(p_token text, p_mes text, p_cop bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_admin record; v_json jsonb;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if v_admin.rol <> 'propietario' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO', 'mensaje', 'La meta la cambia el propietario.');
  end if;
  if coalesce(p_mes, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then
    return jsonb_build_object('ok', false, 'error', 'MES_INVALIDO');
  end if;
  if p_cop is null or p_cop < 100000 or p_cop > 2000000000 then
    return jsonb_build_object('ok', false, 'error', 'VALOR_INVALIDO', 'mensaje', 'Escribe la meta en pesos, por ejemplo 16000000.');
  end if;
  begin
    v_json := coalesce((select valor::jsonb from ajustes where clave = 'meta_ventas_mes'), '{}'::jsonb);
  exception when others then v_json := '{}'::jsonb; end;
  v_json := v_json || jsonb_build_object(p_mes, p_cop);
  insert into ajustes (clave, valor) values ('meta_ventas_mes', v_json::text)
  on conflict (clave) do update set valor = excluded.valor;
  return jsonb_build_object('ok', true, 'mes', p_mes, 'meta_cop', p_cop);
end;
$function$;

-- ─── 2 · Quién ya tiene plan: no sale en «Vienen más» ────────────────────────────────────────────────────────────────
-- Los celulares (10 dígitos) de quien tiene mensualidad vigente o en sus días de gracia. El panel los quita del ranking:
-- quien ya pagó la mensualidad no necesita que se le insista (el sistema los sigue conociendo para reforzar la venta).
create or replace function public.admin_telefonos_con_plan(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_admin record; v_gracia int;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  v_gracia := coalesce(nullif((select valor from ajustes where clave = 'mensualidad_gracia_dias'), '')::int, 3);
  return jsonb_build_object('ok', true, 'telefonos', coalesce((
    select jsonb_agg(distinct right(regexp_replace(m.celular, '\D', '', 'g'), 10))
      from membresias m
     where m.celular is not null and regexp_replace(m.celular, '\D', '', 'g') <> ''
       and current_date between m.inicio and m.fin + v_gracia), '[]'::jsonb));
end;
$function$;

-- ─── 3 · Pendientes viejos: se cierran solos ────────────────────────────────────────────────────────────────────────
-- Una tiquetera comprada en línea que NUNCA reportó pago (la persona no tocó «ya pagué») y lleva 3 días sin moverse ya no
-- es una venta: es un carrito abandonado. A los 15 minutos Timba ya le preguntó si necesitaba ayuda (0176). Se cierra con su
-- nota, igual que si recepción la hubiera descartado. NO toca las que sí dijeron que pagaron (esas pueden ser plata real).
create or replace function public.pendientes_viejos_limpiar()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_n int;
begin
  with c as (
    update tiqueteras
       set estado = 'descartada', activa = false,
           nota = coalesce(nullif(nota, '') || ' · ', '') || 'Sin pagar: se cerró sola a los 3 días',
           descartada_at = now()
     where estado = 'pendiente_pago'
       and pagado_en is null and pago_id is null
       and creada_por is null and premio_de is null
       and creada_en < now() - interval '3 days'
    returning 1)
  select count(*) into v_n from c;
  return jsonb_build_object('ok', true, 'tiqueteras_cerradas', v_n);
end;
$function$;
revoke all on function public.pendientes_viejos_limpiar() from public, anon, authenticated;

do $cron$
begin
  perform cron.unschedule('tumbao-limpiar-pendientes');
exception when others then null;
end
$cron$;
-- 6:05 am de Bogotá, todos los días.
select cron.schedule('tumbao-limpiar-pendientes', '5 11 * * *', 'select public.pendientes_viejos_limpiar()');

-- ─── 4 · Salidas del banco que Timba le pregunta a Tania ───────────────────────────────────────────────────────────
alter table public.salidas_banco
  add column if not exists preguntada_at timestamptz,
  add column if not exists preguntas int not null default 0;

insert into ajustes (clave, valor, nota) values
  ('salidas_timba', 'apagado',
   'Timba le pregunta a Tania a qué corresponden las salidas del banco sin clasificar. apagado / encendido. 0190.'),
  ('salidas_tania_tel', '3006121806',
   'Celular (10 dígitos) de quien responde por las salidas. Confirmar con Damián antes de encender salidas_timba. 0190.'),
  ('salida_pregunta_abierta', '',
   'Estado interno: la salida que Timba está preguntando ahora ({"id","at"}). 0190.')
on conflict (clave) do nothing;

-- La siguiente salida por preguntar: la más vieja que lleve al menos 16 horas sin clasificar (así recepción tiene el día
-- para hacerlo primero) y a la que no se le ha preguntado ya tres veces.
create or replace function public.salida_siguiente_por_preguntar()
returns jsonb
language sql
stable security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
  select jsonb_build_object(
    'id', s.id, 'valor_cop', s.valor_cop,
    'cuando', to_char(s.ocurrio_at at time zone 'America/Bogota', 'DD/MM HH24:MI'),
    'dia', (s.ocurrio_at at time zone 'America/Bogota')::date,
    'cuenta_destino', s.cuenta_destino, 'destinatario', s.destinatario,
    'sugerencia', (select jsonb_build_object('categoria', g.categoria, 'a_quien', g.a_quien, 'concepto', g.concepto)
                     from salidas_banco s2 join gastos g on g.id = s2.gasto_id
                    where s2.cuenta_destino is not null and s2.cuenta_destino = s.cuenta_destino and s2.estado = 'clasificada'
                    order by (s2.valor_cop = s.valor_cop) desc, s2.ocurrio_at desc limit 1),
    'quizas_repetida', (select jsonb_build_object('dia', g.dia, 'concepto', g.concepto, 'categoria', g.categoria)
                          from gastos g
                         where not g.anulado and g.valor_cop = s.valor_cop
                           and g.dia between (s.ocurrio_at at time zone 'America/Bogota')::date - 2
                                         and (s.ocurrio_at at time zone 'America/Bogota')::date + 2
                         order by abs(g.dia - (s.ocurrio_at at time zone 'America/Bogota')::date) limit 1))
    from salidas_banco s
   where s.estado = 'pendiente'
     and s.ocurrio_at < now() - interval '16 hours'
     and s.preguntas < 3
   order by s.ocurrio_at
   limit 1;
$function$;
revoke all on function public.salida_siguiente_por_preguntar() from public, anon, authenticated;

-- Deja abierta la pregunta de una salida (y cuenta que se le preguntó).
create or replace function public.salida_abrir_pregunta(p_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
begin
  update salidas_banco set preguntada_at = now(), preguntas = preguntas + 1 where id = p_id and estado = 'pendiente';
  update ajustes set valor = jsonb_build_object('id', p_id, 'at', now())::text where clave = 'salida_pregunta_abierta';
end;
$function$;
revoke all on function public.salida_abrir_pregunta(uuid) from public, anon, authenticated;

-- La pregunta abierta, SOLO si quien escribe es Tania, Timba está encendido y la salida sigue pendiente.
create or replace function public.salida_pregunta_actual(p_tel text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_tania text; v_abierta jsonb; v_id uuid; v_res jsonb;
begin
  if coalesce((select valor from ajustes where clave = 'salidas_timba'), 'apagado') <> 'encendido' then return null; end if;
  v_tania := nullif(btrim(coalesce((select valor from ajustes where clave = 'salidas_tania_tel'), '')), '');
  if v_tania is null or right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 10) <> v_tania then return null; end if;
  begin v_abierta := nullif((select valor from ajustes where clave = 'salida_pregunta_abierta'), '')::jsonb;
  exception when others then v_abierta := null; end;
  if v_abierta is null then return null; end if;
  -- una pregunta que lleva más de 3 días sin respuesta se da por cerrada: no se le contesta a algo viejo
  if (v_abierta ->> 'at')::timestamptz < now() - interval '3 days' then return null; end if;
  v_id := (v_abierta ->> 'id')::uuid;
  select jsonb_build_object(
    'id', s.id, 'valor_cop', s.valor_cop,
    'cuando', to_char(s.ocurrio_at at time zone 'America/Bogota', 'DD/MM HH24:MI'),
    'cuenta_destino', s.cuenta_destino, 'destinatario', s.destinatario,
    'sugerencia', (select jsonb_build_object('categoria', g.categoria, 'a_quien', g.a_quien, 'concepto', g.concepto)
                     from salidas_banco s2 join gastos g on g.id = s2.gasto_id
                    where s2.cuenta_destino is not null and s2.cuenta_destino = s.cuenta_destino and s2.estado = 'clasificada'
                    order by (s2.valor_cop = s.valor_cop) desc, s2.ocurrio_at desc limit 1))
    into v_res from salidas_banco s where s.id = v_id and s.estado = 'pendiente';
  return v_res;
end;
$function$;
revoke all on function public.salida_pregunta_actual(text) from public, anon, authenticated;

-- Clasifica la salida con lo que dijo Tania. Mismas reglas que admin_salida_clasificar (el valor y el día salen del banco,
-- nunca de lo que se escriba), sin token: la llama el Worker, que es quien validó que escribía Tania.
create or replace function public.salida_clasificar_timba(p_id uuid, p_categoria text, p_concepto text, p_a_quien text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_s salidas_banco; v_gasto uuid;
begin
  select * into v_s from salidas_banco where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'NO_EXISTE'); end if;
  if v_s.estado <> 'pendiente' then
    return jsonb_build_object('ok', true, 'ya_estaba', true, 'estado', v_s.estado);
  end if;
  if coalesce(btrim(p_concepto), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'SIN_CONCEPTO');
  end if;
  if p_categoria is null or p_categoria not in ('nomina','profesores','arriendo','sistema','mercadeo','talleres',
                                                'viaticos','mantenimiento','impuestos','otros') then
    return jsonb_build_object('ok', false, 'error', 'CATEGORIA_INVALIDA');
  end if;

  insert into gastos (dia, valor_cop, concepto, categoria, medio, a_quien, fuente, creado_por, nota)
  values ((v_s.ocurrio_at at time zone 'America/Bogota')::date, v_s.valor_cop, left(btrim(p_concepto), 200), p_categoria,
          'banco', nullif(left(btrim(coalesce(p_a_quien, '')), 60), ''), 'banco', null,
          'Clasificada por Timba con lo que respondió Tania'
          || coalesce(' · a la cuenta ' || v_s.cuenta_destino, '')
          || ' · ' || to_char(v_s.ocurrio_at at time zone 'America/Bogota', 'DD/MM/YYYY HH24:MI'))
  returning id into v_gasto;

  update salidas_banco set estado = 'clasificada', gasto_id = v_gasto, atendida_at = now(), atendida_por = null,
         nota = 'Timba · respuesta de Tania'
   where id = p_id;
  update ajustes set valor = '' where clave = 'salida_pregunta_abierta';
  return jsonb_build_object('ok', true, 'gasto_id', v_gasto,
    'quedan', (select count(*) from salidas_banco where estado = 'pendiente'));
end;
$function$;
revoke all on function public.salida_clasificar_timba(uuid, text, text, text) from public, anon, authenticated;

-- «Esa no es del negocio» / «ya estaba registrada»: se descarta con su motivo.
create or replace function public.salida_descartar_timba(p_id uuid, p_nota text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_s salidas_banco;
begin
  select * into v_s from salidas_banco where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'NO_EXISTE'); end if;
  if v_s.estado <> 'pendiente' then
    return jsonb_build_object('ok', true, 'ya_estaba', true, 'estado', v_s.estado);
  end if;
  if coalesce(btrim(p_nota), '') = '' then return jsonb_build_object('ok', false, 'error', 'SIN_NOTA'); end if;
  update salidas_banco set estado = 'descartada', nota = 'Timba · ' || left(btrim(p_nota), 200),
         atendida_at = now(), atendida_por = null where id = p_id;
  update ajustes set valor = '' where clave = 'salida_pregunta_abierta';
  return jsonb_build_object('ok', true, 'quedan', (select count(*) from salidas_banco where estado = 'pendiente'));
end;
$function$;
revoke all on function public.salida_descartar_timba(uuid, text) from public, anon, authenticated;

-- «No sé / luego»: se deja pendiente y se cierra la pregunta para pasar a la siguiente.
create or replace function public.salida_saltar_timba(p_id uuid)
returns void
language sql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
  update ajustes set valor = '' where clave = 'salida_pregunta_abierta';
$function$;
revoke all on function public.salida_saltar_timba(uuid) from public, anon, authenticated;

-- Una nota para un celular concreto (nota_asistente escribe a la lista de Damián). Misma cola y misma entrega: si la
-- ventana de 24 h está cerrada, el Worker manda el aviso corto y la nota sale cuando la persona toca «Ver resumen».
create or replace function public.nota_a(p_tel text, p_titulo text, p_texto text, p_clave text default null)
returns int
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare n int := 0;
begin
  if coalesce(btrim(p_texto), '') = '' or coalesce(p_tel, '') !~ '^3[0-9]{9}$' then return 0; end if;
  insert into wa_notas (clave, telefono, titulo, texto)
  values (case when p_clave is null then null else p_clave || ':' || p_tel end, p_tel,
          left(coalesce(nullif(btrim(p_titulo), ''), 'Reporte'), 80), left(p_texto, 3500))
  on conflict (clave) do nothing;
  get diagnostics n = row_count;
  if n > 0 then
    perform net.http_post(
      url := (select valor from ajustes where clave = 'wa_notas_url'),
      body := '{}'::jsonb,
      headers := '{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds := 60000);
  end if;
  return n;
end;
$function$;
revoke all on function public.nota_a(text, text, text, text) from public, anon, authenticated;

-- Una vez al día (no domingos ni festivos: es trabajo, no mercadeo) le abre la conversación a Tania con la primera salida.
-- Lo siguiente lo hace el Worker en la misma conversación, una pregunta por vez, mientras ella vaya contestando.
create or replace function public.salidas_preguntar_a_tania()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_tel text; v_s jsonb; v_hay int; v_texto text; v_hoy date; v_sug text;
begin
  if coalesce((select valor from ajustes where clave = 'salidas_timba'), 'apagado') <> 'encendido' then
    return jsonb_build_object('ok', true, 'activo', false);
  end if;
  v_tel := nullif(btrim(coalesce((select valor from ajustes where clave = 'salidas_tania_tel'), '')), '');
  if v_tel is null or v_tel !~ '^3[0-9]{9}$' then
    return jsonb_build_object('ok', true, 'activo', false, 'motivo', 'sin_telefono');
  end if;
  v_hoy := (now() at time zone 'America/Bogota')::date;
  if extract(isodow from v_hoy) = 7 then return jsonb_build_object('ok', true, 'domingo', true); end if;
  -- si ya hay una pregunta abierta de las últimas 20 horas, no se le abre otra conversación
  if exists (select 1 from ajustes where clave = 'salida_pregunta_abierta' and valor <> ''
                and (valor::jsonb ->> 'at')::timestamptz > now() - interval '20 hours') then
    return jsonb_build_object('ok', true, 'ya_abierta', true);
  end if;
  v_s := salida_siguiente_por_preguntar();
  if v_s is null then return jsonb_build_object('ok', true, 'nada', true); end if;
  select count(*) into v_hay from salidas_banco where estado = 'pendiente';

  v_sug := case when v_s -> 'sugerencia' is not null and v_s ->> 'sugerencia' <> 'null'
                then E'\nLa última vez que salió plata a esa cuenta la anotamos como «' || (v_s -> 'sugerencia' ->> 'concepto') || '».'
                else '' end;
  v_texto := 'Hola Tania 👋 Soy Timba. Hay ' || v_hay || ' salidas del banco sin clasificar y quiero dejar el sistema al día. '
          || 'Te las pregunto de a una; contéstame con a qué corresponde y yo la registro.' || E'\n\n'
          || '💸 *$' || to_char((v_s ->> 'valor_cop')::int, 'FM999G999G999') || '* el ' || (v_s ->> 'cuando')
          || coalesce(' · cuenta ' || nullif(v_s ->> 'cuenta_destino', ''), '')
          || v_sug || E'\n¿A qué corresponde? (si no sabes, escribe «luego»)';

  perform salida_abrir_pregunta((v_s ->> 'id')::uuid);
  perform nota_a(v_tel, 'Salidas del banco por clasificar', v_texto, 'salidas-tania:' || v_hoy::text);
  return jsonb_build_object('ok', true, 'preguntada', v_s ->> 'id', 'pendientes', v_hay);
end;
$function$;
revoke all on function public.salidas_preguntar_a_tania() from public, anon, authenticated;

do $cron$
begin
  perform cron.unschedule('tumbao-salidas-tania');
exception when others then null;
end
$cron$;
-- 9:30 am de Bogotá (14:30 UTC), lunes a sábado. Mientras salidas_timba esté apagado no hace nada.
select cron.schedule('tumbao-salidas-tania', '30 14 * * 1-6', 'select public.salidas_preguntar_a_tania()');

-- Lo que se limpia hoy mismo
select public.pendientes_viejos_limpiar();
