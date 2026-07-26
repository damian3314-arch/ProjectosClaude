# Tumbao Reservas — Blueprint

> Generado por The Architect · 2026-07-26
> Arquetipo: SaaS Web App (reservas con verificación semiautomática de pagos)
> Destinatario: una instancia de Claude Code que construya el proyecto de cero a producción.

---

## 1. Visión del Proyecto

### Visión

Tumbao vende clases de baile con cupo limitado. Hoy la reserva ocurre por WhatsApp: la persona escribe, pregunta horarios, transfiere por Nequi o Bancolombia, manda la captura, y alguien del equipo revisa el correo del banco a mano para confirmar que el dinero llegó. Ese ida y vuelta consume tiempo humano en cada reserva y no escala.

Este proyecto reemplaza ese hilo de WhatsApp por una página web propia. WhatsApp deja de ser el canal de reserva y pasa a ser solo el punto de entrada: se le manda un link a la persona y ella completa todo en la web, sin cuenta ni contraseña. Puede hacerlo conversando con un bot que entiende lenguaje natural, o siguiendo un formulario guiado paso a paso — ambos caminos terminan en el mismo lugar. Al subir el comprobante, el sistema lee la imagen, la cruza contra los pagos que ya llegaron al correo, y confirma la reserva en segundos. Si no encuentra el pago, la deja pendiente y avisa que un humano la validará.

El objetivo no es un producto para vender: es quitarle a Tumbao el trabajo manual de tomar reservas y verificar pagos.

### Objetivos

- Que una persona pueda reservar sin hablar con nadie, desde el celular, en menos de dos minutos.
- Que la mayoría de las reservas se confirmen solas, sin intervención humana.
- Que nadie del equipo tenga que abrir el correo del banco para verificar un pago.
- Que sea imposible vender más cupos de los que existen.
- Que la hoja de Google que Luz Alejandra ya usa siga funcionando igual que hoy.

### Métricas de Éxito

- **≥70% de reservas confirmadas automáticamente** (sin tocar el panel admin).
- **Tiempo de confirmación < 10 segundos** desde que se sube el comprobante.
- **0 casos de sobreventa** de cupos.
- **Tiempo humano por reserva: de ~5 min a ~0** en el camino feliz.

---

## 2. Stack Técnico

| Capa | Tecnología | Por qué |
|-------|-----------|-----|
| Framework | Next.js 15 (App Router) | Mismo stack que Beat — una sola tecnología que mantener en los dos proyectos. Server Components eliminan la mitad de los endpoints. |
| Lenguaje | TypeScript (strict) | No negociable. El modelo de datos tiene suficientes estados como para que los tipos paguen solos. |
| Estilos | Tailwind CSS v4 | Estándar. Con `@theme` los tokens de diseño viven en CSS, no en un archivo de config. |
| Componentes | shadcn/ui | Código copiado al repo, no una dependencia. Se personaliza sin pelear. |
| Base de datos | Supabase (Postgres) | Ya conocido del stack de Beat. Postgres da transacciones reales, que es lo que impide la sobreventa. |
| Storage | Supabase Storage | Los comprobantes viven junto a la BD, con URLs firmadas y expiración. |
| Acceso a datos | `@supabase/supabase-js` + SQL directo | No hace falta un ORM: el esquema es pequeño y la lógica crítica (tomar cupo) es una función SQL. Un ORM solo agregaría una capa entre tú y la transacción que importa. |
| Chat / LLM | Claude API — `claude-sonnet-5` | Calidad casi de Opus para conversación con herramientas, a $3/$15 por millón de tokens. Una reserva conversada cuesta centavos. |
| OCR de comprobantes | Claude API — `claude-opus-5` (visión) | Las capturas de Nequi/Bancolombia son ruidosas, comprimidas y de formato variable. Un OCR clásico se ahoga; Opus 5 está en el tier de visión de alta resolución (2576px) y lee con precisión. Aquí un error cuesta dinero real, así que se paga el modelo bueno. |
| Auth (solo admin) | Supabase Auth (email + contraseña) | Dos o tres personas del equipo. No hace falta Clerk ni OAuth para eso. |
| Automatización | n8n (ya existente) | El correo, la hoja de Sheets y el WhatsApp ya viven ahí. No se reimplementa nada. |
| Hosting | Vercel | Deploy desde git, preview por rama, cero servidor que cuidar. |
| Gestor de paquetes | pnpm | Rápido y con node_modules honestos. |

**Nota sobre los modelos:** el chat usa Sonnet 5 y el OCR usa Opus 5. Es deliberado — el chat es alto volumen y tolerante a error (si el bot se confunde, la persona lo corrige en el siguiente mensaje); el OCR es bajo volumen y crítico (si lee mal un valor, se confirma una reserva que no se pagó).

---

## 3. Estructura de Directorios

