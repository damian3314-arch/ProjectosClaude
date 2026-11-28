/* El panel instalado como aplicación (29 oct). Este service worker NO guarda nada en caché a propósito: el panel maneja plata y
   cupos en vivo, y una pantalla vieja es peor que una pantalla lenta. Solo existe para que el celular lo trate como una app
   instalable. Todo pasa directo a la red. */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => { /* sin respuesta propia: el navegador sigue con la red */ });
