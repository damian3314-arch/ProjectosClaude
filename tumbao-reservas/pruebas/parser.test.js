/**
 * Pruebas del parser de correos de Bancolombia.
 *
 * Los casos salen de correos reales de alerta de Bancolombia. Los
 * nombres y números de cuenta están cambiados; la ESTRUCTURA del texto
 * es literal, que es lo que el parser tiene que aguantar.
 *
 *   node pruebas/parser.test.js
 */
const { parsearCorreoBancolombia, parsearMonto, parsearFecha } =
  require('../n8n/parser-bancolombia.js');

let fallos = 0;
const ok = (nombre, cond, extra = '') => {
  console.log(`${cond ? '✓' : '✗'} ${nombre}${extra ? '  → ' + extra : ''}`);
  if (!cond) fallos++;
};

const PRE = '¡Listo! Todo salió bien con tus movimientos Bancolombia: ';

// ── INGRESOS: el dinero entró, hay que registrarlo ───────────────────
const INGRESOS = [
  {
    nombre: 'transferencia recibida por llave Bre-B',
    texto: PRE + 'Tumbao, recibiste una transferencia de CAMILA ROJAS DUQUE por ' +
           '$15000.00 en tu cuenta *4471 conectada a la llave 3017833550 el ' +
           '26/07/26 a las 19:05. Con Bre-b es de una y gratis.',
    espera: { valor_cop: 15000, remitente: 'CAMILA ROJAS DUQUE', ultimos_4: '4471', llave: '3017833550' },
  },
  {
    nombre: 'transferencia recibida sin llave',
    texto: PRE + 'Recibiste una transferencia por $650000 de JULIANA SANTIAGO ' +
           'en tu cuenta **4471, el 10/07/2026 a las 10:10. Si tienes dudas, hablemos:',
    espera: { valor_cop: 650000, remitente: 'JULIANA SANTIAGO', ultimos_4: '4471' },
  },
  {
    nombre: 'monto con separador colombiano de miles y decimales',
    texto: PRE + 'Recibiste una transferencia por $1.500.000,00 de PEDRO GOMEZ ' +
           'en tu cuenta **4471, el 05/07/2026 a las 08:30.',
    espera: { valor_cop: 1500000 },
  },
  {
    nombre: 'monto sin decimales ni separadores',
    texto: PRE + 'Recibiste una transferencia por $15000 de ANA MARIA LOPEZ ' +
           'en tu cuenta **4471, el 26/07/2026 a las 20:15.',
    espera: { valor_cop: 15000 },
  },
  {
    nombre: 'pago recibido por codigo QR',
    texto: PRE + 'Recibiste un pago por codigo QR de LAURA MARTINEZ por $30000.00 ' +
           'en tu cuenta *4471 el 26/07/2026 a las 19:40.',
    espera: { valor_cop: 30000, remitente: 'LAURA MARTINEZ' },
  },
  {
    nombre: 'Bre-B recibido REAL (monto con coma de miles)',
    texto: PRE + 'Damian, recibiste una transferencia de Damian Antonio Barragan Campo ' +
           'por $1,000.00 en tu cuenta *8621 conectada a la llave 3015373964 el ' +
           '26/07/26 a las 15:27. Con llaves es de una y gratis.',
    espera: { valor_cop: 1000, ultimos_4: '8621', llave: '3015373964' },
  },
];

