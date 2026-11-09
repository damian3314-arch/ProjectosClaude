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
    whatsapp: '573016068003',     // [CONFIRMAR] número público del Instagram de la joyería. Es el WhatsApp que recibe las citas
    direccion: '[DIRECCIÓN]',     // [CONFIRMAR]
    horario: 'Jornada continua de 9:30 a. m. a 7:30 p. m.',   // sábados de campaña (Damián, 9 nov). [CONFIRMAR] domingos
    instagram: ''                 // [CONFIRMAR] ej. https://instagram.com/...
  },
  // URL pública donde quede publicada la landing. Si queda vacío, se usa la dirección actual del navegador.
  baseUrl: '',
  // Precios que ve el público general. Los invitados premium (?p=1) ven el shampoo de regalo.
  precios: { shampoo: 'desde $20.000', reparacion: 'desde $30.000', pulsera: 'desde $30.000' },
  agenda: {
    inicio: '09:30',              // primer turno
    fin: '19:00',                 // el último turno empieza a las 6:30 p. m.; se cierra 7:30 p. m.
    bloqueMin: 30,
    cuposPorBloque: 3,            // personas atendidas a la vez en cada turno de 30 min
    maxJoyas: 3,
    // Opcional: URL de la Web App de Google Apps Script (ver apps-script/Code.gs). Con esto la cita se crea en el Calendar y en una hoja.
    endpoint: ''
  },
  // Fechas del evento. publico:false = solo se ofrece con ?p=1 en el link (clientes selectos del día de prueba).
  fechas: [
    { f: '2026-11-14', tipo: 'ensayo',   publico: false, etiqueta: 'Ensayo interno sin clientes' },
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
    { f: '2026-11-09', t: 'Grabación día 1: producto, taller, pulsera tejida, vitrina tapada, Tania a cámara', tipo: 'hito' },
    { f: '2026-11-10', t: 'Grabación día 2 con clientes. Autorizaciones firmadas. Material a Drive', tipo: 'hito' },
    { f: '2026-11-11', t: '6 p.m.: tarjeta de invitación, flyer y primeras historias para aprobación de Tania', tipo: 'hito' },
    { f: '2026-11-12', t: '6 p.m.: reels R1 y R2 editados', tipo: 'hito' },
    { f: '2026-11-13', t: '6 p.m.: reels R3 y R4 editados; tarjetas listas para las asesoras', tipo: 'hito' },
    { f: '2026-11-14', t: 'ENSAYO INTERNO sin clientes: turnos, shampoo, bebidas y caída de la tela, con familiares o empleados', tipo: 'evento' },
    { f: '2026-11-15', t: 'Se publica la vitrina tapada y R1', tipo: 'redes' },
    { f: '2026-11-16', t: 'Festivo (joyería cerrada): Damián revisa y pule todo: invitación, tarjeta, landing, textos, lista y plantillas. Se publica R2 y "faltan 5"', tipo: 'hito' },
    { f: '2026-11-17', t: 'ARRANCAN LAS INVITACIONES de las asesoras (17 al 20) · R4 (test) · anuncio del servicio pago', tipo: 'hito' },
    { f: '2026-11-18', t: 'Invitaciones · R3 · empieza montaje de fachada', tipo: 'redes' },
    { f: '2026-11-19', t: '6 p.m.: R5 con clientes; fachada y decoración listas; ensayo', tipo: 'hito' },
    { f: '2026-11-20', t: 'Recordatorio a cada cita; "mañana se abre el telón"; bebidas, hielo, tela y moño', tipo: 'hito' },
    { f: '2026-11-21', t: 'LANZAMIENTO · revelación a las 9:00', tipo: 'evento' },
    { f: '2026-11-22', t: 'Reel resumen y agradecimientos "Tu oro, tu corona"', tipo: 'redes' },
    { f: '2026-11-23', t: 'Resultados del 21 y ajustes para Black Friday', tipo: 'hito' },
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
    'Base de clientes con celular y marca premium cargada en el panel (antes del 16)',
    'Lunes 16 (festivo): Damián revisa invitación, tarjeta, landing, textos, lista y plantillas; todo pulido para salir el 17',
    'Ensayo interno del sábado 14: quién hace de cliente, cronometrar cada turno',
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
    'Costos reales confirmados con Tania (pestaña Propietaria · Costos y retorno)',
    'Brief creativo entregado al creativo (creativo.html)'
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
    // Shampoo de brillo: de regalo solo para los invitados; el resto lo paga.
    invitadosRegalo: 50, costoShampoo: 5000,
    clientesPagan: 120, costoShampooPago: 6500, precioShampoo: 25000,
    // Bebidas: Corona y soda ≈ $2.500; agua y Canada Dry ≈ $1.000–1.500.
    acompanantes: 0.5, partCervezaSoda: 0.6, costoCervezaSoda: 2500, costoAguaCanada: 1250,
    hieloJornada: 20000, snacksPersona: 0,
    // Costos que sí se cargan a la campaña (Tania quiere recuperarlos).
    decoracion: 1750000, fotoVideo: 550000,
    // Opcionales: 0 = ya los asume la joyería (empaques, personal).
    empaques: 0, personalExtraJornada: 0,
    ventaSabadoCampana: 10000000, ventaSabado2025: 5270000, ventaDomingo: 3000000, canibalizacionDomingo: 0.3,
    margen: 0.45
  },

  // Meta noviembre + diciembre: se ajustó de 400 M a 380 M (decisión del 9 nov) y su contraste con los datos del libro de ventas.
  metaNovDic: {
    meta: 380000000, metaOriginal: 400000000, nov2025: 88905000, dic2025: 229812000,
    vendidoNov: 13260000, corte: '2026-11-07',
    diasAbiertos: 43, domingos: 4,
    ritmoOct: 3390000, subidaTemporada: 1.34, proyeccion: 222000000
  },
  drive: { carpeta: '' }          // [CONFIRMAR] link de la carpeta de Drive del creativo
};
