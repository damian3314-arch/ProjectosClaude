/**
 * El elector de reporte de afiliados, sin n8n.
 * Cada caso es uno que ya pasó o que está a un tecleo de pasar.
 */
import { readFileSync } from 'node:fs';
const cuerpo = readFileSync(new URL('../n8n/elegir-reporte-afiliados.js', import.meta.url), 'utf8');
const correr = (archivos) => {
  const $input = { all: () => archivos.map(json => ({ json })) };
  return new Function('$input', cuerpo)($input)[0].json;
};
const hoy = new Intl.DateTimeFormat('en-CA', { timeZone:'America/Bogota',
  year:'numeric', month:'2-digit', day:'2-digit' }).format(new Date());
const haceDias = n => {
  const d = new Date(hoy + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0,10);
};
let ok = 0, mal = 0;
const t = (n, c, f) => { const r = correr(c); const p = f(r);
  p ? (ok++, console.log(`  ✓ ${n}`))
    : (mal++, console.log(`  ✗ ${n}\n      → ${JSON.stringify(r).slice(0,260)}`)); };

console.log('\n── Elegir el reporte de afiliados ──\n');

// LO QUE ACABA DE PASAR: el archivo se sube con otro nombre y el sistema
// culpa al de julio, así que nadie entiende qué está mal.
t('un archivo llamado "Miembros activos" SÍ se ve',
  [{id:'1',name:'Afiliados activos '+haceDias(9)+'.xlsx'},
   {id:'2',name:'Miembros activos '+hoy+'.xlsx'}],
  r => r.ok === true && r.file_id === '2');

t('el de hoy le gana al de ayer',
  [{id:'1',name:'Afiliados activos '+haceDias(1)+'.xlsx'},
   {id:'2',name:'Afiliados activos '+hoy+'.xlsx'}],
  r => r.ok === true && r.file_id === '2' && r.dias_de_atraso === 0);

t('un cierre de caja (DD-MM-AAAA) nunca se confunde con el reporte',
  [{id:'1',name:'08-08-2026.xlsx'},
   {id:'2',name:'Afiliados activos '+hoy+'.xlsx'}],
  r => r.ok === true && r.file_id === '2');

t('con datos viejos se frena, y dice qué vio',
  [{id:'1',name:'Afiliados activos '+haceDias(9)+'.xlsx'}],
  r => r.ok === false && r.error === 'archivo_viejo'
       && /1 archivos en total y 1 de afiliados/.test(r.mensaje));

// El caso que confundía: subió el archivo pero sin fecha en el nombre.
// Antes el mensaje hablaba del de julio y no mencionaba el nuevo.
t('si el archivo nuevo no trae fecha, lo dice por su nombre',
  [{id:'1',name:'Afiliados activos '+haceDias(9)+'.xlsx'},
   {id:'2',name:'Listado miembros activos.xlsx'}],
  r => r.ok === false && /Listado miembros activos\.xlsx/.test(r.mensaje)
       && /no traen fecha/.test(r.mensaje));

t('si NINGUNO trae fecha, explica cómo renombrarlo',
  [{id:'1',name:'Miembros activos.xlsx'}],
  r => r.ok === false && r.error === 'sin_fecha_en_el_nombre'
       && /AAAA-MM-DD/.test(r.mensaje));

t('carpeta sin reporte: lista lo que sí hay',
  [{id:'1',name:'08-08-2026.xlsx'},{id:'2',name:'notas.txt'}],
  r => r.ok === false && r.error === 'sin_archivo'
       && /08-08-2026\.xlsx/.test(r.mensaje));

t('una fecha futura se rechaza (error de tipeo)',
  [{id:'1',name:'Afiliados activos '+haceDias(-3)+'.xlsx'}],
  r => r.ok === false && r.error === 'fecha_futura');

t('el límite son 7 días: a los 7 pasa',
  [{id:'1',name:'Afiliados activos '+haceDias(7)+'.xlsx'}],
  r => r.ok === true);
t('y a los 8 no',
  [{id:'1',name:'Afiliados activos '+haceDias(8)+'.xlsx'}],
  r => r.ok === false && r.error === 'archivo_viejo');

console.log(`\n${mal ? mal + ' FALLOS' : 'todo en verde'}  (${ok} comprobaciones)\n`);
process.exit(mal ? 1 : 0);
