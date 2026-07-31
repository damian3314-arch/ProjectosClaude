-- ═══════════════════════════════════════════════════════════════
--
--   TUMBAO — EL SÁBADO, 15 Y 15
--
--   Pégalo entero en el SQL Editor de Supabase y dale Run.
--   Se puede correr las veces que quieras.
--
--   ¿Qué hace? Parte el aforo del sábado en dos cupos independientes:
--   15 puestos para afiliados y 15 para clase suelta. Cuando se llenan
--   los 15 de plan no entra ningún afiliado más, aunque queden sueltas
--   libres — y al revés.
--
--   Y el cliente no se entera del reparto.
--
--   CÓMO SE MANTIENE INVISIBLE
--   La página ya sabe quién está mirando: lo primero que pregunta es
--   "¿vienes con mensualidad o por clase suelta?". Así que no hay que
--   esconder nada — a cada quien se le contesta el número de SU lado.
--   Los números del otro lado ni siquiera salen del servidor, así que
--   no hay nada que encontrar mirando la respuesta.
--
--   Cuando un lado se llena, el mensaje es el mismo de siempre
--   ("Esa clase se llenó"), justo para no delatar el reparto.
--
--   ENTRE SEMANA NO CAMBIA NADA. Ahí el afiliado ni siquiera reserva:
--   su puesto ya está descontado del aforo.
--
--   ¿Y si mañana quieres 20 y 10? Es un número guardado, no una
--   fórmula:
--
--     update clases set cupo_miembros = 20, cupo_sueltas = 10
--      where extract(dow from fecha_hora at time zone 'America/Bogota') = 6
--        and fecha_hora > now();
--
--   (y cambia el `/ 2` de generar_horario para los sábados nuevos)
--
--   Agrega dos columnas a `clases` y un índice. No borra nada.
--
-- ═══════════════════════════════════════════════════════════════

-- =====================================================================
-- El sábado, 15 y 15
--
-- QUÉ SE PIDE
-- Partir el aforo del sábado: 15 puestos para afiliados y 15 para clase
-- suelta, como dos cupos independientes. Cuando se llenen los 15 de
-- plan, no entra ningún afiliado más aunque queden sueltas libres, y al
-- revés.
--
-- Y que el cliente NO se entere del reparto.
--
-- CÓMO SE MANTIENE INVISIBLE
-- Resulta que la página ya sabe quién está mirando: lo primero que
-- pregunta es "¿vienes con mensualidad o por clase suelta?". Así que no
-- hace falta esconder nada — basta con contestarle a cada quien el
-- número de SU lado. Un afiliado ve los que quedan de afiliados, quien
-- viene por suelta ve los suyos, y ninguno de los dos ve un reparto.
--
-- Por eso el endpoint público pasa a ser `clases_para(tipo)`: devuelve
-- el mundo tal como lo ve ese tipo de persona. Los números del otro lado
-- ni siquiera salen del servidor, así que no hay nada que encontrar
-- mirando la respuesta.
--
-- POR QUÉ DOS COLUMNAS Y NO UN PORCENTAJE
-- Porque 15 y 15 es una decisión de negocio que puede cambiar a 20 y 10
-- sin avisar. Un número guardado se cambia; una fórmula hay que
-- reescribirla.
--
-- Van en NULL para todas las demás clases, y null significa "sin
-- reparto": entre semana todo sigue exactamente igual que hoy.
--
-- POR QUÉ NO HAY CONTADORES NUEVOS
-- La tentación era `tomado_miembros` y `tomado_sueltas`. Serían dos
-- contadores más que mantener sincronizados en tomar_cupo, en rechazar
-- y en deshacer — y ya vimos lo que cuesta cada contador desalineado.
-- Se cuentan las reservas vivas en el momento de decidir, dentro del
-- mismo `select ... for update` que ya protege el cupo. Son decenas de
-- filas por clase: contar sale gratis y no se puede desincronizar.
-- =====================================================================

alter table clases add column if not exists cupo_miembros int
  check (cupo_miembros is null or cupo_miembros >= 0);
alter table clases add column if not exists cupo_sueltas  int
  check (cupo_sueltas  is null or cupo_sueltas  >= 0);

comment on column clases.cupo_miembros is
  'Tope de reservas de afiliados en esta clase. NULL = sin reparto, el cupo es uno solo y compartido.';
comment on column clases.cupo_sueltas is
  'Tope de reservas de clase suelta. NULL = sin reparto.';

-- Buscar las reservas vivas de una clase por tipo es lo que se hace en
-- cada consulta del horario y en cada intento de reserva.
create index if not exists reservas_por_clase_y_tipo
  on reservas (clase_id, tipo, estado);


