// Elige cual archivo de Drive es el reporte de afiliados de hoy.
//
// OJO CON LA CARPETA
// En la carpeta de reportes conviven DOS cosas:
//   - los cierres de caja, que se llaman solo con la fecha:  25-07-2026.xlsx
//   - el reporte de afiliados:  Afiliados activos 2026-07-27.xlsx
// Si no se exigiera el prefijo, "el mas reciente" seria un cierre de caja
// y se leeria como si fuera el listado de afiliados.
//
// POR QUE LA FECHA VA EN EL NOMBRE
// La operacion de busqueda de Drive NO devuelve fecha de modificacion —
// solo id y nombre. El nombre es la unica senal de que dia es el reporte.
// Y ademas es la correcta: lo que importa no es cuando se subio el
// archivo, sino de que dia son los datos que trae. Un archivo de julio
// subido hoy sigue teniendo datos de julio.
//
// POR QUE IMPORTA QUE ESTE FRESCO
// Las membresias traen inicio y fin, asi que las vencidas se descuentan
// solas. Pero quien se afilio DESPUES del archivo no aparece: el sistema
// cree que hay menos gente con plan de la que hay y ofrece mas clases
// sueltas de las que caben. O sea, sobrevende.
//
// EL MENSAJE DE ERROR DICE QUE VIO
// Antes solo decia "el mas nuevo es de hace 9 dias". Cuando alguien sube
// el archivo con otro nombre, ese mensaje miente por omision: el archivo
// existe pero no se esta mirando. Ahora se lista todo lo que hay.

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

const todos = $input.all().map(i => i.json).filter(f => f && f.id && f.name);

// "Afiliados activos", "Miembros activos", "Listado de afiliados": todas
// valen. Antes solo se aceptaba /afiliado/, asi que un archivo correcto
// llamado "Miembros activos 2026-08-08.xlsx" era invisible y el error
// culpaba al archivo de julio.
const candidatos = todos.filter(f => /afiliad|miembro/i.test(f.name));
const nombres = (lista) => lista.map(f => f.name).join(", ") || "(ninguno)";

if (!candidatos.length) {
  return [{ json: { ok: false, error: "sin_archivo",
    archivos_en_la_carpeta: todos.length,
    mensaje: "No hay ningun archivo con 'afiliados' ni 'miembros' en el nombre " +
             "dentro de la carpeta de reportes. Lo que si hay: " + nombres(todos.slice(0, 12)) +
             ". Revisa que el archivo del dia se haya guardado en esa carpeta." } }];
}

const conFecha = candidatos
  .map(f => ({ ...f, fecha: fechaDelNombre(f.name) }))
  .filter(f => f.fecha !== null);
const sinFecha = candidatos.filter(f => fechaDelNombre(f.name) === null);

if (!conFecha.length) {
  return [{ json: { ok: false, error: "sin_fecha_en_el_nombre",
    mensaje: "Se encontraron " + candidatos.length + " archivos de afiliados pero " +
             "ninguno trae la fecha en el nombre en formato AAAA-MM-DD: " +
             nombres(candidatos.slice(0, 12)) +
             ". Renombralo como 'Afiliados activos 2026-08-08.xlsx'. " +
             "No se usa la fecha de subida a proposito: lo que importa es de " +
             "que dia son los datos, no cuando se guardo el archivo." } }];
}

conFecha.sort((a, b) => b.fecha - a.fecha);
const elegido = conFecha[0];
const hoy = hoyBogota();
const atraso = Math.round((hoy - elegido.fecha) / 86400000);

// Un archivo del futuro casi siempre es un error de tipeo en el nombre.
if (atraso < 0) {
  return [{ json: { ok: false, error: "fecha_futura", file_name: elegido.name,
    mensaje: "El archivo mas reciente dice " + elegido.name +
             ", que es una fecha futura. Revisa el nombre." } }];
}

if (atraso > MAX_DIAS_ATRASO) {
  return [{ json: { ok: false, error: "archivo_viejo",
    file_name: elegido.name, dias_de_atraso: atraso,
    mensaje: "El reporte con fecha mas nueva es de hace " + atraso + " dias (" +
             elegido.name + "). No se importa: con datos tan viejos se pueden " +
             "vender cupos que no existen. La carpeta tiene " + todos.length +
             " archivos en total y " + candidatos.length + " de afiliados: " +
             nombres(candidatos.slice(0, 12)) +
             (sinFecha.length
               ? ". OJO: " + sinFecha.length + " de ellos no traen fecha AAAA-MM-DD " +
                 "en el nombre y por eso no se pueden usar (" + nombres(sinFecha) + ")."
               : ".") } }];
}

return [{ json: {
  ok: true,
  file_id: elegido.id,
  file_name: elegido.name,
  dias_de_atraso: atraso,
  candidatos: candidatos.length,
  ignorados_sin_fecha: sinFecha.length ? nombres(sinFecha) : null,
  // Lo normal es 1: el reporte se genera al cerrar el dia, asi que en la
  // corrida de la manana el mas nuevo es el de ayer.
  aviso: atraso > 2 ? "El reporte tiene " + atraso + " dias de atraso." : null
} }];

// ---------------------------------------------------------------------
// CÓMO BUSCA EL ARCHIVO EL NODO DE DRIVE
//
// No por carpeta. Los reportes se guardan en una carpeta por mes, así
// que un folderId fijo se rompe el día 1 de cada mes — y se rompió: el
// workflow miraba la de julio mientras el archivo de agosto estaba en la
// suya, y el error decía "el más nuevo es de hace 9 días" sin mencionar
// que existía uno nuevo en otra parte.
//
// La consulta que usa el nodo:
//
//   (name contains 'afiliados' or name contains 'miembros')
//     and trashed = false
//     and mimeType != 'application/vnd.google-apps.folder'
//
// Lo que protege contra importar cualquier cosa no es la carpeta, es lo
// de aquí abajo: exigir AAAA-MM-DD en el nombre y menos de 7 días de
// atraso. La carpeta nunca fue una garantía.
// ---------------------------------------------------------------------