```
tumbao-reservas/
├── src/
│   ├── app/
│   │   ├── (public)/                    # Rutas públicas — sin auth
│   │   │   ├── page.tsx                 # Landing: qué es, clases de la semana, CTA a reservar
│   │   │   ├── reservar/
│   │   │   │   ├── page.tsx             # Selector: "conversar con el bot" o "formulario paso a paso"
│   │   │   │   ├── chat/page.tsx        # Chat conversacional (client component, streaming)
│   │   │   │   └── form/page.tsx        # Formulario guiado multi-paso
│   │   │   ├── reserva/[codigo]/page.tsx # Estado de una reserva (confirmada / pendiente)
│   │   │   └── layout.tsx               # Layout público: header mínimo + footer
│   │   ├── (admin)/
│   │   │   ├── admin/
│   │   │   │   ├── page.tsx             # Bandeja de pendientes — la pantalla que más se usa
│   │   │   │   ├── clases/page.tsx      # CRUD de clases y cupos
│   │   │   │   ├── reservas/page.tsx    # Historial con filtros
│   │   │   │   └── pagos/page.tsx       # Pagos ingresados por n8n (debug de la ingesta)
│   │   │   ├── login/page.tsx           # Login admin
│   │   │   └── layout.tsx               # Layout admin: sidebar + guard de sesión
│   │   ├── api/
│   │   │   ├── chat/route.ts            # POST — turno de conversación con Claude (streaming SSE)
│   │   │   ├── reservas/
│   │   │   │   ├── route.ts             # POST — crear reserva (usado por chat y formulario)
│   │   │   │   └── [id]/comprobante/route.ts # POST — subir comprobante → dispara verificación
│   │   │   ├── pagos/ingest/route.ts    # POST — webhook desde n8n (protegido por secreto)
│   │   │   └── admin/
│   │   │       └── reservas/[id]/decidir/route.ts # POST — aprobar o rechazar
│   │   ├── layout.tsx                   # Root layout: fuentes, tema oscuro, metadata
│   │   └── globals.css                  # Tailwind v4 + tokens con @theme
│   ├── components/
│   │   ├── ui/                          # Primitivas shadcn (button, dialog, input, badge...)
│   │   ├── reserva/
│   │   │   ├── ChatReserva.tsx          # Contenedor del chat, maneja el stream
│   │   │   ├── MensajeBurbuja.tsx       # Una burbuja de mensaje
│   │   │   ├── SelectorClase.tsx        # Grid de clases con cupo disponible
│   │   │   ├── SubidaComprobante.tsx    # Drag & drop + preview + estado de verificación
│   │   │   └── PasosFormulario.tsx      # Stepper del camino sin chat
│   │   ├── admin/
│   │   │   ├── TarjetaPendiente.tsx     # Comprobante + lectura OCR + botones aprobar/rechazar
│   │   │   ├── PlantillaWhatsApp.tsx    # Mensaje redactado listo para copiar
│   │   │   └── TablaClases.tsx
│   │   └── shared/
│   ├── lib/
│   │   ├── supabase/
│   │   │   ├── client.ts                # Cliente de navegador (anon key)
│   │   │   ├── server.ts                # Cliente de servidor (service role — NUNCA al cliente)
│   │   │   └── middleware.ts            # Helper de sesión para el guard admin
│   │   ├── claude/
│   │   │   ├── client.ts                # Instancia del SDK de Anthropic
│   │   │   ├── chat.ts                  # Loop de conversación + definición de herramientas
│   │   │   ├── ocr.ts                   # Extracción estructurada del comprobante
│   │   │   └── prompts.ts               # System prompts (constantes, sin interpolación dinámica)
│   │   ├── reservas/
│   │   │   ├── crear.ts                 # Lógica de creación + toma de cupo
│   │   │   └── verificar.ts             # Cruce OCR ↔ pagos, decide confirmada/pendiente
│   │   ├── validaciones.ts              # Esquemas Zod compartidos cliente/servidor
│   │   └── utils.ts                     # cn(), formateo de fechas y montos en COP
│   ├── types/
│   │   ├── database.ts                  # Tipos generados desde Supabase
│   │   └── index.ts                     # Tipos de dominio
│   └── middleware.ts                    # Protege /admin/*
├── supabase/
│   └── migrations/                      # SQL versionado — el esquema vive aquí
├── n8n/
│   └── README.md                        # Contrato del webhook + cómo configurar el workflow
├── public/
├── .env.example
└── README.md
```

---

## 4. Modelo de Datos

### Entidades

**clases** — Una clase concreta en el calendario (no una plantilla; cada ocurrencia es una fila).

| Campo | Tipo | Notas |
|-------|------|-------|
| id | uuid | PK, default `gen_random_uuid()` |
| nombre | text | "Salsa Caleña Nivel 1" |
| profesor | text | |
| fecha_hora | timestamptz | Inicio de la clase |
| duracion_min | int | Default 60 |
| cupo_total | int | > 0, CHECK |
| cupo_tomado | int | Default 0. **Se modifica solo dentro de la función `tomar_cupo`.** |
| precio_cop | int | En pesos enteros, sin decimales |
| lugar | text | Nullable |
| activa | boolean | Default true. Desactivar oculta la clase sin borrar reservas. |
| created_at | timestamptz | |

**reservas** — Una intención de asistir. Nace en `pendiente_pago` y avanza.

| Campo | Tipo | Notas |
|-------|------|-------|
| id | uuid | PK |
| codigo | text | UNIQUE, 6 caracteres alfanuméricos. Es lo que se le da al cliente. |
| clase_id | uuid | FK → clases.id |
| nombre | text | |
| telefono | text | Normalizado a E.164 (+57...). Identifica al cliente. |
| email | text | Nullable |
| estado | text | ENUM: `pendiente_pago`, `verificando`, `confirmada`, `pendiente_validacion`, `rechazada`, `expirada` |
| comprobante_url | text | Path en Supabase Storage, nullable |
| ocr_json | jsonb | Lo que Claude leyó del comprobante, nullable |
| pago_id | uuid | FK → pagos.id. Se llena solo cuando hubo match. Nullable. |
| motivo_rechazo | text | Nullable |
| origen | text | `chat` o `formulario` — para saber cuál camino usa la gente |
| expira_en | timestamptz | Cupo reservado hasta aquí; un job lo libera si sigue sin pagar |
| created_at | timestamptz | |
| updated_at | timestamptz | |

**pagos** — Espejo en Postgres de lo que n8n extrae del correo. Fuente de verdad para el cruce.

