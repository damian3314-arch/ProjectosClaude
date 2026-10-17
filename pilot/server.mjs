// Receptor mínimo de webhooks Kapso (piloto). Sin dependencias.
// Uso: KAPSO_API_KEY=... KAPSO_WEBHOOK_SECRET=... node server.mjs
import { createServer } from "node:http";
import { createHmac, timingSafeEqual } from "node:crypto";

const PORT = process.env.PORT || 3000;
const PHONE_NUMBER_ID = process.env.KAPSO_PHONE_NUMBER_ID || "1401782769681817";
const API_KEY = process.env.KAPSO_API_KEY;
const SECRET = process.env.KAPSO_WEBHOOK_SECRET;
const AUTO_REPLY = process.env.AUTO_REPLY === "true"; // apagado por defecto
if (!API_KEY || !SECRET) throw new Error("Faltan KAPSO_API_KEY o KAPSO_WEBHOOK_SECRET");

// `to` puede ser un teléfono o un identificador de usuario de WhatsApp (ej. "CO.1845..."),
// que Meta entrega en `from_user_id` cuando el contacto oculta su número.
async function sendText(to, body) {
  const isUserId = /^[A-Z]{2}\./.test(to);
  const r = await fetch(`https://api.kapso.ai/meta/whatsapp/v24.0/${PHONE_NUMBER_ID}/messages`, {
    method: "POST",
    headers: { "X-API-Key": API_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ messaging_product: "whatsapp", ...(isUserId ? { recipient: to } : { to }), type: "text", text: { body } }),
  });
  console.log("send:", r.status);
}

function validSignature(raw, sig) {
  if (!/^[a-f0-9]{64}$/i.test(sig || "")) return false;
  const expected = createHmac("sha256", SECRET).update(raw).digest();
  return timingSafeEqual(expected, Buffer.from(sig, "hex"));
}

createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/health") return res.end("ok");
  if (req.method !== "POST" || req.url !== "/webhooks/kapso") { res.statusCode = 404; return res.end(); }

  const chunks = [];
  for await (const c of req) chunks.push(c);
  const raw = Buffer.concat(chunks);

  if (!validSignature(raw, req.headers["x-webhook-signature"])) { res.statusCode = 401; return res.end("bad signature"); }
  res.statusCode = 200; res.end("ok"); // responder rápido, procesar después

  const event = req.headers["x-webhook-event"];
  let p; try { p = JSON.parse(raw.toString("utf8")); } catch { return; }
  console.log(event, JSON.stringify(p).slice(0, 500));

  if (event === "whatsapp.message.received" && AUTO_REPLY) {
    const m = p.message || p.data?.message || {};
    const from = m.from || m.from_user_id || p.conversation?.phone_number || p.data?.conversation?.phone_number;
    const text = m.text?.body || m.body || "";
    if (from) await sendText(from, `Recibido: "${text}". Piloto Kapso funcionando.`);
  }
}).listen(PORT, () => console.log(`Piloto Kapso escuchando en :${PORT}`));
