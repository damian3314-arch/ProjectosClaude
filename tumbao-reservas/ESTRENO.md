# Salir a producción — lista de verificación

Escrito el 8 de agosto de 2026, antes del estreno con clientes reales en
`tumbaobaila.com`.

---

## 🔴 Lo que hay que hacer ANTES de abrirle a la gente

### 1. ~~Subir el reporte de afiliados~~ ✅ resuelto el 8 de agosto

`Afiliados activos 2026-08-08.xlsx` importado: **63 afiliados, 0
descartados, 15 clases recalculadas, 0 clases apretadas**.

El reparto que quedó vivo:

| Clase | Con plan |
|---|---|
| 7:00 am | 21 |
| 6:00 pm | 24 |
| 7:00 pm | 18 |

Y comprobado contra la página pública: el lunes 10 salen 12 libres a las
7 am, 6 a las 6 pm y 14 a las 7 pm. Los números cambian de un día a otro
porque las membresías vencen en fechas distintas y se descuentan solas.

**Lo que había pasado:** los reportes se guardan en una carpeta por mes
y el workflow apuntaba a la de julio. Ya no depende de la carpeta —
busca el archivo por nombre en todo el Drive, así que el 1 de septiembre
no se vuelve a romper.

**Sigue siendo el único paso manual del que dependen los cupos.** Cada
día hay que exportar de AdminGym y guardar en Drive con la fecha en el
nombre:

    Afiliados activos AAAA-MM-DD.xlsx

Vale que diga "afiliados" o "miembros", en cualquier carpeta, pero la
fecha va en ese orden: los cierres de caja usan `DD-MM-AAAA` y el
sistema los distingue por ahí. Si el archivo no trae fecha en el nombre,
se ignora y el error lo dice — ya pasó con `Afiliados activos.xls` y
`Afiliados 2.xls`, que siguen ahí sin usarse.

No se usa la fecha de subida de Drive a propósito: lo que importa es de
qué día son los datos, no cuándo se guardó. Un reporte de julio subido
hoy sigue teniendo datos de julio. Si pasan más de 7 días sin subir
nada, el import se frena en vez de vender cupos que no existen.

### 2. ~~Pegar el SQL~~ ✅ aplicado

Verificado contra la base el 11 de agosto: el corte de producción está en
`2026-08-08`, la cola de "Por validar" está en cero, `admin_pendientes`
filtra por el corte y `caja_del_dia` trae el control del banco **y** el
arreglo del doble conteo.

> El archivo `PEGAR_LISTO_PRODUCCION.sql` **se borró**. Reemplazaba
> `caja_del_dia` entera, y después de aplicarlo otra sesión arregló un
> doble conteo de plata dentro de esa misma función. Volver a pegarlo lo
> habría deshecho en silencio. Ver `aplicar/LEEME-ANTES-DE-PEGAR.md`.

### 2b. ~~El panel gastaba n8n por clic~~ ✅ resuelto el 11 de agosto

Medido: **483 ejecuciones del workflow del panel en 24 horas**, contra un
plan de 2.500 al mes. Cinco días de vida. Y al agotarse no caía solo el
panel: la página pública reserva por n8n también, así que un cajero
repasando el tablero podía dejar sin reservar a los clientes.

Las nueve rutas del panel se movieron al Worker `tumbao-caja`, que ya
tenía el secreto y el CORS configurados — por eso no hubo nada que
configurar. Ahí caben 100.000 peticiones diarias y no cuestan nada.

El workflow `Tumbao · Panel de admin` se deja **activo a propósito**: un
webhook en reposo no gasta nada, y si a alguien le quedó la página vieja
abierta en el celular, sus clics siguen funcionando en vez de dar 404.
Se puede apagar cuando lleve un día sin recibir llamadas.

### 3. Revocar los tokens de prueba

Se compartieron dos por chat para depurar:

- `aenqLp4JAoaBPIMcCzysoC0CA2opFHP9_UNEDVBHS1U`
- `_YYeMg1F0AzlsDYo10_WieZoblpfRSu2Ti_isOhAses`

```sql
update admin_tokens set activo = false
 where nombre in ('...');   -- mira primero: select id, nombre, activo from admin_tokens;
```

Y crear el de la recepcionista con su nombre, para que en el cierre se
sepa quién registró cada movimiento.

---

## 🟡 Conviene, pero no bloquea

