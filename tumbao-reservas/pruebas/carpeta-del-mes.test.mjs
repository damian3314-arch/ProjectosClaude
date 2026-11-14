/**
 * Prueba de la resolucion de la carpeta de Drive.
 *
 * Existe porque el workflow ya se rompio una vez por mirar una carpeta
 * fija: el 1 de agosto seguia leyendo la de julio, y el error culpaba al
 * archivo viejo sin decir que existia uno nuevo en otra parte.
 *
 * Las carpetas de CARPETAS_REALES son las que hay de verdad en
 * Drive el 28 de agosto de 2026, con el nombre mal escrito incluido:
 * "02_Marzo" deberia ser "03_Marzo".
 */
import { elegirAno, elegirMes, MESES, GLOBAL } from '../n8n/carpeta-del-mes.js';

let fallos = 0;
const ok = (n, c, extra = '') => {
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`);
  if (!c) fallos++;
};

const CARPETAS_REALES = [
  { id: 'ago', name: '08_Agosto' },     { id: 'dic', name: '12_Diciembre' },
  { id: 'nov', name: '11_Noviembre' },  { id: 'oct', name: '10_Octubre' },
  { id: 'sep', name: '09_Septiembre' }, { id: 'jul', name: '07_Julio' },
  { id: 'jun', name: '06_Junio' },      { id: 'may', name: '05_Mayo' },
  { id: 'abr', name: '04_Abril' },      { id: 'mar', name: '02_Marzo' },
  { id: 'feb', name: '02_Febrero' },    { id: 'ene', name: '01_Enero' },
];

console.log('-- El ano --------------------------------------------------');
{
  const r = elegirAno([{ id: 'a', name: '2026' }, { id: 'b', name: '2025' }], '2026');
  ok('toma la carpeta del ano en curso', r.ok && r.folder_id === 'a', r.folder_name);
}
{
  // El 1 de enero la carpeta nueva puede no estar creada.
  const r = elegirAno([{ id: 'b', name: '2026' }], '2027');
  ok('si no existe la del ano, la mas alta que haya',
     r.ok && r.folder_id === 'b' && /No existe la carpeta 2027/.test(r.motivo), r.motivo);
}
{
  const r = elegirAno([{ id: 'x', name: 'Archivo viejo' }], '2026');
  ok('sin ninguna carpeta de ano lo dice y no revienta',
     r.ok === false && r.folder_id === null, r.motivo);
}

console.log('\n-- El mes, contra las carpetas reales de Drive --------------');
{
  // El caso que importa: los doce meses tienen que acertar aunque una
  // carpeta tenga el numero mal escrito.
  let mal = [];
  for (let m = 1; m <= 12; m++) {
    const r = elegirMes(CARPETAS_REALES, m, { folder_name: '2026' });
    const primera = r.carpeta.split(' + ')[0];
    if (!primera.includes(MESES[m - 1])) mal.push(`${MESES[m - 1]}→${primera}`);
  }
  ok('los 12 meses encuentran SU carpeta', mal.length === 0,
     mal.length ? mal.join(', ') : 'ninguno falla');
}
{
  // "02_Marzo" tiene el prefijo mal. Por numero, marzo se quedaba sin
  // carpeta y febrero se llevaba las dos.
  const marzo = elegirMes(CARPETAS_REALES, 3, null);
  ok('marzo encuentra "02_Marzo" pese al numero mal escrito',
     marzo.carpeta.split(' + ')[0] === '02_Marzo', marzo.carpeta);
  const feb = elegirMes(CARPETAS_REALES, 2, null);
  ok('febrero no se lleva tambien la de marzo',
     feb.carpeta.split(' + ')[0] === '02_Febrero', feb.carpeta);
}
{
  const r = elegirMes(CARPETAS_REALES, 8, { folder_name: '2026' });
  ok('mira agosto y tambien julio, por si el archivo quedo en el anterior',
     r.modo === 'carpeta' && r.carpeta === '08_Agosto + 07_Julio', r.carpeta);
  ok('la consulta pide las dos carpetas por parents',
     /'ago' in parents or 'jul' in parents/.test(r.query) &&
     /mimeType != 'application\/vnd.google-apps.folder'/.test(r.query));
  ok('sin nada raro que avisar, no avisa', r.aviso === null, String(r.aviso));
}
{
  // El 1 de enero: existe diciembre pero todavia no la de enero.
  const soloDic = [{ id: 'dic', name: '12_Diciembre' }];
  const r = elegirMes(soloDic, 1, null);
  ok('el dia 1 sin carpeta nueva, usa la del mes anterior y avisa',
     r.modo === 'carpeta' && r.carpeta === '12_Diciembre' &&
     /Todavia no existe la carpeta de Enero/.test(r.aviso), r.aviso);
}
{
  // Sin ninguna carpeta util se vuelve a como funcionaba antes, pero
  // diciendolo: importar a ciegas desde todo el Drive es como se cuelan
  // reportes de otro sitio.
  const r = elegirMes([], 8, { folder_name: '2026' });
  ok('sin carpetas cae a la busqueda global', r.modo === 'global' && r.query === GLOBAL);
  ok('y el aviso lo dice para que se note', /menos seguro/.test(r.aviso), r.aviso);
}
{
  // Una carpeta llamada solo "03": el numero sigue valiendo de respaldo.
  const r = elegirMes([{ id: 'x', name: '03' }], 3, null);
  ok('una carpeta llamada solo "03" tambien vale', r.carpeta === '03', r.carpeta);
}

console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