| Campo | Tipo | Notas |
|-------|------|-------|
| id | uuid | PK |
| banco | text | `nequi`, `bancolombia`, `daviplata`, `otro` |
| valor_cop | int | Pesos enteros |
| fecha_pago | timestamptz | La que dice el correo, no la de ingesta |
| referencia | text | Número de comprobante/transacción del banco. Nullable. |
| remitente | text | Nombre de quien envió, si el correo lo trae. Nullable. |
| ultimos_4 | text | Últimos 4 dígitos de cuenta/celular. Nullable. |
| consumido | boolean | Default false. Un pago solo puede confirmar **una** reserva. |
| raw_email | text | Cuerpo original — indispensable para depurar la extracción |
| hoja_fila | text | Referencia a la fila en la hoja diaria, para trazabilidad |
| created_at | timestamptz | |

**admin_users** — Gestionado por Supabase Auth. Solo se guarda el rol.

| Campo | Tipo | Notas |
|-------|------|-------|
| id | uuid | FK → auth.users.id |
| rol | text | `admin` o `operador` |

### Relaciones

- `clases` 1 → N `reservas`
- `pagos` 1 → 0..1 `reservas` (un pago confirma como máximo una reserva; el flag `consumido` lo garantiza)
- `auth.users` 1 → 1 `admin_users`

### Esquema SQL

```sql
-- supabase/migrations/0001_esquema_inicial.sql

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

-- El índice que hace rápido el cruce: por valor y fecha, solo sobre los no consumidos.
create index pagos_busqueda on pagos (valor_cop, fecha_pago) where not consumido;
create index pagos_referencia on pagos (referencia) where referencia is not null;

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
  updated_at      timestamptz not null default now()
);

create index reservas_pendientes on reservas (created_at desc)
  where estado = 'pendiente_validacion';
create index reservas_por_clase on reservas (clase_id);
create index reservas_por_telefono on reservas (telefono);

-- Un pago no puede confirmar dos reservas.
create unique index reservas_pago_unico on reservas (pago_id) where pago_id is not null;

create table admin_users (
  id  uuid primary key references auth.users(id) on delete cascade,
  rol text not null default 'operador' check (rol in ('admin','operador'))
);
```

```sql
-- supabase/migrations/0002_tomar_cupo.sql
-- ESTA FUNCIÓN ES EL CORAZÓN DEL SISTEMA. No reemplazar por lógica en TypeScript.
-- El bloqueo de fila es lo único que impide vender dos veces el último cupo.

create or replace function tomar_cupo(
  p_clase_id uuid,
  p_nombre   text,
  p_telefono text,
  p_email    text,
  p_origen   text
) returns reservas
language plpgsql
security definer
as $$
declare
  v_clase   clases%rowtype;
  v_reserva reservas%rowtype;
  v_codigo  text;
begin
  -- FOR UPDATE bloquea la fila: cualquier otra transacción que quiera esta
  -- misma clase espera aquí hasta que terminemos. Sin esto hay sobreventa.
  select * into v_clase from clases where id = p_clase_id for update;

  if not found then
    raise exception 'CLASE_NO_EXISTE';
  end if;
  if not v_clase.activa then
    raise exception 'CLASE_INACTIVA';
  end if;
  if v_clase.fecha_hora < now() then
    raise exception 'CLASE_YA_PASO';
  end if;
  if v_clase.cupo_tomado >= v_clase.cupo_total then
    raise exception 'SIN_CUPO';
  end if;

  -- Código legible, sin caracteres ambiguos (0/O, 1/I).
  loop
    v_codigo := upper(substring(translate(encode(gen_random_bytes(8),'base64'),
                                          '+/=0O1lI','') from 1 for 6));
    exit when length(v_codigo) = 6
      and not exists (select 1 from reservas where codigo = v_codigo);
  end loop;

  update clases set cupo_tomado = cupo_tomado + 1 where id = p_clase_id;

  insert into reservas (codigo, clase_id, nombre, telefono, email, origen)
  values (v_codigo, p_clase_id, p_nombre, p_telefono, p_email, p_origen)
  returning * into v_reserva;

  return v_reserva;
end;
$$;

-- Liberar cupos de reservas que nunca pagaron.
create or replace function liberar_cupos_expirados() returns int
language plpgsql security definer as $$
declare v_n int;
begin
  with liberadas as (
    update reservas set estado = 'expirada', updated_at = now()
    where estado = 'pendiente_pago' and expira_en < now()
    returning clase_id
  )
  update clases c set cupo_tomado = greatest(0, c.cupo_tomado - sub.n)
  from (select clase_id, count(*) n from liberadas group by clase_id) sub
  where c.id = sub.clase_id;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
```

```sql
-- supabase/migrations/0003_rls.sql
-- RLS activo en todas las tablas. El servidor usa service_role y las omite;
-- el navegador solo puede leer lo que es explícitamente público.

alter table clases   enable row level security;
alter table reservas enable row level security;
alter table pagos    enable row level security;

-- Cualquiera ve las clases activas y futuras (para el selector).
create policy clases_publicas on clases for select
  using (activa and fecha_hora > now());

-- reservas y pagos: sin políticas para el rol anon.
-- Toda lectura/escritura pasa por el servidor con service_role.
-- pagos NUNCA se expone al navegador: contiene datos bancarios.
```

---

## 5. Diseño de API

### Rutas

| Método | Ruta | Descripción | Auth |
|--------|------|-------------|------|
| POST | `/api/chat` | Un turno de conversación. Devuelve SSE con el texto en streaming. | no |
| POST | `/api/reservas` | Crea la reserva y toma el cupo. Usado por chat y formulario. | no |
| POST | `/api/reservas/[id]/comprobante` | Sube la imagen, dispara OCR y cruce. | no (valida por `codigo`) |
| GET | `/api/reservas/[codigo]` | Estado actual de una reserva. | no |
| POST | `/api/pagos/ingest` | Webhook de n8n. Inserta un pago. | header secreto |
| POST | `/api/admin/reservas/[id]/decidir` | Aprobar o rechazar una pendiente. | sesión admin |

