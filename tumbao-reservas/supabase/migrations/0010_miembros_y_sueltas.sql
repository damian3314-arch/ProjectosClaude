-- =====================================================================
-- Dos caminos en la página: miembro o clase suelta
--
-- REGLA
-- El plan (mensualidad o media) asegura las clases ENTRE SEMANA en el
-- horario del plan. El sábado NO está cubierto: ahí el miembro también
-- tiene que reservar, pero sin pagar.
--
-- La persona elige al principio y eso decide todo lo demás:
--   miembro       -> no se le pide soporte de pago
--   clase suelta  -> paga y sube el soporte
--
-- POR QUÉ SE VERIFICA Y NO SE CREE NOMÁS
-- Ya tenemos la tabla `membresias` con celular y documento, así que
-- comprobar cuesta cero. Sin comprobar, cualquiera escribe "miembro" y
-- entra gratis.
--
-- UN PROBLEMA QUE HAY QUE ATAJAR
-- Los cupos de clase suelta ya se calculan como aforo − activos_plan.
-- El puesto del miembro entre semana YA está descontado ahí. Si además
-- lo dejáramos reservar entre semana, consumiría un cupo suelto y
-- estaríamos contando su puesto dos veces: la clase se vería llena
-- teniendo sitio. Por eso entre semana, en su propio horario, no se le
-- deja reservar — se le dice que ya está cubierto y que solo llegue.
-- =====================================================================

do $$ begin
  create type tipo_reserva as enum ('suelta', 'miembro');
exception when duplicate_object then null; end $$;

alter table reservas add column if not exists tipo tipo_reserva not null default 'suelta';
alter table reservas add column if not exists membresia_id bigint references membresias(id);

create index if not exists reservas_por_tipo on reservas (tipo, estado);


-- ---------------------------------------------------------------------
-- Solo dígitos, y sin el indicativo 57 de Colombia.
-- ---------------------------------------------------------------------
create or replace function solo_digitos(p text) returns text
language sql immutable
set search_path = public, extensions, pg_temp
as $$
  select case
    when length(regexp_replace(coalesce(p,''), '[^0-9]', '', 'g')) = 12
     and left(regexp_replace(coalesce(p,''), '[^0-9]', '', 'g'), 2) = '57'
    then substr(regexp_replace(coalesce(p,''), '[^0-9]', '', 'g'), 3)
    else regexp_replace(coalesce(p,''), '[^0-9]', '', 'g')
  end;
$$;


-- ---------------------------------------------------------------------
-- tomar_cupo con los dos caminos
-- ---------------------------------------------------------------------
drop function if exists tomar_cupo(uuid, text, text, text, text);

