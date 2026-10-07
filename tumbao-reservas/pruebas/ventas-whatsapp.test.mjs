/**
 * Ventas por WhatsApp (0141/0142): la baranda y las reglas que no se negocian.
 *
 * El asistente conversa con IA, y la IA se equivoca: inventa un precio, un descuento, un enlace.
 * Esta prueba protege lo que NO se le deja decidir al modelo:
 *   1. cifras: solo las del perfil (paquetes, mensualidad, suelta y sus cuentas);
 *   2. enlaces: solo tumbaobaila.com y el WhatsApp del equipo;
 *   3. promesas que el negocio no hizo (descuentos, regalos, «últimos cupos»);
 *   4. el prompt trae las reglas duras (no mentir sobre ser persona, respetar el «no»);
 *   5. la plantilla de apertura y la ruta del Worker existen, y la ronda nace APAGADA.
 *
 *   node ventas-whatsapp.test.mjs
 */
import { readFileSync } from 'node:fs';
import {
  guardarRespuestaVentas, montosEnTexto, enlacesEnTexto, cifrasPermitidas, opcionesDeVenta,
  INSTRUCCIONES_VENTAS, RESPUESTA_SEGURA_VENTAS, MAX_TURNOS_VENTAS, textoSeguimientoVentas,
} from '../../tumbao-caja/src/ventas.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const perfil = {
  nombre: 'Laura', visitas_30d: 4, precio_suelta: 15000, valor_mensualidad: 125000,
  aplica_mensualidad: true,
  cupos_mensualidad: { '07:00': 10, '18:00': 7, '19:00': 0 },
  paquetes_tiquetera: [
    { clave: '4', clases: 4, precio_cop: 52000, vigencia_dias: 30 },
    { clave: '8', clases: 8, precio_cop: 96000, vigencia_dias: 30 },
  ],
};
const dice = (t) => guardarRespuestaVentas(t, perfil);

titulo('1. Cifras: solo las de la base');
{
  const permitidas = [...cifrasPermitidas(perfil)].sort((a, b) => a - b);
  ok('permite precios de paquetes, mensualidad y suelta', [52000, 96000, 125000, 15000].every(n => permitidas.includes(n)));
  ok('permite el precio por clase ($12.000 y $13.000)', permitidas.includes(12000) && permitidas.includes(13000));
  ok('permite lo que ahorra: 8×15.000−96.000 = $24.000', permitidas.includes(24000));
  ok('la tiquetera de 8 a $96.000 pasa', dice('Con la tiquetera de 8 clases (96.000) cada clase te sale a $12.000 💃').ok);
  ok('«96 mil» también pasa (es 96.000)', dice('Son 96 mil por 8 clases y la usas cuando quieras').ok);
  ok('un precio inventado NO pasa ($80.000)', !dice('La tiquetera de 8 te queda en $80.000').ok);
  ok('«70 mil» inventado NO pasa', !dice('Te la dejo en 70 mil').ok);
  ok('un precio inventado en pesos NO pasa', !dice('Son 99000 pesos al mes').ok);
  ok('números que no son plata no estorban (horas, clases, teléfono)',
     dice('Las clases son a las 7:00 am, 8 clases en 30 días. Escríbenos al 301 783 3550').ok);
  ok('detecta montos escritos de varias formas', montosEnTexto('$96.000 y 52.000 pesos y 125 mil y $12000').sort((a, b) => a - b).join() === '12000,52000,96000,125000');
}

titulo('2. Enlaces: solo la página y el WhatsApp del equipo');
{
  ok('tumbaobaila.com/mensualidad pasa', dice('Entra a tumbaobaila.com/mensualidad y elige tu tiquetera').ok);
  ok('con https y punto final pasa', dice('Aquí: https://tumbaobaila.com/mensualidad.').ok);
  ok('wa.me del equipo pasa', dice('Escríbenos: wa.me/573017833550').ok);
  ok('otro dominio NO pasa', !dice('Paga en pagos-tumbao.com/ya').ok);
  ok('un acortador NO pasa', !dice('Mira esto bit.ly/abc123').ok);
  ok('otro WhatsApp NO pasa', !dice('Escríbeme a wa.me/573001112233').ok);
  ok('detecta dominios aunque no tengan http', enlacesEnTexto('entra a mipago.co ya').length === 1);
  ok('sin enlaces no se queja', dice('Claro que sí, ¿en qué horario te queda mejor?').ok);
}

