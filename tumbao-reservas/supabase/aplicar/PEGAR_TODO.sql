-- ═══════════════════════════════════════════════════════════════════════
--
--   TUMBAO — TODO LO PENDIENTE, EN UN SOLO PEGUE
--
--   Cópialo entero, pégalo en el SQL Editor de Supabase y dale Run.
--   Una sola vez. No hay que partirlo ni correrlo por pedazos.
--
--   Se puede volver a correr las veces que quieras: todo está escrito
--   con "create or replace" y "if not exists". Correrlo dos veces no
--   duplica nada ni borra nada.
--
--   NO BORRA DATOS. No hay un solo drop ni truncate sobre tus tablas:
--   solo crea funciones, columnas e índices nuevos. Las reservas, los
--   pagos y las membresías quedan intactos. (Los pocos "delete" que vas
--   a ver son de las auto-pruebas limpiando lo que ellas mismas crean.)
--
--   Son los seis pendientes, en el orden en que tienen que ir:
--
--     1.  Arreglo del panel        Quita el "Invalid time value" que no dejaba entrar.
--     2.  Pestaña de Tablero       Cupos, gente con plan y reservas, clase por clase.
--     3.  Botón de deshacer        Revierte el último confirmar o rechazar.
--     4.  Lista de la puerta       Quién entra hoy, con marcar asistió / ingresó.
--     5.  Vencen ese día           Aviso punteado de cuántos planes terminan ese día.
--     6.  El sábado, 15 y 15       Parte el aforo del sábado en afiliados y sueltas.
--
--   Cada bloque termina revisando su propio trabajo. Si algo sale mal
--   la ejecución se detiene ahí con un mensaje claro y NADA se guarda
--   —el editor de Supabase corre todo en una transacción—, así que no
--   te puede dejar la base a medio camino.
--
--   Al final debe salir una tabla con seis filas que dicen "listo".
--
-- ═══════════════════════════════════════════════════════════════════════



-- ╔═══════════════════════════════════════════════════════════════════╗
-- ║  PARTE 1 de 6   ·   Arreglo del panel                           ║
-- ║  Quita el "Invalid time value" que no dejaba entrar.              ║
-- ╚═══════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════
--
--   TUMBAO — ARREGLO DEL PANEL DE ADMIN
--
--   Pégalo entero en el SQL Editor de Supabase y dale Run.
--   Se puede correr las veces que quieras.
--
--   ¿Qué arregla? El "Invalid time value" que salía en rojo debajo
--   del token y no dejaba entrar al panel.
--
--   El token estaba bien. Lo que pasaba es que Supabase devolvía la
--   fecha de cada día así:
--
--       "2026-07-28T00:00:00+00:00"     en vez de   "2026-07-28"
--
--   y la página, al intentar escribir "martes 28 de jul" con esa
--   fecha, se caía. El error subía hasta el login, que lo pintaba
--   donde va el mensaje de token incorrecto. De ahí la confusión.
--
--   ¿Tengo que pegar esto para poder entrar? No. La página ya quedó
--   arreglada por su lado y entra igual. Esto corrige el origen, y
--   de paso quita un fallo escondido: la fecha vieja cambiaba según
--   la zona horaria de la conexión, así que algún día los días de la
--   cuadrícula se podían correr uno.
--
-- ═══════════════════════════════════════════════════════════════

-- =====================================================================
-- El panel de admin no abría: "Invalid time value"
--
-- EL BUG
-- `admin_semana` armaba los siete días así:
--
--     from generate_series(p_desde, p_desde + 6, interval '1 day') g(dia)
--
-- `generate_series` con paso de intervalo NO devuelve date: promueve los
-- extremos a `timestamptz`. Así que `jsonb_build_object('fecha', dia)`
-- no serializaba "2026-07-28" sino:
--
--     "2026-07-28T00:00:00+00:00"
--
-- La página hace `fecha.split('-')` para partir el ISO en año/mes/día.
-- Con esa forma, el tercer trozo es "28T00:00:00+00:00" → Number(...) es
-- NaN → Date.UTC(2026, 6, NaN) es Invalid Date → Intl lanza
-- `RangeError: Invalid time value`. La excepción subía hasta el catch
-- del login, que pintaba el mensaje del error en rojo bajo el token.
-- Desde fuera parecía que el token estaba mal. El token estaba bien: la
-- semana llegaba y la página moría al pintarla.
--
-- Y había un segundo problema escondido en el mismo sitio: al ser
-- `timestamptz`, tanto el texto del JSON como `extract(dow ...)`
-- dependían de la zona horaria de la conexión. Hoy PostgREST se conecta
-- en UTC y cuadra; el día que no, los días de la cuadrícula se corrían
-- uno.
--
-- LA CORRECCIÓN
-- Recorrer con enteros y sumarlos a la fecha: `p_desde + n` entre un
-- `date` y un `int` da `date`, sin pasar nunca por un timestamp. El JSON
-- sale "2026-07-28" y `dow` ya no depende de la zona de la sesión.
--
-- Por qué no lo vio ninguna prueba: el espejo local (pruebas/espejo-api.mjs)
-- devolvía la fecha ya limpia, porque la arma en Node. Probaba la página
-- contra un contrato inventado, no contra el de verdad. Es el mismo hueco
-- que escondió el bug de `.first()` en los nodos Code de n8n. El espejo
-- ahora imita la forma fea a propósito.
-- =====================================================================

create or replace function admin_semana(p_token text, p_desde date)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_dias  jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select coalesce(jsonb_agg(d order by d->>'fecha'), '[]'::jsonb) into v_dias
  from (
    select jsonb_build_object(
      'fecha', dia,
      'dow',   extract(dow from dia)::int,
      'clases', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'clase_id',    c.id,
                 'nombre',      c.nombre,
                 'hora',        to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'),
                 'profesor',    c.profesor,
                 'activa',      c.activa,
                 'aforo',       c.aforo,
                 'activos_plan', c.activos_plan,
                 'cupo_total',  c.cupo_total,
                 'cupo_tomado', c.cupo_tomado,
                 'cupo_manual', c.cupo_manual,
                 'ya_paso',     c.fecha_hora <= now()
               ) order by c.fecha_hora)
          from clases c
         where (c.fecha_hora at time zone 'America/Bogota')::date = dia
      ), '[]'::jsonb)
    ) as d
    -- date + int = date. Con `interval '1 day'` esto era timestamptz y
    -- el JSON salía con hora y desfase pegados a la fecha.
    from generate_series(0, 6) g(n)
    cross join lateral (select (p_desde + g.n)::date as dia) f
  ) s;

  return jsonb_build_object('ok', true, 'desde', p_desde,
    'hasta', p_desde + 6, 'dias', v_dias);
end;
$$;

comment on function admin_semana(text, date) is
  'Los 7 dias de la semana para el panel. fecha sale como AAAA-MM-DD: no usar generate_series con intervalo, que la convierte en timestamptz.';

-- ── Comprobación: esto tiene que decir "fechas OK" ───────────────
do $$
declare v_tok text; v_f text;
begin
  v_tok := (crear_token_admin('comprobacion de fechas'))->>'token';
  for v_f in select d->>'fecha'
               from jsonb_array_elements((admin_semana(v_tok, current_date))->'dias') d loop
    if v_f !~ '^\d{4}-\d{2}-\d{2}$' then
      raise exception 'la fecha sigue saliendo mal: %', v_f;
    end if;
  end loop;
  -- El token de la comprobación se borra: no sirve para entrar.
  delete from admin_tokens where nombre = 'comprobacion de fechas';
  raise notice 'fechas OK';