### Endpoints críticos en detalle

#### `POST /api/reservas`

Único punto de creación. El chat lo llama vía tool-use; el formulario lo llama directo. No dupliques esta lógica en dos sitios.

```ts
// Request
{ clase_id: string, nombre: string, telefono: string, email?: string,
  origen: 'chat' | 'formulario' }

// 201
{ ok: true, data: { id, codigo, expira_en, clase: { nombre, fecha_hora, precio_cop } } }

// 409 — el caso que más va a pasar
{ ok: false, error: { code: 'SIN_CUPO', message: 'Esa clase ya se llenó.' } }
```

Validación: `telefono` se normaliza a E.164 asumiendo Colombia (+57) si viene sin indicativo; se rechaza si no queda con 10 dígitos. `nombre` mínimo 2 caracteres. `clase_id` debe existir, estar activa y ser futura — pero **no lo valides en TypeScript antes de llamar a la función SQL**: la función ya lo hace dentro de la transacción, y hacerlo antes crea una ventana de carrera.

Errores posibles desde `tomar_cupo`: `SIN_CUPO` → 409, `CLASE_NO_EXISTE` → 404, `CLASE_INACTIVA` / `CLASE_YA_PASO` → 410.

#### `POST /api/reservas/[id]/comprobante`

Recibe `multipart/form-data` con el archivo y el `codigo` como prueba de posesión.

Secuencia:
1. Valida: tipo `image/jpeg|png|webp|heic`, máximo 10 MB.
2. Sube a Storage en `comprobantes/{reserva_id}/{uuid}.{ext}`.
3. Pasa la reserva a `verificando`.
4. Genera URL firmada (5 min) y llama a `extraerComprobante()` (§ OCR).
5. Llama a `cruzarConPagos()`.
6. Devuelve el resultado final.

```ts
// 200 — confirmada
{ ok: true, data: { estado: 'confirmada', codigo: 'K7M2QX', clase: {...} } }

// 200 — pendiente (NO es error: es un desenlace válido y esperado)
{ ok: true, data: { estado: 'pendiente_validacion',
    mensaje: 'Recibimos tu comprobante. Alguien del equipo lo valida y te escribimos por WhatsApp.' } }
```

**Nunca devuelvas 4xx cuando el pago no hace match.** El sistema funcionó correctamente; simplemente no encontró el pago. Un error HTTP aquí hace que la UI muestre un fallo donde debería mostrar tranquilidad.

#### `POST /api/pagos/ingest`

Llamado por n8n cada vez que llega un correo de banco. Protegido con `X-Webhook-Secret` comparado en tiempo constante.

```ts
// Request
{ banco: 'nequi'|'bancolombia'|'daviplata'|'otro', valor_cop: number,
  fecha_pago: string /* ISO 8601 */, referencia?: string,
  remitente?: string, ultimos_4?: string, raw_email?: string, hoja_fila?: string }

// 201
{ ok: true, data: { id, reservas_reconciliadas: 1 } }
```

**Efecto secundario importante:** después de insertar el pago, este endpoint intenta reconciliar hacia atrás — busca reservas en `pendiente_validacion` que calcen con este pago recién llegado y las confirma. Esto cubre el caso real y frecuente en que la persona sube el comprobante **antes** de que el correo del banco llegue. Sin esta reconciliación inversa, esas reservas quedarían esperando a un humano innecesariamente.

Idempotencia: si llega dos veces el mismo `(banco, valor_cop, fecha_pago, referencia)`, no insertes duplicado; devuelve el existente con 200.

---

## 6. Arquitectura de Frontend

### Páginas

| Ruta | Página | Qué ve el usuario |
|-------|------|-------------|
| `/` | Landing | Qué es Tumbao, clases de la semana con cupo, botón grande "Reservar" |
| `/reservar` | Selector de camino | Dos tarjetas: "Cuéntame qué quieres" (chat) / "Ver horarios y reservar" (formulario) |
| `/reservar/chat` | Chat | Conversación con el bot; widgets embebidos para elegir clase y subir comprobante |
| `/reservar/form` | Formulario | Stepper: clase → datos → pago → comprobante → resultado |
| `/reserva/[codigo]` | Estado | Confirmada (con detalles) o pendiente (con explicación) |
| `/admin` | Bandeja | Lista de pendientes; cada una con comprobante y lectura OCR lado a lado |
| `/admin/clases` | Clases | Crear, editar, activar/desactivar; ver cupo tomado |
| `/admin/reservas` | Historial | Filtros por estado, clase, fecha |
| `/admin/pagos` | Pagos | Lo que n8n ha ingresado; sirve para depurar la extracción |

### Jerarquía de componentes

```
/reservar/chat
└── ChatReserva                      (client — dueño del estado de la conversación)
    ├── ListaMensajes
    │   └── MensajeBurbuja[]         (rol: usuario | bot)
    ├── WidgetInline                 (lo que el bot inyecta según el paso)
    │   ├── SelectorClase            → al elegir, manda el mensaje por el usuario
    │   ├── DatosPersona             → nombre + teléfono
    │   ├── InstruccionesPago        → cuenta, monto, botón copiar
    │   └── SubidaComprobante        → drag & drop + preview + estado
    └── EntradaTexto

/admin
└── BandejaPendientes                (server component — carga inicial)
    └── TarjetaPendiente[]           (client — acciones)
        ├── VisorComprobante         (imagen con zoom)
        ├── LecturaOCR               (lo que se extrajo, campo por campo)
        ├── PagosCercanos            (candidatos que casi calzaron — clave para decidir)
        ├── BotonesDecision          (aprobar / rechazar con motivo)
        └── PlantillaWhatsApp        (mensaje redactado, botón copiar)
```

