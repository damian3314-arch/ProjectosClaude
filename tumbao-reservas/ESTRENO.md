# Salir a producción — lista de verificación

Escrito el 8 de agosto de 2026, antes del estreno con clientes reales en
`tumbaobaila.com`.

---

## 🔴 Lo que hay que hacer ANTES de abrirle a la gente

### 1. Subir el reporte de afiliados a Drive

**Este es el bloqueo de verdad.** El reporte más nuevo en la carpeta de
Drive es `Afiliados activos 2026-07-30.xlsx`, de hace 9 días.

El workflow que reparte los cupos entre afiliados y clases sueltas se
niega a importar nada con más de 7 días de atraso, y hace bien: con la
lista vieja, quien se afilió después del 30 de julio no existe para el
sistema, así que la página ofrece clases sueltas en puestos que ya tienen
dueño. **Sobrevende.**

Lleva fallando dos veces al día (9:30 pm y 8:00 am) desde principios de
agosto. Los correos van a `bailatumbao@gmail.com` — si no los has visto,
mira en spam.

**Comprobado el 8 de agosto:** la carpeta que vigila n8n tiene 27
archivos y **ninguno posterior al 30 de julio** — ni el reporte de
afiliados ni los cierres de caja diarios. Lo que se suba a otra carpeta
es invisible para el sistema.

Qué hacer:

1. Exportar de AdminGym el listado de afiliados activos.
2. Guardarlo **en esta carpeta**, no en otra:
   `https://drive.google.com/drive/folders/1aqP6ZmNCUEBpLe9Nkfbf8aKEZdmMnJYp`
3. Con la fecha en el nombre en formato `AAAA-MM-DD`, por ejemplo
   `Afiliados activos 2026-08-08.xlsx`. Vale que diga "afiliados" o
   "miembros", pero la fecha va en ese orden: los cierres de caja usan
   `DD-MM-AAAA` y el sistema los distingue por ahí.
4. Confirmar que la corrida de las 9:30 pm pasa a verde.

No se usa la fecha de subida de Drive a propósito: lo que importa es de
qué día son los datos, no cuándo se guardó el archivo. Un reporte de
julio subido hoy sigue teniendo datos de julio.

Y luego, **todos los días**. Es el único paso manual del que depende que
los cupos sean ciertos.

### 2. Pegar `aplicar/PEGAR_LISTO_PRODUCCION.sql` en Supabase

Trae el control del banco y el corte de producción. No borra nada y se
puede correr dos veces.

Después de pegarlo, la cola de "Por validar" arranca vacía y el banco
deja de arrastrar los 73 depósitos viejos.

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
# Base de datos: 12 pruebas de humo sobre Postgres
cd tumbao-reservas/pruebas
psql -d <base> -f humo-corte.sql        # el corte no esconde cupos vivos
psql -d <base> -f humo-banco.sql        # conciliación depósito por depósito
psql -d <base> -f humo-aforo.sql        # no se vende dos veces el mismo puesto

# Panel: navegador de verdad, haciendo clic
node prueba-caja.mjs        # 41 comprobaciones
node prueba-apuntar.mjs     # 14
node prueba-admin.mjs       # necesita `node espejo-api.mjs` en otra terminal

# Guardián: ningún DELETE/UPDATE sin WHERE en las migraciones
node sin-delete-sin-where.mjs
```

---

## Lo que hay que mirar la primera semana

| Qué | Dónde | Qué significa si se tuerce |
|---|---|---|
| El reporte de afiliados importa | correo de fallos de n8n | Si falla, los cupos mienten |
| Consumo de n8n | panel de n8n | El plan son 2.500/mes; medido ~2.500-3.000 |
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
  sube.