-- ---------------------------------------------------------------------
-- El sábado nace partido
-- ---------------------------------------------------------------------
-- El orden de los parametros es el de 0009 y no se toca. Cambiarlo no
-- reemplaza la funcion: crea una SEGUNDA con otra firma, y a partir de
-- ahi cualquier llamada con solo dos fechas queda ambigua y falla con
-- "function generar_horario(date, date) is not unique". Paso.
create or replace function generar_horario(
  p_desde date,
  p_hasta date,
  p_precio_cop int default 15000,
  p_aforo int default 30,
  p_profesor text default 'Por asignar',
  p_lugar text default 'Sede Tumbao')
returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_creadas int;
begin
  with horario as (
    -- dow: 1=lunes … 5=viernes, 6=sábado
    select * from (values
      (array[1,2,3,4,5], time '07:00', 'Clase 7:00 am'),
      (array[1,2,3,4,5], time '18:00', 'Clase 6:00 pm'),
      (array[1,2,3,4,5], time '19:00', 'Clase 7:00 pm'),
      (array[6],         time '08:00', 'Clase 8:00 am'),
      (array[6],         time '09:00', 'Clase 9:00 am')
    ) as h(dows, hora, nombre)
  ),
  dias as (
    select (p_desde + g)::date as dia
    from generate_series(0, (p_hasta - p_desde)) g
  ),
  nuevas as (
    insert into clases (nombre, profesor, fecha_hora, duracion_min,
                        cupo_total, precio_cop, lugar, aforo, activa,
                        cupo_miembros, cupo_sueltas)
    select h.nombre, p_profesor,
           (dias.dia + h.hora) at time zone 'America/Bogota',
           60, p_aforo, p_precio_cop, p_lugar, p_aforo, true,
           -- Solo el sábado se parte. Entre semana el afiliado ni
           -- siquiera reserva: su puesto ya está descontado del aforo.
           case when 6 = any(h.dows) then p_aforo / 2 end,
           case when 6 = any(h.dows) then p_aforo - p_aforo / 2 end
    from dias
    join horario h on extract(dow from dias.dia)::int = any(h.dows)
    where not exists (
      select 1 from clases c
       where c.fecha_hora = (dias.dia + h.hora) at time zone 'America/Bogota'
    )
    returning 1
  )
  select count(*)::int into v_creadas from nuevas;

  return v_creadas;
end;
$$;

-- Y los sábados que ya estaban creados, que son los de estas semanas.
update clases
   set cupo_miembros = aforo / 2,
       cupo_sueltas  = aforo - aforo / 2
 where extract(dow from fecha_hora at time zone 'America/Bogota') = 6
   and fecha_hora > now()
   and cupo_miembros is null;


-- ---------------------------------------------------------------------
-- El horario, visto por quien lo está mirando
--
-- Devuelve las mismas columnas de siempre, pero con `cupo_total` y
-- `cupo_tomado` ya traducidos al lado de esa persona, de forma que
-- `cupo_total - cupo_tomado` siga siendo los cupos que le quedan. Así
-- n8n no tiene que saber nada de repartos: sigue restando igual.
-- ---------------------------------------------------------------------
create or replace function clases_para(p_tipo text default 'suelta')
returns table (
  id           uuid,
  nombre       text,
  profesor     text,
  lugar        text,
  fecha_hora   timestamptz,
  duracion_min int,
  precio_cop   int,
  cupo_total   int,
  cupo_tomado  int)
language sql
security definer
set search_path = public, extensions, pg_temp
as $$
  with vivas as (
    select r.clase_id, count(*)::int as n
      from reservas r
     where r.tipo = (case when p_tipo = 'miembro' then 'miembro' else 'suelta' end)::tipo_reserva
       and r.estado not in ('rechazada', 'expirada')
     group by r.clase_id
  ),
  calc as (
    select c.*,
           coalesce(v.n, 0) as tomadas_tipo,
           case when p_tipo = 'miembro' then c.cupo_miembros else c.cupo_sueltas end
             as tope_tipo
      from clases c
      left join vivas v on v.clase_id = c.id
     where c.activa
       and c.fecha_hora > now()
  )
  select
    k.id, k.nombre, k.profesor, k.lugar, k.fecha_hora,
    k.duracion_min, k.precio_cop,
    -- Sin reparto, todo sigue igual que siempre.
    coalesce(k.tope_tipo, k.cupo_total) as cupo_total,
    case when k.tope_tipo is null then k.cupo_tomado
         -- Con reparto, se devuelven dos números cuya resta es el cupo
         -- real: el menor entre lo que queda del tope de su lado y lo
         -- que queda del aforo compartido.
         else k.tope_tipo - greatest(least(
                k.cupo_total - k.cupo_tomado,
                k.tope_tipo  - k.tomadas_tipo), 0)
    end as cupo_tomado
  from calc k
  order by k.fecha_hora;
