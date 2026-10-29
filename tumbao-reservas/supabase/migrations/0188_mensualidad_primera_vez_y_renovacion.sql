-- 0188 · Mensualidad por la página: primera vez (registro completo) y renovación (directo al pago)
--
-- Damián (29 oct): quien paga la mensualidad por primera vez tiene que dejar nombre completo, correo, celular y
-- fecha de nacimiento (sin eso el sistema de accesos no la crea), aceptar el tratamiento de datos —incluida la
-- huella— y contestar unas preguntas de salud con su declaración. Quien ya es alumna y renueva solo pone nombre y
-- celular y pasa al pago. Autorizó la migración (solo agrega columnas, no borra nada).
--
-- Qué hace:
--   1. mensualidad_solicitudes gana: fecha_nacimiento, salud (jsonb), datos_aceptados_at, salud_aceptada_at,
--      primera_vez y es_renovacion. Todas opcionales: lo que ya existe no cambia.
--   2. mensualidad_solicitar_v2(): decide en el servidor si la persona es nueva o ya es alumna (por celular, en
--      membresías o con historial de plan), exige los datos solo a quien es nueva y va a poder pagar, y deja pagar
--      sin cupo libre a quien renueva el mismo horario dentro de la gracia (su cupo ya es suyo).
--   3. mensualidad_cupos(): una renovación no cuenta dos veces (ya está en «activas» por la gracia).
--   4. mensualidad_lista(): el panel ve si es primera vez (hay que crearla con huella) o renovación, la fecha de
--      nacimiento y si marcó algo en salud.

alter table public.mensualidad_solicitudes
  add column if not exists fecha_nacimiento    date,
  add column if not exists salud               jsonb,
  add column if not exists datos_aceptados_at  timestamptz,
  add column if not exists salud_aceptada_at   timestamptz,
  add column if not exists primera_vez         boolean not null default false,
  add column if not exists es_renovacion       boolean not null default false;

comment on column public.mensualidad_solicitudes.primera_vez is
  'true = persona nueva: recepción la crea en el sistema de accesos y le toma la huella el primer día.';
comment on column public.mensualidad_solicitudes.es_renovacion is
  'true = ya era alumna en este mismo horario (dentro de la gracia): su cupo ya cuenta en activas.';

-- ─── 3 · el cupo no se cuenta dos veces ──────────────────────────────────────────────────────────────────────
create or replace function public.mensualidad_cupos()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_tope int; v_horas text; v_valor int; v_out jsonb;
  v_gracia int := coalesce(nullif((select valor from ajustes where clave = 'mensualidad_gracia_dias'), '')::int, 3);
  v_topes text;
begin
  select coalesce((select valor::int from ajustes where clave='mensualidad_tope_por_hora'),25) into v_tope;
  select coalesce((select valor from ajustes where clave='mensualidad_horas'),'07:00,18:00,19:00') into v_horas;
  select coalesce((select valor::int from ajustes where clave='mensualidad_valor_cop'),125000) into v_valor;
  select (select valor from ajustes where clave='mensualidad_topes') into v_topes;

  with horas as (
    select btrim(x)::time as hora, ordinality as orden
      from unnest(string_to_array(v_horas, ',')) with ordinality as t(x, ordinality)
  ),
  cuenta as (
    select h.hora, h.orden,
           coalesce((select btrim(split_part(t, '=', 2))::int
                       from unnest(string_to_array(coalesce(v_topes, ''), ',')) as t
                      where btrim(split_part(t, '=', 1)) = to_char(h.hora, 'HH24:MI')
                      limit 1), v_tope) as tope_hora,
           (select count(distinct coalesce(nullif(right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10), ''), m.id::text))
              from membresias m
             where m.hora = h.hora and current_date between m.inicio and m.fin + v_gracia)::int as activas,
           -- 0188: una renovación ya está en «activas» (gracia): no se suma otra vez mientras paga.
           (select count(*) from mensualidad_solicitudes s
             where s.hora = h.hora and s.estado = 'esperando_pago' and not s.es_renovacion
               and s.creado_at > now() - interval '24 hours')::int as apartadas,
           (select count(*) from mensualidad_solicitudes s
             where s.hora = h.hora and s.estado = 'pagada' and not s.es_renovacion)::int as pagadas,
           (select count(*) from mensualidad_solicitudes s
             where s.hora = h.hora and s.estado = 'lista_espera'
               and s.creado_at > now() - interval '90 days')::int as en_espera
      from horas h
  )
  select jsonb_build_object(
    'ok', true, 'tope', v_tope, 'valor_cop', v_valor,
    'horas', coalesce(jsonb_agg(jsonb_build_object(
        'hora', to_char(c.hora,'HH24:MI'),
        'etiqueta', ltrim(to_char(c.hora,'HH12:MI am'),'0'),
        'ocupadas', c.activas + c.apartadas + c.pagadas,
        'activas', c.activas,
        'por_procesar', c.pagadas,
        'apartadas', c.apartadas,
        'en_espera', c.en_espera,
        'tope', c.tope_hora,
        'reservadas_lista', (select count(*) from mensualidad_fila(c.hora) f where f.aplica)::int,
        'libres', greatest(c.tope_hora - (c.activas + c.apartadas + c.pagadas)
                           - (select count(*) from mensualidad_fila(c.hora) f where f.aplica)::int, 0)
      ) order by c.orden), '[]'::jsonb))
    into v_out from cuenta c;
  return v_out;
