-- ═══════════════════════════════════════════════════════════════════════
--
--   TUMBAO — CUPOS SIN RELOJ
--
--   Cópialo entero, pégalo en el SQL Editor de Supabase y dale Run.
--   Se puede correr las veces que quieras.
--
--   ¿Qué arregla? Que un cupo abandonado tarde hasta una hora en
--   soltarse, y que eso cueste 480 ejecuciones de n8n al mes.
--
--   Después de aplicarlo, el workflow "Tumbao · Liberar cupos vencidos"
--   sobra: se puede DESACTIVAR en n8n y recuperas esas 480.
--
--   NO BORRA DATOS. Solo reemplaza dos funciones y crea una tercera.
--   (La prueba del final crea una clase de mentira, la usa y la borra.)
--
--   Probado contra una base levantada desde cero con 0001–0020:
--   auto-prueba en verde, aplicado dos veces sin error, permisos
--   correctos, y las pruebas de humo con los mismos resultados que
--   sin este cambio.
--
-- ═══════════════════════════════════════════════════════════════════════

-- ---------------------------------------------------------------------
-- 0021 — Expirar los cupos sin reloj
--
-- EL PROBLEMA
-- Una reserva nace en pendiente_pago y aparta el cupo desde el primer
-- clic. Si la persona abandona, ahi se queda. `liberar_cupos_expirados()`
-- existe desde 0002 y su comentario dice "la llama el cron" — ese cron
-- nunca se creo, asi que cada abandono se comia un cupo para siempre.
--
-- POR QUE NO SE ARREGLA CON UN RELOJ
-- Se probo: un Schedule Trigger en n8n cada 5 minutos. Son 8.640
-- ejecuciones al mes y el plan de Tumbao son 2.500. Bajarlo a una vez
-- por hora deja el cupo bloqueado hasta 60 minutos, que es justo cuando
-- alguien lo esta pidiendo.
--
-- LA IDEA
-- No hace falta reloj. Los cupos vencidos solo importan en dos momentos,
-- y en los dos ya hay alguien mirando:
--
--   al ESCRIBIR  tomar_cupo ya bloquea la fila de la clase. Se sueltan
--                ahi dentro, antes de contar. Coste: cero ejecuciones.
--   al LEER      clases_para descuenta los vencidos sin escribir nada,
--                para que la pagina nunca muestre llena una clase que
--                no lo esta.
--
-- Se puede correr las veces que quieras.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- liberar_cupos_de_clase — la version de una sola clase
--
-- Misma logica que liberar_cupos_expirados(), acotada. Se llama desde
-- dentro del bloqueo de tomar_cupo, asi que NO vuelve a bloquear: si lo
-- hiciera, se bloquearia a si misma.
--
-- liberar_cupos_expirados() se deja como esta: sirve para una limpieza
-- manual de toda la base, y no estorba.
-- ---------------------------------------------------------------------
create or replace function liberar_cupos_de_clase(p_clase_id uuid)
returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_n int;
begin
  with liberadas as (
    update reservas set estado = 'expirada', updated_at = now()
     where clase_id = p_clase_id
       and estado = 'pendiente_pago'
       and expira_en < now()
    returning 1
  )
  select count(*)::int into v_n from liberadas;

  if v_n > 0 then
    update clases set cupo_tomado = greatest(0, cupo_tomado - v_n)
     where id = p_clase_id;
  end if;

  return v_n;
end;
$$;

comment on function liberar_cupos_de_clase(uuid) is
  'Suelta los cupos sin pagar de UNA clase. La llama tomar_cupo dentro de su propio bloqueo de fila.';

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

  -- Se sueltan aqui los cupos que nunca pagaron, dentro del mismo
  -- bloqueo de fila que ya se tomo arriba. Es el unico momento en que
  -- de verdad importa: alguien esta pidiendo ESTE cupo ahora mismo.
  -- Antes esto dependia de un reloj en n8n; un Schedule Trigger cada 5
  -- minutos son 8.640 ejecuciones al mes y el plan son 2.500.
  perform liberar_cupos_de_clase(p_clase_id);
  select * into v_clase from clases where id = p_clase_id;

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
-- clases_para — descontar los vencidos AL LEER, sin escribir nada
--
-- Sin esto quedaria un agujero feo: una clase con cupos vencidos se
-- mostraria llena, nadie intentaria reservar, y como el barrido ahora
-- vive dentro de tomar_cupo, nadie lo dispararia. La clase se quedaria
-- llena para siempre. Aqui solo se resta al mostrar; el arreglo de
-- verdad lo hace tomar_cupo cuando alguien lo pide.
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
  with vencidas as (
    select r.clase_id, count(*)::int as n
      from reservas r
     where r.estado = 'pendiente_pago'
       and r.expira_en < now()
     group by r.clase_id
  ),
  vivas as (
    select r.clase_id, count(*)::int as n
      from reservas r
     where r.tipo = (case when p_tipo = 'miembro' then 'miembro' else 'suelta' end)::tipo_reserva
       and r.estado not in ('rechazada', 'expirada')
       -- Ya vencida pero todavia no barrida: no ocupa.
       and not (r.estado = 'pendiente_pago' and r.expira_en < now())
     group by r.clase_id
  ),
  calc as (
    select c.*,
           greatest(c.cupo_tomado - coalesce(x.n, 0), 0) as tomado_real,
           coalesce(v.n, 0) as tomadas_tipo,
           case when p_tipo = 'miembro' then c.cupo_miembros else c.cupo_sueltas end
             as tope_tipo
      from clases c
      left join vivas v    on v.clase_id = c.id
      left join vencidas x on x.clase_id = c.id
     where c.activa
       and c.fecha_hora > now()
  )
  select
    k.id, k.nombre, k.profesor, k.lugar, k.fecha_hora,
    k.duracion_min, k.precio_cop,
    coalesce(k.tope_tipo, k.cupo_total) as cupo_total,
    case when k.tope_tipo is null then k.tomado_real
         else k.tope_tipo - greatest(least(
                k.cupo_total - k.tomado_real,
                k.tope_tipo  - k.tomadas_tipo), 0)
    end as cupo_tomado
  from calc k
  order by k.fecha_hora;