$$;

comment on function clases_para(text) is
  'El horario tal como lo ve un miembro o alguien de clase suelta. Los numeros del otro lado no salen del servidor: el reparto del sabado es invisible para el cliente.';


-- ---------------------------------------------------------------------
-- Y la puerta de verdad: tomar_cupo
--
-- Lo de arriba es lo que se muestra. Esto es lo que decide, y es lo
-- único que impide pasarse: dos personas del mismo tipo dando al botón
-- a la vez hacen fila sobre la misma fila de `clases`.
-- ---------------------------------------------------------------------
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
  v_tope      int;
  v_tomadas   int;
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

    v_estado := 'confirmada';
  end if;

  ------------------------------------------------------------------
  -- Cupo compartido: el techo de la sala, siempre manda
  ------------------------------------------------------------------
  if v_clase.cupo_tomado >= v_clase.cupo_total then
    return jsonb_build_object('ok', false, 'error', 'SIN_CUPO',
      'mensaje', 'Esa clase se llenó. Elige otro horario.');
  end if;

  ------------------------------------------------------------------
  -- Cupo del lado que le toca, cuando la clase está partida
  --
  -- Se cuenta aquí y no en un contador guardado: ya estamos dentro del
  -- `for update` de la clase, así que dos personas del mismo tipo no
  -- pueden leer la misma cuenta y pasar las dos.
  --
  -- El mensaje es el MISMO que el de sin cupo, a propósito: si dijera
  -- "se acabaron los de afiliados" el cliente se enteraría del reparto,
  -- que es justo lo que no se quiere.
  ------------------------------------------------------------------
  v_tope := case when p_tipo = 'miembro' then v_clase.cupo_miembros
                 else v_clase.cupo_sueltas end;
  if v_tope is not null then
    select count(*) into v_tomadas
      from reservas r
     where r.clase_id = p_clase_id
       and r.tipo = p_tipo::tipo_reserva
       and r.estado not in ('rechazada', 'expirada');
    if v_tomadas >= v_tope then
      return jsonb_build_object('ok', false, 'error', 'SIN_CUPO',
        'mensaje', 'Esa clase se llenó. Elige otro horario.');
    end if;
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
    'cupos_restantes', greatest(v_clase.cupo_total - v_clase.cupo_tomado - 1, 0));
end;
$$;


