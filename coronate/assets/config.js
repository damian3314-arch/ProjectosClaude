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
    { f: '2026-11-09', t: 'Grabación con clientes (día 1): producto, taller, Tania a cámara, vitrina tapada', tipo: 'hito' },
    { f: '2026-11-10', t: 'Grabación con clientes (día 2): testimonios, brindis, entregas. Autorizaciones firmadas', tipo: 'hito' },
    { f: '2026-11-11', t: 'Confirmar con Tania si va la prueba del 14 y con qué clientes', tipo: 'hito' },
    { f: '2026-11-12', t: 'Si hay prueba: invitaciones a mano a un grupo pequeño de selectos (sin redes)', tipo: 'hito' },
    { f: '2026-11-14', t: 'PRUEBA OPCIONAL con grupo pequeño · Tania en tienda cerrando ventas', tipo: 'evento' },
    { f: '2026-11-15', t: 'Arranca expectativa en redes: vitrina tapada, "estamos preparando algo muy especial"', tipo: 'redes' },
    { f: '2026-11-16', t: 'Festivo. Teaser en historias (las asesoras no envían hoy)', tipo: 'redes' },
    { f: '2026-11-17', t: 'Invitaciones a la base (asesoras, línea actual): martes', tipo: 'hito' },
    { f: '2026-11-18', t: 'Invitaciones: miércoles · información abierta del servicio pago', tipo: 'hito' },
    { f: '2026-11-19', t: 'Invitaciones: jueves · fachada y decoración en montaje', tipo: 'hito' },
    { f: '2026-11-20', t: 'Recordatorio a cada cita. Fachada lista, moño puesto, bebidas y hielo', tipo: 'hito' },
    { f: '2026-11-21', t: 'LANZAMIENTO · la gran revelación de la vitrina', tipo: 'evento' },
    { f: '2026-11-27', t: 'Black Friday', tipo: 'hito' },
    { f: '2026-11-28', t: 'Sábado de Black Friday', tipo: 'evento' },
    { f: '2026-12-06', t: 'Primer domingo de diciembre con cita', tipo: 'evento' },
    { f: '2026-12-15', t: 'Primas: se pagan hasta el 20 de diciembre', tipo: 'hito' },
    { f: '2026-12-20', t: 'Domingo de primas', tipo: 'evento' },
    { f: '2026-12-24', t: 'Nochebuena', tipo: 'hito' },
    { f: '2026-12-25', t: 'Navidad: cerrado', tipo: 'hito' },
    { f: '2026-12-26', t: 'Último sábado de la campaña', tipo: 'evento' },
    { f: '2026-12-27', t: 'Último domingo con cita', tipo: 'evento' }
  ],
  checklist: [
    'Guion, lista de tomas y autorizaciones de imagen impresas para el 9 y 10 de nov (grabacion.html)',
    'Tania aprueba el texto de la invitación y el shampoo de regalo',
    'Decidir si va la prueba del 14 y con qué clientes',
    'Completar contacto en config.js (WhatsApp, dirección, horario)',
    'Vitrina tapada con tela o cortinas desde el 15 de nov',
    'Decoración de Navidad y moño en la fachada',
    'Fachada: tapar el jardín, tanque de cervezas, mesitas y banquitos, sofá abajo',
    'Bolsas, empaques y agendas nuevas',
    'Bebidas: Corona (+18, con documento), soda de frutos rojos, Canada Dry, agua helada',
    'Decidir snacks',
    'Música y luces del día',
    'Fotógrafo / videógrafo para el 21',
    'Turnos del personal: 2 puestos de shampoo a la vez',
    'Insumos del shampoo de brillo',
    'Coronas, hielo y control de edad (+18 con documento)',
    'Decidir domingo de noviembre y quién cubre los domingos',
    'Precio del servicio pago y qué hacer con quien no cabe el 21',
    'Teaser de expectativa en redes programado',
    'Carpeta de Drive del creativo creada y compartida',
    'Calendar compartido con las asesoras',
    'Costos reales confirmados con Tania (pestaña Propietaria · Costos y retorno)'
  ],
  // Decisiones abiertas: se muestran en el panel hasta que se definan.
  pendientes: [
    { q: '¿Qué pasa con quien paga el servicio y no cabe el 21?', opciones: 'Agendarlo martes o miércoles · habilitar otra máquina · lista de espera', quien: 'Tania' },
    { q: 'Precio del servicio pago (para quien no es invitado)', opciones: '[CONFIRMAR]', quien: 'Tania' },
    { q: 'Snacks: ¿sí o no, y cuáles?', opciones: 'Galletas, frutos secos, nada', quien: 'Tania' },
    { q: 'Domingo de noviembre', opciones: '29 de nov o ninguno', quien: 'Tania y Damián' },
    { q: '¿Quién cubre los domingos?', opciones: 'Una asesora (normal) o dos · Damián 2–3 h en la tarde', quien: 'Tania' },
    { q: '¿Va la prueba del 14?', opciones: 'Sí con grupo pequeño de selectos · no', quien: 'Tania' }
  ],
  // Honorarios y costos de la campaña. Todo lo marcado [CONFIRMAR] es un supuesto de ejemplo.
  honorarios: { fase1: 1500000, fase2: 2000000 },
  costos: {
    sabados: 6, domingos: 4,
    clientesSabado: 22, clientesDomingo: 8, acompanantes: 0.5,
    shampooInsumo: 3000, shampooMin: 15, horaTecnico: 12000,
    bebidaPromedio: 3500, hieloJornada: 30000, snacksPersona: 0,
    empaquesLote: 600000, decoracion: 1500000, fotoVideo: 800000, personalExtraJornada: 120000,
    ventaSabadoCampana: 10000000, ventaSabado2025: 5270000, ventaDomingo: 3000000, canibalizacionDomingo: 0.3,
    margen: 0.45
  },
  // Meta noviembre + diciembre (decisión del 8–9 nov) y su contraste con los datos del libro de ventas.
  metaNovDic: {
    meta: 400000000, nov2025: 88905000, dic2025: 229812000,
    vendidoNov: 13260000, corte: '2026-11-07',
    diasAbiertos: 43, domingos: 4,
    ritmoOct: 3390000, subidaTemporada: 1.34, proyeccion: 222000000
  },
  drive: { carpeta: '' }          // [CONFIRMAR] link de la carpeta de Drive del creativo
};
