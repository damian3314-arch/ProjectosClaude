/**
 * La invitación a la tiquetera del cierre de «¿cómo te fue?».
 *
 * Damián (29 sep): «los que contestaron "me encantó" son los ideales para
 * invitarles a que compren tiquetera». Hoy 7 personas contestaron y el
 * modelo la mencionó en 6, sin precio ni enlace. Esto prueba la versión con
 * código: siempre igual, con el precio real, y solo a quien elogió.
 *
 *   node pruebas/oferta-tiquetera.test.mjs
 */
import { invitacionTiquetera, debeInvitarATiquetera } from '../../tumbao-caja/src/oferta.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : 'FALLO'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const REAL = [
  { clave: '4', clases: 4, precio_cop: 52000, vigencia_dias: 30 },
  { clave: '8', clases: 8, precio_cop: 96000, vigencia_dias: 30 },
];

titulo('1. El texto, con los precios de verdad');
{
  const t = invitacionTiquetera(REAL);
  ok('dice el precio del paquete de 4', t.includes('$52.000'), t);
  ok('dice cuánto sale cada clase', t.includes('$13.000 por clase'));
  ok('dice cuánto dura', t.includes('30 días'));
  ok('lleva el enlace de compra', t.includes('https://tumbaobaila.com/mensualidad'));
  ok('ofrece el paquete chico, no el de 8', !t.includes('96.000') && !t.includes('8 clases'));
  ok('no menciona el pase de regalo (es silencioso)', !/regalo|pase|constancia/i.test(t));
  ok('no promete descuentos', !/descuento|gratis|promo/i.test(t));
}

titulo('2. Si Damián cambia un precio, cambia solo');
{
  const t = invitacionTiquetera([{ clases: 4, precio_cop: 60000, vigencia_dias: 45 }]);
  ok('usa el precio nuevo', t.includes('$60.000') && t.includes('$15.000 por clase'), t);
  ok('y la vigencia nueva', t.includes('45 días'));
  const sin = invitacionTiquetera([{ clases: 4, precio_cop: 50000 }]);
  ok('sin vigencia no inventa una', !/dura/.test(sin) && sin.includes('la usas cuando quieras'), sin);
}

titulo('3. Sin paquetes, no se manda nada raro');
{
  ok('lista vacía → nada', invitacionTiquetera([]) === '');
  ok('null → nada', invitacionTiquetera(null) === '');
  ok('objeto suelto → nada', invitacionTiquetera({}) === '');
  ok('paquete sin precio → nada', invitacionTiquetera([{ clases: 4 }]) === '');
  ok('paquete de 0 clases → nada', invitacionTiquetera([{ clases: 0, precio_cop: 1000 }]) === '');
}

titulo('4. A quién sí y a quién no');
{
  const base = { estadoAntes: 'invitada', cerrar: true, tipo: 'elogio', urgente: false };
  ok('elogio en el primer cierre: sí', debeInvitarATiquetera(base));
  ok('si venía conversando también', debeInvitarATiquetera({ ...base, estadoAntes: 'conversando' }));
  ok('todavía no cierra: no', !debeInvitarATiquetera({ ...base, cerrar: false }));
  ok('ya estaba cerrada (un «gracias» después): no se repite', !debeInvitarATiquetera({ ...base, estadoAntes: 'cerrada' }));
  ok('queja: no', !debeInvitarATiquetera({ ...base, tipo: 'queja' }));
  ok('sugerencia: no', !debeInvitarATiquetera({ ...base, tipo: 'sugerencia' }));
  ok('mixta: no', !debeInvitarATiquetera({ ...base, tipo: 'mixta' }));
  ok('sin tipo: no', !debeInvitarATiquetera({ ...base, tipo: '' }));
  ok('elogio pero urgente: no', !debeInvitarATiquetera({ ...base, urgente: true }));
}

console.log(fallos ? `\n\x1b[31m${fallos} fallo(s)\x1b[0m` : '\n\x1b[32mtodo en verde\x1b[0m');
process.exit(fallos ? 1 : 0);