end; $function$;

-- ─── 2 · la solicitud nueva ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.mensualidad_solicitar_v2(
  p_nombre text, p_celular text, p_hora text,
  p_documento text default null, p_correo text default null,
  p_modo text default 'nueva',                 -- 'nueva' (primera vez) | 'renovacion'
  p_nacimiento date default null,
  p_salud jsonb default null,                  -- {corazon, pecho, lesion, embarazo, otra: boolean, detalle: texto}
  p_datos boolean default false,               -- aceptó el tratamiento de datos (incluida la huella)
  p_salud_ok boolean default false             -- aceptó la declaración de salud
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_hora time; v_gracia int; v_celular text;
  v_en_gracia boolean := false; v_conocida boolean := false;
  v_libres int; v_pagara boolean := false; v_previa mensualidad_solicitudes;
  v_r jsonb; v_id uuid; v_estado text; v_salud jsonb; v_alerta boolean := false;
  v_primera boolean; v_ren boolean; v_ev jsonb; k text;
begin
  v_celular := right(regexp_replace(coalesce(p_celular,''), '\D', '', 'g'), 10);
  if coalesce(p_celular,'') !~ '^\d{10}$' then
    return jsonb_build_object('ok', false, 'error', 'CELULAR_INVALIDO'); end if;
  if length(btrim(coalesce(p_nombre,''))) < 2 then
    return jsonb_build_object('ok', false, 'error', 'NOMBRE_CORTO'); end if;
  begin v_hora := btrim(p_hora)::time;
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'HORA_INVALIDA'); end;

  v_gracia := coalesce(nullif((select valor from ajustes where clave = 'mensualidad_gracia_dias'), '')::int, 3);

  -- ¿Ya es alumna de este horario (vigente o en gracia)? Entonces su cupo ya es suyo.
  select exists (select 1 from membresias m
                  where right(regexp_replace(coalesce(m.celular,''), '\D', '', 'g'), 10) = v_celular
                    and m.hora = v_hora
                    and current_date between m.inicio and m.fin + v_gracia)
    into v_en_gracia;

  -- ¿Ha sido alumna alguna vez? (membresía de cualquier horario o historial de plan)
  v_conocida := v_en_gracia or exists (select 1 from membresias m
                  where right(regexp_replace(coalesce(m.celular,''), '\D', '', 'g'), 10) = v_celular);
  if not v_conocida then
    begin
      v_ev := premium_evaluar(v_celular);
      v_conocida := coalesce((v_ev -> 'personas' -> 0 ->> 'meses_con_plan_en_total')::int, 0) > 0
                    and (v_ev ->> 'encontradas')::int = 1;
    exception when others then null; end;
  end if;

  if p_modo = 'renovacion' and not v_conocida then
    return jsonb_build_object('ok', false, 'error', 'NO_ENCONTRADA',
      'mensaje', 'No te encontramos como alumna con ese celular. Si es tu primera vez, completa tus datos.');
  end if;

  v_primera := not v_conocida;
  v_ren := v_en_gracia;

  -- ¿Va a poder pagar? (para exigir los datos de registro solo cuando de verdad hay compra)
  if v_ren then
    v_pagara := true;
  else
    select * into v_previa from mensualidad_solicitudes
     where celular = v_celular and hora = v_hora and estado in ('lista_espera','esperando_pago','pagada')
       and creado_at > now() - interval '24 hours' order by creado_at desc limit 1;
    if found and v_previa.estado in ('esperando_pago','pagada') then v_pagara := true; end if;
    if not v_pagara then
      select (h->>'libres')::int into v_libres
        from jsonb_array_elements(mensualidad_cupos()->'horas') h
       where h->>'hora' = to_char(v_hora,'HH24:MI');
      v_pagara := coalesce(v_libres,0) > 0 or premium_puede_pagar(v_celular, p_documento, v_hora);
    end if;
  end if;

  -- Datos de registro: solo a quien es nueva y va a pagar.
  if v_primera and v_pagara then
    if p_nacimiento is null or p_nacimiento > current_date - interval '10 years'
       or p_nacimiento < current_date - interval '100 years' then
      return jsonb_build_object('ok', false, 'error', 'DATOS_INCOMPLETOS', 'campo', 'nacimiento',
        'mensaje', 'Falta tu fecha de nacimiento.'); end if;
    if coalesce(p_correo,'') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      return jsonb_build_object('ok', false, 'error', 'DATOS_INCOMPLETOS', 'campo', 'correo',
        'mensaje', 'Falta un correo válido.'); end if;
    if position(' ' in btrim(p_nombre)) = 0 then
      return jsonb_build_object('ok', false, 'error', 'DATOS_INCOMPLETOS', 'campo', 'nombre',
        'mensaje', 'Escribe tu nombre completo, con apellido.'); end if;
    if not coalesce(p_datos, false) then
      return jsonb_build_object('ok', false, 'error', 'DATOS_INCOMPLETOS', 'campo', 'datos',
        'mensaje', 'Falta autorizar el tratamiento de tus datos.'); end if;
    if p_salud is null then
      return jsonb_build_object('ok', false, 'error', 'DATOS_INCOMPLETOS', 'campo', 'salud',
        'mensaje', 'Contesta las preguntas de salud.'); end if;
    foreach k in array array['corazon','pecho','lesion','embarazo','otra'] loop
      if jsonb_typeof(p_salud -> k) is distinct from 'boolean' then
        return jsonb_build_object('ok', false, 'error', 'DATOS_INCOMPLETOS', 'campo', 'salud',
          'mensaje', 'Contesta todas las preguntas de salud.'); end if;
      v_alerta := v_alerta or (p_salud ->> k)::boolean;
    end loop;
    if not coalesce(p_salud_ok, false) then
      return jsonb_build_object('ok', false, 'error', 'DATOS_INCOMPLETOS', 'campo', 'salud_ok',
        'mensaje', 'Falta aceptar la declaración de salud.'); end if;
  end if;

  -- La solicitud se crea (o se reencuentra) con la lógica de siempre.
  v_r := mensualidad_solicitar(p_nombre, v_celular, p_hora, p_documento, p_correo);
  if not coalesce((v_r ->> 'ok')::boolean, false) then return v_r; end if;
  v_id := (v_r ->> 'id')::uuid;
  v_estado := v_r ->> 'estado';

  -- Quien renueva su mismo horario paga sin esperar cupo: ya es suyo.
  if v_ren and v_estado = 'lista_espera' then
    update mensualidad_solicitudes set estado = 'esperando_pago' where id = v_id;
    v_estado := 'esperando_pago';
  end if;

  if v_primera and p_salud is not null then
    v_salud := jsonb_build_object(
      'corazon', (p_salud ->> 'corazon')::boolean, 'pecho', (p_salud ->> 'pecho')::boolean,
      'lesion', (p_salud ->> 'lesion')::boolean, 'embarazo', (p_salud ->> 'embarazo')::boolean,
      'otra', (p_salud ->> 'otra')::boolean, 'alerta', v_alerta,
      'detalle', left(coalesce(p_salud ->> 'detalle', ''), 400));
  end if;

  update mensualidad_solicitudes set
      primera_vez = v_primera and v_estado = 'esperando_pago',
      es_renovacion = v_ren,
      fecha_nacimiento = coalesce(p_nacimiento, fecha_nacimiento),
      salud = coalesce(v_salud, salud),
      datos_aceptados_at = case when coalesce(p_datos, false) then coalesce(datos_aceptados_at, now()) else datos_aceptados_at end,
      salud_aceptada_at = case when coalesce(p_salud_ok, false) then coalesce(salud_aceptada_at, now()) else salud_aceptada_at end
    where id = v_id;

  return v_r || jsonb_build_object('estado', v_estado, 'primera_vez', v_primera and v_estado = 'esperando_pago',
                                   'es_renovacion', v_ren);
