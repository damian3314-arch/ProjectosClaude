# Migraciones — versión blueprint

Estas migraciones implementan el esquema del **blueprint de The Architect**
(`clases` / `reservas` / `pagos` con contador `cupo_tomado`), no el de la
carpeta `db/` de la raíz.

> **Hay dos esquemas en este repo a propósito, mientras se decide la
> arquitectura.** `db/` es el de la primera versión (página estática +
> n8n, modelo de datos de Beat). `supabase/migrations/` es el del
> blueprint (app Next.js). No se aplican los dos a la misma base.

## Auditoría del SQL del blueprint

Corrí el SQL del blueprint tal cual sobre Postgres 16 antes de reescribirlo.

### Lo que estaba bien

`tomar_cupo()` **pasa la prueba de concurrencia que el propio blueprint
exige en su Paso 3**: 20 llamadas simultáneas sobre una clase de cupo 3
producen exactamente 3 reservas y 17 `SIN_CUPO`. El `SELECT ... FOR UPDATE`
hace su trabajo. El diseño de fondo es correcto.

### Los cuatro fallos que encontré

**1 · El generador de códigos producía justo los caracteres que decía evitar**

El original:

```sql
upper(substring(translate(encode(gen_random_bytes(8),'base64'),'+/=0O1lI','') from 1 for 6))
```

El comentario dice "sin caracteres ambiguos (0/O, 1/I)". Pero `translate`
borra la `O` y la `I` **mayúsculas**, deja pasar la `o` y la `i`
minúsculas, y el `upper()` posterior las convierte de vuelta.

Medido sobre 5.000 muestras: **19,1% de los códigos contenían `O` o `I`**.
En un código que se dicta por teléfono, eso es una llamada de soporte cada
cinco reservas.

Ahora se construye desde un alfabeto explícito (`ABCDEFGHJKMNPQRSTUVWXYZ23456789`).
Lo que no está en el alfabeto no puede salir. Verificado: 0 ambiguos en
5.000, todos de longitud 6.

**2 · `SECURITY DEFINER` sin `search_path` fijo**

Las dos funciones corrían con los privilegios de su dueño pero con el
`search_path` de quien las llama — vector de escalada de privilegios que
el propio advisor de Supabase marca. Añadido `set search_path = public, pg_temp`.

**3 · El código se elegía y se insertaba en dos pasos**

El original comprobaba `not exists (select 1 from reservas where codigo = ...)`
y después insertaba. Entre la comprobación y el insert cabe otra
transacción; si ambas escogen el mismo código, la segunda revienta con
`unique_violation` y aborta la reserva completa. Ahora el insert va dentro
del loop y un choque solo cuesta otra vuelta.

**4 · `liberar_cupos_expirados()` devolvía el número equivocado**

Terminaba con `get diagnostics v_n = row_count`, que cuenta las filas de la
**última** sentencia — el `update` sobre `clases`, no las reservas
expiradas. Con 7 reservas vencidas de una sola clase devolvía `1`.

Los cupos sí se liberaban bien; lo que mentía era el valor de retorno, o
sea el log del cron. Verificado tras el fix: devuelve 7, deja
`cupo_tomado` en 0, y una segunda llamada devuelve 0.

## Dos adiciones al esquema

**`reservas.habeas_data_at`** — Ley 1581 de 2012. Recoger nombre y celular
de una persona en Colombia exige autorización explícita y registrar cuándo
se dio. El blueprint no lo contempla y es obligatorio.

**Índice único `pagos_unicos`** — el blueprint pide que la ingesta de pagos
sea idempotente pero lo deja en manos de la aplicación. Si dos correos
llegan a la vez, la comprobación en TypeScript no alcanza. Cerrado en
Postgres sobre `(banco, valor_cop, fecha_pago, referencia)`.

## Probar en local

```bash
createdb tumbao_bp
psql -d tumbao_bp -c "create schema auth; create table auth.users(id uuid primary key);
                      create role service_role; create role anon;"
psql -d tumbao_bp -f 0001_esquema_inicial.sql \
                  -f 0002_tomar_cupo.sql \
                  -f 0003_rls.sql
```

`auth.users`, `service_role` y `anon` los crea Supabase; fuera de Supabase
hay que simularlos para que las migraciones apliquen.
