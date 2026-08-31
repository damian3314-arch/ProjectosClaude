/* ---------------------------------------------------------------------
 * Sacar el texto legible de un correo crudo.
 *
 * POR QUÉ HACE FALTA ESTO
 * En n8n este problema no existía: la API de Gmail entregaba el cuerpo
 * ya decodificado en `json.text`. Cloudflare entrega el correo tal como
 * viaja por SMTP, así que hay que abrirlo a mano: encontrar la parte de
 * texto dentro del multipart y deshacer la codificación de transporte.
 *
 * Se escribió contra un correo REAL de alerta de Bancolombia reenviado
 * al buzón el 31 de agosto: multipart/alternative con text/plain y
 * text/html, los dos en quoted-printable y UTF-8. Las pruebas usan esa
 * misma estructura con los nombres y las cuentas cambiadas.
 *
 * No se usa una librería de MIME a propósito: haría falta meter un
 * paquete y un paso de bundling en un Worker que hoy no tiene ninguno,
 * para resolver un caso muy acotado —correos de un solo remitente, con
 * una estructura que ya conocemos—. Si algún día llegan correos raros
 * (adjuntos, anidados de verdad), esto se cambia por postal-mime.
 * ------------------------------------------------------------------- */

/** Lee una cabecera, juntando antes las líneas continuadas. */
export function cabecera(texto, nombre) {
  const plano = texto.replace(/\r?\n[ \t]+/g, ' ');
  const re = new RegExp('^' + nombre + ':[ \\t]*(.*)$', 'im');
  const m = re.exec(plano);
  return m ? m[1].trim() : '';
}

/** base64 → texto. En un Worker no hay Buffer, solo atob. */
function deBase64(cuerpo, charset) {
  const limpio = cuerpo.replace(/[^A-Za-z0-9+/=]/g, '');
  if (!limpio) return '';
  try {
    const bin = atob(limpio);
    const bytes = Uint8Array.from(bin, (ch) => ch.charCodeAt(0));
    return new TextDecoder(charset || 'utf-8').decode(bytes);
  } catch (_) {
    return '';
  }
}

/** quoted-printable → texto. Es lo que usa Gmail al reenviar. */
function deQuotedPrintable(cuerpo, charset) {
  // Un "=" al final de línea es un corte de línea blando: no es dato.
  const unido = cuerpo.replace(/=\r?\n/g, '');
  const bytes = [];
  for (let i = 0; i < unido.length; i++) {
    const hex = unido.slice(i + 1, i + 3);
    if (unido[i] === '=' && /^[0-9A-Fa-f]{2}$/.test(hex)) {
      bytes.push(parseInt(hex, 16));
      i += 2;
    } else {
      bytes.push(unido.charCodeAt(i) & 0xff);
    }
  }
  try {
    return new TextDecoder(charset || 'utf-8').decode(new Uint8Array(bytes));
  } catch (_) {
    return unido;
  }
}

function decodificar(cuerpo, codificacion, charset) {
  const c = (codificacion || '').toLowerCase().trim();
  if (c === 'base64') return deBase64(cuerpo, charset);
  if (c === 'quoted-printable') return deQuotedPrintable(cuerpo, charset);
  return cuerpo;
}

/**
 * Recorre el árbol del correo y devuelve las hojas de texto que
 * encuentre, ya decodificadas: [{ tipo, texto }].
 */
function hojas(crudo, profundidad = 0) {
  if (profundidad > 5) return [];

  const corte = /\r?\n\r?\n/.exec(crudo);
  if (!corte) return [];
  const cab = crudo.slice(0, corte.index);
  const cuerpo = crudo.slice(corte.index + corte[0].length);

  const tipo = cabecera(cab, 'Content-Type').toLowerCase();
  const cod = cabecera(cab, 'Content-Transfer-Encoding');
  const charset = (/charset="?([^";\s]+)/i.exec(tipo) || [])[1];

  if (tipo.startsWith('multipart/')) {
    const b = (/boundary="?([^";\s]+?)"?(?:;|$)/i.exec(tipo) || [])[1];
    if (!b) return [];
    // El separador real lleva dos guiones delante; el último lleva dos
    // detrás y cierra. Se descarta el preámbulo (lo de antes del primero).
    const trozos = cuerpo.split('--' + b);
    const dentro = trozos.slice(1).filter((t) => !/^--/.test(t));
    return dentro.flatMap((t) => hojas(t.replace(/^\r?\n/, ''), profundidad + 1));
  }

  // Una hoja sin Content-Type es text/plain por defecto (RFC 2045).
  const esTexto = !tipo || tipo.startsWith('text/');
  if (!esTexto) return [];
  return [{ tipo: tipo || 'text/plain', texto: decodificar(cuerpo, cod, charset) }];
}

/**
 * El texto del correo, listo para el parser: se prefiere text/plain, y
 * si solo hay HTML se le quitan las etiquetas.
 *
 * La normalización final es LA MISMA que hacía el nodo "Parsear correo"
 * de n8n. Tiene que serlo: el parser está afinado contra ese formato y
 * las pruebas de parser.test.js dan por hecho ese aplanado.
 */
export function textoDelCorreo(crudo) {
  const partes = hojas(String(crudo || ''));
  const plano = partes.find((p) => p.tipo.startsWith('text/plain') && p.texto.trim());
  const html = partes.find((p) => p.tipo.startsWith('text/html') && p.texto.trim());
  const bruto = (plano || html || { texto: '' }).texto;

  return bruto
    .replace(/\[[^\]]*https?:[^\]]*\]/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/\s+/g, ' ')
    .replace(/¡Listo!\s*Todo sali[oó] bien con tus movimientos\s*/i, '')
    .trim();
}

/**
 * De quién viene de verdad.
 *
 * Cuando Gmail reenvía por filtro, el sobre SMTP lo manda Google pero la
 * cabecera From: sigue siendo la del banco. Así que se mira primero la
 * cabecera y el sobre queda de respaldo.
 */
export function remitenteReal(crudo, deSobre) {
  const from = cabecera(String(crudo || ''), 'From');
  const m = /<([^>]+)>/.exec(from);
  const dir = (m ? m[1] : from).trim().toLowerCase();
  return dir || String(deSobre || '').toLowerCase();
}
