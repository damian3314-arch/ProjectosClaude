-- 0095 — El cambio de horario tiene su propio cupo, chiquito y aparte
--
-- POR QUÉ
--
-- Damián, 23 de septiembre: alguien de mensualidad de las 7am quiere ir
-- un día a la clase de las 6pm. Hoy eso rebota siempre —`tomar_cupo` le
-- contesta OTRO_HORARIO y la manda a comprar clase suelta— pero él lo
-- describió con números precisos:
--
--   «si tengo 24 mensualidades y vendo 10 sueltas ya se cumple el cupo
--    del salón… pero nada nos asegura que las de mensualidad vayan a
--    llegar. Ahí siempre podemos jugar entre 4 y 5 cupos… la prioridad
--    siempre van a ser las sueltas, porque necesitamos ese ingreso
--    diario, luego la cantidad de membresías activas… a un máximo de
--    cuatro personas la página debería dejarle hacer ese proceso, y ya
--    luego que les salga un aviso invitándolas a WhatsApp.»
--
-- Tres prioridades, en este orden: sueltas primero (la plata del día),
-- luego los miembros de esa misma hora (ya están descontados del aforo
-- en `cupo_total`), y al final —solo si sobra algo— los cambios.
--
-- ── UN CUPO QUE NO COMPITE CON NADA DE LO QUE YA HABÍA ──────────────
--
-- La tentación era meter esto en el reparto que ya existe
-- (`cupo_miembros`/`cupo_sueltas`), pero ese reparto es OTRA cosa: es el
-- del sábado, donde cualquier mensualidad entra sin pagar porque su plan
-- no la cubre ese día. Un cambio entre semana es distinto en la premisa
-- misma: Damián no está prometiendo que esa silla exista en el papel.
-- La está jugando a que alguien de la hora original no llegue.
--
-- Por eso:
--   · Tipo de reserva nuevo, 'cambio', que no toca `cupo_miembros` ni
--     `cupo_sueltas`.
--   · NO se cuenta contra el techo de la sala (`cupo_total`/
--     `cupo_tomado`) que sí manda sobre sueltas y sábado. Si contara
--     ahí, un cambio le quitaría la silla a quien SÍ está pagando ese
--     día, que es justo lo que él dijo que nunca debe pasar.
--   · NO suma a `cupo_tomado`, por la misma razón: ese número es lo que
--     la página de sueltas lee como «vendido», y un cambio no es una
--     venta de suelta.
--   · Su único techo es aparte y pequeño: `cambios_tope_por_clase`
--     (un ajuste global, arranca en 4) o `clases.cupo_cambios` si algún
--     día hace falta afinarlo clase por clase. Es la cuenta que sí
--     limita esto — y adrede no protege contra que TODOS lleguen: es
--     la apuesta que Damián describió, no un accidente.
--
-- El sábado no se toca: ahí ya funciona (Damián, 23 de septiembre: «con
-- los horarios y los días, o sea, la gente hoy está reservando y todo
-- está funcionando correctamente»), y el chequeo de hora solo corre
-- entre semana.
--
-- ── EL AVISO POR WHATSAPP YA EXISTÍA ─────────────────────────────────
--
-- No hace falta tocar la página. `docs/index.html` ya pega, a CUALQUIER
-- error de reserva, un enlace de WhatsApp con clic al final del mensaje
-- del servidor (línea ~1224: `+ ' <a href="${waUrl(...)}">Escríbenos</a>'`).
-- Cuando el cupo de cambios se llena, el mensaje que manda Postgres ya
-- sale con ese enlace pegado, gratis, con el mismo mecanismo que usa
-- cualquier otro rebote de esta página.

-- ── 1. el tipo de reserva, en SU PROPIA transacción ─────────────────
--
-- Postgres exige que un valor nuevo de enum esté confirmado antes de
-- poder usarse; por eso esto va solo, sin nada más en el mismo bloque.
alter type tipo_reserva add value if not exists 'cambio';

-- ── 2. dónde vive el techo ───────────────────────────────────────────
--
-- Un ajuste global (arranca en 4, que fue el número que dio Damián) y
-- una columna para afinarlo clase por clase el día que haga falta.
-- Mismo patrón que `cupo_manual`: null quiere decir «usa el default».

insert into ajustes (clave, valor, nota) values (
  'cambios_tope_por_clase', '4',
  'Máximo de reservas tipo «cambio» (mensualidad pidiendo otra hora entre '
  'semana) por clase. No es el aforo: es un cupo aparte y chiquito, porque '
  'no se sabe si la gente de esa hora va a llegar. Lo mueve el propietario '
  'con admin_cambios_tope. 0095.'
) on conflict (clave) do nothing;

alter table clases add column if not exists cupo_cambios int;
comment on column clases.cupo_cambios is
  '0095: techo de reservas tipo «cambio» PARA ESTA CLASE. NULL usa el '
  'default de ajustes.cambios_tope_por_clase. No tiene nada que ver con '
  'cupo_manual/cupo_miembros/cupo_sueltas: esos reparten el aforo real, '
  'esto es un cupo que se juega aparte, sin tocar el aforo.';


