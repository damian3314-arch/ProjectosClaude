// Elige cuales archivos de Drive pueden ser el reporte de afiliados.
// Devuelve VARIOS candidatos en orden; el siguiente se intenta solo si el
// anterior no se pudo leer.
//
// - En la carpeta conviven los cierres de caja (25-07-2026.xlsx) y el reporte
//   (Afiliados activos 2026-07-27.xlsx). Por eso el filtro por nombre se hace
//   aqui y no en Drive: asi un archivo con otro nombre no queda invisible.
// - La fecha sale del NOMBRE (AAAA-MM-DD), no de la fecha de subida: importa
//   de que dia son los datos. Con datos viejos el sistema sobrevende cupos.
// - Los exports de UN SOLO horario ("... (7pm).xls") traen ~18 filas; importarlos
//   borraria a casi todos. Van de ultimos y el parser los rechaza.
import { hoyBogota } from "./fechas.js";

export const MAX_DIAS_ATRASO = 7;
export const MAX_INTENTOS = 3;

// Solo AAAA-MM-DD. DD-MM-AAAA es de los cierres de caja y no se acepta.
const fechaDelNombre = (nombre) => {
  const m = /(\d{4})-(\d{2})-(\d{2})/.exec(String(nombre || ""));
  if (!m) return null;
  const a = +m[1], mes = +m[2], d = +m[3];
  if (mes < 1 || mes > 12 || d < 1 || d > 31) return null;
  return Date.UTC(a, mes - 1, d);
};

const esParcial = (nombre) =>
  /\([^)]*\d{1,2}\s*[:.]?\d{0,2}\s*[ap]\.?\s*m\.?[^)]*\)/i.test(String(nombre || ""));

const nombres = (lista) => lista.map((f) => f.name).join(", ") || "(ninguno)";

export function elegirCandidatos(archivos, now = new Date()) {
  const todos = archivos.filter((f) => f && f.id && f.name);
  const candidatos = todos.filter((f) => /afiliad|miembro/i.test(f.name));

  if (!candidatos.length) {
    return { ok: false, error: "sin_archivo", archivos_en_la_carpeta: todos.length,
      mensaje: "No hay ningun archivo con 'afiliados' ni 'miembros' en el nombre dentro de la " +
        "carpeta de reportes, que tiene " + todos.length + " archivos. Los mas recientes: " +
        nombres(todos.slice(0, 8)) + ". Revisa que el archivo del dia se haya guardado en ESA carpeta." };
  }

  const conFecha = candidatos
    .map((f) => ({ ...f, fecha: fechaDelNombre(f.name), parcial: esParcial(f.name) }))
    .filter((f) => f.fecha !== null);
  const sinFecha = candidatos.filter((f) => fechaDelNombre(f.name) === null);

  if (!conFecha.length) {
    return { ok: false, error: "sin_fecha_en_el_nombre",
      mensaje: "Se encontraron " + candidatos.length + " archivos de afiliados pero ninguno trae la " +
        "fecha en el nombre en formato AAAA-MM-DD: " + nombres(candidatos.slice(0, 12)) +
        ". Renombralo como 'Afiliados activos 2026-08-08.xlsx'. No se usa la fecha de subida a " +
        "proposito: lo que importa es de que dia son los datos, no cuando se guardo el archivo." };
  }

  // Primero el mas nuevo; el mismo dia, el completo antes que el de un horario.
  conFecha.sort((a, b) => (b.fecha - a.fecha) || (a.parcial - b.parcial));

  const hoy = hoyBogota(now);
  const dias = (f) => Math.round((hoy - f.fecha) / 86400000);
  const elegido = conFecha[0];
  const atraso = dias(elegido);

  if (atraso < 0) {
    return { ok: false, error: "fecha_futura", file_name: elegido.name,
      mensaje: "El archivo mas reciente dice " + elegido.name + ", que es una fecha futura. Revisa el nombre." };
  }

  if (atraso > MAX_DIAS_ATRASO) {
    return { ok: false, error: "archivo_viejo", file_name: elegido.name, dias_de_atraso: atraso,
      archivos_en_la_carpeta: todos.length,
      mensaje: "El reporte con fecha mas nueva es de hace " + atraso + " dias (" + elegido.name +
        "). No se importa: con datos tan viejos se pueden vender cupos que no existen. La carpeta tiene " +
        todos.length + " archivos en total y " + candidatos.length + " de afiliados: " +
        nombres(candidatos.slice(0, 12)) +
        (sinFecha.length
          ? ". OJO: " + sinFecha.length + " de ellos no traen fecha AAAA-MM-DD en el nombre y por eso " +
            "no se pueden usar (" + nombres(sinFecha) + ")."
          : ". Si acabas de subir el archivo del dia, se guardo en otra carpeta.") };
  }

  const viables = conFecha.filter((f) => dias(f) <= MAX_DIAS_ATRASO).slice(0, MAX_INTENTOS);

  return { ok: true, candidatos: viables.map((f, i) => ({
    file_id: f.id, file_name: f.name, parcial: f.parcial, dias_de_atraso: dias(f),
    intento: i + 1, de_cuantos: viables.length,
    ignorados_sin_fecha: sinFecha.length ? nombres(sinFecha) : null,
    aviso: i === 0 && atraso > 2 ? "El reporte tiene " + atraso + " dias de atraso." : null,
  })) };
}
