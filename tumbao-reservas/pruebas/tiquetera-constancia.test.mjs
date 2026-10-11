/**
 * La plantilla tiquetera_constancia (11 oct): la tiquetera vendida por constancia y disciplina, no por ahorro.
 * Damián: «anímate a tu tiquetera con constancia y disciplina; siempre vendrán cosas buenas; rétate tú»; nada de «sorpresas» ni
 * tono de vendedor; y que sirva para hombres también (también bailan): lenguaje neutro, sin «misma/mismo» ni «@».
 *
 *   node tiquetera-constancia.test.mjs
 */
import { readFileSync } from 'node:fs';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const w = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');
const i = w.indexOf("name: 'tiquetera_constancia'");
const t = w.slice(i, w.indexOf("name: 'tiquetera_semana'", i));
const cuerpo = (() => { const m = /type: 'BODY',\s*text:\s*([\s\S]*?),\s*example:/.exec(t); return m ? eval(m[1]) : ''; })();

ok('existe y es de MARKETING (para vender), en español', i > 0 && /category: 'MARKETING'/.test(t) && /language: 'es'/.test(t));
ok('el texto que aprobó Damián (opción 1): constancia, reto, compromiso y «cosas buenas»', /Este mes bailaste \{\{2\}\} veces, y eso ya dice mucho de ti\./.test(cuerpo)
   && /Los objetivos no se cumplen con ganas, se cumplen con constancia\./.test(cuerpo) && /Rétate a seguir: tu tiquetera es ese compromiso contigo/.test(cuerpo)
   && /siempre llegan cosas buenas/.test(cuerpo), cuerpo);
ok('lenguaje neutro: sirve igual para un hombre (sin «misma/mismo», «@», «bienvenida», «lista para ti»…)', !/\bmism[oa]\b|@|\bbienvenid[oa]\b|\b(sol|list|segur|motivad|cansad)[oa]\b/i.test(cuerpo.replace(/clases listas/, '')));
ok('sin sorpresas prometidas, sin precios, sin descuentos ni urgencias inventadas', !/sorpresa|regalo|gratis|descuento|promo|\$|últim|solo hoy|hasta el/i.test(cuerpo));
ok('dos variables: el nombre y las clases del mes, con ejemplo para Meta', /\{\{1\}\}/.test(cuerpo) && /\{\{2\}\}/.test(cuerpo) && !/\{\{3\}\}/.test(cuerpo) && /body_text: \[\['Laura', '4'\]\]/.test(t));
ok('cabe de sobra (WhatsApp: 1024 caracteres)', cuerpo.length > 100 && cuerpo.length < 600, String(cuerpo.length));
ok('botones: comprar en la página, «Cuéntame de la tiquetera» (lo contesta el asistente con los paquetes) y la baja', /type: 'URL', text: 'Quiero mi tiquetera', url: 'https:\/\/tumbaobaila\.com\/mensualidad'/.test(t)
   && /type: 'QUICK_REPLY', text: 'Cuéntame de la tiquetera'/.test(t) && /type: 'QUICK_REPLY', text: 'No quiero más mensajes'/.test(t));
ok('los textos de los botones caben (25 caracteres)', ['Quiero mi tiquetera', 'Cuéntame de la tiquetera', 'No quiero más mensajes'].every(b => b.length <= 25));
ok('«No quiero más mensajes» da la baja (lo atiende PIDE_SALIR)', /PIDE_SALIR = \/\^\\s\*\(salir\|baja\|stop\|parar\|cancelar\|no\\s\+m\[aá\]s\(\\s\+mensajes\)\?\|no\\s\+quiero\\s\+\(m\[aá\]s\\s\+\)\?mensajes\)/.test(w));
ok('la plantilla vieja sigue definida (Meta no deja editar una aprobada: se crea otra con otro nombre)', w.includes("name: 'tiquetera_semana'"));

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo en verde.');
process.exit(fallos ? 1 : 0);
