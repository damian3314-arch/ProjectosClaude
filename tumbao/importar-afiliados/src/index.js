// Tumbao · Importar afiliados y recalcular cupos
// Corre a las 9:30 pm y a las 8:00 am (Bogota). Importa el reporte mas reciente
// que encuentre, asi que correr dos veces no hace dano.
import { tokenDeAcceso, listar, descargar } from "./drive.js";
import { elegirAnio, armarConsulta } from "./carpetas.js";
import { elegirCandidatos } from "./candidatos.js";
import { leerFilas } from "./xlsx.js";
import { parsearAfiliados } from "./parser.js";
import { importarMembresias } from "./supabase.js";

const SOLO_CARPETAS = (id) => `'${id}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false`;
const ETIQUETA_HORA = { "07:00:00": "7:00 am", "08:00:00": "8:00 am", "09:00:00": "9:00 am", "18:00:00": "6:00 pm", "19:00:00": "7:00 pm" };

export async function run(env, { dry = false, now = new Date() } = {}) {
  const token = await tokenDeAcceso(JSON.parse(env.GOOGLE_SERVICE_ACCOUNT));

  const anio = elegirAnio(await listar(token, SOLO_CARPETAS(env.DRIVE_ROOT_FOLDER_ID)), now);
  const meses = anio.folder_id ? await listar(token, SOLO_CARPETAS(anio.folder_id)) : [];
  const donde = armarConsulta(meses, anio, now);

  const sel = elegirCandidatos(await listar(token, donde.query), now);
  if (!sel.ok) throw new Error(sel.mensaje);

  let ultimoMotivo = "motivo desconocido";
  for (const cand of sel.candidatos) {
    let parsed;
    try {
      parsed = parsearAfiliados(leerFilas(await descargar(token, cand.file_id)), cand.file_name);
    } catch (e) {
      // Un archivo que no baja o no abre no frena el resto: se prueba el siguiente.
      ultimoMotivo = `${cand.file_name}: ${e.message}`;
      console.warn(JSON.stringify({ evento: "candidato_fallido", archivo: cand.file_name, motivo: e.message }));
      continue;
    }
    if (!parsed.ok) {
      ultimoMotivo = parsed.mensaje;
      console.warn(JSON.stringify({ evento: "candidato_rechazado", archivo: cand.file_name, motivo: parsed.mensaje }));
      continue;
    }

    const lineas = Object.entries(parsed.por_hora).sort()
      .map(([h, n]) => `  ${ETIQUETA_HORA[h] || h}: ${n} con plan`);
    const base = {
      archivo: parsed.archivo, carpeta: donde.carpeta, modo_de_busqueda: donde.modo,
      aviso: [donde.aviso, cand.aviso].filter(Boolean).join(" ") || null,
      fila_cabecera: parsed.fila_cabecera, descartados: parsed.descartados,
      detalle_descartes: parsed.detalle_descartes,
    };
    const resumen = `Archivo: ${parsed.archivo}` + (donde.carpeta ? `\nCarpeta: ${donde.carpeta}` : "") +
      (base.aviso ? `\nOJO: ${base.aviso}` : "") + "\n" + lineas.join("\n");

    if (dry) {
      return { dry: true, ok: true, ...base, afiliados_a_importar: parsed.total, resumen };
    }

    const d = await importarMembresias(env, parsed.filas);
    const out = {
      ok: !!d && d.ok === true, ...base,
      afiliados_importados: d?.membresias ?? parsed.total,
      clases_actualizadas: d?.cupos?.clases_actualizadas ?? null,
      clases_apretadas: d?.cupos?.clases_sobrevendidas_por_reservas_previas ?? null,
      resumen,
    };
    console.log(JSON.stringify({ evento: "importacion", ...out }));
    // Si la funcion SQL dice ok:false (p. ej. archivo vacio) la corrida debe verse roja.
    if (!out.ok) throw new Error("importar_membresias devolvio ok != true: " + JSON.stringify(d));
    return out;
  }

  throw new Error(
    `No se importaron afiliados: se intentaron ${sel.candidatos.length} archivos y ninguno se pudo leer (` +
    sel.candidatos.map((c) => c.file_name).join(", ") + `). Ultimo motivo: ${ultimoMotivo}. ` +
    "No se toco la tabla de membresias, asi que los cupos quedaron como estaban.");
}

export default {
  // Cron: si run() lanza, la invocacion queda marcada como fallida en Cloudflare.
  async scheduled(_event, env) {
    await run(env);
  },

  // Prueba en seco, nunca escribe en Supabase: GET /run?dry=1 con Authorization: Bearer <RUN_TOKEN>.
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.pathname !== "/run" || !env.RUN_TOKEN) return new Response("Not found", { status: 404 });
    if (req.headers.get("Authorization") !== `Bearer ${env.RUN_TOKEN}`) return new Response("Unauthorized", { status: 401 });
    if (url.searchParams.get("dry") !== "1") return new Response("Solo se permite ?dry=1", { status: 400 });
    try {
      return Response.json(await run(env, { dry: true }));
    } catch (e) {
      return Response.json({ ok: false, error: e.message }, { status: 500 });
    }
  },
};