end; $function$;

-- ─── 4 · lo que ve recepción ─────────────────────────────────────────────────────────────────────────────────
create or replace function public.mensualidad_lista(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_admin uuid;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO'); end if;
  return jsonb_build_object('ok', true, 'cupos', mensualidad_cupos(),
    'solicitudes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id,
               'cuando', to_char(s.creado_at at time zone 'America/Bogota','DD/MM HH24:MI'),
               'dias', (current_date - (s.creado_at at time zone 'America/Bogota')::date),
               'nombre', s.nombre, 'celular', s.celular, 'documento', s.documento,
               'correo', s.correo, 'hora', to_char(s.hora,'HH24:MI'),
               'estado', s.estado, 'valor_cop', s.valor_cop,
               'referencia', s.referencia, 'pagado_en', s.pagado_en, 'nota', s.nota,
               'primera_vez', s.primera_vez, 'es_renovacion', s.es_renovacion,
               'nacimiento', s.fecha_nacimiento, 'salud', s.salud,
               'datos_aceptados', s.datos_aceptados_at is not null)
             order by case s.estado when 'pagada' then 0 when 'esperando_pago' then 1
                                    when 'lista_espera' then 2 else 3 end, s.creado_at)
        from mensualidad_solicitudes s
       where s.estado <> 'anulada' and s.creado_at > now() - interval '90 days'), '[]'::jsonb));
end; $function$;