$$;

-- Postgres da execute a public en toda funcion nueva, y service_role
-- —el rol con el que entra n8n— lo hereda de ahi. Al quitarselo a public
-- hay que devolverselo explicito, o el panel y la pagina se caen.
revoke execute on function liberar_cupos_de_clase(uuid) from public, anon, authenticated;
revoke execute on function clases_para(text)            from public, anon, authenticated;
revoke execute on function tomar_cupo(uuid, text, text, text, text, text) from public, anon, authenticated;

grant execute on function liberar_cupos_de_clase(uuid) to service_role;
grant execute on function clases_para(text)            to service_role;
grant execute on function tomar_cupo(uuid, text, text, text, text, text) to service_role;

-- ---------------------------------------------------------------------
-- Se revisa a si misma. Si algo falla, la ejecucion se detiene aqui y
-- el editor de Supabase no guarda nada: corre todo en una transaccion.
-- ---------------------------------------------------------------------
do $$
declare
  v_clase   uuid;
  v_antes   int;
  v_leido   int;
  v_r       jsonb;
  v_est     text;
  v_n       int;
begin
  -- Una clase de prueba, lejos en el futuro para no chocar con nada real.
  insert into clases (nombre, fecha_hora, duracion_min, precio_cop,
                      cupo_total, cupo_tomado, profesor, lugar, activa)
  values ('PRUEBA 0021', now() + interval '40 days', 60, 15000,
          10, 0, 'Prueba', 'Prueba', true)
  returning id into v_clase;

  -- Una reserva que aparto cupo y nunca pago, ya vencida.
  insert into reservas (clase_id, codigo, nombre, telefono, tipo, estado,
                        origen, expira_en)
  values (v_clase, 'ZZ0021', 'Prueba vencida', '3000000021', 'suelta',
          'pendiente_pago', 'formulario', now() - interval '1 hour');
  update clases set cupo_tomado = 1 where id = v_clase;

  -- 1. Al LEER no debe contar como ocupado.
  select cupo_tomado into v_leido
    from clases_para('suelta') where id = v_clase;
  if v_leido is null then
    raise exception 'la clase de prueba no salio en clases_para';
  end if;
  if v_leido <> 0 then
    raise exception 'clases_para todavia cuenta el cupo vencido: %', v_leido;
  end if;

  -- 2. Al ESCRIBIR debe soltarlo de verdad.
  select cupo_tomado into v_antes from clases where id = v_clase;
  if v_antes <> 1 then
    raise exception 'la prueba no quedo montada, cupo_tomado = %', v_antes;
  end if;

  select tomar_cupo(v_clase, 'Prueba nueva', '3000000022', null,
                    'formulario', 'suelta') into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'tomar_cupo fallo: %', v_r;
  end if;

  -- La vencida quedo expirada y la nueva ocupa: cupo_tomado sigue en 1.
  select estado::text into v_est from reservas where codigo = 'ZZ0021';
  if v_est is distinct from 'expirada' then
    raise exception 'la reserva vencida no se expiro, quedo en %', v_est;
  end if;
  select cupo_tomado into v_antes from clases where id = v_clase;
  if v_antes <> 1 then
    raise exception 'el conteo quedo mal despues de tomar_cupo: %', v_antes;
  end if;

  -- 3. Idempotente: sin nada vencido, no toca nada.
  select liberar_cupos_de_clase(v_clase) into v_n;
  if v_n <> 0 then
    raise exception 'solto % cupos cuando no habia ninguno vencido', v_n;
  end if;

  -- Limpieza: la clase de prueba y sus reservas no pueden quedar vivas.
  delete from reservas where clase_id = v_clase;
  delete from clases   where id = v_clase;

  raise notice 'cupos sin reloj OK — se descuenta al leer y se suelta al escribir';
end $$;

select 'Cupos sin reloj' as resultado;