titulo('3. Promesas que el negocio no hizo');
{
  for (const t of ['Te hago un descuento si compras hoy', 'Tengo una promo para ti', 'Te regalo una clase',
                   'Quedan los últimos cupos', 'Es una oferta especial', 'Está gratis la primera']) {
    ok(`no pasa: «${t}»`, !dice(t).ok);
  }
  // Lo legítimo no se bloquea: apuntarse a la lista de espera «no tiene costo».
  ok('«no tiene ningún costo» sí pasa', dice('Apuntarte a la lista de espera no tiene ningún costo').ok);
  ok('«regalado» o «promocionar» no se confunden con las palabras prohibidas',
     dice('Te cuento cómo funciona, sin afán').ok);
}

titulo('4. Vacío, largo y opciones');
{
  ok('vacío no pasa', !dice('   ').ok);
  ok('demasiado largo no pasa', !dice('a'.repeat(901)).ok);
  const o = opcionesDeVenta(perfil);
  ok('hay cupo a las 7 am y a las 6 pm para quien aplica', o.mensualidad_7am && o.mensualidad_6pm);
  ok('quien no aplica no recibe la opción de 6 pm', !opcionesDeVenta({ ...perfil, aplica_mensualidad: false }).mensualidad_6pm);
  ok('quien sale de la lista de espera para las 6 pm sí tiene la opción aunque no cumpla el historial',
     opcionesDeVenta({ ...perfil, aplica_mensualidad: false }, 'mensualidad_6pm').mensualidad_6pm);
  ok('pero no si ese objetivo es otro', !opcionesDeVenta({ ...perfil, aplica_mensualidad: false }, 'tiquetera').mensualidad_6pm);
    ok('sin cupo a las 6 pm tampoco', !opcionesDeVenta({ ...perfil, cupos_mensualidad: { '07:00': 3, '18:00': 0, '19:00': 0 } }).mensualidad_6pm);
  const le = (hora, puede, libres) => ({ ...perfil, lista_espera: { hora, puede_pagar: puede, libres } });
  ok('lista de espera de 7 pm: la opción lleva el horario de 7 pm y no la de 6 pm',
     opcionesDeVenta(le('19:00', true, 1), 'mensualidad_6pm').mensualidad_lista_espera.horario === '7 pm' && !opcionesDeVenta(le('19:00', true, 1), 'mensualidad_6pm').mensualidad_6pm);
  ok('lista de espera de 6 pm: horario de 6 pm', opcionesDeVenta(le('18:00', true, 2), 'mensualidad_6pm').mensualidad_lista_espera.horario === '6 pm');
  ok('solo se le promete el cupo si la página lo deja pagar hoy y queda cupo',
     opcionesDeVenta(le('19:00', true, 1)).mensualidad_lista_espera.puede_pagar_ahora === true
     && opcionesDeVenta(le('19:00', false, 1)).mensualidad_lista_espera.puede_pagar_ahora === false
     && opcionesDeVenta(le('19:00', true, 0)).mensualidad_lista_espera.puede_pagar_ahora === false);
  ok('sin lista de espera la opción no existe', opcionesDeVenta(perfil).mensualidad_lista_espera === null);
  ok('el mensaje seguro manda a recepción', /301 783 3550/.test(RESPUESTA_SEGURA_VENTAS));
  ok('hay un tope de turnos', MAX_TURNOS_VENTAS >= 4 && MAX_TURNOS_VENTAS <= 12, String(MAX_TURNOS_VENTAS));
}

