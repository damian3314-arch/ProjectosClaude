// Resuelve en QUE carpeta de Drive hay que buscar el reporte de hoy.
//
// Fuente de verdad de dos nodos del workflow "Tumbao · Importar afiliados
// y recalcular cupos": "Elegir el ano" y "Elegir el mes". Si se cambia
// aqui, se cambia alla.
//
// EL ARBOL
//   Miembros Activos/          <- id fijo, esta carpeta no cambia
//     2026/                    <- una por ano
//       08_Agosto/             <- una por mes
//         Afiliados activos 2026-08-28.xlsx
//
// POR QUE NO UN ID FIJO DE LA CARPETA DEL MES
// Porque ya se rompio asi. El workflow miraba la carpeta de julio
// mientras el archivo de agosto estaba en la suya, y el error decia "el
// mas nuevo es de hace 9 dias" sin mencionar que existia uno nuevo en
// otra parte. Un id fijo se rompe el dia 1 de cada mes, sin ruido.
//
// POR QUE SE MIRAN DOS MESES
// El dia 1 la carpeta nueva puede no estar creada todavia, y el reporte
// de anoche esta en la del mes anterior. Que sobren archivos no estorba:
// quien decide cual se usa es "Elegir los candidatos", por la fecha del
// nombre y el limite de 7 dias de atraso.
//
// POR QUE EL NOMBRE DEL MES MANDA SOBRE EL NUMERO
// En el Drive real hay una carpeta llamada "02_Marzo" — el prefijo esta
// mal escrito, deberia ser "03". Eligiendo por numero, marzo se quedaba
// sin carpeta y febrero se llevaba dos. Comprobado contra las 12
// carpetas reales: por numero fallan 2 meses, por nombre aciertan los 12.
// Conviene arreglar el nombre en Drive igual, pero el flujo ya no
// depende de eso.

const CARPETA_RAIZ = "1AV37nWzy2-UbQAvZTAMbYzTq1NM6tsHM"; // Miembros Activos

const MESES = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio",
               "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"];

// Lo que se usaba antes de mirar por carpeta, y a lo que se vuelve si la
// carpeta del mes no aparece. Es peor —puede traer archivos de cualquier
// rincon del Drive— pero es mejor que no importar nada y quedarse
// vendiendo cupos con datos viejos.
const GLOBAL = "(name contains 'afiliados' or name contains 'miembros') " +
               "and trashed = false and mimeType != 'application/vnd.google-apps.folder'";

const norm = (s) => String(s == null ? "" : s)
  .normalize("NFD").replace(/[̀-ͯ]/g, "").trim().toLowerCase();

// ---------- nodo "Elegir el ano" ----------
// De las subcarpetas de Miembros Activos, la del ano en curso. Si no
// existe (pasa el 1 de enero), la mas alta que haya: el reporte del 31
// de diciembre sigue sirviendo hasta que creen la carpeta nueva.
function elegirAno(carpetas, anio) {
  const nombre = (f) => String(f.name).trim();
  const exacta = carpetas.find(f => nombre(f) === anio);
  const deAnio = carpetas.filter(f => /^\d{4}$/.test(nombre(f)))
                         .sort((a, b) => nombre(b).localeCompare(nombre(a)));
  const elegida = exacta || deAnio[0] || null;
  if (!elegida) {
    return { ok: false, folder_id: null, anio,
      motivo: "En 'Miembros Activos' no hay ninguna carpeta con nombre de ano. " +
              "Lo que hay: " + (carpetas.map(nombre).join(", ") || "(nada)") + "." };
  }
  return { ok: true, anio, folder_id: elegida.id, folder_name: nombre(elegida),
    motivo: exacta ? null
      : "No existe la carpeta " + anio + "; se mira " + nombre(elegida) + "." };
}

// ---------- nodo "Elegir el mes" ----------
function buscarMes(carpetas, m) {
  const porNombre = carpetas.filter(f => norm(f.name).includes(norm(MESES[m - 1])));
  if (porNombre.length) return porNombre;
  return carpetas.filter(f => norm(f.name).startsWith(String(m).padStart(2, "0")));
}

function elegirMes(carpetas, mesAhora, anio) {
  const nombre = (f) => String(f.name).trim();
  const mesAntes = mesAhora === 1 ? 12 : mesAhora - 1;
  const delMes   = buscarMes(carpetas, mesAhora);
  const delAntes = buscarMes(carpetas, mesAntes).filter(f => !delMes.some(x => x.id === f.id));
  const aMirar   = [...delMes, ...delAntes];

  if (!aMirar.length) {
    return { query: GLOBAL, modo: "global", carpeta: null,
      aviso: "No se encontro la carpeta de " + MESES[mesAhora - 1] +
             (anio && anio.folder_name ? " dentro de " + anio.folder_name : "") +
             ". Se busco en todo el Drive por nombre, que es menos seguro. " +
             "Lo que hay en esa carpeta: " +
             (carpetas.map(nombre).join(", ") || "(nada)") + "." +
             (anio && anio.motivo ? " " + anio.motivo : "") };
  }

  const enParents = aMirar.map(f => "'" + f.id + "' in parents").join(" or ");
  return {
    query: "(" + enParents + ") and trashed = false " +
           "and mimeType != 'application/vnd.google-apps.folder'",
    modo: "carpeta",
    carpeta: aMirar.map(nombre).join(" + "),
    aviso: [delMes.length ? null
              : "Todavia no existe la carpeta de " + MESES[mesAhora - 1] +
                "; se esta mirando la de " + MESES[mesAntes - 1] + ".",
            anio && anio.motivo].filter(Boolean).join(" ") || null
  };
}

export { CARPETA_RAIZ, MESES, GLOBAL, elegirAno, elegirMes, buscarMes };
