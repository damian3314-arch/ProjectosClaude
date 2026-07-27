-- ═══════════════════════════════════════════════════════════════
--
--   TUMBAO — HISTÓRICO DE MEMBRESÍAS
--
--   Corto. Pégalo en el SQL Editor de Supabase y dale Run.
--
--   ¿Para qué? Hoy la tabla de afiliados se borra y se recarga entera
--   cada noche. Eso está bien para saber quién está activo HOY, pero
--   significa que el ayer no existe: no se puede responder "¿cuántos
--   activos teníamos en junio?" ni "¿quién se fue?".
--
--   Eso NO se puede reconstruir después. Cada noche que pase sin esto
--   es un día de historia que se pierde para siempre. Por eso entra
--   ahora, aunque el dashboard que lo va a usar todavía no exista.
--
--   Después de pegarlo, la importación de cada noche guarda sola una
--   foto del día. No hay que hacer nada más.
--
--   Se puede correr las veces que quieras.
--
-- ═══════════════════════════════════════════════════════════════

-- =====================================================================
-- Foto diaria de las membresías
--
-- POR QUÉ AHORA Y NO DESPUÉS
-- `membresias` se borra y se recarga entera en cada importación. Es lo
-- correcto para saber quién está activo hoy, pero significa que el ayer
-- no existe: no se puede responder "¿cuántos activos teníamos en junio?"
-- ni "¿quién se fue?".
--
-- Eso no se puede reconstruir después. Cada día que pase sin guardar la
-- foto es un día de retención que no se va a poder analizar nunca. Por
-- eso entra ahora, aunque el dashboard que la va a usar todavía no
-- exista.
--
-- La foto la toma la misma `importar_membresias`, no un workflow aparte:
-- así no hay forma de que se importen membresías sin quedar registradas.
-- =====================================================================

create table if not exists membresias_historico (
  fecha_foto  date not null,
  afiliado    text not null,
  membresia   text not null,
  hora        time not null,
  tipo        text not null,
  documento   text,
  celular     text,
  inicio      date not null,
  fin         date not null,
  primary key (fecha_foto, afiliado, hora)
);

comment on table membresias_historico is
  'Una fila por afiliado activo por dia. La toma importar_membresias(). Solo se lee.';

create index if not exists membresias_historico_fecha on membresias_historico (fecha_foto);
create index if not exists membresias_historico_doc   on membresias_historico (documento, fecha_foto);

alter table membresias_historico enable row level security;


-- ---------------------------------------------------------------------
-- importar_membresias, ahora guardando la foto del día
--
-- Cambia solo eso respecto a 0010. La foto se toma DESPUÉS de cargar
-- `membresias`, y se reemplaza la del mismo día: correr la importación
-- dos veces en un día deja una sola foto, no dos.
--
-- La clave primaria es (fecha_foto, afiliado, hora), así que si el
-- reporte trae dos veces a la misma persona en el mismo horario, se
-- queda con una. Eso pasa: los nombres del reporte vienen escritos a
-- mano y hay duplicados.
-- ---------------------------------------------------------------------
create or replace function importar_membresias(p_filas jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_n      int;
  v_cupos  jsonb;
  v_foto   int;
  v_hoy    date := (now() at time zone 'America/Bogota')::date;
begin
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'formato_invalido',
      'mensaje', 'Se esperaba una lista de afiliados.');
  end if;

  v_n := jsonb_array_length(p_filas);

  -- Un archivo vacio casi siempre es un error de exportacion, no que
  -- Tumbao se quedo sin afiliados. Borrar dejaria los cupos inflados y
  -- se venderian puestos que no existen.
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'error', 'archivo_vacio',
      'mensaje', 'El archivo no trajo filas. No se toca nada.');
  end if;

  -- "where true" por la extension safeupdate de Supabase, que rechaza
  -- cualquier DELETE sin WHERE en las conexiones de PostgREST.
  delete from membresias where true;

  insert into membresias (afiliado, membresia, hora, tipo, documento,
                          celular, correo, inicio, fin)
  select f->>'afiliado',
         f->>'membresia',
         (f->>'hora')::time,
         coalesce(f->>'tipo', 'otro'),
         nullif(f->>'documento', ''),
         solo_digitos(f->>'celular'),
         nullif(f->>'correo', ''),
         (f->>'inicio')::date,
         (f->>'fin')::date
    from jsonb_array_elements(p_filas) f;

  -- ── la foto del dia ──────────────────────────────────────────────
  delete from membresias_historico where fecha_foto = v_hoy;

  insert into membresias_historico
    (fecha_foto, afiliado, membresia, hora, tipo, documento, celular, inicio, fin)
  select v_hoy, m.afiliado, m.membresia, m.hora, m.tipo,
         m.documento, m.celular, m.inicio, m.fin
    from membresias m
  on conflict (fecha_foto, afiliado, hora) do nothing;

  get diagnostics v_foto = row_count;

  select recalcular_cupos() into v_cupos;

  return jsonb_build_object('ok', true,
    'membresias', v_n,
    'foto_del_dia', jsonb_build_object('fecha', v_hoy, 'filas', v_foto),
    'cupos', v_cupos);
end;
$$;

revoke execute on function importar_membresias(jsonb) from public, anon, authenticated;
grant  execute on function importar_membresias(jsonb) to service_role;


-- ---------------------------------------------------------------------
-- Dos vistas que el dashboard va a necesitar, y que ya se pueden usar
-- desde el SQL Editor mientras tanto.
-- ---------------------------------------------------------------------

-- Quien vence en los proximos dias. Es la lista mas accionable que hay
-- en todo el sistema: se puede escribir hoy mismo.
create or replace view proximos_vencimientos as
  select afiliado, membresia, hora, documento, celular, fin,
         (fin - (now() at time zone 'America/Bogota')::date) as dias_restantes
    from membresias
   where fin >= (now() at time zone 'America/Bogota')::date
     and fin <  (now() at time zone 'America/Bogota')::date + 8
   order by fin, afiliado;

comment on view proximos_vencimientos is
  'Afiliados cuya membresia vence dentro de los proximos 7 dias.';

-- Cuantos activos habia cada dia, por horario. Se llena solo, un dia por
-- cada corrida de la importacion.
create or replace view activos_por_dia as
  select fecha_foto,
         hora,
         count(*)                                as activos,
         count(*) filter (where tipo = 'plan')   as plan,
         count(*) filter (where tipo = 'media')  as media
    from membresias_historico
   group by fecha_foto, hora
   order by fecha_foto desc, hora;

comment on view activos_por_dia is
  'Serie diaria de afiliados activos por horario. Alimenta el dashboard.';

alter view proximos_vencimientos set (security_invoker = on);
alter view activos_por_dia       set (security_invoker = on);


-- ═══════════════════════════════════════════════════════════════
--   Comprobación — mira la tabla de abajo
-- ═══════════════════════════════════════════════════════════════
select 'Historico listo' as estado,
       (select count(*) from membresias)              as afiliados_activos_hoy,
       (select count(*) from membresias_historico)    as filas_de_historia,
       (select count(*) from proximos_vencimientos)   as vencen_en_7_dias;

-- Y esta es la lista que ya puedes usar hoy mismo:
select * from proximos_vencimientos;
