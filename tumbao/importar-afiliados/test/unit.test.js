import { test } from "node:test";
import assert from "node:assert/strict";
import { parsearAfiliados } from "../src/parser.js";
import { elegirCandidatos } from "../src/candidatos.js";
import { elegirAnio, armarConsulta } from "../src/carpetas.js";

// 2026-10-14 10:00 Bogota
const AHORA = new Date("2026-10-14T15:00:00Z");

const CAB = ["Afiliado", "Membresia", "# Documento", "Celular", "Correo", "Inicio Membresia", "Final Membresia"];

test("parser: cabecera corrida, horas y fechas", () => {
  const r = parsearAfiliados([
    ["Reporte de afiliados activos"], [], ["Filtros: todos"], CAB,
    ["Ana Perez", "Plan 7:00 am", "123", "300", "a@x.co", "01/oct./2026", "31/oct./2026"],
    ["Luis Gil", "Media 7:00 pm", "456", "", "", "15/sep./2026", "15/oct./2026"],
    ["Sin Fecha", "Plan 6:00 pm", "", "", "", "", ""],
  ], "demo.xlsx");
  assert.equal(r.ok, true);
  assert.equal(r.fila_cabecera, 4);
  assert.equal(r.total, 2);
  assert.equal(r.descartados, 1);
  assert.equal(r.filas[0].hora, "07:00:00");
  assert.equal(r.filas[0].tipo, "plan");
  assert.equal(r.filas[0].inicio, "2026-10-01");
  assert.equal(r.filas[1].hora, "19:00:00");
  assert.equal(r.filas[1].tipo, "media");
  assert.equal(r.filas[1].celular, null);
  assert.deepEqual(r.por_hora, { "07:00:00": 1, "19:00:00": 1 });
});

test("parser: 12 am / 12 pm", () => {
  const r = parsearAfiliados([CAB,
    ["A", "Plan 12:00 pm", "", "", "", "1/ene./2026", "2/ene./2026"],
    ["B", "Plan 12:30 am", "", "", "", "1/ene./2026", "2/ene./2026"]]);
  assert.equal(r.filas[0].hora, "12:00:00");
  assert.equal(r.filas[1].hora, "00:30:00");
});

test("parser: rechaza export de un solo horario ('Afiliado Titular')", () => {
  const r = parsearAfiliados([["Afiliado Titular", "Clase", "Hora"], ["Ana", "x", "7pm"]], "x (7pm).xls");
  assert.equal(r.ok, false);
  assert.equal(r.error, "sin_cabecera");
});

test("parser: un titulo suelto con 'Afiliado' no gana a la cabecera real", () => {
  const r = parsearAfiliados([["Afiliado"], CAB,
    ["Ana", "Plan 7:00 am", "", "", "", "1/oct./2026", "31/oct./2026"]]);
  assert.equal(r.ok, true);
  assert.equal(r.fila_cabecera, 2);
});

test("candidatos: ignora cierres de caja y manda el mas nuevo completo primero", () => {
  const r = elegirCandidatos([
    { id: "1", name: "13-10-2026.xlsx" },
    { id: "2", name: "Afiliados activos 2026-10-13.xlsx" },
    { id: "3", name: "Afiliados activos 2026-10-13 (7pm).xls" },
    { id: "4", name: "Miembros activos 2026-10-12.xlsx" },
    { id: "5", name: "Afiliados activos 2026-10-01.xlsx" },
  ], AHORA);
  assert.equal(r.ok, true);
  assert.deepEqual(r.candidatos.map((c) => c.file_id), ["2", "3", "4"]);
  assert.equal(r.candidatos[1].parcial, true);
  assert.equal(r.candidatos[0].dias_de_atraso, 1);
});

test("candidatos: errores explicitos", () => {
  assert.equal(elegirCandidatos([{ id: "1", name: "13-10-2026.xlsx" }], AHORA).error, "sin_archivo");
  assert.equal(elegirCandidatos([{ id: "1", name: "Afiliados activos.xlsx" }], AHORA).error, "sin_fecha_en_el_nombre");
  assert.equal(elegirCandidatos([{ id: "1", name: "Afiliados 2026-10-01.xlsx" }], AHORA).error, "archivo_viejo");
  assert.equal(elegirCandidatos([{ id: "1", name: "Afiliados 2026-10-20.xlsx" }], AHORA).error, "fecha_futura");
});

test("candidatos: usa el dia de Bogota, no el de UTC (cron de las 02:30 UTC)", () => {
  const r = elegirCandidatos([{ id: "1", name: "Afiliados activos 2026-10-13.xlsx" }],
    new Date("2026-10-14T02:30:00Z")); // 21:30 del 13 en Bogota
  assert.equal(r.candidatos[0].dias_de_atraso, 0);
});

test("carpetas: anio exacto, y el mas alto si falta el actual", () => {
  const cs = [{ id: "a", name: "2025" }, { id: "b", name: "2026" }];
  assert.equal(elegirAnio(cs, AHORA).folder_id, "b");
  const r = elegirAnio([{ id: "a", name: "2025" }], AHORA);
  assert.equal(r.folder_id, "a");
  assert.match(r.motivo, /No existe la carpeta 2026/);
  assert.equal(elegirAnio([{ id: "z", name: "notas" }], AHORA).ok, false);
});

test("carpetas: mes por nombre (02_Marzo mal prefijada) y mes anterior", () => {
  const meses = [{ id: "m1", name: "01_Enero" }, { id: "m2", name: "02_Marzo" }, { id: "m3", name: "02_Febrero" },
    { id: "m9", name: "09_Septiembre" }, { id: "m10", name: "10_Octubre" }];
  const q = armarConsulta(meses, { folder_name: "2026" }, AHORA);
  assert.equal(q.modo, "carpeta");
  assert.equal(q.carpeta, "10_Octubre + 09_Septiembre");
  assert.equal(armarConsulta(meses, {}, new Date("2026-03-10T15:00:00Z")).carpeta, "02_Marzo + 02_Febrero");
});

test("carpetas: sin carpeta cae a busqueda global con aviso", () => {
  const q = armarConsulta([], { folder_name: "2026" }, AHORA);
  assert.equal(q.modo, "global");
  assert.match(q.aviso, /Octubre/);
});

test("carpetas: 1 de enero mira diciembre", () => {
  const q = armarConsulta([{ id: "d", name: "12_Diciembre" }], { motivo: null }, new Date("2026-01-01T15:00:00Z"));
  assert.equal(q.carpeta, "12_Diciembre");
  assert.match(q.aviso, /Todavia no existe la carpeta de Enero/);
});