end $$;


-- ╔═══════════════════════════════════════════════════════════════════╗
-- ║  PARTE 2 de 6   ·   Pestaña de Tablero                          ║
-- ║  Cupos, gente con plan y reservas, clase por clase.               ║
-- ╚═══════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════
--
--   TUMBAO — PESTAÑA DE TABLERO
--
--   Pégalo entero en el SQL Editor de Supabase y dale Run.
--   Se puede correr las veces que quieras.
--
--   ¿Qué agrega? La pestaña "Tablero" del panel, que responde de un
--   vistazo, clase por clase:
--
--       cuántos cupos quedan para vender
--       cuánta gente con plan tiene ese horario
--       cuántas reservas llevamos
--       cuánta gente va a entrar en total a la sala
--
--   Esta última no estaba en ningún lado y es la que decide si cabe
--   una persona más: entre semana entran los que tienen plan (que no
--   reservan, solo llegan) MÁS los que compraron clase suelta.
--
--   ¿Tengo que pegar esto? Sí, esta vez sí. Sin esto la pestaña
--   Tablero sale en rojo diciendo que no encuentra la función. El
--   resto del panel —Horario y Por validar— funciona igual.
--
--   No toca ninguna tabla, no borra nada y no escribe: solo lee y
--   cuenta. También agrega dos datos a la cola de validación
--   (clase_id y tipo) para poder agruparla por horario.
--
-- ═══════════════════════════════════════════════════════════════

-- =====================================================================
-- El tablero del día
--
-- Lo que hay que poder responder de un vistazo, sin abrir nada más:
--
--   ¿Cuántos cupos quedan para vender de la clase de las 7?
--   ¿Cuánta gente con plan tiene esa hora?
--   ¿Cuántas reservas llevamos?
--   ¿Cuánta gente va a entrar en total a esa sala?
--
-- Esa última no estaba en ningún sitio y es la que de verdad importa
-- cuando se abre la puerta: entre semana entran los que tienen plan
-- (que no reservan, solo llegan) MÁS los que compraron clase suelta.
-- El sábado nadie tiene plan, así que ahí "en sala" son las reservas.
--
--     en sala = gente con plan + reservas vivas
--
-- Todo sale de columnas que ya se mantienen solas (`clases.aforo`,
-- `activos_plan`, `cupo_total`, `cupo_tomado`). Esta función no calcula
-- nada nuevo ni escribe: solo junta y cuenta. Si algún número se ve
-- raro, el problema está en la importación de la noche, no aquí.
--
-- Lectura pura: no hay un solo insert/update/delete.
-- =====================================================================

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
      -- de dónde sale el cupo
      'aforo',       c.aforo,
      'con_plan',    c.activos_plan,
      'a_la_venta',  c.cupo_total,
      'cupo_manual', c.cupo_manual,
      -- qué se ha vendido
      'reservadas',  c.cupo_tomado,
      'libres',      greatest(c.cupo_total - c.cupo_tomado, 0),
      'confirmadas', n.confirmadas,
      'por_validar', n.por_validar,
      'esperando',   n.esperando,
      -- cuánta gente entra
      'en_sala',     c.activos_plan + c.cupo_tomado,
      'ingreso_cop', n.confirmadas * c.precio_cop
    ) as x
    from clases c
    cross join lateral (
      select
        count(*) filter (where r.estado = 'confirmada')::int            as confirmadas,
        count(*) filter (where r.estado = 'pendiente_validacion')::int  as por_validar,
        count(*) filter (where r.estado in ('pendiente_pago','verificando'))::int as esperando
      from reservas r where r.clase_id = c.id
    ) n
   where (c.fecha_hora at time zone 'America/Bogota')::date = v_dia
  ) s;

  return jsonb_build_object(
    'ok', true,
    'dia', v_dia,
    'es_hoy', v_dia = v_hoy,
    'clases', v_clases,
    -- El resumen se saca de las mismas tarjetas para que no puedan
    -- contradecirse: si sumas las tarjetas a mano, da esto.
    'resumen', jsonb_build_object(
      'clases',      jsonb_array_length(v_clases),
      'aforo',       coalesce((select sum((c->>'aforo')::int)       from jsonb_array_elements(v_clases) c), 0),
      'con_plan',    coalesce((select sum((c->>'con_plan')::int)    from jsonb_array_elements(v_clases) c), 0),
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

comment on function admin_tablero(text, date) is
  'Tarjetas del dia para el panel: cupos, gente con plan, reservas y cuanta gente entra a cada clase. Solo lectura.';


-- ---------------------------------------------------------------------
-- La cola de validacion, ahora agrupable por clase
--
-- El caso real es el mostrador: llega alguien, el cajero tiene que
-- encontrarlo en la lista. Con diez tarjetas seguidas y todas iguales
-- no se distingue quien viene a la clase de las 7 de quien viene a la
-- de las 6. Se agrega `clase_id` para poder agrupar sin adivinar por
-- la fecha, y `tipo` para ver de un golpe si es miembro o clase suelta.
--
-- Lo demas queda igual: mismos campos, mismo orden.
-- ---------------------------------------------------------------------

create or replace function admin_pendientes(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_out   jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select coalesce(jsonb_agg(x order by x->>'creada_at'), '[]'::jsonb) into v_out
  from (
    select jsonb_build_object(
      'codigo',      r.codigo,
      'nombre',      r.nombre,
      'telefono',    r.telefono,
      'estado',      r.estado,
      'tipo',        r.tipo,
      'creada_at',   r.created_at,
      'pagado_en',   r.pagado_en,
      'pagador',     r.pagador_nombre,
      'referencia',  r.referencia_pago,
      'clase_id',    c.id,
      'clase',       c.nombre,
      'fecha_hora',  c.fecha_hora,
      'precio_cop',  c.precio_cop,
      'pagos_sueltos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'pago_id',   p.id,
                 'valor_cop', p.valor_cop,
                 'fecha',     p.fecha_pago,
                 'remitente', p.remitente,
                 -- El parecido se mide contra quien paga de verdad.
                 'parecido',  round(similitud_nombre(
                                coalesce(r.pagador_nombre, r.nombre), p.remitente), 2),
                 -- Minutos de diferencia con la hora que declaro. Es el
                 -- dato que mas rapido resuelve el caso a ojo.
                 'minutos',   case when r.pagado_en is null then null
                              else round(extract(epoch from
                                     (p.fecha_pago - r.pagado_en)) / 60) end)
               order by case when r.pagado_en is null then 0
                        else abs(extract(epoch from (p.fecha_pago - r.pagado_en))) end)
          from pagos p
         where p.valor_cop = c.precio_cop
           and p.fecha_pago between coalesce(r.pagado_en, r.created_at) - interval '1 hour'
                               and coalesce(r.pagado_en, r.created_at) + interval '3 hours'
           and not exists (select 1 from reservas r2 where r2.pago_id = p.id)
      ), '[]'::jsonb)
    ) as x
    from reservas r
    join clases c on c.id = r.clase_id
   where r.estado in ('pendiente_validacion', 'verificando')
  ) s;

  return jsonb_build_object('ok', true, 'reservas', v_out);
