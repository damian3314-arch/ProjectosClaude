import * as XLSX from "xlsx";

// Primera hoja con datos como filas de texto (sin cabecera, celdas vacias = "").
// Prefiere 'Sheet1' (como el nodo de n8n); si no existe, la primera.
// Sirve para .xlsx y .xls.
export function leerFilas(buffer) {
  const wb = XLSX.read(new Uint8Array(buffer), { type: "array" });
  const nombre = wb.SheetNames.includes("Sheet1") ? "Sheet1" : wb.SheetNames[0];
  if (!nombre) return [];
  return XLSX.utils.sheet_to_json(wb.Sheets[nombre], { header: 1, raw: false, defval: "", blankrows: true });
}
