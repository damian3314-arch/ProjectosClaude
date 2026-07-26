# Cómo poner esto en línea

Cuatro pasos, en este orden. El orden importa: si se publica el workflow
antes de aplicar el SQL, la página va a pedirle a Supabase una función que
todavía no existe y toda reserva va a fallar.

---

## 1. Aplicar el SQL a Supabase

Supabase → **SQL Editor** → New query → pegar todo el contenido de:

```
supabase/aplicar/0007-0010_todo_junto.sql
```

→ **Run**.

Se puede correr dos veces sin romper nada (está probado). Qué agrega:

| | |
|---|---|
| 0007 | compara nombres, para saber quién pagó cuando hay dos pagos iguales |
| 0008 | usa esa comparación al conciliar |
| 0009 | calcula los cupos sueltos = aforo − gente con plan activo a esa hora |
| 0010 | separa reserva de miembro y de clase suelta, e importa afiliados |

Para comprobar que quedó, en el mismo SQL Editor:

```sql
select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and proname in
   ('importar_membresias','recalcular_cupos','generar_horario','similitud_nombre');
```

Tienen que salir las cuatro.

---

## 2. Cargar el horario

Sin esto la página no muestra nada, porque la tabla `clases` está vacía.
En el SQL Editor, para las próximas dos semanas:

```sql
select generar_horario(current_date, current_date + 13);
```

Genera lunes a viernes 7:00 am, 6:00 pm y 7:00 pm, y sábado 8:00 am y
9:00 am. Domingo no. Aforo 30 y precio $15.000; si alguno cambia se pasa
como parámetro.

Después hay que correr la importación de afiliados una vez (workflow
**Tumbao · Importar afiliados y recalcular cupos**, botón Execute), para
que los cupos dejen de ser 30 y pasen a ser los reales.

---

## 3. Publicar el workflow de la API

El workflow **Tumbao · API de reservas** (`miCjQNjUlTgwuok7`) tiene cambios
sin publicar: la versión activa todavía no sabe distinguir miembro de clase
suelta. Hay que darle **Publish** en n8n.

Esto va después del paso 1, no antes.

---

## 4. Publicar la página

`web/index.html` es un archivo suelto, sin build ni dependencias. Sirve
cualquier hosting estático (Cloudflare Pages, Netlify, GitHub Pages). Hay
que subir `web/index.html` y la carpeta `web/img/`.

La URL de n8n ya está puesta en el bloque `CONFIG` del archivo. Si el
dominio de n8n cambia, se cambia ahí y en ningún otro lado.

---

## Antes de cobrarle a alguien de verdad

- [ ] El workflow de ingesta (**Tumbao · Ingesta de pagos**) hoy lee el
      correo personal de Damián, que fue lo que se usó para probar. Hay
      que cambiarle la credencial de Gmail a la cuenta de Tumbao y borrar
      los pagos de prueba de la tabla `pagos`.
- [ ] Los nodos que mandan WhatsApp están **desactivados** a propósito.
      Activarlos es mandarle mensajes a clientes reales, así que eso se
      decide aparte.
- [ ] Falta definir qué da **MEDIA MENSUALIDAD**: ¿acceso a todas las
      clases de su hora, o a la mitad? Hoy se cuentan como plan completo,
      y son 15 de 61 personas. Si en realidad vienen día por medio,
      estamos ofreciendo menos cupos sueltos de los que se podrían vender.

---

## Probar sin tocar nada real

```bash
node pruebas/espejo-api.mjs          # imita los 4 webhooks
node pruebas/prueba-pagina.mjs       # recorre la página en Chromium
```

El camino de validación humana (cuando el correo del banco no llega):

```bash
NUNCA_LLEGA=1 MINUTOS_ESPERA=0.15 node pruebas/espejo-api.mjs
node pruebas/prueba-validacion-humana.mjs
```

Y las funciones de Postgres, contra una base local:

```bash
psql -d tumbao -f pruebas/humo-supabase.sql
```
