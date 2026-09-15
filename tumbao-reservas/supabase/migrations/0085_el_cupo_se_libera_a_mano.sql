-- 0085 · El cupo se libera a mano, y el tope se puede mover sin migración.
--
-- LO QUE PIDIÓ DAMIÁN (15 de septiembre)
-- «Necesito un control para dar el acceso al pago a los clientes de lista
-- de espera, eso significa que si el cliente ingresa y comienza a colocar
-- los datos que le deje pasar o pagar porque ya se liberó un cupo para esa
-- persona. Y que en la página de admin uno pueda controlar de manera
-- manual cuántos cupos se van liberando.»
--
-- Son dos mandos distintos y conviene no confundirlos:
--
--   · «déjala pasar a ELLA»      → admin_mensualidad_dar_cupo
--   · «en esa hora caben N»      → admin_mensualidad_topes
--
-- El primero es una excepción para una persona. El segundo cambia la
-- regla para todo el mundo. Mezclarlos en un botón haría imposible saber
-- después por qué esa hora terminó con 27 en vez de 25.
--
-- ─────────────────────────────────────────────────────────────────────
-- POR QUÉ ESTA MIGRACIÓN NO PARCHEA NADA
--
-- La primera versión de esto añadía una columna `cupo_hasta` y parcheaba
-- `mensualidad_cupos` y `mensualidad_solicitar` para que la miraran. Tres
-- piezas tocadas, dos de ellas con `pg_get_functiondef` a ciegas sobre un
-- cuerpo que en producción ya viene reescrito por la 0074 y la 0075.
--
-- No hace falta. El mecanismo que ya existe hace exactamente lo que se
-- pide, si se usa al derecho:
--
--   · `mensualidad_cupos` cuenta como apartada toda `esperando_pago`
--     con menos de 24 horas.
--   · `mensualidad_solicitar` le devuelve a quien vuelve su solicitud
--     viva de las últimas 24 horas, con el estado que tenga.
--
-- O sea: si al liberar el cupo se crea una solicitud NUEVA en
-- `esperando_pago`, el cupo queda apartado solo y la persona, al volver
-- a la página y escribir su celular y su hora, cae directo en la
-- pantalla de pago. Sin tocar una línea de las dos funciones que hoy
-- deciden si alguien puede pagar. Esas dos son lo más delicado que hay
-- aquí: si se rompen, o se vende un cupo que no existe o no se vende
-- ninguno.
--
-- La solicitud vieja no se borra ni se reescribe: se marca `atendida`
-- con una nota. Queda el rastro de cuándo pidió, cuánto esperó y quién
-- le abrió la puerta.
--
-- LAS 24 HORAS NO SON UN NÚMERO NUEVO
-- Es el mismo plazo que la página ya le promete a todo el que pasa a
-- pagar: «te guardamos el cupo de las 6:00 pm por 24 horas». Darle 48 a
-- quien viene de la lista obligaría a cambiar ese texto y a explicar por
-- qué unos tienen más que otros. Si el plazo se queda corto, se vuelve a
-- pulsar el botón: son dos toques, no un problema de diseño.
--
-- SE PUEDE PASAR DEL TOPE, Y SE DICE
-- Si la hora está llena —que es justo por lo que hay lista de espera—,
-- liberar un cupo deja la hora en tope+1. Eso es lo que se pidió: el
-- mando es manual. Pero no puede ser silencioso, así que la función
-- devuelve `ocupadas`, `tope` y `sobre_el_tope`, y el panel lo enseña.
-- Un mando que no dice lo que acaba de hacer se usa dos veces.
--
-- EL AVISO A LA CLIENTA LO MANDA UNA PERSONA
-- Esta función no escribe a nadie. Devuelve el nombre, el celular y la
-- hora para que el panel arme el mensaje y alguien lo mande desde su
-- WhatsApp. Mandar mensajes a clientas reales está en rojo en el
-- framework de la casa, y además el aviso de «ya tienes cupo» merece ir
-- con nombre propio, no desde un robot.

