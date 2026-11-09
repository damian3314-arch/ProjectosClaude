/* Configuración de la campaña. Edita SOLO este archivo para cambiar fechas, textos y metas.
   Lo marcado [CONFIRMAR] son datos que aún no tengo: la página los muestra tal cual hasta que los completes. */
window.CORO = {
  campana: {
    nombre: 'Sábados de Realeza',
    lema: 'Oro brillante. Corona bien fría.',
    marca: 'Joyería Tanya Santiago',
    ciudad: 'Barrancabermeja',
    prueba: '2026-11-14',
    lanzamiento: '2026-11-21'
  },
  contacto: {
    whatsapp: '',                 // [CONFIRMAR] formato 573001234567 (sin + ni espacios). Es el WhatsApp de la joyería que recibe las citas
    direccion: '[DIRECCIÓN]',     // [CONFIRMAR]
    horario: '[HORARIO]',         // [CONFIRMAR] ej. "Jornada continua, 9:00 a.m. a 5:00 p.m."
    instagram: ''                 // [CONFIRMAR] ej. https://instagram.com/...
  },
  // URL pública donde quede publicada la landing. Si queda vacío, se usa la dirección actual del navegador.
  baseUrl: '',
  agenda: {
    inicio: '09:00',              // [CONFIRMAR]
    fin: '17:00',                 // [CONFIRMAR]
    bloqueMin: 30,
    cuposPorBloque: 2,            // puestos de servicio a la vez (plan: 2)
    maxJoyas: 3,
    // Opcional: URL de la Web App de Google Apps Script (ver apps-script/Code.gs). Con esto la cita se crea en el Calendar y en una hoja.
    endpoint: ''
  },
  // Fechas del evento. publico:false = solo se ofrece con ?p=1 en el link (clientes selectos del día de prueba).
  fechas: [
    { f: '2026-11-14', tipo: 'prueba',   publico: false, etiqueta: 'Día de prueba · clientes selectos' },
    { f: '2026-11-21', tipo: 'sabado',   publico: true,  etiqueta: 'Lanzamiento · la gran revelación' },
    { f: '2026-11-28', tipo: 'sabado',   publico: true,  etiqueta: 'Sábado de Black Friday' },
    { f: '2026-12-05', tipo: 'sabado',   publico: true,  etiqueta: 'Sábado de Realeza' },
    { f: '2026-12-06', tipo: 'domingo',  publico: true,  etiqueta: 'Domingo con cita' },
    { f: '2026-12-12', tipo: 'sabado',   publico: true,  etiqueta: 'Sábado de Realeza' },
    { f: '2026-12-13', tipo: 'domingo',  publico: true,  etiqueta: 'Domingo con cita' },
    { f: '2026-12-19', tipo: 'sabado',   publico: true,  etiqueta: 'Sábado de primas' },
    { f: '2026-12-20', tipo: 'domingo',  publico: true,  etiqueta: 'Domingo de primas' },
    { f: '2026-12-26', tipo: 'sabado',   publico: true,  etiqueta: 'Sábado post Navidad' },
    { f: '2026-12-27', tipo: 'domingo',  publico: true,  etiqueta: 'Domingo con cita' }
    // Domingo de noviembre por decidir: agrega aquí p. ej. { f: '2026-11-29', tipo: 'domingo', publico: true, etiqueta: 'Domingo con cita' }
  ],
  // Metas por fecha. La de la prueba es menor porque va a una base pequeña.
  metasPrueba: { invitaciones: 60, respuestas: 18, citas: 12, llegan: 9, compran: 4, venta: 8000000 },
  metasDia:    { invitaciones: 150, respuestas: 45, citas: 30, llegan: 22, compran: 9, venta: 10000000 },
  ventaSabadoNormal: 7300000,     // promedio desde junio según el Plan Corónate
  // Texto de bebidas para la landing. [CONFIRMAR] qué se ofrece de verdad antes de publicar.
  bebidas: 'Corona bien fría (solo mayores de 18, con documento), soda de frutos rojos, Canada Dry y agua helada.',
  mostrarSnacks: false,           // pasa a true cuando se confirme que habrá algo para picar
  snacksTexto: 'Algo para picar mientras esperas.',
  // Línea de tiempo que ve la propietaria. tipo: hito | redes | evento
  linea: [
    { f: '2026-11-09', t: 'Aprobar texto e invitación; elegir clientes selectos', tipo: 'hito' },
    { f: '2026-11-10', t: 'Asesoras envían invitaciones a la base selecta (≈75 por día)', tipo: 'hito' },
    { f: '2026-11-13', t: 'Confirmación de cada cita + quincena', tipo: 'hito' },
    { f: '2026-11-14', t: 'DÍA DE PRUEBA con base pequeña', tipo: 'evento' },
    { f: '2026-11-16', t: 'Festivo. Arranca expectativa en redes (vitrina tapada) [SUPUESTO]', tipo: 'redes' },
    { f: '2026-11-17', t: 'Revisión del piloto: ajustar texto, tarjeta y cupos', tipo: 'hito' },
    { f: '2026-11-18', t: 'Invitaciones a la base completa (asesoras) [SUPUESTO]', tipo: 'hito' },
    { f: '2026-11-20', t: 'Última confirmación de citas. Fachada lista, moño puesto', tipo: 'hito' },
    { f: '2026-11-21', t: 'LANZAMIENTO · la gran revelación de la vitrina', tipo: 'evento' },
    { f: '2026-11-27', t: 'Black Friday', tipo: 'hito' },
    { f: '2026-12-15', t: 'Primas: se pagan hasta el 20 de diciembre', tipo: 'hito' },
    { f: '2026-12-24', t: 'Nochebuena', tipo: 'hito' },
    { f: '2026-12-25', t: 'Navidad: cerrado', tipo: 'hito' },
    { f: '2026-12-26', t: 'Último sábado de la campaña', tipo: 'evento' }
  ],
  checklist: [
    'Tania aprueba el texto de la invitación y el shampoo de regalo',
    'Completar contacto en config.js (WhatsApp, dirección, horario)',
    'Decoración de Navidad y moño en la fachada',
    'Fachada: tapar el jardín, tanque de cervezas, mesitas y banquitos, sofá abajo',
    'Bolsas, empaques y agendas nuevas',
    'Bebidas sin alcohol: soda de frutos rojos, Canada Dry, agua helada',
    'Decidir si habrá algo para picar (galletas, snacks)',
    'Música y luces del día',
    'Fotógrafo / videógrafo para el 21 (material para regalos y redes)',
    'Turnos del personal: 2 puestos de shampoo a la vez',
    'Insumos del shampoo de brillo',
    'Coronas, hielo y control de edad (+18 con documento)',
    'Decidir domingo de noviembre',
    'Teaser de expectativa en redes programado',
    'Carpeta de Drive del creativo creada y compartida',
    'Calendar compartido con las asesoras',
    'Dominio y publicación (Cloudflare)'
  ],
  drive: { carpeta: '' }          // [CONFIRMAR] link de la carpeta de Drive del creativo
};
