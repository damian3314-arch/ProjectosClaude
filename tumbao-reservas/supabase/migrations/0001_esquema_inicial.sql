-- =====================================================================
-- Tumbao Reservas — esquema inicial
-- Fiel al blueprint. Las dos únicas adiciones están marcadas [ADICIÓN].
-- =====================================================================

create type estado_reserva as enum (
  'pendiente_pago', 'verificando', 'confirmada',
  'pendiente_validacion', 'rechazada', 'expirada'
);

create table clases (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null,
  profesor      text not null,
  fecha_hora    timestamptz not null,
  duracion_min  int not null default 60,
  cupo_total    int not null check (cupo_total > 0),
  cupo_tomado   int not null default 0 check (cupo_tomado >= 0),
  precio_cop    int not null check (precio_cop > 0),
  lugar         text,
  activa        boolean not null default true,
  created_at    timestamptz not null default now(),
  -- La garantía dura de que no hay sobreventa vive aquí, en la base.
  -- Aunque alguien se salte tomar_cupo(), esto no deja pasar.
  constraint cupo_no_excedido check (cupo_tomado <= cupo_total)
);

create index clases_proximas on clases (fecha_hora) where activa;

create table pagos (
  id          uuid primary key default gen_random_uuid(),
  banco       text not null,
  valor_cop   int not null check (valor_cop > 0),
  fecha_pago  timestamptz not null,
  referencia  text,
  remitente   text,
  ultimos_4   text,
  consumido   boolean not null default false,
  raw_email   text,
  hoja_fila   text,
  created_at  timestamptz not null default now()
);

-- El índice que hace rápido el cruce: por valor y fecha, solo sobre los
-- no consumidos.
create index pagos_busqueda   on pagos (valor_cop, fecha_pago) where not consumido;
create index pagos_referencia on pagos (referencia) where referencia is not null;

-- [ADICIÓN] Idempotencia de la ingesta a nivel de base.
-- El blueprint pide que POST /api/pagos/ingest sea idempotente, pero lo
-- deja en manos de la aplicación. Si dos correos llegan a la vez, la
-- comprobación en TypeScript no alcanza. Esto lo cierra en Postgres.
create unique index pagos_unicos
  on pagos (banco, valor_cop, fecha_pago, coalesce(referencia, ''));

create table reservas (
  id              uuid primary key default gen_random_uuid(),
  codigo          text not null unique,
  clase_id        uuid not null references clases(id),
  nombre          text not null,
  telefono        text not null,
  email           text,
  estado          estado_reserva not null default 'pendiente_pago',
  comprobante_url text,
  ocr_json        jsonb,
  pago_id         uuid references pagos(id),
  motivo_rechazo  text,
  origen          text not null default 'formulario',
  expira_en       timestamptz not null default now() + interval '30 minutes',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  -- [ADICIÓN] Ley 1581 de 2012. Recoger nombre y celular de una persona
  -- en Colombia exige autorización explícita y registrar cuándo se dio.
  -- El blueprint no lo contempla y es obligatorio.
  habeas_data_at  timestamptz not null default now()
);

create index reservas_pendientes on reservas (created_at desc)
  where estado = 'pendiente_validacion';
create index reservas_por_clase    on reservas (clase_id);
create index reservas_por_telefono on reservas (telefono);

-- Un pago no puede confirmar dos reservas.
create unique index reservas_pago_unico on reservas (pago_id) where pago_id is not null;

create table admin_users (
  id  uuid primary key references auth.users(id) on delete cascade,
  rol text not null default 'operador' check (rol in ('admin','operador'))
);
