# Tablero gerencial · Taller Joyería Santiago

Página estática (HTML + JS sin dependencias) que lee la información de la hoja de ventas y muestra: cómo vamos (día, semana, mes, trimestre, semestre, año) contra el periodo anterior y el año pasado, meta del mes, recaudo por cuenta, plan de lo que falta del año por fechas pico, hallazgos automáticos y precio del oro.

**Estado: v1 con datos de demostración.** Las cifras que se ven al abrirla son sintéticas (hay un aviso naranja que lo dice). Falta conectar la hoja real (ver abajo).

## Ver el tablero

```bash
cd dashboard-joyeria
npm run serve      # http://localhost:5173
npm test           # 15 pruebas de los cálculos
```

## Conectar los datos reales

El tablero espera un JSON con la forma de las dos pestañas de la hoja `Ingresos por ventas 2025`:

```json
{
  "meta": { "demo": false },
  "resumen":     [{ "fecha": "2026-10-22", "ventas_contado": 0, "creditos_total_ventas": 0, "creditos_abonos": 0, "saldo_cxc_mes": 0 }],
  "movimientos": [{ "fecha": "2026-10-22", "cliente": "…", "valor": 0, "cuenta": "…", "tipo": "VENTA" }]
}
```

**Opción A, ya disponible (manual):** descargar cada pestaña como CSV y convertir.

```bash
node scripts/sheet-to-json.mjs Resumen_Diario.csv movimientos_detallados.csv > data/real.json
```

Luego en `js/config.js`: `fuentesDatos: ['data/real.json']`. Para comparar contra 2024 se agrega otro JSON a esa lista.

**Opción B (recomendada, pendiente de autorización):** un workflow de n8n con webhook protegido por token que lea las dos pestañas y devuelva este JSON. Así el tablero se actualiza solo.

El tablero nunca escribe en la hoja. No hay que tocar sus columnas.

## Definiciones (confirmar con la hoja real)

| Término | Cálculo | Fuente |
|---|---|---|
| Facturado | `ventas_contado + creditos_total_ventas` | Resumen_Diario |
| Recaudo | `ventas_contado + creditos_abonos` | Resumen_Diario |
| Recaudo por cuenta | suma de `Valor` por `Cuenta_Destino` (VENTA = contado, ABONO = crédito) | movimientos_detallados |
| Cuadre | Σ movimientos del día = `ventas_contado + creditos_abonos`; si no, se marca | ambas |
| Meta / equilibrio | 120 M / 100 M **por mes**, medidos sobre lo **facturado** | `js/config.js` |

Comparativos "a la misma altura": el mes se compara con los mismos días del mes anterior y del año pasado. Día y semana se comparan 7 y 364 días atrás, para que caigan en el mismo día de la semana.

## Cómo evita errores

- Las fechas son texto `YYYY-MM-DD`; nunca pasan por la zona horaria del navegador.
- Nada se descarta en silencio: filas ilegibles, cuentas vacías, tipos raros y duplicados quedan listados en "Calidad de los datos".
- Una cuenta nueva (como Camila) aparece sola en cuanto trae su primer movimiento y se marca "nueva".
- Si un periodo tiene días sin cargar, la tarjeta lo dice (`20/22 días con datos`) y las comparaciones con base incompleta llevan asterisco.
- Cuando no hay año anterior suficiente, no se proyecta con él: se dice "sin base".

## Oro

- **Bolsa:** XAU/USD de gold-api.com × TRM oficial de datos.gov.co ÷ 31,1035 g. Sin llaves.
- **Mercado local:** no existe una fuente pública confiable; se registra a mano una vez al día (compra y venta 18k) y se muestra la prima o descuento contra la bolsa.
- **Señal:** compara el precio de hoy con el promedio de las lecturas guardadas (±2 %). Hoy el historial vive en el navegador, así que necesita 7 días de uso. Para tener historia real, registrar el precio a diario en una pestaña de la hoja con n8n.
- Es una referencia mecánica, no una recomendación de inversión.

## Fechas pico

Si hay datos del año pasado, el reparto de lo que falta sigue la forma de ventas de ese año. Si no, usa los multiplicadores de `eventos` en `js/config.js`, que son supuestos para calibrar.
