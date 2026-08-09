# Reservas de Tumbao — arreglos

Esta carpeta no es el sistema de reservas: es donde quedan los arreglos que
se le van haciendo, con el porqué. El sistema vive en Supabase
(`tumbao-reservas`) y en los workflows de n8n.

---

## Cupos fantasma en el Tablero — 9 de agosto de 2026

**Síntoma.** El panel mostraba `1 RESERVAS` para la clase de 6:00 pm del
lunes 10, pero esa persona no aparecía en ninguna parte: ni en *Por validar*,
ni en confirmadas, ni en *Ver quién entra*. Un número sin persona.

**Qué había pasado.** La reserva `YH978Z` (luisa, 300 612 1806) apartó un cupo
el viernes 8 a las 6:47 pm y nunca pagó. La reserva quedó en `pendiente_pago`
con `expira_en` a los 30 minutos, y ahí se quedó.

**Dos causas, no una:**

1. **El cupo nunca se soltó.** El workflow `Tumbao · Liberar cupos vencidos`
   existía, estaba bien hecho, y estaba **apagado** — nunca se publicó. Su
   propia nota ya advertía el problema: *"la función `liberar_cupos_expirados()`
   está en la base desde el primer día, y su comentario dice 'la llama el cron'.
   Ese cron nunca se creó."* Se activó.

2. **El panel contaba distinto a como listaba.** `admin_tablero` sacaba
   `reservadas` de `c.cupo_tomado`, el contador de la clase, que sí incluye
   los `pendiente_pago` vencidos. Pero `admin_lista_clase` los excluye a
   propósito. El número las contaba y la lista no las mostraba.

**El arreglo (`sql/01_tablero_sin_fantasmas.sql`).** `reservadas` ahora usa
el mismo filtro, palabra por palabra, que `admin_lista_clase`. Los cupos
atascados salen aparte en un campo nuevo, `por_soltar`.

```
reservadas + por_soltar + libres = a_la_venta
```

`libres` no cambió: sigue saliendo de `cupo_tomado`, que es lo que de verdad
limita la venta. Es preferible mostrar un cupo de menos que vender uno que no
existe.

**Por qué los dos arreglos y no solo el cron.** El cron resuelve el cupo
atascado, pero si algún día se vuelve a apagar el panel volvería a mentir en
silencio. Con este cambio, aunque se apague, el número siempre corresponde a
alguien que se puede abrir, y `por_soltar` deja ver que hay cupos por
recuperar.

**Cómo se verificó.** Se insertó una reserva fantasma real en una clase futura
y se compararon `admin_tablero` y `admin_lista_clase`:

| | Tablero dice | La lista muestra | Por soltar |
|---|---|---|---|
| sin fantasma | 0 | 0 | 0 |
| con fantasma | 0 | 0 | **1** |

Antes del arreglo, la fila de abajo habría sido `1` contra `0` — el bug exacto.
La reserva de prueba y el token temporal se borraron después.

---

## Pendiente

El frontend del panel todavía no pinta `por_soltar`. El dato ya viaja en la
respuesta de `admin_tablero`; falta mostrarlo cuando sea mayor que cero, algo
como *"1 cupo por soltar"* junto a los libres. Ese código no está en este repo.