### Manejo de estado

- **Server Components por defecto.** La landing, el listado de clases y las tablas admin se renderizan en servidor y consultan Supabase directo. No hay endpoint intermedio para leer.
- **Client Components solo donde hay interacción real:** el chat, la subida de comprobante y los botones del admin.
- **El chat mantiene su propio historial en estado de React** y lo manda completo en cada turno. La API de Claude no tiene memoria: el historial es responsabilidad del cliente. No persistas la conversación en la base — no aporta y complica.
- **Sin librería de estado global.** El árbol es plano y el estado es local a cada flujo. Meter Zustand o Redux aquí sería infraestructura sin usuario.
- **Revalidación:** `revalidatePath('/admin')` después de cada decisión. El listado de clases usa `revalidate = 60`.

---

## 7. Sistema de Diseño

Dirección: **oscuro y moderno**. Fondo profundo, acentos vibrantes, sensación de app y no de sitio web. Se ve bien en el celular de noche, que es cuando la gente reserva.

### Colores

| Rol | Hex | Uso |
|------|-----|-------|
| Background | `#0A0A0F` | Fondo de página. Casi negro con un sesgo azul, no negro puro. |
| Surface | `#14141C` | Tarjetas, paneles, burbujas del bot |
| Surface elevada | `#1E1E2A` | Modales, dropdowns, hover |
| Primary | `#FF4D6D` | Acción principal, CTA, acentos. Rojo coral con energía. |
| Primary hover | `#FF6B85` | |
| Secondary | `#7C5CFF` | Acentos secundarios, badges de estado neutro |
| Text | `#F2F2F7` | Texto principal — nunca blanco puro, cansa la vista |
| Muted | `#8B8B9E` | Texto secundario, etiquetas, placeholders |
| Border | `#2A2A38` | Bordes, separadores |
| Success | `#3DD68C` | Reserva confirmada, pago encontrado |
| Warning | `#FFB84D` | Pendiente de validación |
| Destructive | `#FF5A5A` | Errores, rechazar, sin cupo |

```css
/* globals.css — Tailwind v4 usa @theme, no tailwind.config.js */
@import "tailwindcss";

@theme {
  --color-background: #0A0A0F;
  --color-surface: #14141C;
  --color-surface-elevated: #1E1E2A;
  --color-primary: #FF4D6D;
  --color-primary-hover: #FF6B85;
  --color-secondary: #7C5CFF;
  --color-foreground: #F2F2F7;
  --color-muted: #8B8B9E;
  --color-border: #2A2A38;
  --color-success: #3DD68C;
  --color-warning: #FFB84D;
  --color-destructive: #FF5A5A;

  --font-display: "Clash Display", system-ui, sans-serif;
  --font-sans: "Inter Variable", system-ui, sans-serif;

  --radius-card: 16px;
  --radius-control: 10px;
}
```

### Tipografía

| Rol | Fuente | Tamaño | Peso |
|------|------|------|--------|
| Display (hero, títulos de página) | Clash Display | 40–64px, `clamp()` | 600 |
| Encabezados | Clash Display | 20–32px | 500 |
| Cuerpo | Inter Variable | 16px (nunca menos en móvil) | 400 |
| Etiquetas / meta | Inter Variable | 13px | 500, `letter-spacing: 0.02em` |
| Números (montos, códigos) | Inter Variable | — | 500, `font-variant-numeric: tabular-nums` |

Clash Display se sirve local desde `/public/fonts` con `next/font/local`. **No cargues fuentes desde CDN** — es un salto de red en el critical path.

### Espaciado y layout

- Escala base 4px: `4, 8, 12, 16, 24, 32, 48, 64, 96`.
- Radios: `10px` controles, `16px` tarjetas, `full` avatares y badges.
- Ancho máximo de contenido: `1120px`. El chat se limita a `680px` para que las líneas sean legibles.
- Breakpoints Tailwind por defecto. **Mobile-first sin excepción** — más del 90% del tráfico viene del link de WhatsApp, o sea de un celular.
- Área táctil mínima 44×44px en todo lo clicable.

### Estilo de componentes

Superficies planas con bordes sutiles de `1px` en lugar de sombras — en fondo oscuro las sombras no se ven y solo agregan peso. El acento primario se usa con moderación: un solo CTA rojo por pantalla, todo lo demás en superficies neutras.

Movimiento con propósito, no decorativo: transiciones de 150ms en hover y focus, entrada de mensajes del chat con `translateY(8px)` + fade de 200ms, y un pulso suave en el estado "verificando" que comunica que algo está pasando. Respeta `prefers-reduced-motion` y apaga todo lo no esencial.

Los estados de reserva siempre se muestran como badge con color **y texto** — nunca solo color, porque un daltónico no distingue confirmada de pendiente.

---

## 8. Autenticación y Autorización

### Flujo

**Clientes: no hay auth.** Reservan con nombre y teléfono. El `codigo` de 6 caracteres es la única credencial y sirve para consultar el estado. Es el diseño correcto: cada campo de registro que agregas es gente que abandona.

**Admin:** Supabase Auth con email y contraseña. Los usuarios se crean a mano desde el dashboard de Supabase — no hay registro público, y no debe haberlo. Login en `/admin/login` → cookie de sesión → `middleware.ts` protege todo `/admin/*`.

### Rutas protegidas

| Ruta | Acceso |
|------|--------|
| `/`, `/reservar/*`, `/reserva/[codigo]` | Público |
| `/api/chat`, `/api/reservas*` | Público (con rate limiting) |
| `/api/pagos/ingest` | Secreto compartido en header |
| `/admin/*` | Sesión válida + fila en `admin_users` |
| `/api/admin/*` | Sesión válida, verificada en el servidor |