-- ── 1. Déjala pasar a pagar ──────────────────────────────────────────
create or replace function public.admin_mensualidad_dar_cupo(
  p_token text,
  p_id    uuid,
  p_nota  text default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_admin   record;
  v_vieja   mensualidad_solicitudes;
  v_nueva   uuid;
  v_cupos   jsonb;
  v_hora    jsonb;
begin
  -- VOLATILE y no STABLE: verificar_token_admin_rol escribe `ultimo_uso`.
  -- Marcarla STABLE es el error que ya costó un 25006 en la 0073.
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  -- Quién entra a una hora llena es una decisión de negocio, no de caja.
  if v_admin.rol = 'cajero' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO',
      'mensaje', 'Liberar un cupo lo hace el propietario o el administrador.');
  end if;

  -- El `for update` es lo que evita que dos personas del panel liberen
  -- el mismo cupo a la vez y salgan dos solicitudes nuevas.
  select * into v_vieja from mensualidad_solicitudes
   where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE',
      'mensaje', 'Esa solicitud ya no está.');
  end if;

  -- Solo desde la lista de espera. Quien ya está en `esperando_pago` no
  -- necesita que le abran nada, y quien ya pagó tampoco.
  if v_vieja.estado <> 'lista_espera' then
    return jsonb_build_object('ok', false, 'error', 'NO_ESTA_EN_ESPERA',
      'estado', v_vieja.estado,
      'mensaje', case v_vieja.estado
        when 'esperando_pago' then 'Esa persona ya tiene el cupo apartado y puede pagar.'
        when 'pagada'         then 'Esa persona ya pagó.'
        when 'atendida'       then 'Esa solicitud ya se atendió.'
        when 'anulada'        then 'Esa solicitud está anulada.'
        else 'Esa solicitud no está en lista de espera.' end);
  end if;

  -- La solicitud nueva: misma persona, misma hora, mismo valor, reloj a
  -- cero. `creado_at` cae en su valor por defecto —ahora— y eso es todo
  -- lo que hace falta para que las dos funciones de siempre la vean como
  -- un cupo recién apartado.
  --
  -- El valor se copia de la vieja y NO se vuelve a leer de `ajustes`: si
  -- la mensualidad subió de precio mientras esperaba, cobrarle el nuevo
  -- por haber hecho fila sería el peor premio posible. Si hay que
  -- cambiárselo, se hace a mano y se ve.
  insert into mensualidad_solicitudes
    (nombre, celular, documento, correo, hora, tipo, valor_cop, estado, nota)
  values (v_vieja.nombre, v_vieja.celular, v_vieja.documento, v_vieja.correo,
          v_vieja.hora, v_vieja.tipo, v_vieja.valor_cop, 'esperando_pago',
          'Cupo liberado a mano desde la lista de espera'
            || case when coalesce(btrim(p_nota), '') = '' then ''
                    else ' · ' || btrim(p_nota) end)
  returning id into v_nueva;

  -- La vieja se cierra, no se borra: es el registro de cuánto esperó.
  update mensualidad_solicitudes
     set estado       = 'atendida',
         atendida_at  = now(),
         atendida_por = v_admin.id,
         nota = case when coalesce(btrim(nota), '') = ''
                     then 'Se le liberó cupo'
                     else nota || ' · Se le liberó cupo' end
   where id = p_id;

  -- Cómo quedó la hora DESPUÉS de liberar. Se lee al final a propósito:
  -- así el número que ve el panel incluye el cupo que acaba de dar.
  v_cupos := mensualidad_cupos();
  select h into v_hora
    from jsonb_array_elements(v_cupos->'horas') h
   where h->>'hora' = to_char(v_vieja.hora, 'HH24:MI');

  return jsonb_build_object(
    'ok', true,
    'id', v_nueva,
    'id_anterior', p_id,
    'nombre', v_vieja.nombre,
    'celular', v_vieja.celular,
    'hora', to_char(v_vieja.hora, 'HH24:MI'),
    'etiqueta', ltrim(to_char(v_vieja.hora, 'HH12:MI am'), '0'),
    'valor_cop', v_vieja.valor_cop,
    'espero_dias', (current_date - (v_vieja.creado_at at time zone 'America/Bogota')::date),
    'horas_de_plazo', 24,
    'ocupadas', (v_hora->>'ocupadas')::int,
    'tope', (v_hora->>'tope')::int,
    -- El aviso: liberar en una hora llena la deja por encima del tope.
    -- No se impide —el mando es manual— pero se dice.
    'sobre_el_tope', coalesce((v_hora->>'ocupadas')::int, 0)
                     > coalesce((v_hora->>'tope')::int, 0));
end;
$function$;