end;
$$;


-- ---------------------------------------------------------------------
-- Nada de esto se toca con la llave publica
--
-- Postgres le da EXECUTE a PUBLIC a toda funcion nueva. Sin esta linea,
-- `admin_tablero` quedaba abierta a la llave anon: cualquiera con la
-- URL del proyecto veria el aforo, los afiliados y la caja del dia. Lo
-- caza pruebas/humo-tablero.sql, que fue exactamente como aparecio.
--
-- `create or replace` conserva los permisos, asi que el revoke de
-- admin_pendientes es redundante — pero cuesta una linea y quita la
-- duda de si se conservan o no.
-- ---------------------------------------------------------------------
revoke execute on function admin_tablero(text, date)  from public, anon, authenticated;
revoke execute on function admin_pendientes(text)     from public, anon, authenticated;

-- Y despues del revoke hay que devolverle el permiso a service_role, que
-- es el rol con el que entra n8n. Postgres le da execute a public en toda
-- funcion nueva, y service_role lo heredaba de ahi; al quitarselo a public
-- se lo quitamos tambien a el. Sin este grant el Tablero contesta
-- "permission denied for function admin_tablero". Es el mismo par
-- revoke/grant de 0011, que aqui se habia quedado a medias.
grant execute on function admin_tablero(text, date) to service_role;

-- ── Comprobación: esto tiene que decir "tablero OK" ──────────────
do $$
declare v_tok text; v_r jsonb; v_c jsonb;
begin
  v_tok := (crear_token_admin('comprobacion del tablero'))->>'token';

  v_r := admin_tablero(v_tok, (now() at time zone 'America/Bogota')::date);
  if (v_r->>'ok')::boolean is not true then
    raise exception 'el tablero no respondio: %', v_r;
  end if;

  -- Si hoy hay clases, los numeros tienen que cuadrar entre si.
  for v_c in select c from jsonb_array_elements(v_r->'clases') c loop
    if (v_c->>'en_sala')::int <> (v_c->>'con_plan')::int + (v_c->>'reservadas')::int then
      raise exception 'la clase de las % no cuadra: %', v_c->>'hora', v_c;
    end if;
  end loop;

  if (admin_pendientes(v_tok)->>'ok')::boolean is not true then
    raise exception 'la cola de validacion dejo de responder';
  end if;

  -- El token de la comprobación se borra: no sirve para entrar.
  delete from admin_tokens where nombre = 'comprobacion del tablero';
  raise notice 'tablero OK — % clase(s) hoy', jsonb_array_length(v_r->'clases');
end $$;


-- ╔═══════════════════════════════════════════════════════════════════╗
-- ║  PARTE 3 de 6   ·   Botón de deshacer                           ║
-- ║  Revierte el último confirmar o rechazar.                         ║
-- ╚═══════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════
--
--   TUMBAO — BOTÓN DE DESHACER
--
--   Pégalo entero en el SQL Editor de Supabase y dale Run.
--   Se puede correr las veces que quieras.
--
--   ¿Qué agrega? Un botón para revertir el último confirmar o
--   rechazar. La duda —"¿era este el que había pagado?"— llega medio
--   segundo después del clic, y hasta ahora la única salida era tocar
--   la base a mano.
--
--   Tres candados, a propósito:
--
--     1. Solo lo que resolvió una persona desde el panel. Lo que
--        concilió solo el sistema no se toca desde ahí.
--     2. Solo dentro de los 15 minutos siguientes.
--     3. Una sola vez. No se puede deshacer el deshacer.
--
--   Vuelve al estado EXACTO de antes, no a uno inventado: al
--   confirmar o rechazar se anota de dónde venía y a qué pago
--   apuntaba, y deshacer restaura eso.
--
--   Lo único que puede no poder hacer: si deshaces un rechazo y
--   mientras tanto alguien compró ese cupo, se niega y te lo dice.
--   Antes de sobrevender, prefiere quedarse quieto.
--
--   ¿Tengo que pegar esto? Para que aparezca el botón, sí. Si no lo
--   pegas, el panel funciona igual que hoy y el botón sencillamente
--   no sale — comprobado.
--
--   Agrega cuatro columnas a `reservas` (quién resolvió, cuándo, y de
--   dónde venía). No borra nada ni toca ninguna reserva existente.
--
-- ═══════════════════════════════════════════════════════════════

-- =====================================================================
-- Deshacer lo último
--
-- EL PROBLEMA
-- Confirmar y rechazar son irreversibles y están uno al lado del otro.
-- La duda de "¿era este el que había pagado?" llega medio segundo
-- después del clic, y hoy la única salida es tocar la base a mano.
-- Rechazar además suelta el cupo, así que un clic equivocado puede
-- vender el puesto de alguien que sí pagó.
--
-- QUÉ SE PUEDE Y QUÉ NO
-- Esto no es un historial ni un "control Z" general: es deshacer LO
-- QUE ACABAS DE HACER. Tres candados, a propósito:
--
--   1. Solo lo que resolvió una persona desde el panel. Lo que concilió
--      solo el sistema no se toca desde aquí: no fue un movimiento de
--      nadie, y deshacerlo sería desarmar la conciliación automática.
--   2. Solo dentro de los 15 minutos siguientes. Pasado ese rato ya no
--      es un resbalón, es cambiar de opinión sobre algo cerrado — y a
--      la persona probablemente ya se le avisó por WhatsApp.
--   3. Una sola vez. Al deshacer se borra la marca, así que no se puede
--      deshacer el deshacer.
--
-- CÓMO VUELVE ATRÁS
-- No se adivina el estado anterior: se guarda. Al confirmar o rechazar
-- se anota en qué estado estaba y a qué pago apuntaba, y deshacer
-- restaura exactamente eso. Es la diferencia entre "vuelve a pendiente"
-- (que se inventa un estado) y "vuelve a como estaba".
--
-- EL CASO INCÓMODO
-- Deshacer un rechazo tiene que volver a tomar el cupo, y en el rato
-- que pasó alguien pudo comprarlo. Si ya no hay, NO se sobrevende: se
-- niega y lo dice con nombre y apellido. Es lo único que esta función
-- puede no poder hacer, y por eso el aviso al rechazar dice que el
-- cupo queda libre de una.
-- =====================================================================

-- Quién resolvió, cuándo, y desde dónde venía. Sin esto, deshacer
-- tendría que adivinar — y no podría distinguir un clic del cajero de
-- una conciliación automática de las 3 de la mañana.
-- on delete set null: si se revoca un token, lo peor que puede pasar es
-- que se pierda la opcion de deshacer. Nunca que falle un borrado.
alter table reservas add column if not exists resuelta_por   uuid
  references admin_tokens(id) on delete set null;
alter table reservas add column if not exists resuelta_at    timestamptz;
alter table reservas add column if not exists estado_antes   estado_reserva;
alter table reservas add column if not exists pago_id_antes  uuid;

comment on column reservas.resuelta_por is
  'Token de admin que confirmo o rechazo a mano. Null = lo resolvio el sistema, y entonces no se puede deshacer desde el panel.';
comment on column reservas.estado_antes is
  'Estado justo antes de resolverla a mano. Deshacer restaura esto, no un estado inventado.';