-- ── 3. subir y bajar el techo, solo el propietario ──────────────────
--
-- Mismo patrón de lectura/escritura que admin_mensualidad_topes: sin
-- p_tope, lee; con p_tope, valida y guarda.
--
-- El techo va entre 0 y 10, no entre 0 y 35 como el aforo. No es un
-- descuido: un cambio NO se cuenta contra el aforo (ver el porqué en la
-- cabecera de esta migración), así que un número grande aquí sería
-- prometer sillas que de verdad no hay. 10 ya es generoso para lo que
-- Damián describió (4 o 5).

create or replace function public.admin_cambios_tope(
  p_token text, p_tope int default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_admin record;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if v_admin.rol <> 'propietario' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO',
      'mensaje', 'El máximo de cambios de horario lo mueve el propietario.');
  end if;

  if p_tope is not null then
    if p_tope < 0 or p_tope > 10 then
      return jsonb_build_object('ok', false, 'error', 'FUERA_DE_RANGO',
        'mensaje', 'El máximo de cambios va entre 0 y 10 por clase. Llegó '
                || p_tope || '.');
    end if;
    insert into ajustes (clave, valor, nota)
    values ('cambios_tope_por_clase', p_tope::text,
            'Máximo de reservas tipo «cambio» por clase. Lo mueve el '
            'propietario con admin_cambios_tope. 0095.')
    on conflict (clave) do update set valor = excluded.valor;
  end if;

  return jsonb_build_object('ok', true,
    'tope', coalesce((select valor::int from ajustes
                        where clave = 'cambios_tope_por_clase'), 4),
    'guardado', p_tope is not null);
end;
$function$;

revoke all on function public.admin_cambios_tope(text, int)
  from public, anon, authenticated;
grant execute on function public.admin_cambios_tope(text, int) to service_role;


-- ── 4. tomar_cupo: el cambio se intenta antes de rebotar ────────────
--
-- Reejecutable a propósito, como el resto de los parches de esta serie:
-- si ya tiene el marcador «0095:», no hace nada.

do $$
declare
  d text := pg_get_functiondef('public.tomar_cupo(uuid, text, text, text, text, text)'::regprocedure);

  -- 1 · dos variables nuevas en el declare
  d_viejo constant text := $tag1$  v_memb_id   bigint := null;
  v_tope      int;
  v_tomadas   int;
begin$tag1$;
  d_nuevo constant text := $tag1$  v_memb_id   bigint := null;
  v_tope      int;
  v_tomadas   int;
  -- 0095: el cupo aparte para pedir una clase de otra hora.
  v_cambios_tomados int;
  v_tope_cambios    int;
begin$tag1$;

  -- 2 · el corazón: OTRO_HORARIO deja de ser un rebote automático
  a_viejo constant text := $tag2$    if not v_es_sabado then
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
    end if;$tag2$;
  a_nuevo constant text := $tag2$    if not v_es_sabado then
      if v_memb.hora = v_hora then
        return jsonb_build_object('ok', false, 'error', 'PLAN_YA_CUBRE',
          'mensaje', 'Tu plan ya te cubre esta clase, no necesitas reservar. '
                  || 'Solo llega 10 minutos antes.');
      else
        -- 0095: cambio de horario. Antes esto rebotaba siempre; ahora
        -- se deja pasar un cupo aparte y chiquito -- ver la cabecera de
        -- la 0095 para el porqué no compite con nada de lo que ya había.
        select count(*) into v_cambios_tomados
          from reservas r
         where r.clase_id = p_clase_id
           and r.tipo = 'cambio'::tipo_reserva
           and r.estado not in ('rechazada', 'expirada');

        v_tope_cambios := coalesce(v_clase.cupo_cambios,
          (select valor::int from ajustes
            where clave = 'cambios_tope_por_clase'), 4);

        if v_cambios_tomados >= v_tope_cambios then
          return jsonb_build_object('ok', false, 'error', 'CAMBIO_LLENO',
            'mensaje', 'Ya se llenaron los cambios de horario para esta '
                    || 'clase. Escríbenos por WhatsApp y miramos qué se '
                    || 'puede hacer.',
            'hora_plan', to_char(v_memb.hora, 'HH12:MI am'));
        end if;

        p_tipo := 'cambio';
      end if;
    end if;$tag2$;

  -- 3 · el cupo por tipo (miembros/sueltas) no es cosa de un cambio
  b_viejo constant text := $tag3$  v_tope := case when p_tipo = 'miembro' then v_clase.cupo_miembros
                 else v_clase.cupo_sueltas end;
  if v_tope is not null then$tag3$;
  b_nuevo constant text := $tag3$  -- 0095: un cambio no juega en el reparto de miembros/sueltas del
  -- sábado. Su cupo ya se comprobó arriba; este es OTRO cupo.
  v_tope := case when p_tipo = 'cambio' then null
                 when p_tipo = 'miembro' then v_clase.cupo_miembros
                 else v_clase.cupo_sueltas end;
  if v_tope is not null then$tag3$;

  -- 4 · el techo de la sala tampoco es cosa de un cambio
  c_viejo constant text := $tag4$  if v_clase.cupo_tomado >= v_clase.cupo_total then
    return jsonb_build_object('ok', false, 'error', 'SIN_CUPO',
      'mensaje', 'Esa clase se llenó. Elige otro horario.');
  end if;$tag4$;
  c_nuevo constant text := $tag4$  -- 0095: un cambio no compite por el techo de la sala. Es justo lo
  -- que lo hace un cupo aparte: sale del hueco que deja la
  -- inasistencia de mensualidad, no del aforo del papel.
  if p_tipo <> 'cambio' and v_clase.cupo_tomado >= v_clase.cupo_total then
    return jsonb_build_object('ok', false, 'error', 'SIN_CUPO',
      'mensaje', 'Esa clase se llenó. Elige otro horario.');
  end if;$tag4$;

  -- 5 · y no suma al contador que ve la página de sueltas
  e_viejo constant text :=
    $tag5$  update clases set cupo_tomado = cupo_tomado + 1 where id = p_clase_id;$tag5$;
  e_nuevo constant text := $tag5$  -- 0095: por la misma razón, un cambio no suma aquí. Si sumara, se
  -- leería como una silla de suelta vendida y le robaría cupo a quien
  -- de verdad está pagando ese día.
  if p_tipo <> 'cambio' then
    update clases set cupo_tomado = cupo_tomado + 1 where id = p_clase_id;
  end if;$tag5$;