- **El token de Cloudflare** `cfat_VLRH…` sigue vivo con permisos de
  Pages y Workers. Si no se va a usar más, revocarlo.
- **Las dos credenciales de Gmail en n8n** se llaman parecido y una es de
  Joyería. Renombrarlas evita que alguien las cruce.
- **Datos de prueba en `pagos` y `caja_movimientos`** (los dos de $1.000,
  las notas "PRUEBA CLAUDE"). Con el corte ya no se ven, así que borrarlos
  es opcional. Si se quiere, está en `aplicar/LIMPIAR_PRUEBAS.sql` — pero
  léelo antes: borra de verdad.

---

## Cómo se comprueba que sigue en pie

Las pruebas no son decorativas: cada una existe porque algo se rompió.

```bash
cd tumbao-reservas/pruebas

# Base de datos: 12 pruebas de humo sobre Postgres
psql -d <base> -f humo-corte.sql        # el corte no esconde cupos vivos
psql -d <base> -f humo-banco.sql        # conciliación depósito por depósito
psql -d <base> -f humo-aforo.sql        # no se vende dos veces el mismo puesto

# Panel: navegador de verdad, haciendo clic
node espejo-api.mjs &       # el panel necesita el espejo en otra terminal
node prueba-admin.mjs       # tablero, puerta, horario, cola, "Es este"
node prueba-caja.mjs        # 53 comprobaciones
node prueba-apuntar.mjs     # 14

# Sin navegador
node ../../tumbao-opina/pruebas/limpiar-transcripcion.test.mjs
node elegir-reporte.test.mjs      # qué archivo de afiliados se importa
node sin-delete-sin-where.mjs     # ningún DELETE/UPDATE sin WHERE
```

---

## Lo que hay que mirar la primera semana

| Qué | Dónde | Qué significa si se tuerce |
|---|---|---|
| El reporte de afiliados importa | correo de fallos de n8n | Si falla, los cupos mienten |
| Consumo de n8n | panel de n8n | El plan son 2.500/mes. Con el panel fuera debería bajar a ~600-900 |
| "Sin identificar, de hoy" | pestaña Caja | Si no baja a cero, alguien pagó y no se registró |
| "Apuntado sin respaldo" | pestaña Caja | Transferencias que el banco no confirmó |
| Cola de "Por validar" | pestaña Por validar | Tiene que vaciarse cada día |

---

## Límites conocidos

- **Solo lee Bancolombia.** Un pago por Nequi o a otra cuenta no genera
  correo, así que aparece como "sin respaldo". No es un error del
  sistema: es que esa plata entró por un canal que nadie está leyendo.
- **El parser reconoce cuatro formatos** de aviso de Bancolombia. Si el
  banco cambia el texto, el pago cae en "estructura_no_reconocida" y no
  entra. Conviene cuadrar contra el extracto los primeros días.
- **El cierre de AdminGym se sube a mano.** Nadie avisa si un día no se
  sube. Los cierres de julio dejaron de subirse el día 30; si ahora van a
  la carpeta del mes, bien, pero de eso no avisa nadie todavía.

---

## Lo que queda por hacer (nada bloquea el estreno)

En orden de lo que más se nota en el mostrador:

1. **Varios cupos con un solo pago.** Alguien llega y reserva para tres;
   hoy la recepcionista lo hace a mano por WhatsApp. Necesita endpoint,
   RPC y pantalla. Toca plata, así que conviene hacerlo completo.
2. **Botón "Reprogramar"** junto a "Entró": quien pagó y no pudo venir,
   que se le mueva el cupo sin volver a cobrar.
3. **Miembro con plan en otro horario.** Hoy `tomar_cupo` lo bloquea a
   propósito (`OTRO_HORARIO`, `PLAN_YA_CUBRE`). Antes de tocarlo hay que
   decidir la regla: ¿cuántas veces al mes? ¿solo si hay cupo libre?
4. **`por_soltar` en el Tablero.** El dato ya viaja en la respuesta desde
   que se arreglaron los cupos fantasma; falta pintarlo cuando sea > 0.
5. **Default branch a `main`** en Settings del repo. Hoy es
   `claude/aprende-esto-khjryq`, que solo tiene el CLAUDE.md, y ya tumbó
   una vez el despliegue de Cloudflare Pages.
6. **Tablas `cheo_*` en Supabase**, vacías y sin uso. Decidir si se
   borran.