create or replace function tomar_cupo(
  p_clase_id uuid,
  p_nombre   text,
  p_telefono text,
  p_email    text,
  p_origen   text,
  p_tipo     text default 'suelta'
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_clase     clases%rowtype;
  v_reserva   reservas%rowtype;
  v_memb      membresias%rowtype;
  v_codigo    text;
  v_intentos  int := 0;
  v_tel       text;
  v_fecha     date;
  v_hora      time;
  v_es_sabado boolean;
  v_estado    estado_reserva := 'pendiente_pago';
  v_memb_id   bigint := null;
begin
  select * into v_clase from clases where id = p_clase_id for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'CLASE_NO_EXISTE',
      'mensaje', 'Esa clase ya no está disponible.');
  end if;
  if not v_clase.activa then
    return jsonb_build_object('ok', false, 'error', 'CLASE_INACTIVA',
      'mensaje', 'Esa clase fue cancelada.');
  end if;
  if v_clase.fecha_hora < now() then
    return jsonb_build_object('ok', false, 'error', 'CLASE_YA_PASO',
      'mensaje', 'Esa clase ya empezó. Elige otro horario.');
  end if;

  v_tel       := solo_digitos(p_telefono);
  v_fecha     := (v_clase.fecha_hora at time zone 'America/Bogota')::date;
  v_hora      := (v_clase.fecha_hora at time zone 'America/Bogota')::time;
  v_es_sabado := extract(dow from v_fecha)::int = 6;

  ------------------------------------------------------------------
  -- Camino miembro
  ------------------------------------------------------------------
  if p_tipo = 'miembro' then
    select * into v_memb
      from membresias m
     where v_fecha between m.inicio and m.fin
       and (solo_digitos(m.celular) = v_tel or solo_digitos(m.documento) = v_tel)
     order by m.fin desc
     limit 1;

    if not found then
      return jsonb_build_object('ok', false, 'error', 'MEMBRESIA_NO_ENCONTRADA',
        'mensaje', 'No encontramos una mensualidad activa con ese celular. '
                || 'Si crees que es un error escríbenos por WhatsApp; si vienes '
                || 'por clase suelta, elige esa opción.');
    end if;

    v_memb_id := v_memb.id;

    if not v_es_sabado then
      if v_memb.hora = v_hora then
        -- Su puesto ya está contado en activos_plan. Dejarlo reservar
        -- consumiría además un cupo suelto: el mismo puesto dos veces.
        return jsonb_build_object('ok', false, 'error', 'PLAN_YA_CUBRE',
          'mensaje', 'Tu plan ya te cubre esta clase, no necesitas reservar. '
                  || 'Solo llega 10 minutos antes.');
      else
        return jsonb_build_object('ok', false, 'error', 'OTRO_HORARIO',
          'mensaje', 'Tu plan es de las ' || to_char(v_memb.hora, 'HH12:MI am')
                  || '. Venir a otra hora entre semana es clase suelta: '
                  || 'elige esa opción.',
          'hora_plan', to_char(v_memb.hora, 'HH12:MI am'));
      end if;
    end if;

    -- Sábado: el plan no lo cubre, reserva sin pagar.
    v_estado := 'confirmada';
  end if;

  ------------------------------------------------------------------
  -- Cupo
  ------------------------------------------------------------------
  if v_clase.cupo_tomado >= v_clase.cupo_total then
    return jsonb_build_object('ok', false, 'error', 'SIN_CUPO',
      'mensaje', 'Esa clase se llenó. Elige otro horario.');
  end if;

  update clases set cupo_tomado = cupo_tomado + 1 where id = p_clase_id;

  loop
    v_intentos := v_intentos + 1;
    v_codigo := generar_codigo_reserva();
    begin
      insert into reservas (codigo, clase_id, nombre, telefono, email,
                            origen, tipo, estado, membresia_id)
      values (v_codigo, p_clase_id, p_nombre, v_tel, p_email,
              p_origen, p_tipo::tipo_reserva, v_estado, v_memb_id)
      returning * into v_reserva;
      exit;
    exception when unique_violation then
      if v_intentos >= 5 then raise; end if;
    end;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'tipo',        p_tipo,
    'requiere_pago', v_estado = 'pendiente_pago',
    'reserva_id',  v_reserva.id,
    'codigo',      v_reserva.codigo,
    'nombre',      v_reserva.nombre,
    'telefono',    v_reserva.telefono,
    'estado',      v_reserva.estado,
    'expira_en',   v_reserva.expira_en,
    'clase',       v_clase.nombre,
    'profesor',    v_clase.profesor,
    'fecha_hora',  v_clase.fecha_hora,
    'lugar',       v_clase.lugar,
    'precio_cop',  v_clase.precio_cop,
    'cupos_restantes', v_clase.cupo_total - v_clase.cupo_tomado - 1);
end;
$$;


-- ---------------------------------------------------------------------
-- Importar el reporte de afiliados
--
-- Reemplaza la tabla entera dentro de una transacción y recalcula los
-- cupos. Si algo falla, no queda a medias.
--
-- Recibe el array ya parseado por n8n: cada fila con afiliado,
-- membresia, hora, tipo, documento, celular, correo, inicio, fin.
-- ---------------------------------------------------------------------
create or replace function importar_membresias(p_filas jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_n        int;
  v_recalc   jsonb;
begin
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'formato_invalido');
  end if;

  select count(*) into v_n from jsonb_array_elements(p_filas);

  -- Un archivo vacío casi siempre es un error de exportación, no que
  -- Tumbao se quedó sin afiliados. Borrar todo dejaría cupos inflados.
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
         f->>'documento',
         f->>'celular',
         f->>'correo',
         (f->>'inicio')::date,
         (f->>'fin')::date
    from jsonb_array_elements(p_filas) f
   where f->>'hora' is not null
     and f->>'inicio' is not null
     and f->>'fin' is not null;

  get diagnostics v_n = row_count;

  v_recalc := recalcular_cupos();

  return jsonb_build_object('ok', true, 'membresias', v_n, 'cupos', v_recalc);
end;
$$;


revoke execute on function tomar_cupo(uuid, text, text, text, text, text) from public, anon, authenticated;
revoke execute on function importar_membresias(jsonb)                     from public, anon, authenticated;
revoke execute on function solo_digitos(text)                             from public, anon, authenticated;
grant  execute on function tomar_cupo(uuid, text, text, text, text, text) to service_role;
grant  execute on function importar_membresias(jsonb)                     to service_role;
