// Todo lo que el negocio puede querer cambiar vive aquí, no regado en el código.
export const CONFIG = {
  negocio: 'Taller Joyería Santiago',

  // Metas en pesos por mes. Equilibrio = ventas mínimas para no perder; meta = ventas para tener ganancia.
  puntoEquilibrioMensual: 100_000_000,
  metaMensual: 120_000_000,

  // Cuántos pesos pensaba el dueño que se necesitaban en Nov+Dic. Se contrasta con el cálculo real.
  intuicionNovDic: 200_000_000,

  // Fuentes de datos con el mismo formato JSON (ver README). Se combinan en orden.
  // Producción: reemplazar por la URL del endpoint de n8n que lee la hoja.
  fuentesDatos: ['data/demo.json'],

  // Cuadre: tolerancia en pesos entre Σ movimientos y el resumen diario.
  toleranciaCuadre: 1,

  // Días de la semana en que el taller no registra ventas (0=lunes ... 6=domingo). Vacío = todos los días cuentan.
  diasCerrados: [],

  // Días hacia atrás en los que se buscan huecos de carga.
  ventanaHuecos: 21,

  // Una cuenta se marca como "nueva" si su primer movimiento fue hace menos de estos días.
  diasCuentaNueva: 60,

  // Fechas pico. Ventanas disjuntas. Los multiplicadores SOLO se usan si no hay datos del año anterior
  // para repartir la meta; son supuestos a calibrar, no mediciones.
  eventos: [
    { id: 'halloween', nombre: 'Halloween', desde: '2026-10-31', hasta: '2026-10-31', mult: 1.1 },
    { id: 'blackfriday', nombre: 'Black Friday', desde: '2026-11-27', hasta: '2026-11-29', mult: 2.2 },
    { id: 'cyber', nombre: 'Cyber Lunes', desde: '2026-11-30', hasta: '2026-11-30', mult: 1.8 },
    { id: 'prima', nombre: 'Prima y novena', desde: '2026-12-15', hasta: '2026-12-20', mult: 1.5 },
    { id: 'navidad', nombre: 'Navidad', desde: '2026-12-21', hasta: '2026-12-25', mult: 1.8 },
    { id: 'anonuevo', nombre: 'Fin de año', desde: '2026-12-26', hasta: '2026-12-31', mult: 1.2 },
  ],

  // Oro
  oro: {
    umbralSenal: 0.02, // ±2% contra el promedio de las lecturas guardadas
    minLecturas: 7,
    quilates: [
      { k: 24, pureza: 1 },
      { k: 18, pureza: 0.75 },
      { k: 14, pureza: 0.585 },
      { k: 10, pureza: 0.417 },
    ],
  },
};