### Roles

| Rol | Puede |
|------|--------|
| `operador` | Ver y decidir sobre reservas pendientes |
| `admin` | Todo lo anterior + crear/editar clases + ver pagos |

### Sesiones

Cookies httpOnly manejadas por `@supabase/ssr`. El middleware refresca el token en cada request. **La `service_role` key solo existe en el servidor** — si aparece en un archivo con `'use client'` o en una variable `NEXT_PUBLIC_*`, es una fuga total de la base de datos.

---

## 9. Orden de Construcción

Cada paso deja algo que se puede probar. No pases al siguiente sin verificar el anterior.

**Paso 1 — Scaffolding**
```bash
pnpm create next-app@latest tumbao-reservas --typescript --tailwind --app --src-dir --use-pnpm
cd tumbao-reservas
pnpm add @supabase/supabase-js @supabase/ssr @anthropic-ai/sdk zod
pnpm dlx shadcn@latest init
pnpm dlx shadcn@latest add button input label card dialog badge select textarea toast skeleton
```
Configura el alias `@/*`, pega los tokens de `@theme` en `globals.css`, monta el layout raíz con tema oscuro y las fuentes locales. **Verificable:** una página en blanco con el fondo `#0A0A0F` y la tipografía correcta.

**Paso 2 — Base de datos**
Crea el proyecto en Supabase. Aplica las tres migraciones de la §4 en orden. Genera tipos: `pnpm dlx supabase gen types typescript --project-id XXX > src/types/database.ts`. Inserta 5–6 clases de prueba con cupos pequeños (2–3) para poder llenar una fácil. **Verificable:** `select * from clases` devuelve datos y `select tomar_cupo(...)` crea una reserva y sube el contador.

**Paso 3 — Prueba de la carrera de cupos**
Antes de construir nada de UI, verifica que la función aguanta concurrencia. Script que dispara 20 llamadas simultáneas a `tomar_cupo` sobre una clase de cupo 3. **Debe resultar en exactamente 3 reservas y 17 errores `SIN_CUPO`.** Si sale distinto, la función está mal y todo lo demás se construye sobre arena.

**Paso 4 — Formulario de reserva end-to-end**
El camino sin chat, completo: `/reservar/form` con el stepper, `POST /api/reservas`, pantalla de instrucciones de pago, `/reserva/[codigo]`. Sin comprobante todavía. **Verificable:** reservar desde el navegador y ver la fila en la base.

**Paso 5 — Subida de comprobante (sin OCR)**
Bucket de Storage, componente de subida con preview, endpoint que guarda el archivo y deja la reserva en `pendiente_validacion`. **Verificable:** la imagen aparece en Storage y la reserva cambia de estado.

**Paso 6 — Panel admin**
Login, middleware, bandeja de pendientes con el comprobante visible, botones aprobar/rechazar, plantilla de WhatsApp. **En este punto el sistema ya es usable en producción**, solo que con verificación 100% manual. Es un buen momento para que Tumbao empiece a usarlo de verdad mientras construyes el resto.

**Paso 7 — Ingesta de pagos**
`POST /api/pagos/ingest` con validación Zod, secreto e idempotencia. En n8n: agrega un nodo HTTP Request al final del workflow que ya escribe en la hoja. **No toques la parte que escribe en Sheets** — solo agrega el POST después. Prueba con `curl` primero, luego con un correo real. **Verificable:** llega un correo de banco → aparece fila en la hoja **y** en la tabla `pagos`.

**Paso 8 — OCR**
`lib/claude/ocr.ts` con `claude-opus-5` y salida estructurada. Junta 15–20 comprobantes reales de distintos bancos y estados (buenos, borrosos, recortados, capturas de pantalla de pantalla) y mide la precisión campo por campo. Ajusta el prompt hasta que valor y fecha sean confiables. **Verificable:** ≥95% de acierto en `valor_cop` sobre el set de prueba.

**Paso 9 — Cruce y confirmación automática**
`lib/reservas/verificar.ts`, conectado al endpoint del paso 5. Reconciliación inversa en el endpoint de ingesta. **Verificable:** un flujo completo confirma solo, sin tocar el admin.

**Paso 10 — Chat con Claude**
`POST /api/chat` con `claude-sonnet-5`, streaming y herramientas. `ChatReserva` en el cliente con los widgets embebidos. El chat **reutiliza los endpoints existentes** — no reimplementa la creación de reservas.

**Paso 11 — Landing**
Hero, clases de la semana con cupo en vivo, cómo funciona en tres pasos, CTA. Metadata y Open Graph decentes: este link se comparte por WhatsApp, así que la preview importa más que el SEO.

**Paso 12 — Job de expiración**
Vercel Cron cada 15 minutos llamando a `liberar_cupos_expirados()`. Sin esto, los cupos se van filtrando y la clase aparece llena estando vacía.

**Paso 13 — Pulido**
Estados de carga, empty states, manejo de errores con mensajes en español y humanos, `error.tsx` por segmento, responsive verificado en dispositivo real (no solo en el devtools), rate limiting en las rutas públicas.

**Paso 14 — Deploy**
Proyecto en Vercel, variables de entorno, dominio, apuntar n8n al webhook de producción. Prueba el flujo completo en prod con una clase de $1.000 antes de abrirlo.

---

## 10. Entorno

### Prerrequisitos

- Node.js 20+
- pnpm 9+
- Cuenta de Supabase
- API key de Anthropic (console.anthropic.com)
- Acceso a la instancia de n8n
- Acceso al correo de Luz Alejandra (el que recibe las notificaciones bancarias)

### Variables de entorno