-- ---------------------------------------------------------------------
-- El panel SÍ lo ve
--
-- El cliente no tiene por qué enterarse del reparto, pero quien mira el
-- tablero sí: sin esto, "4 libres" el sábado no se puede interpretar.
-- ---------------------------------------------------------------------
create or replace function admin_tablero(p_token text, p_dia date default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_dia    date;
  v_clases jsonb;
  v_hoy    date;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  v_hoy := (now() at time zone 'America/Bogota')::date;
  v_dia := coalesce(p_dia, v_hoy);

  select coalesce(jsonb_agg(x order by x->>'hora'), '[]'::jsonb) into v_clases
  from (
    select jsonb_build_object(
      'clase_id',    c.id,
      'nombre',      c.nombre,
      'hora',        to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'),
      'activa',      c.activa,
      'ya_paso',     c.fecha_hora <= now(),
      'aforo',       c.aforo,
      'con_plan',    c.activos_plan,
      'a_la_venta',  c.cupo_total,
      'cupo_manual', c.cupo_manual,
      'vencen',      v.vencen,
      'reservadas',  c.cupo_tomado,
      'libres',      greatest(c.cupo_total - c.cupo_tomado, 0),
      'confirmadas', n.confirmadas,
      'por_validar', n.por_validar,
      'esperando',   n.esperando,
      'en_sala',     c.activos_plan + c.cupo_tomado,
      'ingreso_cop', n.confirmadas * c.precio_cop,
      -- El reparto, solo si esta clase lo tiene
      'reparto', case when c.cupo_miembros is null then null else
        jsonb_build_object(
          'miembros_tope',    c.cupo_miembros,
          'miembros_tomados', n.de_miembros,
          'miembros_libres',  greatest(c.cupo_miembros - n.de_miembros, 0),
          'sueltas_tope',     c.cupo_sueltas,
          'sueltas_tomadas',  n.de_sueltas,
          'sueltas_libres',   greatest(c.cupo_sueltas - n.de_sueltas, 0))
      end
    ) as x
    from clases c
    cross join lateral (
      select
        count(*) filter (where r.estado = 'confirmada')::int            as confirmadas,
        count(*) filter (where r.estado = 'pendiente_validacion')::int  as por_validar,
        count(*) filter (where r.estado in ('pendiente_pago','verificando'))::int as esperando,
        count(*) filter (where r.tipo = 'miembro'
                           and r.estado not in ('rechazada','expirada'))::int as de_miembros,
        count(*) filter (where r.tipo = 'suelta'
                           and r.estado not in ('rechazada','expirada'))::int as de_sueltas
      from reservas r where r.clase_id = c.id
    ) n
    cross join lateral (
      select count(*)::int as vencen
        from membresias m
       where m.hora = (c.fecha_hora at time zone 'America/Bogota')::time
         and (c.fecha_hora at time zone 'America/Bogota')::date
             between m.inicio and m.fin
         and m.fin = (c.fecha_hora at time zone 'America/Bogota')::date
    ) v
   where (c.fecha_hora at time zone 'America/Bogota')::date = v_dia
  ) s;

  return jsonb_build_object(
    'ok', true,
    'dia', v_dia,
    'es_hoy', v_dia = v_hoy,
    'clases', v_clases,
    'resumen', jsonb_build_object(
      'clases',      jsonb_array_length(v_clases),
      'aforo',       coalesce((select sum((c->>'aforo')::int)       from jsonb_array_elements(v_clases) c), 0),
      'con_plan',    coalesce((select sum((c->>'con_plan')::int)    from jsonb_array_elements(v_clases) c), 0),
      'vencen',      coalesce((select sum((c->>'vencen')::int)      from jsonb_array_elements(v_clases) c), 0),
      'a_la_venta',  coalesce((select sum((c->>'a_la_venta')::int)  from jsonb_array_elements(v_clases) c), 0),
      'reservadas',  coalesce((select sum((c->>'reservadas')::int)  from jsonb_array_elements(v_clases) c), 0),
      'libres',      coalesce((select sum((c->>'libres')::int)      from jsonb_array_elements(v_clases) c), 0),
      'confirmadas', coalesce((select sum((c->>'confirmadas')::int) from jsonb_array_elements(v_clases) c), 0),
      'por_validar', coalesce((select sum((c->>'por_validar')::int) from jsonb_array_elements(v_clases) c), 0),
      'esperando',   coalesce((select sum((c->>'esperando')::int)   from jsonb_array_elements(v_clases) c), 0),
      'en_sala',     coalesce((select sum((c->>'en_sala')::int)     from jsonb_array_elements(v_clases) c), 0),
      'ingreso_cop', coalesce((select sum((c->>'ingreso_cop')::int) from jsonb_array_elements(v_clases) c), 0)
    ));
end;
$$;


revoke execute on function clases_para(text)                        from public, anon, authenticated;
revoke execute on function tomar_cupo(uuid, text, text, text, text, text) from public, anon, authenticated;
revoke execute on function generar_horario(date, date, int, int, text, text) from public, anon, authenticated;
revoke execute on function admin_tablero(text, date)                from public, anon, authenticated;

-- ── Comprobación: esto tiene que decir "sabado OK" ───────────────
do $$
declare
  v_n int; v_mal text; v_sab record;
begin
  -- 1. Todos los sabados futuros tienen que haber quedado partidos.
  select count(*) into v_n from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') = 6
     and fecha_hora > now() and cupo_miembros is null;
  if v_n > 0 then
    raise exception '% sabados futuros se quedaron sin reparto', v_n;
  end if;

  -- 2. Y entre semana NO puede haberse puesto ninguno.
  select count(*) into v_n from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') <> 6
     and cupo_miembros is not null;
  if v_n > 0 then
    raise exception '% clases de entre semana quedaron partidas por error', v_n;
  end if;

  -- 3. El reparto tiene que caber en el aforo de cada clase.
  select string_agg(to_char(fecha_hora at time zone 'America/Bogota',
                            'DD Mon HH24:MI'), ', ') into v_mal
    from clases
   where cupo_miembros is not null
     and cupo_miembros + cupo_sueltas > aforo;
  if v_mal is not null then
    raise exception 'el reparto no cabe en el aforo en: %', v_mal;
  end if;

  select count(*) into v_n from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') = 6
     and fecha_hora > now();
  raise notice 'sabado OK — % sabados futuros repartidos 15/15, entre semana sin tocar', v_n;
end $$;

select 'Sabado partido' as resultado;
