// Recorrido completo con Drive y Supabase simulados (datos dummy, nada real).
import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import * as XLSX from "xlsx";
import { run } from "../src/index.js";

const AHORA = new Date("2026-10-14T15:00:00Z");
const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const SA = { client_email: "bot@demo.iam.gserviceaccount.com", token_uri: "https://oauth2.googleapis.com/token",
  private_key: privateKey.export({ type: "pkcs8", format: "pem" }) };

const CAB = ["Afiliado", "Membresia", "# Documento", "Celular", "Correo", "Inicio Membresia", "Final Membresia"];
const xlsx = (filas) => {
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(filas), "Sheet1");
  const b = XLSX.write(wb, { type: "buffer", bookType: "xlsx" });
  return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
};
const COMPLETO = xlsx([["Reporte"], CAB,
  ["Ana", "Plan 7:00 am", "1", "300", "a@x.co", "01/oct./2026", "31/oct./2026"],
  ["Luis", "Media 6:00 pm", "2", "", "", "01/oct./2026", "31/oct./2026"]]);
const PARCIAL = xlsx([["Afiliado Titular", "Clase"], ["Ana", "x"]]);

const ARBOL = {
  raiz: [{ id: "y26", name: "2026" }],
  y26: [{ id: "m10", name: "10_Octubre" }],
  m10: [{ id: "f1", name: "Afiliados activos 2026-10-13.xlsx" }, { id: "f2", name: "Afiliados activos 2026-10-13 (7pm).xls" },
    { id: "f0", name: "13-10-2026.xlsx" }],
};
const ENV = { GOOGLE_SERVICE_ACCOUNT: JSON.stringify(SA), SUPABASE_URL: "https://sb.test", SUPABASE_SERVICE_KEY: "k",
  DRIVE_ROOT_FOLDER_ID: "raiz" };

let llamadas, original, supabase;
beforeEach(() => {
  llamadas = []; original = globalThis.fetch;
  supabase = () => Response.json({ ok: true, membresias: 2, cupos: { clases_actualizadas: 5, clases_sobrevendidas_por_reservas_previas: 1 } });
  globalThis.fetch = async (url, init = {}) => {
    const u = new URL(String(url)); llamadas.push(u.href + (u.host === "sb.test" ? " " + init.body : ""));
    if (u.host === "oauth2.googleapis.com") return Response.json({ access_token: "tok" });
    if (u.host === "sb.test") return supabase();
    if (u.pathname.endsWith("/files")) {
      const q = u.searchParams.get("q");
      const padre = Object.keys(ARBOL).find((k) => q.includes(`'${k}' in parents`));
      return Response.json({ files: ARBOL[padre] || [] });
    }
    const id = u.pathname.split("/").pop();
    return new Response(id === "f1" ? COMPLETO : PARCIAL);
  };
});
afterEach(() => { globalThis.fetch = original; });

test("flujo feliz: importa el reporte completo y resume", async () => {
  const r = await run(ENV, { now: AHORA });
  assert.equal(r.ok, true);
  assert.equal(r.archivo, "Afiliados activos 2026-10-13.xlsx");
  assert.equal(r.carpeta, "10_Octubre");
  assert.equal(r.afiliados_importados, 2);
  assert.match(r.resumen, /7:00 am: 1 con plan/);
  const sb = llamadas.find((l) => l.includes("sb.test"));
  assert.match(sb, /"p_filas":\[\{"afiliado":"Ana"/);
});

test("dry run: no llama a Supabase", async () => {
  const r = await run(ENV, { now: AHORA, dry: true });
  assert.equal(r.dry, true);
  assert.equal(r.afiliados_a_importar, 2);
  assert.ok(!llamadas.some((l) => l.includes("sb.test")));
});

test("si el mas nuevo no sirve, prueba el siguiente", async () => {
  ARBOL.m10 = [{ id: "f2", name: "Afiliados activos 2026-10-13.xlsx" }, { id: "f1", name: "Afiliados activos 2026-10-12.xlsx" }];
  try {
    const r = await run(ENV, { now: AHORA });
    assert.equal(r.archivo, "Afiliados activos 2026-10-12.xlsx");
  } finally {
    ARBOL.m10 = [{ id: "f1", name: "Afiliados activos 2026-10-13.xlsx" }];
  }
});

test("si ninguno se puede leer: falla y NO toca Supabase", async () => {
  ARBOL.m10 = [{ id: "f2", name: "Afiliados activos 2026-10-13.xlsx" }];
  await assert.rejects(run(ENV, { now: AHORA }), /ninguno se pudo leer/);
  assert.ok(!llamadas.some((l) => l.includes("sb.test")));
});

test("Supabase con HTTP error o ok:false: la corrida falla", async () => {
  ARBOL.m10 = [{ id: "f1", name: "Afiliados activos 2026-10-13.xlsx" }];
  supabase = () => new Response("boom", { status: 500 });
  await assert.rejects(run(ENV, { now: AHORA }), /HTTP 500/);
  supabase = () => Response.json({ ok: false, error: "archivo vacio" });
  await assert.rejects(run(ENV, { now: AHORA }), /ok != true/);
});
