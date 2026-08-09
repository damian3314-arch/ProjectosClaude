-- Cheo recibe notas de voz y fotos.
--
-- Ojo al leer 01_cheo.sql: este archivo REEMPLAZA tres de sus funciones
-- (cheo_guardar_turno, cheo_historial y cheo_semana). Si vas a montar
-- esto desde cero, corre 01 y despues 02.

-- Se guarda POR QUE MEDIO llego cada mensaje. No es adorno: si la gente
-- prefiere hablar a escribir, eso cambia por donde hay que abrirle la
-- puerta, y sale en el reporte semanal.
alter table public.cheo_mensajes
  add column if not exists medio text not null default 'texto'
  check (medio in ('texto','voz','foto'));

comment on column public.cheo_mensajes.medio is
  'Como llego el mensaje. Las fotos NO se guardan: se guarda lo que Cheo vio, igual que con los comprobantes.';

-- Firma nueva (se agrega p_medio). Se borra la vieja para que PostgREST
-- no quede con dos funciones ambiguas.
drop function if exists public.cheo_guardar_turno(text, text, text);

create or replace function public.cheo_guardar_turno(
  p_sesion_id text,
  p_usuario   text,
  p_cheo      text,
  p_medio     text default 'texto'
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_conv record;
  v_medio text;
begin
  select * into v_conv from cheo_conversaciones where sesion_id = p_sesion_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_existe');
  end if;

  if v_conv.mensajes_count >= 120 then
    return jsonb_build_object('ok', false, 'error', 'conversacion_muy_larga');
  end if;

  v_medio := case when p_medio in ('texto','voz','foto') then p_medio else 'texto' end;

  if coalesce(trim(p_usuario), '') <> '' then
    insert into cheo_mensajes (conversacion_id, rol, texto, medio)
    values (v_conv.id, 'usuario', left(p_usuario, 4000), v_medio);
  end if;

  -- Cheo siempre responde en texto, sin importar como le hablaron.
  if coalesce(trim(p_cheo), '') <> '' then
    insert into cheo_mensajes (conversacion_id, rol, texto, medio)
    values (v_conv.id, 'cheo', left(p_cheo, 4000), 'texto');
  end if;

  update cheo_conversaciones
  set ultima_actividad = now(),
      mensajes_count = mensajes_count
        + (case when coalesce(trim(p_usuario), '') <> '' then 1 else 0 end)
        + (case when coalesce(trim(p_cheo), '') <> '' then 1 else 0 end),
      clasificada = false,
      estado = 'abierta',
      cerrada_en = null
  where id = v_conv.id;

  return jsonb_build_object('ok', true, 'conversacion_id', v_conv.id);
end $$;


-- El historial ahora dice por que medio llego cada mensaje, para que la
-- burbuja pinte la marquita de nota de voz o de foto al reabrir. Sin eso,
-- la descripcion de una foto se leeria como si la persona la hubiera
-- escrito.
create or replace function public.cheo_historial(
  p_sesion_id text,
  p_limite    integer default 24
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_conv record; v_msgs jsonb;
begin
  select * into v_conv from cheo_conversaciones where sesion_id = p_sesion_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_existe');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('rol', ult.rol, 'texto', ult.texto, 'medio', ult.medio)
                            order by ult.id), '[]'::jsonb)
    into v_msgs
  from (
    select id, rol, texto, medio from cheo_mensajes
    where conversacion_id = v_conv.id
    order by id desc
    limit greatest(coalesce(p_limite, 24), 1)
  ) ult;

  return jsonb_build_object(
    'ok', true,
    'conversacion_id', v_conv.id,
    'mensajes_count', v_conv.mensajes_count,
    'nombre', v_conv.nombre,
    'telefono', v_conv.telefono,
    'email', v_conv.email,
    'origen', v_conv.origen,
    'mensajes', v_msgs
  );
end $$;


-- El reporte semanal ahora tambien cuenta por que medio hablo la gente.
create or replace function public.cheo_semana(
  p_desde date default null,
  p_hasta date default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_desde date; v_hasta date;
  v_convs jsonb; v_total int; v_msgs int; v_conteo jsonb; v_medios jsonb;
begin
  v_hasta := coalesce(p_hasta, (date_trunc('week', (now() at time zone 'America/Bogota')))::date - 1);
  v_desde := coalesce(p_desde, v_hasta - 6);

  select count(*)::int, coalesce(sum(mensajes_count), 0)::int
    into v_total, v_msgs
  from cheo_conversaciones
  where (ultima_actividad at time zone 'America/Bogota')::date between v_desde and v_hasta
    and mensajes_count > 0;

  select coalesce(jsonb_agg(t order by (t->>'urgencia')::int desc), '[]'::jsonb) into v_convs from (
    select jsonb_build_object(
      'origen', c.origen,
      'tipo', coalesce(c.tipo, 'sin_clasificar'),
      'tema', c.tema,
      'resumen', c.resumen,
      'urgencia', coalesce(c.urgencia, 3),
      'sentimiento', coalesce(c.sentimiento, 'neutral'),
      'accion_sugerida', c.accion_sugerida,
      'dejo_contacto', (c.telefono is not null or c.email is not null),
      -- OJO: esto trae VARIOS mensajes pegados con ' | '. El prompt del
      -- reporte tiene que saberlo, o el modelo copia el bloque entero
      -- creyendo que es una sola cita.
      'dice_la_persona', left(coalesce((
          select string_agg(m.texto, ' | ' order by m.id)
          from cheo_mensajes m
          where m.conversacion_id = c.id and m.rol = 'usuario'), ''), 1200)
    ) as t
    from cheo_conversaciones c
    where (c.ultima_actividad at time zone 'America/Bogota')::date between v_desde and v_hasta
      and c.mensajes_count > 0
    limit 200
  ) s;

  select coalesce(jsonb_object_agg(tipo, n), '{}'::jsonb) into v_conteo from (
    select coalesce(tipo, 'sin_clasificar') as tipo, count(*)::int as n
    from cheo_conversaciones
    where (ultima_actividad at time zone 'America/Bogota')::date between v_desde and v_hasta
      and mensajes_count > 0
    group by 1
  ) k;

  select coalesce(jsonb_object_agg(medio, n), '{}'::jsonb) into v_medios from (
    select m.medio, count(*)::int as n
    from cheo_mensajes m
    join cheo_conversaciones c on c.id = m.conversacion_id
    where (c.ultima_actividad at time zone 'America/Bogota')::date between v_desde and v_hasta
      and m.rol = 'usuario'
    group by 1
  ) mm;

  return jsonb_build_object(
    'ok', true,
    'semana_inicio', v_desde,
    'semana_fin', v_hasta,
    'total_conversaciones', v_total,
    'total_mensajes', v_msgs,
    'por_tipo', v_conteo,
    'por_medio', v_medios,
    'conversaciones', v_convs
  );
end $$;
