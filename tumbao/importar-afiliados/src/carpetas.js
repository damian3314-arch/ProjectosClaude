// Resuelve en CADA corrida la carpeta del anio y del mes. Nunca ids fijos
// (salvo la raiz 'Miembros Activos'): un id fijo se rompe el dia 1 de cada mes.
import { anioMesBogota, norm } from "./fechas.js";

const MESES = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio",
  "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"];

const GLOBAL = "(name contains 'afiliados' or name contains 'miembros') " +
  "and trashed = false and mimeType != 'application/vnd.google-apps.folder'";

const nombre = (f) => String(f.name).trim();
const validas = (l) => l.filter((f) => f && f.id && f.name);

// Carpeta del anio en curso; si no existe (1 de enero), la mas alta que haya.
export function elegirAnio(carpetas, now = new Date()) {
  const { anio } = anioMesBogota(now);
  const lista = validas(carpetas);
  const exacta = lista.find((f) => nombre(f) === anio);
  const deAnio = lista.filter((f) => /^\d{4}$/.test(nombre(f)))
    .sort((a, b) => nombre(b).localeCompare(nombre(a)));
  const elegida = exacta || deAnio[0] || null;

  if (!elegida) {
    return { ok: false, folder_id: null, anio,
      motivo: "En 'Miembros Activos' no hay ninguna carpeta con nombre de ano. Lo que hay: " +
        (lista.map(nombre).join(", ") || "(nada)") + "." };
  }
  return { ok: true, anio, folder_id: elegida.id, folder_name: nombre(elegida),
    motivo: exacta ? null : "No existe la carpeta " + anio + "; se mira " + nombre(elegida) + "." };
}

// Arma la consulta de Drive: carpeta del mes en curso + la del anterior (el dia 1
// la nueva puede no existir). Si no hay ninguna, cae a la busqueda global por
// nombre, que es peor, y deja un aviso que viaja hasta el resumen.
// El NOMBRE del mes manda sobre el numero: hay una carpeta '02_Marzo' mal prefijada.
export function armarConsulta(carpetasMeses, anio, now = new Date()) {
  const { mes: mesAhora } = anioMesBogota(now);
  const mesAntes = mesAhora === 1 ? 12 : mesAhora - 1;
  const carpetas = validas(carpetasMeses);

  const buscarMes = (m) => {
    const porNombre = carpetas.filter((f) => norm(f.name).includes(norm(MESES[m - 1])));
    if (porNombre.length) return porNombre;
    return carpetas.filter((f) => norm(f.name).startsWith(String(m).padStart(2, "0")));
  };

  const delMes = buscarMes(mesAhora);
  const delAntes = buscarMes(mesAntes).filter((f) => !delMes.some((x) => x.id === f.id));
  const aMirar = [...delMes, ...delAntes];

  if (!aMirar.length) {
    return { query: GLOBAL, modo: "global", carpeta: null,
      aviso: "No se encontro la carpeta de " + MESES[mesAhora - 1] +
        (anio && anio.folder_name ? " dentro de " + anio.folder_name : "") +
        ". Se busco en todo el Drive por nombre, que es menos seguro. Lo que hay en esa carpeta: " +
        (carpetas.map(nombre).join(", ") || "(nada)") + "." +
        (anio && anio.motivo ? " " + anio.motivo : "") };
  }

  const enParents = aMirar.map((f) => "'" + f.id + "' in parents").join(" or ");
  return {
    query: "(" + enParents + ") and trashed = false and mimeType != 'application/vnd.google-apps.folder'",
    modo: "carpeta",
    carpeta: aMirar.map(nombre).join(" + "),
    aviso: [delMes.length ? null
        : "Todavia no existe la carpeta de " + MESES[mesAhora - 1] + "; se esta mirando la de " + MESES[mesAntes - 1] + ".",
      anio && anio.motivo].filter(Boolean).join(" ") || null,
  };
}