| Variable | Descripción | Dónde se obtiene |
|----------|-------------|--------------|
| `NEXT_PUBLIC_SUPABASE_URL` | URL del proyecto | Supabase → Settings → API |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Clave pública | Ídem |
| `SUPABASE_SERVICE_ROLE_KEY` | Clave de servidor. **Nunca `NEXT_PUBLIC_`.** | Ídem |
| `ANTHROPIC_API_KEY` | API key de Claude | console.anthropic.com |
| `N8N_WEBHOOK_SECRET` | Secreto compartido con n8n | Genera con `openssl rand -hex 32` |
| `CRON_SECRET` | Protege el endpoint de cron | Ídem |
| `NEXT_PUBLIC_APP_URL` | URL base, para construir links | — |

### Comandos iniciales

```bash
pnpm install
cp .env.example .env.local     # y llena los valores
pnpm dlx supabase link --project-ref XXXX
pnpm dlx supabase db push
pnpm dlx supabase gen types typescript --linked > src/types/database.ts
pnpm dev
```

---

## 11. Dependencias

### Core

| Paquete | Para qué |
|---------|---------|
| `next` (15.x) | Framework |
| `react`, `react-dom` (19.x) | |
| `@supabase/supabase-js` | Cliente de base de datos y storage |
| `@supabase/ssr` | Manejo de sesión con cookies en App Router |
| `@anthropic-ai/sdk` | Chat y OCR |
| `zod` | Validación compartida entre cliente y servidor |
| `tailwindcss` (4.x) | Estilos |
| `class-variance-authority`, `clsx`, `tailwind-merge` | Variantes de componentes (viene con shadcn) |
| `lucide-react` | Iconos |
| `date-fns` + locale `es` | Fechas en español ("jueves 7 de agosto, 7:00 p. m.") |

### Dev

| Paquete | Para qué |
|---------|---------|
| `typescript` | |
| `@types/node`, `@types/react` | |
| `eslint`, `eslint-config-next` | |
| `vitest` | Tests unitarios de la lógica de cruce |
| `@playwright/test` | E2E del flujo de reserva |
| `supabase` (CLI) | Migraciones y generación de tipos |

**No agregues:** ORM (Prisma/Drizzle), librería de estado global, librería de formularios pesada, framework de animación. Ninguno resuelve un problema que este proyecto tenga.

---

## 12. Estrategia de Despliegue

### Hosting

Vercel, región `iad1` (más cercana a Supabase si el proyecto está en US East — verifica y alinea, la latencia entre app y base es lo que más se siente).

- Rutas de API como Node.js runtime (el SDK de Anthropic no corre en Edge).
- `maxDuration: 60` en `/api/reservas/[id]/comprobante` — el OCR puede tardar.
- Cron en `vercel.json`:

```json
{ "crons": [{ "path": "/api/cron/expirar", "schedule": "*/15 * * * *" }] }
```

### CI/CD

Push a `main` → producción. Cualquier otra rama → preview automático. Los previews apuntan al **mismo** Supabase; para no ensuciar datos reales, marca las clases de prueba con un prefijo y fíltralas en producción. Antes de hacer merge: `pnpm build && pnpm lint && pnpm test`.

### Dominio

Subdominio del dominio de Tumbao, por ejemplo `reservas.tumbao.co`. Es el link que se pega en WhatsApp, así que debe ser corto y creíble — una URL de `vercel.app` genera desconfianza justo cuando le vas a pedir a alguien que suba un comprobante de pago.

### Entornos

| Entorno | Base | Claude | n8n |
|---------|------|--------|-----|
| Local | Supabase dev | API key real (paga poco) | Webhook manual con curl |
| Preview | Supabase producción | Misma key | No conectado |
| Producción | Supabase producción | Misma key | Workflow activo |

Un solo proyecto de Supabase es suficiente al principio. Cuando haya volumen real, separa.

---

## 13. Estrategia de Pruebas

### Unitarias (Vitest)

Concéntrate en la lógica que decide si se cobra bien:

- `lib/reservas/verificar.ts` — la matriz completa de casos de cruce: valor exacto + fecha dentro de ventana, valor exacto pero fecha vieja, referencia coincide pero valor no, múltiples pagos candidatos, ningún candidato, pago ya consumido.
- `lib/validaciones.ts` — normalización de teléfono: `3001234567`, `+573001234567`, `300 123 4567`, `57 300 1234567` deben producir todos el mismo resultado.
- Parseo de montos con formato colombiano: `$120.000`, `120.000,00`, `$ 120,000` → `120000`.

### Integración

- `POST /api/pagos/ingest` — idempotencia (mismo pago dos veces = una fila) y reconciliación inversa (confirma una pendiente que ya estaba esperando).
- `tomar_cupo` bajo concurrencia — el test del paso 3, automatizado y corriendo en CI.
- Rechazo del webhook sin el secreto correcto.

### E2E (Playwright)

Tres flujos, en móvil (`viewport` de iPhone):

1. **Camino feliz:** reservar por formulario → subir comprobante que calza → ver confirmada.
2. **Sin match:** reservar → subir comprobante que no calza → ver pendiente → aprobar desde admin → ver confirmada.
3. **Sin cupo:** llenar una clase → intentar reservar → ver el mensaje correcto y que no se creó nada.

Las llamadas a Claude se mockean en E2E — no quemes tokens ni introduzcas no-determinismo en CI. La precisión real del OCR se mide aparte, con el set de comprobantes del paso 8.

---

## 14. Skills a Usar Durante la Construcción

| Skill | Cuándo | Para qué |
|-------|-------------|-----|
| `superpowers` | Pasos 8–10 | El OCR, el cruce y el chat tienen varias formas de fallar; conviene el modo riguroso. |
| `verificador-datos` | Paso 8 | Validar la precisión de la extracción contra comprobantes reales. |
| `all-deploy` | Paso 14 | Auditoría previa, preview, health-check y producción. |
| `claude-api` | Pasos 8 y 10 | Referencia de model IDs, salida estructurada, streaming y tool use. Consúltala antes de escribir código de Claude, no después. |
| `code-review` | Antes de cada merge | |

