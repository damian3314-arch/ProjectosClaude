// Elige cuál archivo de Drive es el reporte de afiliados de hoy.
//
// OJO CON LA CARPETA
// En la carpeta de reportes conviven DOS cosas:
//   - los cierres de caja, que se llaman solo con la fecha:  25-07-2026.xlsx
//   - el reporte de afiliados, con prefijo:  Afiliados activos 2026-07-27.xlsx
// Si no se exigiera el prefijo, "el mas reciente" seria un cierre de caja
// y se intentaria leer como si fuera el listado de afiliados.
//
// POR QUE LA FECHA VA EN EL NOMBRE
// La operacion de busqueda de Drive NO devuelve fecha de modificacion —
// solo id, nombre y poco mas. El nombre es la unica senal fiable de que
// dia es el reporte.
//
// POR QUE IMPORTA QUE ESTE FRESCO
// Las membresias traen inicio y fin, asi que las vencidas se descuentan
// solas. Pero quien se afilio DESPUES del archivo no aparece: el sistema
// cree que hay menos gente con plan de la que hay y ofrece mas clases
// sueltas de las que caben. O sea, sobrevende. Por eso se mide el atraso
// y se frena si es absurdo.

const MAX_DIAS_ATRASO = 7;

const hoyBogota = () => {
  const s = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Bogota", year: "numeric", month: "2-digit", day: "2-digit"
  }).format(new Date());
  const [a, m, d] = s.split("-").map(Number);
  return Date.UTC(a, m - 1, d);
};

// Solo AAAA-MM-DD. No se acepta DD-MM-AAAA a proposito: asi se llaman los
// cierres de caja, y confundirlos seria peor que no encontrar nada.
const fechaDelNombre = (nombre) => {
  const m = /(\d{4})-(\d{2})-(\d{2})/.exec(String(nombre || ""));
  if (!m) return null;
  const a = +m[1], mes = +m[2], d = +m[3];
  if (mes < 1 || mes > 12 || d < 1 || d > 31) return null;
  return Date.UTC(a, mes - 1, d);
};

// Sufijo incremental del navegador: "... Activa (5).xlsx". Solo se usa
// como desempate para los archivos viejos que aun no tienen fecha.
const sufijo = (nombre) => {
  const m = /\((\d+)\)\s*\.[a-z]+$/i.exec(String(nombre || ""));
  return m ? parseInt(m[1], 10) : 0;
};

const candidatos = $input.all()
  .map(i => i.json)
  .filter(f => f && f.id && /afiliado/i.test(f.name || ""));

if (!candidatos.length) {
  return [{ json: { ok: false, error: "sin_archivo",
    mensaje: "No hay ningun archivo con 'Afiliados' en el nombre dentro de la carpeta de reportes. " +
             "Revisa que el archivo del dia se haya guardado ahi." } }];
}

const conFecha = candidatos
  .map(f => ({ ...f, fecha: fechaDelNombre(f.name) }))
  .filter(f => f.fecha !== null);

const hoy = hoyBogota();
let elegido, atraso, comoSeEligio;

if (conFecha.length) {
  conFecha.sort((a, b) => b.fecha - a.fecha);
  elegido = conFecha[0];
  atraso = Math.round((hoy - elegido.fecha) / 86400000);
  comoSeEligio = "fecha en el nombre";
} else {
  // Ningun archivo trae fecha todavia. Se usa el sufijo para no quedarse
  // sin importar durante la transicion, pero no se sabe de que dia es.
  const orden = [...candidatos].sort(
    (a, b) => sufijo(b.name) - sufijo(a.name) || String(b.name).localeCompare(String(a.name)));
  elegido = orden[0];
  atraso = null;
  comoSeEligio = "sufijo (n), porque ningun archivo trae fecha en el nombre";
}

// Un archivo del futuro casi siempre es un error de tipeo en el nombre.
if (atraso !== null && atraso < 0) {
  return [{ json: { ok: false, error: "fecha_futura", file_name: elegido.name,
    mensaje: "El archivo mas reciente dice " + elegido.name +
             ", que es una fecha futura. Revisa el nombre." } }];
}

if (atraso !== null && atraso > MAX_DIAS_ATRASO) {
  return [{ json: { ok: false, error: "archivo_viejo",
    file_name: elegido.name, dias_de_atraso: atraso,
    mensaje: "El reporte mas nuevo es de hace " + atraso + " dias (" + elegido.name +
             "). No se importa: con datos tan viejos se pueden vender cupos que no existen." } }];
}

return [{ json: {
  ok: true,
  file_id: elegido.id,
  file_name: elegido.name,
  dias_de_atraso: atraso,
  como_se_eligio: comoSeEligio,
  candidatos: candidatos.length,
  // Lo normal es 1: el reporte se genera al cerrar el dia, asi que en la
  // corrida de la manana el mas nuevo es el de ayer.
  aviso: atraso === null
    ? "Sin fecha en el nombre; no se puede saber de que dia es el reporte."
    : (atraso > 2 ? "El reporte tiene " + atraso + " dias de atraso." : null)
} }];
