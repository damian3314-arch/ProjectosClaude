# Racionamiento de n8n — 31 de agosto de 2026

## Qué pasó

El plan de n8n son 2.500 ejecuciones al mes. El 30 de agosto iban
2.494, faltando día y medio para que el contador se reinicie el 1 de
septiembre.

## Qué NO estaba en riesgo

La página. Se comprobó con datos, no de memoria: el 31 de agosto los
workflows `Tumbao · API de reservas`, `Tumbao · Panel de admin` y
`Tumbao · Leer comprobante` registraron **cero** ejecuciones, porque
`docs/index.html` y `docs/admin.html` apuntan al Worker `tumbao-caja` y
el lector de comprobantes también se copió al Worker. Aunque n8n se
apague entero, tumbaobaila.com sigue reservando y cobrando.

Lo único que vive todavía en n8n y toca dinero es la **ingesta de
pagos** (`hf3zdlQSeBM0tWF5`): leer las alertas de Bancolombia de Gmail y
llamar a `registrar_pago_y_conciliar()`.

## Por qué se gastaban tantas

El disparador de Gmail sondeaba **cada minuto** de 6am a 10pm. n8n solo
cuenta una ejecución cuando el sondeo encuentra correo nuevo, así que el
gasto no era una por minuto: era **una por alerta del banco**, ~15 al
día.

A eso se le sumaba, hasta el 30 de agosto, el empujón `avisarRevisionInmediata`
del Worker, que llamaba al webhook `Revisar ahora` cada vez que alguien
subía un comprobante. Eso **duplicaba** el gasto: en el historial del
26 al 29 de agosto casi cada ejecución `trigger` viene emparejada con
una `webhook` 30 segundos antes. Se apagó el 30 de agosto y desde
entonces no hay ni una ejecución en modo `webhook`.

## La contingencia del 31 de agosto

Con ~6 ejecuciones disponibles y el grueso de los pagos todavía por
llegar (la tarde-noche concentra dos tercios), sondear seguido las
gastaba antes de las 7pm.

La salida no es sondear menos veces al azar, es **agrupar**: una sola
ejecución procesa hasta 25 correos (`maxResults: 25`) y el filtro de
Gmail ya pide `newer_than:1d`. Así que barrer cada tres horas cuesta una
ejecución y recoge todo lo que llegó en esas tres horas.

Esto es seguro por una razón concreta, no por optimismo: `pagos` tiene
un índice ÚNICO sobre `hoja_fila` (el `gmail_id` del correo),
`pagos_por_correo`. Reprocesar un correo ya registrado no puede
duplicar el pago.

### El cambio

Nodo `Correo de Bancolombia`, parámetro `pollTimes.item`.

**Antes (y a lo que hay que volver el 1 de septiembre):**

```json
[{ "mode": "custom", "cronExpression": "0 * 6-21 * * *" },
 { "mode": "custom", "cronExpression": "0 */15 22-23,0-5 * * *" }]
```

**Durante el racionamiento:**

```json
[{ "mode": "custom", "cronExpression": "0 0 14,17,20,23 * * *" }]
```

Cuatro barridos (2pm, 5pm, 8pm, 11pm hora Bogotá), dejando dos
ejecuciones de reserva por si hay que disparar `Revisar ahora` a mano.

### Lo que cuesta

Hasta tres horas de espera para que un pago se concilie solo. No se
pierde nada: la reserva se queda en `verificando` y aparece en la cola
del panel, donde se confirma a mano con la referencia del comprobante
(migración 0056). `Tumbao · Liberar cupos vencidos` está inactivo, así
que el cupo no se suelta mientras espera.

## El 1 de septiembre

1. Devolver el `pollTimes` de arriba.
2. Republicar los cuatro workflows despublicados el 30 de agosto:
   `mN8KBkmjUpdw8Veo` (Joyería Documentos), `ewI6PvQhe1uwIzYe`
   (Joyería Cierre), `aIJJqVGyoFhW8IIm` (Importar afiliados),
   `YcOzbznaDK2sx5qF` (Reporte de opiniones). Al republicar el de
   Joyería, revisar que no se haya saltado ninguna factura del 30 y 31.

## Lo que no urge tanto como parecía

Mover la ingesta al Worker `tumbao-correo` necesita que Gmail reenvíe a
`pagos@tumbaobaila.com`, y eso está bloqueado: entrar a la cuenta de
Gmail de Tumbao pide aprobación en el celular de la academia.

No es una urgencia. Con el empujón del Worker apagado, la ingesta gasta
~15 ejecuciones al día = ~450 al mes, y Joyería otras ~350. Eso cabe de
sobra en 2.500. La crisis era del último día de agosto, no del modelo.
La migración al Worker sigue valiendo la pena —quita la dependencia de
n8n y de Google— pero puede esperar a que haya acceso al celular.
