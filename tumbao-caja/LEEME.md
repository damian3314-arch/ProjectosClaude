# Tumbao · caja de mostrador

Puerta estrecha entre el panel de admin y Supabase, para registrar la
plata que entra y sale en el mostrador.

**En línea:** https://tumbao-caja.damian3314.workers.dev

## Por qué un Worker y no n8n

Cada venta sería una ejecución. Con 20–30 operaciones diarias son
600–900 al mes sobre un plan de 2.500. Aquí caben 100.000 al día.

## Por qué un Worker y no Supabase directo

Se podría abrir estas funciones a `anon` y que el panel hable con
Supabase de frente — es lo que se va a hacer con los horarios, que son
lecturas públicas. Para el módulo que maneja plata no: así la única
superficie pública son estos cuatro endpoints, y no toda la API de
Supabase dependiendo de que la RLS de cada tabla esté perfecta.

## La autorización no vive aquí

Vive en `verificar_token_admin()` dentro de Postgres. Este Worker no
sabe qué es un token válido, y así debe seguir. Es el mismo token del
panel: si revocas uno, deja de servir también para la caja.

## Endpoints

    POST /api/dia        { token, dia? }              lo del día y el arqueo
    POST /api/registrar  { token, sentido, concepto, valor, medio, nota? }
    POST /api/anular     { token, id }
    POST /api/cerrar     { token, contado, base?, nota? }

## Conceptos permitidos

    ingreso   clase_suelta · mensualidad · cumpleanos · otro_ingreso
    egreso    profesores · cafeteria · aseo · papeleria · otro_egreso

La lista está en el código a propósito: impide que un error de tecleo
invente una categoría nueva y ensucie el cierre.

## Secreto

    SUPABASE_SERVICE_KEY   Workers > tumbao-caja > Settings > Variables

Sin él responde 503 con un mensaje claro, en vez de fallar raro.

## CORS

Solo `tumbaobaila.com`, `www` y `tumbao.pages.dev`. Un endpoint de plata
no lleva `*`.
