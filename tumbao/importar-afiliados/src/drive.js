// Google Drive con cuenta de servicio (reemplaza el OAuth2 de n8n).
// La carpeta 'Miembros Activos' tiene que estar compartida (lector) con el
// correo de la cuenta de servicio.
const SCOPE = "https://www.googleapis.com/auth/drive.readonly";
const API = "https://www.googleapis.com/drive/v3/files";

const b64url = (data) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

const pemADer = (pem) => {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(b64);
  const der = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) der[i] = bin.charCodeAt(i);
  return der.buffer;
};

async function revisar(res, que) {
  if (res.ok) return res;
  const cuerpo = (await res.text().catch(() => "")).slice(0, 300);
  throw new Error(`${que}: HTTP ${res.status} ${cuerpo}`);
}

export async function tokenDeAcceso(sa) {
  const ahora = Math.floor(Date.now() / 1000);
  const aud = sa.token_uri || "https://oauth2.googleapis.com/token";
  const cuerpo = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" })) + "." +
    b64url(JSON.stringify({ iss: sa.client_email, scope: SCOPE, aud, iat: ahora, exp: ahora + 3600 }));
  const llave = await crypto.subtle.importKey("pkcs8", pemADer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const firma = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", llave, new TextEncoder().encode(cuerpo));

  const res = await revisar(await fetch(aud, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: cuerpo + "." + b64url(firma),
    }),
  }), "Google token");
  return (await res.json()).access_token;
}

// Lista todo lo que cumpla la consulta (con paginacion), solo id y nombre.
export async function listar(token, q) {
  const todos = [];
  let pageToken;
  do {
    const url = new URL(API);
    url.search = new URLSearchParams({
      q, pageSize: "1000", fields: "nextPageToken,files(id,name)",
      supportsAllDrives: "true", includeItemsFromAllDrives: "true",
      ...(pageToken ? { pageToken } : {}),
    });
    const res = await revisar(await fetch(url, { headers: { Authorization: `Bearer ${token}` } }), "Drive listar");
    const j = await res.json();
    todos.push(...(j.files || []));
    pageToken = j.nextPageToken;
  } while (pageToken);
  return todos;
}

export async function descargar(token, fileId) {
  const url = `${API}/${encodeURIComponent(fileId)}?alt=media&supportsAllDrives=true`;
  const res = await revisar(await fetch(url, { headers: { Authorization: `Bearer ${token}` } }), "Drive descargar");
  return res.arrayBuffer();
}