revoke all on function public.admin_mensualidad_dar_cupo(text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.admin_mensualidad_dar_cupo(text, uuid, text)
  to service_role;

comment on function public.admin_mensualidad_dar_cupo(text, uuid, text) is
  '0085: mueve a alguien de la lista de espera a esperando_pago creando una '
  'solicitud nueva. No parchea mensualidad_cupos ni mensualidad_solicitar: '
  'les da de comer lo que ya saben leer.';

-- ── 2. Cuántos caben en cada hora ────────────────────────────────────
--
-- La 0074 dejó el mando puesto y nadie lo podía tocar: `mensualidad_topes`
-- es un ajuste con la forma «07:00=32,18:00=26,19:00=24» que
-- `mensualidad_cupos` ya lee, pero que hasta hoy solo se podía escribir
-- entrando a la base de datos a mano. Esto es el mando, con validación.
--
-- Sin argumento, LEE. Con argumento, ESCRIBE. Una sola función porque el
-- panel necesita las dos cosas en la misma pantalla y partirla en dos
-- obligaría a dos viajes para pintar un formulario.
create or replace function public.admin_mensualidad_topes(
  p_token text,
  p_topes text default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_admin   record;
  v_horas   text;
  v_limpio  text;
  v_par     text;
  v_h       text;
  v_n       int;
  v_partes  text[];
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  -- Mover el tope cambia cuánto se puede vender. Eso es del dueño.
  if v_admin.rol <> 'propietario' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO',
      'mensaje', 'El tope de mensualidades por hora lo mueve el propietario.');
  end if;

  select coalesce((select valor from ajustes where clave = 'mensualidad_horas'),
                  '07:00,18:00,19:00')
    into v_horas;

  if p_topes is not null then
    -- Cadena vacía quiere decir «quita el tope por hora y vuelve al
    -- número único». Es una opción de verdad, no un error de tecleo:
    -- sin ella no habría forma de deshacer.
    if btrim(p_topes) = '' then
      delete from ajustes where clave = 'mensualidad_topes';
    else
      v_limpio := '';
      foreach v_par in array string_to_array(btrim(p_topes), ',') loop
        if btrim(v_par) = '' then continue; end if;
        v_partes := string_to_array(v_par, '=');
        if array_length(v_partes, 1) <> 2 then
          return jsonb_build_object('ok', false, 'error', 'FORMATO',
            'mensaje', 'Cada pareja va como 18:00=26. Llegó: ' || v_par);
        end if;
        v_h := btrim(v_partes[1]);
        -- La hora tiene que ser una de las que la página ofrece. Un tope
        -- para una hora que no existe no hace nada y nadie se entera.
        if not exists (select 1 from unnest(string_to_array(v_horas, ',')) x
                        where btrim(x) = v_h) then
          return jsonb_build_object('ok', false, 'error', 'HORA_NO_DISPONIBLE',
            'mensaje', 'La hora ' || v_h || ' no está en las que ofrece la página ('
                       || v_horas || ').');
        end if;
        begin
          v_n := btrim(v_partes[2])::int;
        exception when others then
          return jsonb_build_object('ok', false, 'error', 'FORMATO',
            'mensaje', 'El tope de ' || v_h || ' no es un número.');
        end;
        -- 0 es válido: es «cierra esa hora a mensualidad». El techo son
        -- las 35 sillas del salón; más que eso no es un tope, es un error
        -- de tecleo que se vería como cupos en la página.
        if v_n < 0 or v_n > 35 then
          return jsonb_build_object('ok', false, 'error', 'FUERA_DE_RANGO',
            'mensaje', 'El tope de ' || v_h || ' tiene que ir entre 0 y 35 '
                       || '(el aforo del salón). Llegó ' || v_n || '.');
        end if;
        v_limpio := v_limpio || case when v_limpio = '' then '' else ',' end
                    || v_h || '=' || v_n;
      end loop;

      insert into ajustes (clave, valor, nota)
      values ('mensualidad_topes', v_limpio,
              'Tope de mensualidades por hora, «07:00=32,18:00=26». Lo lee '
              'mensualidad_cupos desde la 0074. Si no existe, manda '
              'mensualidad_tope_por_hora para todas las horas.')
      on conflict (clave) do update set valor = excluded.valor;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'topes', (select valor from ajustes where clave = 'mensualidad_topes'),
    'tope_general', coalesce(
      (select valor::int from ajustes where clave = 'mensualidad_tope_por_hora'), 25),
    'horas', v_horas,
    -- Los cupos recalculados, para que el panel no tenga que pedirlos
    -- aparte y pueda enseñar el efecto del cambio en el acto.
    'cupos', mensualidad_cupos(),
    'guardado', p_topes is not null);
end;
$function$;

revoke all on function public.admin_mensualidad_topes(text, text)
  from public, anon, authenticated;
grant execute on function public.admin_mensualidad_topes(text, text)
  to service_role;

comment on function public.admin_mensualidad_topes(text, text) is
  '0085: lee y escribe ajustes.mensualidad_topes («07:00=32,18:00=26»). '
  'Sin p_topes lee; con p_topes valida y guarda. Solo propietario.';