begin
  if position('0095:' in d) > 0 then
    raise notice '0095 ya estaba puesto en tomar_cupo';
    return;
  end if;
  if position(d_viejo in d) = 0 then raise exception '0095: no encuentro el declare'; end if;
  if position(a_viejo in d) = 0 then raise exception '0095: no encuentro el bloque de la hora'; end if;
  if position(b_viejo in d) = 0 then raise exception '0095: no encuentro el v_tope por tipo'; end if;
  if position(c_viejo in d) = 0 then raise exception '0095: no encuentro el techo de la sala'; end if;
  if position(e_viejo in d) = 0 then raise exception '0095: no encuentro el incremento de cupo_tomado'; end if;

  d := replace(d, d_viejo, d_nuevo);
  d := replace(d, a_viejo, a_nuevo);
  d := replace(d, b_viejo, b_nuevo);
  d := replace(d, c_viejo, c_nuevo);
  d := replace(d, e_viejo, e_nuevo);
  execute d;
end $$;


-- ── 5. admin_tablero: que «en_sala» no mienta por omisión ───────────
--
-- `en_sala` sumaba `activos_plan + cupo_tomado` para decir cuánta gente
-- se espera en esa clase. Un cambio no toca `cupo_tomado` a propósito
-- (ver el punto 4), así que sin este parche cada cambio confirmado
-- desaparecería del conteo — la persona SÍ va a estar ahí, y recepción
-- se enteraría de menos gente de la que en realidad llega.
--
-- De paso se expone `de_cambios`, para quien quiera verlo aparte.

do $$
declare
  d text := pg_get_functiondef('public.admin_tablero(text, date)'::regprocedure);

  a_viejo constant text := $tag1$        count(*) filter (where r.tipo = 'miembro'
                           and r.estado not in ('rechazada','expirada'))::int as de_miembros,
        count(*) filter (where r.tipo = 'suelta'
                           and r.estado not in ('rechazada','expirada'))::int as de_sueltas
      from reservas r where r.clase_id = c.id$tag1$;
  a_nuevo constant text := $tag1$        count(*) filter (where r.tipo = 'miembro'
                           and r.estado not in ('rechazada','expirada'))::int as de_miembros,
        count(*) filter (where r.tipo = 'suelta'
                           and r.estado not in ('rechazada','expirada'))::int as de_sueltas,
        -- 0095: mensualidad de otra hora, cabida aparte del aforo.
        count(*) filter (where r.tipo = 'cambio'
                           and r.estado not in ('rechazada','expirada'))::int as de_cambios
      from reservas r where r.clase_id = c.id$tag1$;

  b_viejo constant text :=
    $tag2$      'en_sala',     c.activos_plan + c.cupo_tomado,$tag2$;
  b_nuevo constant text :=
    $tag2$      -- 0095: un cambio no está en cupo_tomado a propósito; sin
      -- sumarlo aquí, cada cambio confirmado desaparecía del conteo de
      -- gente esperada, y sí va a estar ahí.
      'en_sala',     c.activos_plan + c.cupo_tomado + n.de_cambios,
      'cambios_tomados', n.de_cambios,
      'cambios_tope', coalesce(c.cupo_cambios,
        (select valor::int from ajustes where clave = 'cambios_tope_por_clase'), 4),$tag2$;
begin
  if position('0095:' in d) > 0 then
    raise notice '0095 ya estaba puesto en admin_tablero';
    return;
  end if;
  if position(a_viejo in d) = 0 then raise exception '0095: no encuentro los conteos por tipo'; end if;
  if position(b_viejo in d) = 0 then raise exception '0095: no encuentro en_sala'; end if;
  d := replace(d, a_viejo, a_nuevo);
  d := replace(d, b_viejo, b_nuevo);
  execute d;
end $$;