---

## 15. CLAUDE.md para el Proyecto Destino

```markdown
# Tumbao Reservas

Web de reservas de clases de baile con verificación semiautomática de pagos por transferencia.
Blueprint completo: `blueprints/tumbao-reservas-blueprint.md` en el repo ProjectosClaude.

## Qué es esto

Los clientes llegan por un link de WhatsApp, reservan sin crear cuenta (por chat o por
formulario), y suben el comprobante de la transferencia. El sistema lee el comprobante con
Claude, lo cruza contra los pagos que n8n extrae del correo del banco, y confirma solo.
Si no encuentra el pago, deja la reserva pendiente para que un humano la valide.

## Stack

Next.js 15 (App Router) · TypeScript strict · Tailwind v4 · shadcn/ui · Supabase (Postgres +
Storage + Auth) · Claude API · n8n · Vercel.

## Modelos de Claude

- Chat conversacional: `claude-sonnet-5`, adaptive thinking, `effort: "low"`, streaming.
- OCR de comprobantes: `claude-opus-5` con visión y salida estructurada (`output_config.format`).

No cambies estos IDs sin decirlo. No uses IDs con sufijo de fecha.

## Reglas del proyecto

1. **La toma de cupo vive en SQL.** La función `tomar_cupo()` usa `SELECT ... FOR UPDATE`.
   Nunca leas el cupo en TypeScript y luego escribas — eso reintroduce la sobreventa.
2. **Un solo punto de creación de reservas.** El chat y el formulario llaman al mismo
   `POST /api/reservas`. Si te encuentras duplicando esa lógica, algo se torció.
3. **`SUPABASE_SERVICE_ROLE_KEY` solo en servidor.** Jamás en un archivo `'use client'`,
   jamás en una variable `NEXT_PUBLIC_*`.
4. **Sin match de pago NO es un error HTTP.** Devuelve 200 con `estado: 'pendiente_validacion'`.
5. **Toda respuesta de API tiene la misma forma:** `{ ok: true, data }` o
   `{ ok: false, error: { code, message } }`. El `message` va en español y se le puede mostrar
   al usuario tal cual.
6. **Mobile-first, siempre.** El tráfico llega desde WhatsApp, o sea desde un celular.
7. **Nunca `any`.** Los tipos de la base se generan desde Supabase, no se escriben a mano.
8. **No toques el workflow de n8n que escribe en Sheets.** Solo agrega el POST al final.
9. Antes de escribir código que llame a la API de Claude, consulta la skill `claude-api`.
   Los parámetros cambiaron: `budget_tokens` ya no existe, `temperature` da 400 en estos modelos.

## Autonomía (hereda del framework de ProjectosClaude)

- **Verde — hazlo:** componentes, estilos, tipos, refactor de UI, documentación interna.
- **Amarillo — hazlo y avisa en el mismo mensaje:** nuevos endpoints de lectura, ajustes de copy,
  cambios en queries.
- **Rojo — pregunta primero:** migraciones de esquema, cualquier `DELETE`/`DROP`, tocar el
  workflow de n8n, enviar mensajes a clientes reales, deploy a producción.

## Comandos

pnpm dev · pnpm build · pnpm lint · pnpm test · pnpm test:e2e
pnpm dlx supabase db push · pnpm dlx supabase gen types typescript --linked > src/types/database.ts

## Antes de dar algo por terminado

1. `pnpm build` pasa sin errores ni warnings de tipos.
2. Probaste el flujo en un viewport de móvil real, no solo en el devtools.
3. Si tocaste el cruce de pagos, corriste los tests de `lib/reservas/verificar.ts`.
4. Reporte breve: qué cambiaste, qué quedó pendiente, qué necesita tu autorización.
```

---

## 16. Reglas No Negociables

1. **La toma de cupo ocurre dentro de una transacción de Postgres con bloqueo de fila.** Leer el cupo en TypeScript y después escribir es sobreventa garantizada bajo concurrencia. La función `tomar_cupo()` es la única vía.

2. **Un pago confirma como máximo una reserva.** El flag `consumido` más el índice único parcial sobre `reservas.pago_id` lo garantizan a nivel de base de datos, no de aplicación.

3. **`SUPABASE_SERVICE_ROLE_KEY` nunca sale del servidor.** RLS activo en todas las tablas. La tabla `pagos` no se expone al navegador bajo ninguna circunstancia — contiene información bancaria de terceros.

4. **TypeScript strict, cero `any`.** Los tipos de base se generan, no se escriben.

5. **Toda respuesta de API usa la misma forma:** `{ ok: true, data }` o `{ ok: false, error: { code, message } }`, con `message` en español y apto para mostrarse al usuario.

6. **La decisión de confirmar un pago se registra siempre.** Sea automática o humana, queda `ocr_json` y `pago_id` (o `motivo_rechazo`). Cuando alguien reclame que sí pagó, tiene que existir el rastro.

7. **Mobile-first.** Ninguna funcionalidad se considera terminada si no funciona bien en un celular.

8. **No se envían mensajes a clientes reales de forma automática en la v1.** El sistema redacta; un humano manda. Automatizar el envío es una decisión aparte, con su propia autorización.

9. **Los comprobantes se guardan con URL firmada y expiración.** Nunca en un bucket público — son documentos financieros de personas reales.

10. **El OCR nunca decide solo cuando duda.** Si la confianza de la extracción es baja o hay más de un pago candidato, va a `pendiente_validacion`. Ante la duda, gana el humano.