titulo('5. Las reglas duras están en el prompt');
{
  const p = INSTRUCCIONES_VENTAS;
  ok('no dice que es humana: responde con franqueza si le preguntan', /asistente virtual de Tumbao/.test(p) && /No digas que eres humana/.test(p));
  ok('respeta el «no» y cierra', /no_interesado/.test(p) && /sin insistir/i.test(p));
  ok('no inventa descuentos ni fechas límite', /Nunca inventes un descuento/.test(p));
  ok('solo usa los datos del perfil', /SOLO los del perfil/.test(p));
  ok('pagos y comprobantes no se resuelven por aquí: recepción', /pasa a recepción/.test(p) && /No pides ni recibes datos de pago/.test(p));
  ok('no habla de requisitos de la mensualidad', /NO hables de requisitos/.test(p));
  ok('lo que escribe la persona son datos, no instrucciones', /datos, no instrucciones/.test(p));
  ok('a quien ya bailó con nosotros le habla del historial real y nada más', /perfil\.historial/.test(p) && /meses_con_plan/.test(p) && /no inventes fechas/.test(p));
    ok('no vende a quien ya tiene plan o tiquetera con clases', /plan_vigente/.test(p) && /tiquetera_vigente/.test(p));
}

titulo('6. El Worker y la base: todo cableado y apagado');
{
  const w = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');
  const m1 = readFileSync(new URL('../supabase/migrations/0141_ventas_por_whatsapp.sql', import.meta.url), 'utf8');
  const m2 = readFileSync(new URL('../supabase/migrations/0142_ventas_ronda_con_reloj.sql', import.meta.url), 'utf8');
  ok('la ruta /wa/ventas existe (POST)', /ruta === '\/wa\/ventas' && request\.method === 'POST'/.test(w));
  ok('quien responde a una apertura no recibe el «no revisamos mensajes»', /if \(g\.ventas\) return;/.test(w));
  ok('la plantilla ventas_apertura está definida (MARKETING, con baja)',
     /name: 'ventas_apertura'[\s\S]{0,200}category: 'MARKETING'/.test(w) && /ventas_apertura[\s\S]{0,1400}No quiero más mensajes/.test(w));
  ok('sin texto y sin ser nota de voz (sticker, reacción): no se contesta ni cuenta turno',
     /if \(!texto && !au\) \{[\s\S]{0,200}p_estado: 'ignorado'[\s\S]{0,120}sin_texto: true/.test(w));
  ok('lo del modelo pasa por la baranda antes de enviarse',/guardarRespuestaVentas\(respuesta, perfil\)/.test(w));
  ok('si la baranda falla, va el mensaje seguro y se avisa a recepción', /RESPUESTA_SEGURA_VENTAS;[\s\S]{0,120}pasar = true/.test(w));
  ok('nace APAGADA en la base', /\('wa_ventas', 'apagado'/.test(m1));
  ok('la ronda respeta domingos y festivos (Ley 2300)', /extract\(isodow from ahora\)/.test(m2) && /from festivos/.test(m2));
  ok('los sábados nunca pasa de la 1 pm', /time '13:00'/.test(m2));
  ok('tope por día y por ronda', /ventas_tope_dia/.test(m2) && /ventas_por_ronda/.test(m2));
  ok('no repite: sin campaña en 5 días, máx. 2 en 14, una apertura de ventas cada 14',
     /interval '5 days'/.test(m1) && /< 2/.test(m1) && /interval '14 days'/.test(m1));
  ok('respeta bajas, dueños, planes en gracia y tiqueteras con clases',
     /wa_bajas/.test(m1) && /wa_es_dueno/.test(m1) && /fin \+ 3 >= hoy/.test(m1) && /clases_usadas < clases_totales/.test(m1));
  ok('quien dijo «no» queda fuera 45 días', /no_interesado[\s\S]{0,120}45 days/.test(m1));
  const m3 = readFileSync(new URL('../supabase/migrations/0143_ventas_retomar_clientes_del_historial.sql', import.meta.url), 'utf8');
  const sql3 = m3.replace(/--.*$/gm, '');
  ok('0143: el historial entra con los mismos filtros de siempre',
     /afiliados_historial/.test(sql3) && /wa_bajas/.test(sql3) && /wa_es_dueno/.test(sql3) && /interval '5 days'/.test(sql3) && /< 2/.test(sql3) && /45 days/.test(sql3));
  ok('0143: solo a quien vino varias veces (2+ meses con plan o 3+ sueltas)', /h\.m >= 2 or h\.s >= 3/.test(sql3));
  ok('0143: no a quien vino en los últimos 30 días ni tiene plan o tiquetera', /interval '30 days'/.test(sql3) && /fin \+ 3 >= hoy\.d/.test(sql3) && /clases_usadas < clases_totales/.test(sql3));
  ok('0143: sin DROP ni cambios al CHECK de ventas_chats', !/\bdrop\b/i.test(sql3) && !/alter table/i.test(sql3));
    const m7 = readFileSync(new URL('../supabase/migrations/0147_campanas_solo_en_horario_de_mercadeo.sql', import.meta.url), 'utf8').replace(/--.*$/gm, '');
  ok('0147: el despachador no toma campañas fuera de horario (L-V 9-19, sábado 9-13, ni domingo ni festivo)',
     /time '09:00'/.test(m7) && /time '19:00'/.test(m7) && /time '13:00'/.test(m7) && /from festivos/.test(m7) && /isodow[\s\S]*?< 7/.test(m7));
    ok('costo: el Worker anota categoría y si Meta cobró cada mensaje, y trae el costo real (/wa/costos)',
     /wa_guardar_precio/.test(w) && /st\.pricing\.billable === true/.test(w) && /ruta === '\/wa\/costos'/.test(w) && /pricing_analytics/.test(w));
    const m155 = readFileSync(new URL('../supabase/migrations/0155_ventas_seguimiento_dentro_de_24h.sql', import.meta.url), 'utf8').replace(/--.*$/gm, '');
  const p7 = INSTRUCCIONES_VENTAS;
  ok('prompt: a quien vuelve se le ofrece primero la mensualidad de 7 am, después la tiquetera, después una clase suelta',
     /EN ESTE ORDEN: \(1\)[^]*mensualidad de 7 am[^]*\(2\)[^]*tiquetera[^]*\(3\)[^]*clase suelta/.test(p7));
  ok('prompt: la escasez solo con el número exacto y solo si son 5 o menos', /5 o menos puedes decir cuántos quedan, el número exacto/.test(p7));
  ok('prompt: la tiquetera no se ofrece como la mejor opción a quien casi no viene (vence a los 30 días)', /no se la ofrezcas como la mejor opción a quien casi no viene/.test(p7));
  const segs = [textoSeguimientoVentas({ nombre: 'Laura' }), textoSeguimientoVentas({ nombre: 'Laura', objetivo: 'mensualidad_7am' }),
                textoSeguimientoVentas({ nombre: 'Laura', hora: '19:00' }), textoSeguimientoVentas({ nombre: 'Laura', hora: '18:00' }), textoSeguimientoVentas({})];
  ok('seguimiento: ningún texto trae cifras, promociones ni enlaces ajenos (pasan la baranda)', segs.every(t => guardarRespuestaVentas(t, perfil).ok));
  ok('seguimiento: el de lista de espera nombra el horario correcto', /7 pm/.test(segs[2]) && !/6 pm/.test(segs[2]) && /6 pm/.test(segs[3]));
  ok('seguimiento: no es largo (WhatsApp)', segs.every(t => t.length < 260));
  ok('0155: una sola vez por conversación, dentro de la ventana de 24 h y solo si la última palabra fue nuestra',
     /seguimiento_at/.test(m155) && /interval '22 hours'/.test(m155) && /interval '20 hours' and ahora - interval '3 hours'/.test(m155) && /m\.direccion from wa_mensajes[^]{0,160}\) = 'saliente'/.test(m155));
  ok('0155: no a quien ya compró o está pagando, ni a bajas ni dueños',
     /tiqueteras tq/.test(m155) && /membresias m/.test(m155) && /mensualidad_solicitudes s/.test(m155) && /wa_bajas/.test(m155) && /wa_es_dueno/.test(m155));
  ok('0155: solo en horario (sin domingos ni festivos; sábado hasta la 1 pm) y se apaga con wa_ventas_seguimiento',
     /from festivos/.test(m155) && /time '13:00'/.test(m155) && /time '19:00'/.test(m155) && /wa_ventas_seguimiento/.test(m155));
  ok('0155: sin DROP ni DELETE', !/\bdrop\b/i.test(m155) && !/\bdelete\b/i.test(m155));
  ok('Worker: ruta /wa/ventas-seguimiento que envía y guarda el texto', /ruta === '\/wa\/ventas-seguimiento'/.test(w) && /textoSeguimientoVentas\(\{ nombre: s\.nombre/.test(w));
    const m156 = readFileSync(new URL('../supabase/migrations/0156_ventas_precio_por_clase_y_apertura_con_botones.sql', import.meta.url), 'utf8').replace(/--.*$/gm, '');
  ok('precio por clase: el bot puede decir «alrededor de $5.000» (la cifra viene de la base y pasa la baranda)',
     cifrasPermitidas({ ...perfil, mensualidad_por_clase: 5000 }).has(5000) && guardarRespuestaVentas('La mensualidad sale alrededor de $5.000 por clase, contra $15.000 la suelta.', { ...perfil, mensualidad_por_clase: 5000 }).ok);
  ok('precio por clase: sin el dato en la base, $5.000 NO pasa la baranda', !guardarRespuestaVentas('Sale a $5.000 por clase.', perfil).ok);
  ok('prompt: la mensualidad es de lunes a sábado sin domingos ni festivos y se dice «alrededor de», nunca como descuento',
     /lunes a sábado, sin domingos ni festivos/.test(INSTRUCCIONES_VENTAS) && /alrededor de/.test(INSTRUCCIONES_VENTAS) && /nunca como descuento/.test(INSTRUCCIONES_VENTAS));
  ok('prompt: sabe contestar a quien toca un botón de horario', /Si lo único que escribe es un horario/.test(INSTRUCCIONES_VENTAS) && /7:00 am/.test(INSTRUCCIONES_VENTAS));
  const ih = w.indexOf("name: 'ventas_horario'"); const th = w.slice(ih, ih + 1500);
  ok('plantilla ventas_horario: MARKETING, botones de horario y baja, SIN enlace',
     ih > 0 && /category: 'MARKETING'/.test(th) && ['7:00 am', '6:00 pm', '7:00 pm', 'No quiero más mensajes'].every(b => th.includes(`text: '${b}'`)) && !/tumbaobaila|https?:|type: 'URL'/.test(th.slice(0, th.indexOf('BUTTONS') + 600)));
  ok('0156: la prueba A/B solo se activa cuando ventas_plantilla_b tiene valor (vacía de entrada)', /'ventas_plantilla_b', ''/.test(m156) && /<> '' and c\.id % 2 = 1/.test(m156));
  ok('0156: sin DROP ni DELETE', !/\bdrop\b/i.test(m156) && !/\bdelete\b/i.test(m156));
    const m153 = readFileSync(new URL('../supabase/migrations/0153_gracia_5_dias_y_aviso_automatico_a_la_lista_de_espera.sql', import.meta.url), 'utf8').replace(/--.*$/gm, '');
  ok('0153: la gracia sube a 5 días y las funciones de ventas la leen del ajuste (sin «fin + 3» fijo)',
     /'mensualidad_gracia_dias', '5'/.test(m153) && /ventas_candidatos_historial/.test(m153) && /fin \+ 3/.test(m153) && /replace\(pg_get_functiondef\(r\.oid\), 'fin \+ 3'/.test(m153));
  ok('0153: el aviso a la lista de espera solo va a quien la página deja pagar, sin domingos ni festivos, y respeta bajas y dueños',
     /premium_puede_pagar\(r\.celular, null, v_hora::time\)/.test(m153) && /from festivos/.test(m153) && /wa_bajas/.test(m153) && /wa_es_dueno/.test(m153));
  ok('0153: quien no paga en 48 h deja su turno (anulada) y hay alerta si se pasa el tope de 23',
     /estado = 'anulada'/.test(m153) && /lista_espera_horas_para_pagar/.test(m153) && /v_ocup > v_tope/.test(m153));
  ok('0153: corre a las 9:10 am Bogotá de lunes a sábado y se apaga con wa_lista_espera_auto', /'10 14 \* \* 1-6'/.test(m153) && /wa_lista_espera_auto/.test(m153));
  ok('0153: sin DROP ni DELETE', !/\bdrop\b/i.test(m153) && !/\bdelete\b/i.test(m153));
    ok('la migración 0142 no borra nada (sin DROP)', !/\bdrop function\b/i.test(m2.replace(/--.*$/gm, '')));
}

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
process.exit(fallos ? 1 : 0);
