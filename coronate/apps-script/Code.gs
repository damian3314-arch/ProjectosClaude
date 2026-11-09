/**
 * Recibe las citas de la landing, las guarda en una hoja de Google y crea el evento en Google Calendar.
 * NO PROBADO desde el repositorio: pruébalo con una cita de prueba antes del día de prueba (14 nov).
 *
 * Pasos:
 *  1. Crea una hoja de cálculo de Google y copia su ID (lo que va entre /d/ y /edit en la URL).
 *  2. En la hoja: Extensiones > Apps Script. Pega este archivo.
 *  3. Cambia SHEET_ID. Si usas un calendario compartido, cambia CALENDAR_ID (en Calendar > Configuración > ID del calendario).
 *  4. Implementar > Nueva implementación > Aplicación web. Ejecutar como: tú. Quién tiene acceso: Cualquier usuario.
 *  5. Copia la URL que termina en /exec y pégala en assets/config.js > agenda.endpoint.
 */
var SHEET_ID = 'PEGA_AQUI_EL_ID_DE_LA_HOJA';
var SHEET_NAME = 'Citas';
var CALENDAR_ID = 'primary';
var CUPOS_POR_BLOQUE = 2;
var DURACION_MIN = 30;

function hoja_() {
  var ss = SpreadsheetApp.openById(SHEET_ID);
  var sh = ss.getSheetByName(SHEET_NAME) || ss.insertSheet(SHEET_NAME);
  if (sh.getLastRow() === 0) sh.appendRow(['Creada', 'Día', 'Hora', 'Nombre', 'WhatsApp', 'Joyas', 'Acompañantes', 'Nota', 'Origen', 'EventoId']);
  return sh;
}

function json_(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}

// GET ?fecha=2026-11-21 -> { taken: { "09:00": 1, "09:30": 2 } }
function doGet(e) {
  var fecha = e && e.parameter && e.parameter.fecha;
  var taken = {};
  if (fecha) {
    var rows = hoja_().getDataRange().getValues().slice(1);
    rows.forEach(function (r) {
      var f = Utilities.formatDate(new Date(r[1]), 'America/Bogota', 'yyyy-MM-dd');
      var h = String(r[2]).length > 5 ? Utilities.formatDate(new Date(r[2]), 'America/Bogota', 'HH:mm') : String(r[2]);
      if (f === fecha) taken[h] = (taken[h] || 0) + 1;
    });
  }
  return json_({ taken: taken });
}

// POST con el JSON de la cita (texto plano para evitar problemas de CORS)
function doPost(e) {
  var lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    var c = JSON.parse(e.postData.contents);
    var inicio = new Date(c.f + 'T' + c.h + ':00-05:00');
    var fin = new Date(inicio.getTime() + DURACION_MIN * 60000);

    // Cupo: si el bloque ya está lleno no se crea el evento (la fila queda marcada para revisar)
    var ocupados = 0;
    hoja_().getDataRange().getValues().slice(1).forEach(function (r) {
      var f = Utilities.formatDate(new Date(r[1]), 'America/Bogota', 'yyyy-MM-dd');
      var h = String(r[2]).length > 5 ? Utilities.formatDate(new Date(r[2]), 'America/Bogota', 'HH:mm') : String(r[2]);
      if (f === c.f && h === c.h) ocupados++;
    });
    var lleno = ocupados >= CUPOS_POR_BLOQUE;

    var eventoId = '';
    if (!lleno) {
      var ev = CalendarApp.getCalendarById(CALENDAR_ID === 'primary' ? Session.getActiveUser().getEmail() : CALENDAR_ID)
        .createEvent('Sábado de Realeza · ' + c.nombre, inicio, fin, {
          description: 'WhatsApp: ' + c.tel + '\nJoyas: ' + c.joyas + '\nAcompañantes: ' + c.acomp + '\nNota: ' + (c.nota || '')
        });
      eventoId = ev.getId();
    }
    hoja_().appendRow([new Date(), c.f, c.h, c.nombre, c.tel, c.joyas, c.acomp, (lleno ? '[BLOQUE LLENO] ' : '') + (c.nota || ''), c.origen || 'web', eventoId]);
    return json_({ ok: true, lleno: lleno });
  } catch (err) {
    return json_({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}
