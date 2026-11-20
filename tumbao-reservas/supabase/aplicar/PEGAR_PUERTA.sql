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

select 'Lista de puerta lista' as resultado;
