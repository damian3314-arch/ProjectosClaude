// Llama a la funcion SQL importar_membresias(p_filas) en Supabase.
export async function importarMembresias(env, filas) {
  const res = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/importar_membresias`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: env.SUPABASE_SERVICE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}`,
    },
    body: JSON.stringify({ p_filas: filas }),
  });
  const texto = await res.text();
  if (!res.ok) throw new Error(`Supabase importar_membresias: HTTP ${res.status} ${texto.slice(0, 300)}`);
  let j;
  try { j = JSON.parse(texto); } catch { throw new Error(`Supabase devolvio algo que no es JSON: ${texto.slice(0, 200)}`); }
  return Array.isArray(j) ? j[0] : j;
}