// ── SALIDAS: el dinero salió. Registrarlas confirmaría reservas falsas.
const SALIDAS = [
  { nombre: 'pago por QR (saliente)',
    texto: PRE + 'TUMBAO ACADEMIA pagaste $11000.00 por codigo QR desde tu cuenta ' +
           '*4471 a la llave 0091790861 el 17/07/2026 a las 11:57.' },
  { nombre: 'compra con tarjeta débito',
    texto: PRE + 'Compraste $14.000,00 en CINNAMON GOURMET con tu T.Deb *1958, ' +
           'el 17/07/2026 a las 15:02.' },
  { nombre: 'transferencia enviada a cuenta',
    texto: PRE + 'Transferiste $16000.00 desde tu cuenta 4471 a la cuenta ' +
           '*3143132863 el 17/07/2026 a las 18:45.' },
  { nombre: 'transferencia enviada a llave Bre-B',
    texto: PRE + 'TUMBAO, transferiste $37000.00 a la llave 1120841442 desde tu ' +
           'cuenta *4471 a NICOLAS CIFUENTES el 11/07/26 a las 18:28.' },
  { nombre: 'pago a tercero',
    texto: PRE + 'Pagaste $80000.00 a NU Compania de Financiamiento desde tu ' +
           'producto 4471 el 13/07/2026 12:11:35.' },
  { nombre: 'retiro en corresponsal',
    texto: PRE + 'Retiraste $650000 en nuestro corresponsal BARRIO COLOMBIA ' +
           'en BARRANCABERMEJA, el 10/07/26 a las 10:20.' },
  { nombre: 'correo de marketing sin movimiento',
    texto: 'Damian, tu informe llegó con algo nuevo, conócelo. Tu plata tiene ' +
           'una historia que contarte. Descubre la historia de tus gastos.' },
  { nombre: 'aviso de extracto',
    texto: '¡Toc-toc! Llegó tu extracto del mes. Ya está disponible tu extracto ' +
           'para el producto Cuenta de Ahorros.' },
  { nombre: 'Boton Bancolombia (encabezado distinto)',
    texto: 'Notificación Transaccional Bancolombia: Transferiste $13000.00 por ' +
           'Boton Bancolombia a PARTNERS TELECOM COLOMBIA SAS desde producto ' +
           '*8621. 26/07/2026 08:46:34' },
  { nombre: 'cuerpo vacío', texto: '' },
];

console.log('\n── Ingresos (deben registrarse) ──');
for (const c of INGRESOS) {
  const r = parsearCorreoBancolombia(c.texto);
  if (!r.es_ingreso) {
    ok(c.nombre, false, 'rechazado: ' + r.motivo);
    continue;
  }
  const malos = Object.entries(c.espera)
    .filter(([k, v]) => r[k] !== v)
    .map(([k, v]) => `${k}: esperaba ${JSON.stringify(v)}, dio ${JSON.stringify(r[k])}`);
  ok(c.nombre, malos.length === 0, malos.join(' | ') || `$${r.valor_cop} · ${r.fecha_pago}`);
}

console.log('\n── Salidas y ruido (NO deben registrarse) ──');
for (const c of SALIDAS) {
  const r = parsearCorreoBancolombia(c.texto);
  ok(c.nombre, r.es_ingreso === false,
     r.es_ingreso ? `¡SE COLÓ! $${r.valor_cop}` : r.motivo);
}

console.log('\n── Montos ──');
// Bancolombia mezcla TRES notaciones en los mismos correos. La de coma
// como separador de miles salió de un correo Bre-B real: el cuerpo trae
// "$1,000.00" aunque el snippet de Gmail muestre "$1000.00".
const MONTOS = [
  ['1,000.00',     1000],      // coma = miles, punto = decimales
  ['1,500,000.50', 1500001],   // idem, con decimales
  ['14.000,00',    14000],     // punto = miles, coma = decimales
  ['1.500.000,50', 1500001],
  ['15000',        15000],     // sin separadores
  ['15000.00',     15000],
  ['1.500.000',    1500000],   // punto = miles, sin decimales
  ['1,500,000',    1500000],   // coma = miles, sin decimales
  ['650000',       650000],
  ['2.900,00',     2900],
  ['4187464.00',   4187464],
  ['15.000',       15000],     // ambiguo en teoria: 3 digitos = miles
  ['15.00',        15],        // 2 digitos = decimales
  ['0',            null],
  ['abc',          null],
  ['',             null],
];
for (const [entrada, esperado] of MONTOS) {
  const r = parsearMonto(entrada);
  ok(`"$${entrada}" → ${esperado}`, r === esperado, r !== esperado ? `dio ${r}` : '');
}

console.log('\n── Fechas (Bogotá, UTC-5) ──');
const FECHAS = [
  [['26/07/26', '19:05'], '2026-07-26T19:05:00-05:00'],
  [['10/07/2026', '10:10'], '2026-07-10T10:10:00-05:00'],
  [['05/01/2026', '08:30'], '2026-01-05T08:30:00-05:00'],
  [['32/01/2026', '10:00'], null],
  [['10/13/2026', '10:00'], null],
  [['10/07/2026', '25:00'], null],
];
for (const [[f, h], esperado] of FECHAS) {
  const r = parsearFecha(f, h);
  ok(`${f} ${h} → ${esperado}`, r === esperado, r !== esperado ? `dio ${r}` : '');
}

console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