-- ---------------------------------------------------------------------
-- Confirmar, ahora dejando rastro
-- ---------------------------------------------------------------------
create or replace function admin_confirmar(
  p_token text, p_codigo text, p_pago_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin   uuid;
  v_reserva reservas%rowtype;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_reserva from reservas
   where codigo = upper(trim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  if v_reserva.estado = 'confirmada' then
    return jsonb_build_object('ok', true, 'estado', 'confirmada',
      'codigo', v_reserva.codigo, 'mensaje', 'Ya estaba confirmada.');
  end if;

  if v_reserva.estado not in ('pendiente_validacion', 'verificando', 'pendiente_pago') then
    return jsonb_build_object('ok', false, 'error', 'ESTADO_INVALIDO',
      'estado', v_reserva.estado,
      'mensaje', 'Esa reserva esta en ' || v_reserva.estado || ', no se puede confirmar.');
  end if;

  if p_pago_id is not null then
    if exists (select 1 from reservas where pago_id = p_pago_id and id <> v_reserva.id) then
      return jsonb_build_object('ok', false, 'error', 'PAGO_YA_USADO',
        'mensaje', 'Ese pago ya esta amarrado a otra reserva.');
    end if;
    if not exists (select 1 from pagos where id = p_pago_id) then
      return jsonb_build_object('ok', false, 'error', 'PAGO_NO_EXISTE');
    end if;
  end if;

  update reservas
     set estado = 'confirmada',
         pago_id = coalesce(p_pago_id, pago_id),
         -- El rastro para poder deshacer: de donde venia y a que
         -- apuntaba. Se guarda antes de pisarlo.
         estado_antes  = v_reserva.estado,
         pago_id_antes = v_reserva.pago_id,
         resuelta_por  = v_admin,
         resuelta_at   = now(),
         updated_at    = now()
   where id = v_reserva.id;

  return jsonb_build_object('ok', true, 'estado', 'confirmada',
    'codigo', v_reserva.codigo, 'nombre', v_reserva.nombre,
    'telefono', v_reserva.telefono,
    'se_puede_deshacer', true,
    'mensaje', 'Confirmada a mano.');
end;
$$;


-- ---------------------------------------------------------------------
-- Rechazar, ahora dejando rastro
-- ---------------------------------------------------------------------
create or replace function admin_rechazar(p_token text, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin   uuid;
  v_reserva reservas%rowtype;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_reserva from reservas
   where codigo = upper(trim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  if v_reserva.estado = 'rechazada' then
    return jsonb_build_object('ok', true, 'estado', 'rechazada',
      'codigo', v_reserva.codigo, 'mensaje', 'Ya estaba rechazada.');
  end if;
  if v_reserva.estado = 'confirmada' then
    return jsonb_build_object('ok', false, 'error', 'YA_CONFIRMADA',
      'mensaje', 'Esa reserva ya esta confirmada. Si te acabas de equivocar, '
              || 'usa Deshacer; si no, hay que arreglarlo a mano.');
  end if;

  update reservas
     set estado        = 'rechazada',
         estado_antes  = v_reserva.estado,
         pago_id_antes = v_reserva.pago_id,
         resuelta_por  = v_admin,
         resuelta_at   = now(),
         updated_at    = now()
   where id = v_reserva.id;

  update clases set cupo_tomado = greatest(cupo_tomado - 1, 0)
   where id = v_reserva.clase_id;

  return jsonb_build_object('ok', true, 'estado', 'rechazada',
    'codigo', v_reserva.codigo, 'nombre', v_reserva.nombre,
    'telefono', v_reserva.telefono,
    'se_puede_deshacer', true,
    'mensaje', 'Rechazada, el cupo quedo libre.');
end;
$$;


-- ---------------------------------------------------------------------
-- Deshacer
-- ---------------------------------------------------------------------
create or replace function admin_deshacer(p_token text, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin   uuid;
  v_reserva reservas%rowtype;
  v_clase   clases%rowtype;
  v_minutos int;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_reserva from reservas
   where codigo = upper(trim(p_codigo)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  if v_reserva.estado not in ('confirmada', 'rechazada') then
    return jsonb_build_object('ok', false, 'error', 'NADA_QUE_DESHACER',
      'mensaje', 'Esa reserva no esta confirmada ni rechazada.');
  end if;

  -- Candado 1: lo que concilio solo el sistema no se deshace desde
  -- aqui. No fue el movimiento de nadie.
  if v_reserva.resuelta_por is null or v_reserva.estado_antes is null then
    return jsonb_build_object('ok', false, 'error', 'NO_FUE_A_MANO',
      'mensaje', 'Esta se resolvio sola, no desde el panel. No se deshace desde aqui.');
  end if;

  -- Candado 2: la ventana. Pasados 15 minutos ya no es un resbalon.
  v_minutos := floor(extract(epoch from (now() - v_reserva.resuelta_at)) / 60);
  if v_minutos > 15 then
    return jsonb_build_object('ok', false, 'error', 'FUERA_DE_TIEMPO',
      'minutos', v_minutos,
      'mensaje', 'Ya pasaron ' || v_minutos || ' minutos. Deshacer solo sirve '
              || 'en los primeros 15; despues hay que resolverlo a mano.');
  end if;

  -- Deshacer un rechazo tiene que volver a tomar el cupo, y en ese rato
  -- alguien pudo comprarlo. Antes de sobrevender, se niega.
  if v_reserva.estado = 'rechazada' then
    select * into v_clase from clases where id = v_reserva.clase_id for update;
    if v_clase.cupo_tomado >= v_clase.cupo_total then
      return jsonb_build_object('ok', false, 'error', 'SIN_CUPO',
        'mensaje', 'Mientras tanto se vendio ese cupo y la clase quedo llena. '
                || 'Si hay que meter a esta persona, primero sube el cupo a mano '
                || 'en la pestana Horario.');
    end if;
    update clases set cupo_tomado = cupo_tomado + 1 where id = v_clase.id;
  end if;

  -- Vuelve a como estaba, no a un estado inventado. Y se borra el
  -- rastro: deshacer se usa una vez.
  update reservas
     set estado        = v_reserva.estado_antes,
         pago_id       = v_reserva.pago_id_antes,
         estado_antes  = null,
         pago_id_antes = null,
         resuelta_por  = null,
         resuelta_at   = null,
         updated_at    = now()
   where id = v_reserva.id;

  return jsonb_build_object('ok', true,
    'codigo',  v_reserva.codigo,
    'nombre',  v_reserva.nombre,
    'estado',  v_reserva.estado_antes,
    'deshizo', v_reserva.estado,
    'mensaje', 'Deshecho. Vuelve a la cola tal como estaba.');
end;
$$;

comment on function admin_deshacer(text, text) is
  'Deshace el confirmar/rechazar de los ultimos 15 minutos, solo si lo hizo una persona desde el panel. Restaura el estado guardado, no uno inventado.';


-- ---------------------------------------------------------------------
-- La cola, diciendo tambien que se puede deshacer
--
-- Una reserva resuelta hace un minuto ya no aparece en la cola: se
-- necesita saber, desde la propia respuesta de confirmar/rechazar, si
-- el boton de deshacer tiene sentido. Eso ya viene en 'se_puede_deshacer'.
-- Aqui solo se anaden los minutos que quedan, para que el panel pueda
-- esconder el boton cuando se acabe el plazo.
-- ---------------------------------------------------------------------

revoke execute on function admin_deshacer(text, text)         from public, anon, authenticated;
revoke execute on function admin_confirmar(text, text, uuid)  from public, anon, authenticated;
revoke execute on function admin_rechazar(text, text)         from public, anon, authenticated;

-- admin_deshacer es nueva, asi que nunca tuvo el grant a service_role
-- —el rol con el que entra n8n— y el revoke de arriba le quita el que
-- heredaba de public. Las otras dos ya lo traian de 0011 y el revoke no
-- toca un grant explicito, pero se repiten por claridad: asi este bloque
-- se lee entero sin ir a buscar que paso en otra migracion.
grant execute on function admin_deshacer(text, text)        to service_role;
grant execute on function admin_confirmar(text, text, uuid) to service_role;
grant execute on function admin_rechazar(text, text)        to service_role;

-- ── Comprobación: esto tiene que decir "deshacer OK" ─────────────
do $$
declare
  v_tok text; v_c uuid; v_r jsonb; v_cod text; v_est text;
  v_tomado_antes int; v_tomado int;
begin
  v_tok := (crear_token_admin('comprobacion de deshacer'))->>'token';

  -- Se hace sobre una clase de verdad pero SIN dejar rastro: al final
  -- se borra la reserva de prueba y se devuelve el cupo como estaba.
  select id into v_c from clases where fecha_hora > now() and activa
   order by fecha_hora limit 1;
  if v_c is null then
    delete from admin_tokens where nombre = 'comprobacion de deshacer';
    raise notice 'deshacer OK (sin clases futuras para probar el ciclo)';
    return;
  end if;

  select cupo_tomado into v_tomado_antes from clases where id = v_c;

  select tomar_cupo(v_c, 'PRUEBA BORRAR', '3000000000', null, 'prueba', 'suelta') into v_r;
  if (v_r->>'ok')::boolean is not true then
    delete from admin_tokens where nombre = 'comprobacion de deshacer';
    raise notice 'deshacer OK (la clase estaba llena, no se pudo probar el ciclo)';
    return;
  end if;
  v_cod := v_r->>'codigo';
  update reservas set estado = 'pendiente_validacion' where codigo = v_cod;

  perform admin_rechazar(v_tok, v_cod);
  select admin_deshacer(v_tok, v_cod) into v_r;
  if (v_r->>'ok')::boolean is not true then
    raise exception 'deshacer no funciono: %', v_r;
  end if;
  select estado::text into v_est from reservas where codigo = v_cod;
  if v_est <> 'pendiente_validacion' then
    raise exception 'no restauro el estado, quedo en %', v_est;
  end if;

  -- Y se limpia: la reserva de prueba no puede quedar viva.
  delete from reservas where codigo = v_cod;
  update clases set cupo_tomado = v_tomado_antes where id = v_c;
  select cupo_tomado into v_tomado from clases where id = v_c;
  if v_tomado <> v_tomado_antes then
    raise exception 'la prueba dejo el cupo en % y estaba en %', v_tomado, v_tomado_antes;
  end if;

  delete from admin_tokens where nombre = 'comprobacion de deshacer';
  raise notice 'deshacer OK — probado el ciclo completo y limpiado';
end $$;


-- ╔═══════════════════════════════════════════════════════════════════╗
-- ║  PARTE 4 de 6   ·   Lista de la puerta                          ║
-- ║  Quién entra hoy, con marcar asistió / ingresó.                   ║
-- ╚═══════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════
--
--   TUMBAO — LA LISTA DE LA PUERTA
--
--   Pégalo entero en el SQL Editor de Supabase y dale Run.
--   Se puede correr las veces que quieras.
--
--   ¿Qué resuelve? Llega alguien y dice "yo reservé". Hasta ahora no
--   había dónde mirarlo: la cola de validación solo muestra lo que NO
--   concilió, así que justo la gente que pagó bien desaparecía de la
--   pantalla. Al revés de lo que hace falta en la puerta.
--
--   Cómo se usa: en el Tablero, toca la tarjeta de la clase. Se abre
--   la lista con un buscador y un botón grande por persona.
--
--   OJO CON ALGO IMPORTANTE
--   Entre semana entran DOS grupos y solo uno reserva:
--
--     · quien compró clase suelta  → tiene reserva
--     · quien tiene mensualidad    → NO reserva, solo llega
--
--   La lista trae los dos, separados, y los dos se marcan igual. Con
--   solo las reservas estarías mirando 3 nombres de las 30 personas
--   que van a entrar. El sábado el segundo grupo va vacío, porque ahí
--   nadie tiene plan y todos reservan.
--
--   Crea una tabla nueva (`asistencias`) y dos funciones. No borra
--   nada ni toca ninguna reserva existente. La asistencia se guarda
--   aparte a propósito: `membresias` se borra entera cada noche, y lo
--   que ya pasó por la puerta no puede irse con ella.
--
-- ═══════════════════════════════════════════════════════════════

-- =====================================================================
-- La lista de la puerta
--
-- LA PREGUNTA QUE NO TENÍA RESPUESTA
-- Llega alguien y dice "yo reservé". ¿Dónde se mira? En ningún lado.
-- La cola de validación solo muestra lo que NO concilió: justamente la
-- gente que pagó bien y se confirmó sola desaparece de la pantalla, que
-- es exactamente al revés de lo que hace falta en la puerta.
--
-- QUIÉN ENTRA DE VERDAD A UNA CLASE
-- Entre semana son DOS grupos distintos y solo uno reserva:
--
--   · quien compró clase suelta  → tiene reserva, hay que buscarla
--   · quien tiene mensualidad    → NO reserva, su puesto ya está
--                                   descontado del aforo, solo llega
--
-- Una lista con solo las reservas dejaría al portero mirando 3 nombres
-- de las 30 personas que van a entrar. Por eso esta lista trae los dos
-- grupos, separados y marcables por igual. El sábado el segundo grupo
-- está vacío: ahí nadie tiene plan y todos reservan.
--
-- POR QUÉ UNA TABLA APARTE Y NO UNA COLUMNA EN `reservas`
-- Porque el miembro de entre semana no tiene fila en `reservas`. Y
-- porque `membresias` es una réplica que se BORRA ENTERA cada noche:
-- si la asistencia colgara de ahí, se perdería en la importación. Por
-- eso `asistencias` copia el nombre y el celular en el momento de
-- marcar. Lo que pasó por la puerta es un hecho, no una vista de otra
-- tabla.
-- =====================================================================

create table if not exists asistencias (
  id            uuid primary key default gen_random_uuid(),
  clase_id      uuid not null references clases(id) on delete cascade,
  -- Una de las dos, según de dónde venga la persona.
  reserva_id    uuid   references reservas(id)   on delete cascade,
  membresia_id  bigint references membresias(id) on delete set null,
  -- Copiados a propósito: membresias se reemplaza entera cada noche y
  -- la asistencia tiene que sobrevivir a eso.
  nombre        text not null,
  telefono      text,
  origen        text not null check (origen in ('reserva', 'plan')),
  marcada_at    timestamptz not null default now(),
  marcada_por   uuid references admin_tokens(id) on delete set null
);

-- Una marca por persona y clase. Para las reservas la llave natural es
-- la reserva; para los planes es el celular, que es lo único que
-- sobrevive a que la importación nocturna renumere las membresías.
create unique index if not exists asistencias_una_por_persona
  on asistencias (clase_id, coalesce(reserva_id::text, 'tel:' || coalesce(telefono, nombre)));

create index if not exists asistencias_por_clase on asistencias (clase_id);

comment on table asistencias is
  'Quien entro de verdad a cada clase. Incluye a los de plan, que no reservan. Copia nombre y celular porque membresias se reemplaza cada noche.';


-- ---------------------------------------------------------------------
-- La lista, tal como se necesita en la puerta
--
-- Devuelve los dos grupos y, en cada persona, un `ref` opaco que es lo
-- único que el panel tiene que devolver para marcarla. Así la página no
-- tiene que saber si por dentro es una reserva o una membresía.
-- ---------------------------------------------------------------------
create or replace function admin_lista_clase(p_token text, p_clase_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_clase  clases%rowtype;
  v_fecha  date;
  v_hora   time;
  v_res    jsonb;
  v_plan   jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_clase from clases where id = p_clase_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  v_fecha := (v_clase.fecha_hora at time zone 'America/Bogota')::date;
  v_hora  := (v_clase.fecha_hora at time zone 'America/Bogota')::time;

  -- ── Grupo 1: quienes reservaron ────────────────────────────
  -- Se incluyen las que todavía no concilian. Alguien puede plantarse
  -- en la puerta con el pago hecho hace dos minutos, y el portero tiene
  -- que verlo aunque diga "sin confirmar" al lado.
  select coalesce(jsonb_agg(x order by x->>'nombre'), '[]'::jsonb) into v_res
  from (
    select jsonb_build_object(
      'ref',        'r:' || r.codigo,
      'codigo',     r.codigo,
      'nombre',     r.nombre,
      'telefono',   r.telefono,
      'tipo',       r.tipo,
      'estado',     r.estado,
      'confirmada', r.estado = 'confirmada',
      'asistio',    a.id is not null,
      'marcada_at', a.marcada_at
    ) as x
    from reservas r
    left join asistencias a on a.reserva_id = r.id
   where r.clase_id = p_clase_id
     and r.estado not in ('expirada', 'rechazada')
  ) s;

  -- ── Grupo 2: quienes tienen plan de esa hora ───────────────
  -- Entre semana no reservan: su puesto ya salió del aforo. El sábado
  -- esto viene vacío porque nadie tiene plan de sábado.
  select coalesce(jsonb_agg(x order by x->>'nombre'), '[]'::jsonb) into v_plan
  from (
    select jsonb_build_object(
      'ref',        'p:' || coalesce(solo_digitos(m.celular), m.afiliado),
      'nombre',     m.afiliado,
      'telefono',   m.celular,
      'membresia',  m.membresia,
      'hasta',      m.fin,
      'asistio',    a.id is not null,
      'marcada_at', a.marcada_at
    ) as x
    from membresias m
    left join asistencias a
           on a.clase_id = p_clase_id
          and a.origen = 'plan'
          and solo_digitos(a.telefono) = solo_digitos(m.celular)
   where m.hora = v_hora
     and v_fecha between m.inicio and m.fin
     -- Si además reservó (caso del sábado), ya salió en el grupo 1.
     and not exists (
       select 1 from reservas r
        where r.clase_id = p_clase_id
          and r.estado not in ('expirada', 'rechazada')
          and solo_digitos(r.telefono) = solo_digitos(m.celular))
  ) s;

  return jsonb_build_object(
    'ok', true,
    'clase', jsonb_build_object(
      'clase_id', v_clase.id,
      'nombre',   v_clase.nombre,
      'fecha',    v_fecha,
      'hora',     to_char(v_hora, 'HH24:MI'),
      'aforo',    v_clase.aforo,
      'ya_paso',  v_clase.fecha_hora <= now()),
    'reservas', v_res,
    'con_plan', v_plan,
    'resumen', jsonb_build_object(
      'reservas',        jsonb_array_length(v_res),
      'con_plan',        jsonb_array_length(v_plan),
      'esperados',       jsonb_array_length(v_res) + jsonb_array_length(v_plan),
      'entraron',        (select count(*)::int from asistencias where clase_id = p_clase_id),
      'sin_confirmar',   (select count(*)::int from jsonb_array_elements(v_res) e
                           where (e->>'confirmada')::boolean is not true)));
end;
$$;

comment on function admin_lista_clase(text, uuid) is
  'La lista de la puerta: quien reservo y quien tiene plan de esa hora, con si ya entro. El `ref` de cada persona es lo que se manda a admin_marcar_asistencia.';


-- ---------------------------------------------------------------------
-- Marcar que entró (o deshacerlo)
--
-- `p_ref` es el mismo que devolvió la lista: 'r:CODIGO' para una
-- reserva, 'p:CELULAR' para alguien con plan. El panel no tiene que
-- saber qué significa, solo devolverlo.
--
-- Es idempotente por diseño: en la puerta se dan clics repetidos y con
-- prisa, y marcar dos veces no puede contar dos personas.
-- ---------------------------------------------------------------------
create or replace function admin_marcar_asistencia(
  p_token text, p_clase_id uuid, p_ref text, p_asistio boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_tipo   text;
  v_valor  text;
  v_res    reservas%rowtype;
  v_memb   membresias%rowtype;
  v_clase  clases%rowtype;
  v_hora   time;
  v_fecha  date;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_clase from clases where id = p_clase_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'CLASE_NO_EXISTE');
  end if;

  v_tipo  := split_part(p_ref, ':', 1);
  v_valor := substring(p_ref from position(':' in p_ref) + 1);
  if v_valor is null or v_valor = '' then
    return jsonb_build_object('ok', false, 'error', 'REF_INVALIDA');
  end if;

  ------------------------------------------------------------------
  -- Una reserva
  ------------------------------------------------------------------
  if v_tipo = 'r' then
    select * into v_res from reservas
     where codigo = upper(trim(v_valor)) and clase_id = p_clase_id;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'NO_EXISTE',
        'mensaje', 'Esa reserva no es de esta clase.');
    end if;

    if p_asistio then
      insert into asistencias (clase_id, reserva_id, nombre, telefono,
                               origen, marcada_por)
      values (p_clase_id, v_res.id, v_res.nombre, v_res.telefono,
              'reserva', v_admin)
      on conflict do nothing;          -- marcar dos veces no cuenta dos
    else
      delete from asistencias where reserva_id = v_res.id and clase_id = p_clase_id;
    end if;

    return jsonb_build_object('ok', true, 'ref', p_ref, 'asistio', p_asistio,
      'nombre', v_res.nombre,
      'entraron', (select count(*)::int from asistencias where clase_id = p_clase_id));
  end if;

  ------------------------------------------------------------------
  -- Alguien con plan
  ------------------------------------------------------------------
  if v_tipo = 'p' then
    v_fecha := (v_clase.fecha_hora at time zone 'America/Bogota')::date;
    v_hora  := (v_clase.fecha_hora at time zone 'America/Bogota')::time;

    select * into v_memb from membresias m
     where m.hora = v_hora
       and v_fecha between m.inicio and m.fin
       and (solo_digitos(m.celular) = solo_digitos(v_valor) or m.afiliado = v_valor)
     order by m.fin desc limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'NO_EXISTE',
        'mensaje', 'No hay un plan activo de esa hora con ese celular.');
    end if;

    if p_asistio then
      insert into asistencias (clase_id, membresia_id, nombre, telefono,
                               origen, marcada_por)
      values (p_clase_id, v_memb.id, v_memb.afiliado, v_memb.celular,
              'plan', v_admin)
      on conflict do nothing;
    else
      delete from asistencias
       where clase_id = p_clase_id and origen = 'plan'
         and solo_digitos(telefono) = solo_digitos(v_memb.celular);
    end if;

    return jsonb_build_object('ok', true, 'ref', p_ref, 'asistio', p_asistio,
      'nombre', v_memb.afiliado,
      'entraron', (select count(*)::int from asistencias where clase_id = p_clase_id));
  end if;

  return jsonb_build_object('ok', false, 'error', 'REF_INVALIDA');
end;
$$;

comment on function admin_marcar_asistencia(text, uuid, text, boolean) is
  'Marca o desmarca que una persona entro a una clase. Idempotente: en la puerta se dan clics repetidos.';


revoke execute on function admin_lista_clase(text, uuid)                       from public, anon, authenticated;
revoke execute on function admin_marcar_asistencia(text, uuid, text, boolean)  from public, anon, authenticated;

-- Las dos son nuevas: sin este grant, n8n —que entra como service_role—
-- no puede ni abrir la lista de la puerta ni marcar que alguien entro.
grant execute on function admin_lista_clase(text, uuid)                       to service_role;
grant execute on function admin_marcar_asistencia(text, uuid, text, boolean)  to service_role;

alter table asistencias enable row level security;

-- ── Comprobación: esto tiene que decir "puerta OK" ───────────────
do $$
declare
  v_tok text; v_c uuid; v_l jsonb;
begin
  v_tok := (crear_token_admin('comprobacion de puerta'))->>'token';

  select id into v_c from clases where fecha_hora > now() and activa
   order by fecha_hora limit 1;
  if v_c is null then
    delete from admin_tokens where nombre = 'comprobacion de puerta';
    raise notice 'puerta OK (sin clases futuras para mirar)';
    return;
  end if;

  v_l := admin_lista_clase(v_tok, v_c);
  if (v_l->>'ok')::boolean is not true then
    raise exception 'la lista no respondio: %', v_l;
  end if;
  -- Los dos grupos tienen que sumar lo que dice el resumen.
  if (v_l->'resumen'->>'esperados')::int
     <> jsonb_array_length(v_l->'reservas') + jsonb_array_length(v_l->'con_plan') then
    raise exception 'el resumen no cuadra con las dos listas: %', v_l->'resumen';
  end if;

  delete from admin_tokens where nombre = 'comprobacion de puerta';
  raise notice 'puerta OK — la clase de las % espera % persona(s): % con reserva, % con plan',
    v_l->'clase'->>'hora', v_l->'resumen'->>'esperados',
    v_l->'resumen'->>'reservas', v_l->'resumen'->>'con_plan';
end $$;


-- ╔═══════════════════════════════════════════════════════════════════╗
-- ║  PARTE 5 de 6   ·   Vencen ese día                              ║
-- ║  Aviso punteado de cuántos planes terminan ese día.               ║
-- ╚═══════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════
--
--   TUMBAO — CUÁNTOS VENCEN ESE DÍA
--
--   Pégalo entero en el SQL Editor de Supabase y dale Run.
--   Se puede correr las veces que quieras.
--
--   ¿Qué agrega? Un aviso punteado en la tarjeta de cada clase del
--   Tablero:
--
--       ⌛ 2 con plan vencen este día
--
--   Una mensualidad que termina hoy sigue contando hoy: su puesto
--   está descontado del aforo y no se ofrece a clase suelta. Es lo
--   correcto — pero esa persona puede no venir, y si no viene tampoco
--   renueva. Se guardó un puesto que nadie usó y se dejó de vender
--   una suelta que sí se habría vendido.
--
--   Con ese número puedes arriesgarte a vender hasta esa cantidad de
--   sueltas de más, sabiendo exactamente cuánto arriesgas.
--
--   OJO: NO se suma al cupo. Es una apuesta, no un cupo. Si los dos
--   aparecen —y la gente suele renovar el último día— y encima se
--   vendieron dos sueltas, la sala queda apretada. La decisión la
--   tomas tú con el número delante, no la función sola.
--
--   De paso, en la lista de la puerta cada persona a la que se le
--   acaba el plan ese día sale marcada con "vence hoy". Está enfrente
--   tuyo: es el mejor momento que vas a tener para renovarla.
--
--   No crea tablas ni columnas. Solo cambia dos funciones de lectura.
--
-- ═══════════════════════════════════════════════════════════════

-- =====================================================================
-- Cuántos de los que ocupan puesto vencen ese mismo día
--
-- EL PROBLEMA, TAL CUAL PASA
-- Una mensualidad que termina hoy sigue contando hoy: su puesto está
-- descontado del aforo y el sistema no ofrece esa silla a clase suelta.
-- Correcto — pero esa persona puede no venir, y si no viene tampoco
-- renueva. Resultado: se guardó un puesto que nadie usó y se dejó de
-- vender una suelta que sí se habría vendido.
--
-- Lo que hace falta no es que el sistema decida por su cuenta, sino que
-- diga el número: "de los 27 que tienen plan a las 6, 2 vencen hoy".
-- Con eso se puede arriesgar a vender 2 sueltas de más sabiendo
-- exactamente cuánto se arriesga.
--
-- POR QUÉ NO SE SUMA A `cupo_total`
-- Porque no es un cupo: es una apuesta. Si los dos aparecen —y suelen
-- aparecer, la gente renueva el último día— y además se vendieron dos
-- sueltas, la sala queda apretada y a alguien le toca de pie. Que la
-- decisión la tome una persona, con el número delante, no una función.
--
-- CÓMO SE CUENTA
-- Mismo criterio que `recalcular_cupos` usa para `activos_plan`, más
-- `fin = ese día`. Así el número nuevo siempre es un subconjunto del que
-- ya sale en la tarjeta y los dos no se pueden contradecir.
--
-- Se cuenta contra la fecha DE LA CLASE, no contra hoy: el tablero se
-- mueve día a día, y en la tarjeta del lunes que viene tiene que salir
-- quién vence el lunes que viene.
-- =====================================================================

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
      -- de dónde sale el cupo
      'aforo',       c.aforo,
      'con_plan',    c.activos_plan,
      'a_la_venta',  c.cupo_total,
      'cupo_manual', c.cupo_manual,
      -- de los que tienen plan, cuántos se les acaba ESE día
      'vencen',      v.vencen,
      -- qué se ha vendido
      'reservadas',  c.cupo_tomado,
      'libres',      greatest(c.cupo_total - c.cupo_tomado, 0),
      'confirmadas', n.confirmadas,
      'por_validar', n.por_validar,
      'esperando',   n.esperando,
      -- cuánta gente entra
      'en_sala',     c.activos_plan + c.cupo_tomado,
      'ingreso_cop', n.confirmadas * c.precio_cop
    ) as x
    from clases c
    cross join lateral (
      select
        count(*) filter (where r.estado = 'confirmada')::int            as confirmadas,
        count(*) filter (where r.estado = 'pendiente_validacion')::int  as por_validar,
        count(*) filter (where r.estado in ('pendiente_pago','verificando'))::int as esperando
      from reservas r where r.clase_id = c.id
    ) n
    cross join lateral (
      -- Mismo filtro que recalcular_cupos, y encima `fin = ese dia`. Al
      -- ser un subconjunto, nunca puede salir mayor que `con_plan`.
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

comment on function admin_tablero(text, date) is
  'Tarjetas del dia para el panel. `vencen` son los del plan a los que se les acaba ESE dia: no se suman al cupo, se muestran para poder decidir si se arriesga a vender sueltas de mas.';


-- ---------------------------------------------------------------------
-- Y en la puerta, marcados uno por uno
--
-- Es el momento en que esa persona está enfrente. Saber que su plan se
-- acaba hoy convierte la lista de acceso en la mejor oportunidad de
-- renovación que hay: no hay que llamar a nadie, ya llegó.
-- ---------------------------------------------------------------------
create or replace function admin_lista_clase(p_token text, p_clase_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_clase  clases%rowtype;
  v_fecha  date;
  v_hora   time;
  v_res    jsonb;
  v_plan   jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_clase from clases where id = p_clase_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  v_fecha := (v_clase.fecha_hora at time zone 'America/Bogota')::date;
  v_hora  := (v_clase.fecha_hora at time zone 'America/Bogota')::time;

  select coalesce(jsonb_agg(x order by x->>'nombre'), '[]'::jsonb) into v_res
  from (
    select jsonb_build_object(
      'ref',        'r:' || r.codigo,
      'codigo',     r.codigo,
      'nombre',     r.nombre,
      'telefono',   r.telefono,
      'tipo',       r.tipo,
      'estado',     r.estado,
      'confirmada', r.estado = 'confirmada',
      'asistio',    a.id is not null,
      'marcada_at', a.marcada_at
    ) as x
    from reservas r
    left join asistencias a on a.reserva_id = r.id
   where r.clase_id = p_clase_id
     and r.estado not in ('expirada', 'rechazada')
  ) s;

  select coalesce(jsonb_agg(x order by x->>'nombre'), '[]'::jsonb) into v_plan
  from (
    select jsonb_build_object(
      'ref',        'p:' || coalesce(solo_digitos(m.celular), m.afiliado),
      'nombre',     m.afiliado,
      'telefono',   m.celular,
      'membresia',  m.membresia,
      'hasta',      m.fin,
      'vence_hoy',  m.fin = v_fecha,
      'asistio',    a.id is not null,
      'marcada_at', a.marcada_at
    ) as x
    from membresias m
    left join asistencias a
           on a.clase_id = p_clase_id
          and a.origen = 'plan'
          and solo_digitos(a.telefono) = solo_digitos(m.celular)
   where m.hora = v_hora
     and v_fecha between m.inicio and m.fin
     and not exists (
       select 1 from reservas r
        where r.clase_id = p_clase_id
          and r.estado not in ('expirada', 'rechazada')
          and solo_digitos(r.telefono) = solo_digitos(m.celular))
  ) s;

  return jsonb_build_object(
    'ok', true,
    'clase', jsonb_build_object(
      'clase_id', v_clase.id,
      'nombre',   v_clase.nombre,
      'fecha',    v_fecha,
      'hora',     to_char(v_hora, 'HH24:MI'),
      'aforo',    v_clase.aforo,
      'ya_paso',  v_clase.fecha_hora <= now()),
    'reservas', v_res,
    'con_plan', v_plan,
    'resumen', jsonb_build_object(
      'reservas',        jsonb_array_length(v_res),
      'con_plan',        jsonb_array_length(v_plan),
      'esperados',       jsonb_array_length(v_res) + jsonb_array_length(v_plan),
      'entraron',        (select count(*)::int from asistencias where clase_id = p_clase_id),
      'vencen',          (select count(*)::int from jsonb_array_elements(v_plan) e
                           where (e->>'vence_hoy')::boolean),
      'sin_confirmar',   (select count(*)::int from jsonb_array_elements(v_res) e
                           where (e->>'confirmada')::boolean is not true)));
end;
$$;

revoke execute on function admin_tablero(text, date)     from public, anon, authenticated;
revoke execute on function admin_lista_clase(text, uuid) from public, anon, authenticated;

-- `create or replace` conserva los permisos, asi que el grant de 0016 y
-- 0018 sobrevive y esto es redundante. Va igual: si alguien aplica esta
-- migracion sola, o cambia el orden, el permiso queda puesto de todos
-- modos. Un grant de mas no rompe nada; el que falta si.
grant execute on function admin_tablero(text, date)     to service_role;
grant execute on function admin_lista_clase(text, uuid) to service_role;

-- ── Comprobación: esto tiene que decir "vencimientos OK" ─────────
do $$
declare
  v_tok text; v_t jsonb; v_c jsonb; v_hoy date; v_total int := 0;
begin
  v_tok := (crear_token_admin('comprobacion de vencimientos'))->>'token';
  v_hoy := (now() at time zone 'America/Bogota')::date;

  -- En los proximos 14 dias, el numero nunca puede pasarse de los que
  -- tienen plan. Si se pasara, se estarian ofreciendo puestos ocupados.
  for v_c in
    select c from generate_series(0, 13) g,
         lateral jsonb_array_elements(
           (admin_tablero(v_tok, v_hoy + g))->'clases') c
  loop
    if (v_c->>'vencen')::int > (v_c->>'con_plan')::int then
      raise exception 'vencen (%) mayor que con plan (%) en la clase de las %',
        v_c->>'vencen', v_c->>'con_plan', v_c->>'hora';
    end if;
    v_total := v_total + (v_c->>'vencen')::int;
  end loop;

  delete from admin_tokens where nombre = 'comprobacion de vencimientos';
  raise notice 'vencimientos OK — en los proximos 14 dias vencen % planes (contando cada clase)', v_total;
end $$;


-- ╔═══════════════════════════════════════════════════════════════════╗
-- ║  PARTE 6 de 6   ·   El sábado, 15 y 15                          ║
-- ║  Parte el aforo del sábado en afiliados y sueltas.                ║
-- ╚═══════════════════════════════════════════════════════════════════╝

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

-- clases_para es NUEVA y es la que responde /tumbao/clases: sin este
-- grant la pagina publica no muestra una sola clase. Es el peor de los
-- permisos que se pueden olvidar aqui, porque rompe lo que ya andaba.
-- Las otras tres conservan su grant por `create or replace`, pero se
-- listan explicitas para no depender de eso.
grant execute on function clases_para(text)                                to service_role;
grant execute on function tomar_cupo(uuid, text, text, text, text, text)   to service_role;
grant execute on function generar_horario(date, date, int, int, text, text) to service_role;
grant execute on function admin_tablero(text, date)                        to service_role;

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


-- ╔═══════════════════════════════════════════════════════════════════╗
-- ║  RESUMEN                                                          ║
-- ║  Si ves esta tabla con seis filas, todo entró bien.               ║
-- ╚═══════════════════════════════════════════════════════════════════╝

select * from (values
  (1, 'Arreglo del panel',   'listo'),
  (2, 'Pestana de Tablero',  'listo'),
  (3, 'Boton de deshacer',   'listo'),
  (4, 'Lista de la puerta',  'listo'),
  (5, 'Vencen ese dia',      'listo'),
  (6, 'Sabado 15 y 15',      'listo')
) as t(parte, que, estado);
