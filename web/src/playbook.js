/**
 * Guiones de venta de Loggro por producto (del "Mapa de plantillas de WhatsApp" de Damián). Solo la etapa de VENTA.
 * Los enlaces se reemplazan por [AGENDA] y [VIDEO]: el agente nunca escribe enlaces, el sistema los agrega.
 */
export const PLAYBOOK = {
 "restobar": [
  {
   "situacion": "Contacto 1 (bienvenida)",
   "cuando": "Primer contacto tras el registro del cliente",
   "texto": "¡Hola! 👋 Soy Damian, asesor comercial de Loggro. Vi que te registraste y quiero ayudarte a encontrar la mejor solución para tu negocio.\n\n¿Cuál es tu mayor dolor de cabeza hoy? Por ejemplo, pedidos perdidos, inventario y facturación.\n\nSin afán — cuando tengas un espacio, [AGENDA]"
  },
  {
   "situacion": "Invitación a videollamada (plan personalizado)",
   "cuando": "Invitación directa a videollamada para conocer el programa y recibir un plan personalizado",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 👋 Contamos con un espacio de atención personalizada por videollamada, donde te mostramos cómo funciona Loggro y armamos contigo un plan ajustado a lo que necesita tu negocio.\n\n¿Te gustaría agendarlo? Aprovechamos y vemos qué día te queda mejor.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 2 – no contesta",
   "cuando": "El cliente no respondió al primer mensaje",
   "texto": "Hola [nombre], te saluda Damian de Loggro 👋 Sé que el tiempo no siempre alcanza, así que sin afán: ¿sigue vigente tu interés en organizar y automatizar el negocio?\n\nCuéntame en qué vas y seguimos desde ahí.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 3 – no contesta",
   "cuando": "Segundo intento sin respuesta — se apoya en un video de un cliente real",
   "texto": "Hola, te saluda Damian de Loggro 👋 Te dejo esto rapidito, resolviendo justo pedidos perdidos, inventario y facturación:\n\n[VIDEO]\n\n¿Se parece a lo que te pasa a ti? Cuéntame.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 4 – no contesta",
   "cuando": "Último intento del embudo antes de pausar el contacto",
   "texto": "Hola, te saluda Damian de Loggro 👋 Sin afán — si te gustaría retomar el tema de organizar tu negocio, aquí te dejo el link para agendar cuando te quede bien:[AGENDA]"
  },
  {
   "situacion": "Informativo – sin negocio",
   "cuando": "Persona con interés informativo, sin negocio propio o con un proyecto en mente",
   "texto": "¡Hola, [nombre]! 👋 Soy Damian, de Loggro.\n\nAyudamos a negocios como el que estás armando con pedidos perdidos, inventario y facturación 📊\n\n[VIDEO]\n\nCuéntame qué negocio estás armando y te digo cómo encaja Loggro.\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Informativo – con negocio",
   "cuando": "Persona con negocio activo que indica que le enviaron información por WhatsApp",
   "texto": "¡Hola, [nombre]! 👋 Soy Damian, de Loggro.\n\nCon Loggro resuelves pedidos perdidos, inventario y facturación, todo en un solo lugar 📊\n\n[VIDEO]\n\nCuéntame tu mayor dolor de cabeza hoy y te muestro justo esa parte.\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Transición a interés (agenda)",
   "cuando": "Cliente responde con interés o con su dolor — se pasa a agendar (listo para copiar y pegar)",
   "texto": "¡Hola! Soy Damian, de Loggro 👋 ¡Claro que sí! Eso es justo lo que resolvemos: pedidos, inventario y facturación en un solo lugar, sin hacerlo a mano.\n\n¿Te parece si lo vemos en una videollamada corta? Te muestro cómo aplicaría para tu negocio. ¿Hoy en la tarde o mañana te queda bien?\n\n📅 Si prefieres agendar tú mismo:[AGENDA]"
  },
  {
   "situacion": "Recordatorio de reunión",
   "cuando": "Confirmación de una reunión ya agendada",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro ✋ Te escribo para confirmar nuestra reunión de hoy/mañana a las [hora].\n\n🔗 Link: [enlace de la reunión]\n\nNos vemos ahí — cualquier cosa, me escribes por aquí."
  },
  {
   "situacion": "No asistió a la demo",
   "cuando": "El cliente no llegó a la videollamada agendada",
   "texto": "¡Hola, [nombre]! Te saluda Damian de Loggro 👋 Suena como que surgió algo de último momento — nos pasa a todos.\n\nSin afán, ¿buscamos otro espacio esta semana? [¿Hoy en la tarde o mañana?]\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Levantamiento de info (cotización)",
   "cuando": "El cliente pide precio o cotización directamente — se recopila lo necesario antes de armar la propuesta",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 👋 ¡Listo! Para armar tu cotización, cuéntame:\n\n1️⃣ ¿Cuántos puntos de venta o sedes tienes?\n2️⃣ ¿Cuántos usuarios van a usar el sistema (meseros, cajeros, cocina)?\n3️⃣ ¿Facturas electrónicamente hoy? (Sí/No)\n4️⃣ ¿Necesitas control de inventario y recetas/insumos?\n5️⃣ ¿Tienes algún requerimiento especial? (ej. varias sedes, comandas a cocina/KDS, domicilios, integración con otro software, etc.)\n\nCon eso te armo la propuesta. 🙌"
  },
  {
   "situacion": "Envío de cotización",
   "cuando": "Justo después de la demo/reunión — se envía adjunta o en link la cotización formal",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 Con mucho gusto te comparto la propuesta que armamos pensando en tu negocio 📄👇\n\n[adjuntar cotización]\n\nLos precios de lista y la promo de tu primera compra van marcados por separado, para que los tengas clarísimos.\n\nCuando la revises, cuéntame qué te pareció. Si algo no te cuadra lo ajustamos juntos, y si todo te gusta, arrancamos y yo te acompaño en cada paso 🙌"
  },
  {
   "situacion": "Seguimiento post-demo",
   "cuando": "Después de la demo y con una propuesta ya enviada",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 ¿Cómo te fue revisando la propuesta? Me encantaría saber qué pensaste.\n\nSi hay algo que te genere duda (el precio, los tiempos, cómo funciona), cuéntame sin pena y lo miramos juntos. Y si ya te sientes listo, yo me encargo de dejarte todo andando 🚀"
  },
  {
   "situacion": "Cierre sin respuesta",
   "cuando": "Después de demo o propuesta, sin respuesta del cliente",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 Quería saber cómo vas con la decisión. Sé que estas cosas se piensan con calma, y está muy bien.\n\nPara ayudarte mejor, respóndeme con el número que más se parezca a ti:\n1️⃣ Quiero avanzar\n2️⃣ Tengo una duda y me gustaría resolverla\n3️⃣ Prefiero esperar un tiempo\n\nCualquiera de las tres me sirve, así sé cómo acompañarte 🤝"
  },
  {
   "situacion": "Último mensaje de cierre",
   "cuando": "Cierre formal del ciclo tras varios intentos sin respuesta — se apoya en el mismo video de caso real para reforzar confianza",
   "texto": "Hola [nombre], te saluda Damian de Loggro 😊 Muchas gracias por el tiempo y el interés que le dedicaste a Loggro.\n\nDejo tu proceso en pausa por ahora, pero si quieres retomarlo solo respóndeme con un \"sí\" y seguimos justo donde quedamos 🙌\n\nY si prefieres, puedes agendar directo aquí:[AGENDA]"
  }
 ],
 "alojamientos": [
  {
   "situacion": "Contacto 1 (bienvenida)",
   "cuando": "Primer contacto tras el registro del cliente",
   "texto": "¡Hola! 👋 Soy Damian, asesor comercial de Loggro. Vi que te registraste y quiero ayudarte a encontrar la mejor solución para tu negocio.\n\n¿Cuál es tu mayor dolor de cabeza hoy? Por ejemplo, reservas perdidas por no estar sincronizado en Booking, Expedia y Ayenda, o tarifas que se ajustan a mano.\n\nSin afán — cuando tengas un espacio, [AGENDA]"
  },
  {
   "situacion": "Invitación a videollamada (plan personalizado)",
   "cuando": "Invitación directa a videollamada para conocer el programa y recibir un plan personalizado",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 👋 Contamos con un espacio de atención personalizada por videollamada, donde te mostramos cómo funciona Loggro y armamos contigo un plan ajustado a lo que necesita tu negocio.\n\n¿Te gustaría agendarlo? Aprovechamos y vemos qué día te queda mejor.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 2 – no contesta",
   "cuando": "El cliente no respondió al primer mensaje",
   "texto": "Hola [nombre], te saluda Damian de Loggro 👋 Sé que el tiempo no siempre alcanza, así que sin afán: ¿sigue vigente tu interés en organizar y automatizar el negocio?\n\nCuéntame en qué vas y seguimos desde ahí.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 3 – no contesta",
   "cuando": "Segundo intento sin respuesta — se apoya en un video de un cliente real",
   "texto": "Hola, te saluda Damian de Loggro 👋 Te dejo esto rapidito, resolviendo justo reservas perdidas por no estar sincronizado en Booking, Expedia y Ayenda, o tarifas que se ajustan a mano:\n\n[VIDEO]\n\n¿Se parece a lo que te pasa a ti? Cuéntame.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 4 – no contesta",
   "cuando": "Último intento del embudo antes de pausar el contacto",
   "texto": "Hola, te saluda Damian de Loggro 👋 Sin afán — si te gustaría retomar el tema de organizar tu negocio, aquí te dejo el link para agendar cuando te quede bien:[AGENDA]"
  },
  {
   "situacion": "Informativo – sin negocio",
   "cuando": "Persona con interés informativo, sin negocio propio o con un proyecto en mente",
   "texto": "¡Hola, [nombre]! 👋 Soy Damian, de Loggro.\n\nAyudamos a negocios como el que estás armando con reservas perdidas por no estar sincronizado en Booking, Expedia y Ayenda, o tarifas que se ajustan a mano 📊\n\n[VIDEO]\n\nCuéntame qué negocio estás armando y te digo cómo encaja Loggro.\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Informativo – con negocio",
   "cuando": "Persona con negocio activo que indica que le enviaron información por WhatsApp",
   "texto": "¡Hola, [nombre]! 👋 Soy Damian, de Loggro.\n\nCon Loggro resuelves reservas perdidas por no estar sincronizado en Booking, Expedia y Ayenda, o tarifas que se ajustan a mano, todo en un solo lugar 📊\n\n[VIDEO]\n\nCuéntame tu mayor dolor de cabeza hoy y te muestro justo esa parte.\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Transición a interés (agenda)",
   "cuando": "Cliente responde con interés o con su dolor — se pasa a agendar (listo para copiar y pegar)",
   "texto": "¡Hola! Soy Damian, de Loggro 👋 ¡Claro que sí! Eso es justo lo que resolvemos: reservas sincronizadas con Booking, Expedia y Ayenda, y tarifas siempre al día, sin hacerlo a mano.\n\n¿Te parece si lo vemos en una videollamada corta? Te muestro cómo aplicaría para tu negocio. ¿Hoy en la tarde o mañana te queda bien?\n\n📅 Si prefieres agendar tú mismo:[AGENDA]"
  },
  {
   "situacion": "Recordatorio de reunión",
   "cuando": "Confirmación de una reunión ya agendada",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro ✋ Te escribo para confirmar nuestra reunión de hoy/mañana a las [hora].\n\n🔗 Link: [enlace de la reunión]\n\nNos vemos ahí — cualquier cosa, me escribes por aquí."
  },
  {
   "situacion": "No asistió a la demo",
   "cuando": "El cliente no llegó a la videollamada agendada",
   "texto": "¡Hola, [nombre]! Te saluda Damian de Loggro 👋 Suena como que surgió algo de último momento — nos pasa a todos.\n\nSin afán, ¿buscamos otro espacio esta semana? [¿Hoy en la tarde o mañana?]\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Levantamiento de info (cotización)",
   "cuando": "El cliente pide precio o cotización directamente — se recopila lo necesario antes de armar la propuesta",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 👋 ¡Listo! Para armar tu cotización, cuéntame:\n\n1️⃣ ¿Cuántas habitaciones tienes?\n2️⃣ ¿En qué canales vendes hoy? (Booking, Expedia, Airbnb, Despegar, otros, o ninguno todavía)\n3️⃣ ¿Cuántas personas van a usar el sistema (usuarios)?\n4️⃣ ¿Facturas electrónicamente y manejas reportes SIRE/TRA? (Sí/No)\n5️⃣ ¿Tienes algún requerimiento especial? (ej. varias propiedades en distintas direcciones, integración con otro software, atención con equipo de revenue/precios, etc.)\n\nCon eso te armo la propuesta. 🙌"
  },
  {
   "situacion": "Envío de cotización",
   "cuando": "Justo después de la demo/reunión — se envía adjunta o en link la cotización formal",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 Con mucho gusto te comparto la propuesta que armamos pensando en tu negocio 📄👇\n\n[adjuntar cotización]\n\nLos precios de lista y la promo de tu primera compra van marcados por separado, para que los tengas clarísimos.\n\nCuando la revises, cuéntame qué te pareció. Si algo no te cuadra lo ajustamos juntos, y si todo te gusta, arrancamos y yo te acompaño en cada paso 🙌"
  },
  {
   "situacion": "Seguimiento post-demo",
   "cuando": "Después de la demo y con una propuesta ya enviada",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 ¿Cómo te fue revisando la propuesta? Me encantaría saber qué pensaste.\n\nSi hay algo que te genere duda (el precio, los tiempos, cómo funciona), cuéntame sin pena y lo miramos juntos. Y si ya te sientes listo, yo me encargo de dejarte todo andando 🚀"
  },
  {
   "situacion": "Cierre sin respuesta",
   "cuando": "Después de demo o propuesta, sin respuesta del cliente",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 Quería saber cómo vas con la decisión. Sé que estas cosas se piensan con calma, y está muy bien.\n\nPara ayudarte mejor, respóndeme con el número que más se parezca a ti:\n1️⃣ Quiero avanzar\n2️⃣ Tengo una duda y me gustaría resolverla\n3️⃣ Prefiero esperar un tiempo\n\nCualquiera de las tres me sirve, así sé cómo acompañarte 🤝"
  },
  {
   "situacion": "Último mensaje de cierre",
   "cuando": "Cierre formal del ciclo tras varios intentos sin respuesta — se apoya en el mismo video de caso real para reforzar confianza",
   "texto": "Hola [nombre], te saluda Damian de Loggro 😊 Muchas gracias por el tiempo y el interés que le dedicaste a Loggro.\n\nDejo tu proceso en pausa por ahora, pero si quieres retomarlo solo respóndeme con un \"sí\" y seguimos justo donde quedamos 🙌\n\nY si prefieres, puedes agendar directo aquí:[AGENDA]"
  }
 ],
 "pymes": [
  {
   "situacion": "Contacto 1 (bienvenida)",
   "cuando": "Primer contacto tras el registro del cliente",
   "texto": "¡Hola! 👋 Soy Damian, asesor comercial de Loggro. Vi que te registraste y quiero ayudarte a encontrar la mejor solución para tu negocio.\n\n¿Cuál es tu mayor dolor de cabeza hoy? Por ejemplo, facturación y contabilidad llevadas a mano o en Excel, sin cumplir con la DIAN.\n\nSin afán — cuando tengas un espacio, [AGENDA]"
  },
  {
   "situacion": "Invitación a videollamada (plan personalizado)",
   "cuando": "Invitación directa a videollamada para conocer el programa y recibir un plan personalizado",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 👋 Contamos con un espacio de atención personalizada por videollamada, donde te mostramos cómo funciona Loggro y armamos contigo un plan ajustado a lo que necesita tu negocio.\n\n¿Te gustaría agendarlo? Aprovechamos y vemos qué día te queda mejor.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 2 – no contesta",
   "cuando": "El cliente no respondió al primer mensaje",
   "texto": "Hola [nombre], te saluda Damian de Loggro 👋 Sé que el tiempo no siempre alcanza, así que sin afán: ¿sigue vigente tu interés en organizar y automatizar el negocio?\n\nCuéntame en qué vas y seguimos desde ahí.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 3 – no contesta",
   "cuando": "Segundo intento sin respuesta — se apoya en un video de un cliente real",
   "texto": "Hola, te saluda Damian de Loggro 👋 Te dejo esto rapidito, resolviendo justo facturación y contabilidad llevadas a mano o en Excel, sin cumplir con la DIAN:\n\n[VIDEO]\n\n¿Se parece a lo que te pasa a ti? Cuéntame.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 4 – no contesta",
   "cuando": "Último intento del embudo antes de pausar el contacto",
   "texto": "Hola, te saluda Damian de Loggro 👋 Sin afán — si te gustaría retomar el tema de organizar tu negocio, aquí te dejo el link para agendar cuando te quede bien:[AGENDA]"
  },
  {
   "situacion": "Informativo – sin negocio",
   "cuando": "Persona con interés informativo, sin negocio propio o con un proyecto en mente",
   "texto": "¡Hola, [nombre]! 👋 Soy Damian, de Loggro.\n\nAyudamos a negocios como el que estás armando con facturación y contabilidad llevadas a mano o en Excel, sin cumplir con la DIAN 📊\n\n[VIDEO]\n\nCuéntame qué negocio estás armando y te digo cómo encaja Loggro.\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Informativo – con negocio",
   "cuando": "Persona con negocio activo que indica que le enviaron información por WhatsApp",
   "texto": "¡Hola, [nombre]! 👋 Soy Damian, de Loggro.\n\nCon Loggro resuelves facturación y contabilidad llevadas a mano o en Excel, sin cumplir con la DIAN, todo en un solo lugar 📊\n\n[VIDEO]\n\nCuéntame tu mayor dolor de cabeza hoy y te muestro justo esa parte.\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Transición a interés (agenda)",
   "cuando": "Cliente responde con interés o con su dolor — se pasa a agendar (listo para copiar y pegar)",
   "texto": "¡Hola! Soy Damian, de Loggro 👋 ¡Claro que sí! Eso es justo lo que resolvemos: facturación y contabilidad al día y en regla con la DIAN, sin hacerlo a mano.\n\n¿Te parece si lo vemos en una videollamada corta? Te muestro cómo aplicaría para tu negocio. ¿Hoy en la tarde o mañana te queda bien?\n\n📅 Si prefieres agendar tú mismo:[AGENDA]"
  },
  {
   "situacion": "Recordatorio de reunión",
   "cuando": "Confirmación de una reunión ya agendada",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro ✋ Te escribo para confirmar nuestra reunión de hoy/mañana a las [hora].\n\n🔗 Link: [enlace de la reunión]\n\nNos vemos ahí — cualquier cosa, me escribes por aquí."
  },
  {
   "situacion": "No asistió a la demo",
   "cuando": "El cliente no llegó a la videollamada agendada",
   "texto": "¡Hola, [nombre]! Te saluda Damian de Loggro 👋 Suena como que surgió algo de último momento — nos pasa a todos.\n\nSin afán, ¿buscamos otro espacio esta semana? [¿Hoy en la tarde o mañana?]\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Levantamiento de info (cotización)",
   "cuando": "El cliente pide precio o cotización directamente — se recopila lo necesario antes de armar la propuesta",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 👋 ¡Listo! Para armar tu cotización, cuéntame:\n\n1️⃣ ¿A qué se dedica tu negocio (comercio, servicios, o ambos)?\n2️⃣ ¿Cuántos usuarios van a usar el sistema?\n3️⃣ ¿Facturas electrónicamente hoy? (Sí/No)\n4️⃣ ¿Necesitas también nómina electrónica?\n5️⃣ ¿Tienes algún requerimiento especial? (ej. varias sucursales, integración contable con otro software, etc.)\n\nCon eso te armo la propuesta. 🙌"
  },
  {
   "situacion": "Envío de cotización",
   "cuando": "Justo después de la demo/reunión — se envía adjunta o en link la cotización formal",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 Con mucho gusto te comparto la propuesta que armamos pensando en tu negocio 📄👇\n\n[adjuntar cotización]\n\nLos precios de lista y la promo de tu primera compra van marcados por separado, para que los tengas clarísimos.\n\nCuando la revises, cuéntame qué te pareció. Si algo no te cuadra lo ajustamos juntos, y si todo te gusta, arrancamos y yo te acompaño en cada paso 🙌"
  },
  {
   "situacion": "Seguimiento post-demo",
   "cuando": "Después de la demo y con una propuesta ya enviada",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 ¿Cómo te fue revisando la propuesta? Me encantaría saber qué pensaste.\n\nSi hay algo que te genere duda (el precio, los tiempos, cómo funciona), cuéntame sin pena y lo miramos juntos. Y si ya te sientes listo, yo me encargo de dejarte todo andando 🚀"
  },
  {
   "situacion": "Cierre sin respuesta",
   "cuando": "Después de demo o propuesta, sin respuesta del cliente",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 Quería saber cómo vas con la decisión. Sé que estas cosas se piensan con calma, y está muy bien.\n\nPara ayudarte mejor, respóndeme con el número que más se parezca a ti:\n1️⃣ Quiero avanzar\n2️⃣ Tengo una duda y me gustaría resolverla\n3️⃣ Prefiero esperar un tiempo\n\nCualquiera de las tres me sirve, así sé cómo acompañarte 🤝"
  },
  {
   "situacion": "Último mensaje de cierre",
   "cuando": "Cierre formal del ciclo tras varios intentos sin respuesta — se apoya en el mismo video de caso real para reforzar confianza",
   "texto": "Hola [nombre], te saluda Damian de Loggro 😊 Muchas gracias por el tiempo y el interés que le dedicaste a Loggro.\n\nDejo tu proceso en pausa por ahora, pero si quieres retomarlo solo respóndeme con un \"sí\" y seguimos justo donde quedamos 🙌\n\nY si prefieres, puedes agendar directo aquí:[AGENDA]"
  }
 ],
 "pos": [
  {
   "situacion": "Contacto 1 (bienvenida)",
   "cuando": "Primer contacto tras el registro del cliente",
   "texto": "¡Hola! 👋 Soy Damian, asesor comercial de Loggro. Vi que te registraste y quiero ayudarte a encontrar la mejor solución para tu negocio.\n\n¿Cuál es tu mayor dolor de cabeza hoy? Por ejemplo, inventario descontrolado entre bodegas y complicaciones con la factura electrónica de la DIAN.\n\nSin afán — cuando tengas un espacio, [AGENDA]"
  },
  {
   "situacion": "Invitación a videollamada (plan personalizado)",
   "cuando": "Invitación directa a videollamada para conocer el programa y recibir un plan personalizado",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 👋 Contamos con un espacio de atención personalizada por videollamada, donde te mostramos cómo funciona Loggro y armamos contigo un plan ajustado a lo que necesita tu negocio.\n\n¿Te gustaría agendarlo? Aprovechamos y vemos qué día te queda mejor.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 2 – no contesta",
   "cuando": "El cliente no respondió al primer mensaje",
   "texto": "Hola [nombre], te saluda Damian de Loggro 👋 Sé que el tiempo no siempre alcanza, así que sin afán: ¿sigue vigente tu interés en organizar y automatizar el negocio?\n\nCuéntame en qué vas y seguimos desde ahí.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 3 – no contesta",
   "cuando": "Segundo intento sin respuesta — se apoya en un video de un cliente real",
   "texto": "Hola, te saluda Damian de Loggro 👋 Te dejo esto rapidito, resolviendo justo inventario descontrolado entre bodegas y complicaciones con la factura electrónica de la DIAN:\n\n[VIDEO]\n\n¿Se parece a lo que te pasa a ti? Cuéntame.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 4 – no contesta",
   "cuando": "Último intento del embudo antes de pausar el contacto",
   "texto": "Hola, te saluda Damian de Loggro 👋 Sin afán — si te gustaría retomar el tema de organizar tu negocio, aquí te dejo el link para agendar cuando te quede bien:[AGENDA]"
  },
  {
   "situacion": "Informativo – sin negocio",
   "cuando": "Persona con interés informativo, sin negocio propio o con un proyecto en mente",
   "texto": "¡Hola, [nombre]! 👋 Soy Damian, de Loggro.\n\nAyudamos a negocios como el que estás armando con inventario descontrolado entre bodegas y complicaciones con la factura electrónica de la DIAN 📊\n\n[VIDEO]\n\nCuéntame qué negocio estás armando y te digo cómo encaja Loggro.\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Informativo – con negocio",
   "cuando": "Persona con negocio activo que indica que le enviaron información por WhatsApp",
   "texto": "¡Hola, [nombre]! 👋 Soy Damian, de Loggro.\n\nCon Loggro resuelves inventario descontrolado entre bodegas y complicaciones con la factura electrónica de la DIAN, todo en un solo lugar 📊\n\n[VIDEO]\n\nCuéntame tu mayor dolor de cabeza hoy y te muestro justo esa parte.\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Transición a interés (agenda)",
   "cuando": "Cliente responde con interés o con su dolor — se pasa a agendar (listo para copiar y pegar)",
   "texto": "¡Hola! Soy Damian, de Loggro 👋 ¡Claro que sí! Eso es justo lo que resolvemos: inventario controlado entre bodegas y factura electrónica sin dolores de cabeza, sin hacerlo a mano.\n\n¿Te parece si lo vemos en una videollamada corta? Te muestro cómo aplicaría para tu negocio. ¿Hoy en la tarde o mañana te queda bien?\n\n📅 Si prefieres agendar tú mismo:[AGENDA]"
  },
  {
   "situacion": "Recordatorio de reunión",
   "cuando": "Confirmación de una reunión ya agendada",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro ✋ Te escribo para confirmar nuestra reunión de hoy/mañana a las [hora].\n\n🔗 Link: [enlace de la reunión]\n\nNos vemos ahí — cualquier cosa, me escribes por aquí."
  },
  {
   "situacion": "No asistió a la demo",
   "cuando": "El cliente no llegó a la videollamada agendada",
   "texto": "¡Hola, [nombre]! Te saluda Damian de Loggro 👋 Suena como que surgió algo de último momento — nos pasa a todos.\n\nSin afán, ¿buscamos otro espacio esta semana? [¿Hoy en la tarde o mañana?]\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Levantamiento de info (cotización)",
   "cuando": "El cliente pide precio o cotización directamente — se recopila lo necesario antes de armar la propuesta",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 👋 ¡Listo! Para armar tu cotización, cuéntame:\n\n1️⃣ ¿Cuántos puntos de venta o bodegas tienes?\n2️⃣ ¿Cuántos usuarios/cajeros van a usar el sistema?\n3️⃣ ¿Facturas electrónicamente hoy? (Sí/No)\n4️⃣ ¿Necesitas manejo de inventario entre varias bodegas?\n5️⃣ ¿Tienes algún requerimiento especial? (ej. varios establecimientos con el mismo NIT, integración contable, etc.)\n\nCon eso te armo la propuesta. 🙌"
  },
  {
   "situacion": "Envío de cotización",
   "cuando": "Justo después de la demo/reunión — se envía adjunta o en link la cotización formal",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 Con mucho gusto te comparto la propuesta que armamos pensando en tu negocio 📄👇\n\n[adjuntar cotización]\n\nLos precios de lista y la promo de tu primera compra van marcados por separado, para que los tengas clarísimos.\n\nCuando la revises, cuéntame qué te pareció. Si algo no te cuadra lo ajustamos juntos, y si todo te gusta, arrancamos y yo te acompaño en cada paso 🙌"
  },
  {
   "situacion": "Seguimiento post-demo",
   "cuando": "Después de la demo y con una propuesta ya enviada",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 ¿Cómo te fue revisando la propuesta? Me encantaría saber qué pensaste.\n\nSi hay algo que te genere duda (el precio, los tiempos, cómo funciona), cuéntame sin pena y lo miramos juntos. Y si ya te sientes listo, yo me encargo de dejarte todo andando 🚀"
  },
  {
   "situacion": "Cierre sin respuesta",
   "cuando": "Después de demo o propuesta, sin respuesta del cliente",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 Quería saber cómo vas con la decisión. Sé que estas cosas se piensan con calma, y está muy bien.\n\nPara ayudarte mejor, respóndeme con el número que más se parezca a ti:\n1️⃣ Quiero avanzar\n2️⃣ Tengo una duda y me gustaría resolverla\n3️⃣ Prefiero esperar un tiempo\n\nCualquiera de las tres me sirve, así sé cómo acompañarte 🤝"
  },
  {
   "situacion": "Último mensaje de cierre",
   "cuando": "Cierre formal del ciclo tras varios intentos sin respuesta — se apoya en el mismo video de caso real para reforzar confianza",
   "texto": "Hola [nombre], te saluda Damian de Loggro 😊 Muchas gracias por el tiempo y el interés que le dedicaste a Loggro.\n\nDejo tu proceso en pausa por ahora, pero si quieres retomarlo solo respóndeme con un \"sí\" y seguimos justo donde quedamos 🙌\n\nY si prefieres, puedes agendar directo aquí:[AGENDA]"
  }
 ],
 "nomina": [
  {
   "situacion": "Contacto 1 (bienvenida)",
   "cuando": "Primer contacto tras el registro del cliente",
   "texto": "¡Hola! 👋 Soy Damian, asesor comercial de Loggro. Vi que te registraste y quiero ayudarte a encontrar la mejor solución para tu negocio.\n\n¿Cuál es tu mayor dolor de cabeza hoy? Por ejemplo, liquidaciones con errores, atrasos en PILA y nómina electrónica sin cumplir con la DIAN.\n\nSin afán — cuando tengas un espacio, [AGENDA]"
  },
  {
   "situacion": "Invitación a videollamada (plan personalizado)",
   "cuando": "Invitación directa a videollamada para conocer el programa y recibir un plan personalizado",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 👋 Contamos con un espacio de atención personalizada por videollamada, donde te mostramos cómo funciona Loggro y armamos contigo un plan ajustado a lo que necesita tu negocio.\n\n¿Te gustaría agendarlo? Aprovechamos y vemos qué día te queda mejor.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 2 – no contesta",
   "cuando": "Segundo intento de contacto, sin respuesta al primero",
   "texto": "Hola [nombre], te saluda Damian de Loggro 👋 Sé que el tiempo no siempre alcanza, así que sin afán: ¿sigue vigente tu interés en organizar y automatizar el negocio?\n\nCuéntame en qué vas y seguimos desde ahí.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 3 – no contesta",
   "cuando": "Tercer intento de contacto, con video de apoyo",
   "texto": "Hola, te saluda Damian de Loggro 👋 Te dejo esto rapidito, resolviendo justo liquidaciones con errores, atrasos en PILA y nómina electrónica sin cumplir con la DIAN:\n\n[VIDEO]\n\n¿Se parece a lo que te pasa a ti? Cuéntame.\n\n[AGENDA]"
  },
  {
   "situacion": "Contacto 4 – no contesta",
   "cuando": "Cuarto y último intento de contacto por silencio",
   "texto": "Hola, te saluda Damian de Loggro 👋 Sin afán — si te gustaría retomar el tema de organizar tu negocio, aquí te dejo el link para agendar cuando te quede bien:[AGENDA]"
  },
  {
   "situacion": "Informativo – sin negocio",
   "cuando": "Cliente aún no tiene negocio armado, mensaje informativo",
   "texto": "¡Hola, [nombre]! 👋 Soy Damian, de Loggro.\n\nAyudamos a negocios como el que estás armando con liquidaciones con errores, atrasos en PILA y nómina electrónica sin cumplir con la DIAN 📊\n\n[VIDEO]\n\nCuéntame qué negocio estás armando y te digo cómo encaja Loggro.\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Informativo – con negocio",
   "cuando": "Cliente ya tiene negocio activo, mensaje informativo",
   "texto": "¡Hola, [nombre]! 👋 Soy Damian, de Loggro.\n\nCon Loggro resuelves liquidaciones con errores, atrasos en PILA y nómina electrónica sin cumplir con la DIAN, todo en un solo lugar 📊\n\n[VIDEO]\n\nCuéntame tu mayor dolor de cabeza hoy y te muestro justo esa parte.\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Transición a interés (agenda)",
   "cuando": "Cliente responde con interés o con su dolor — se pasa a agendar (listo para copiar y pegar)",
   "texto": "¡Hola! Soy Damian, de Loggro 👋 ¡Claro que sí! Eso es justo lo que resolvemos: liquidación sin errores, PILA al día y nómina electrónica en regla con la DIAN, sin hacerlo a mano.\n\n¿Te parece si lo vemos en una videollamada corta? Te muestro cómo aplicaría para tu negocio. ¿Hoy en la tarde o mañana te queda bien?\n\n📅 Si prefieres agendar tú mismo:[AGENDA]"
  },
  {
   "situacion": "Recordatorio de reunión",
   "cuando": "Confirmación de reunión agendada",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro ✋ Te escribo para confirmar nuestra reunión de hoy/mañana a las [hora].\n\n🔗 Link: [enlace de la reunión]\n\nNos vemos ahí — cualquier cosa, me escribes por aquí."
  },
  {
   "situacion": "No asistió a la demo",
   "cuando": "Cliente no asistió a la reunión agendada",
   "texto": "¡Hola, [nombre]! Te saluda Damian de Loggro 👋 Suena como que surgió algo de último momento — nos pasa a todos.\n\nSin afán, ¿buscamos otro espacio esta semana? [¿Hoy en la tarde o mañana?]\n\n📅 Agenda aquí:[AGENDA]"
  },
  {
   "situacion": "Levantamiento de info (cotización)",
   "cuando": "Recolectar información para armar la cotización",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 👋 ¡Listo! Para armar tu cotización, cuéntame:\n\n1️⃣ ¿Cuántos empleados tienes en nómina hoy?\n2️⃣ ¿Cómo liquidas actualmente? (Excel, manual, otro software)\n3️⃣ ¿Generas nómina electrónica hoy? (Sí/No)\n4️⃣ ¿Necesitas también gestión de PILA y seguridad social?\n5️⃣ ¿Tienes algún requerimiento especial? (ej. varios centros de costo, tipos de contrato distintos, integración con otro software, etc.)\n\nCon eso te armo la propuesta. 🙌"
  },
  {
   "situacion": "Envío de cotización",
   "cuando": "Envío de la propuesta comercial",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 Con mucho gusto te comparto la propuesta que armamos pensando en tu negocio 📄👇\n\n[adjuntar cotización]\n\nLos precios de lista y la promo de tu primera compra van marcados por separado, para que los tengas clarísimos.\n\nCuando la revises, cuéntame qué te pareció. Si algo no te cuadra lo ajustamos juntos, y si todo te gusta, arrancamos y yo te acompaño en cada paso 🙌"
  },
  {
   "situacion": "Seguimiento post-demo",
   "cuando": "Seguimiento después de enviar la propuesta",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 ¿Cómo te fue revisando la propuesta? Me encantaría saber qué pensaste.\n\nSi hay algo que te genere duda (el precio, los tiempos, cómo funciona), cuéntame sin pena y lo miramos juntos. Y si ya te sientes listo, yo me encargo de dejarte todo andando 🚀"
  },
  {
   "situacion": "Cierre sin respuesta",
   "cuando": "Cliente no responde tras la cotización",
   "texto": "¡Hola, [nombre]! Soy Damian, de Loggro 😊 Quería saber cómo vas con la decisión. Sé que estas cosas se piensan con calma, y está muy bien.\n\nPara ayudarte mejor, respóndeme con el número que más se parezca a ti:\n1️⃣ Quiero avanzar\n2️⃣ Tengo una duda y me gustaría resolverla\n3️⃣ Prefiero esperar un tiempo\n\nCualquiera de las tres me sirve, así sé cómo acompañarte 🤝"
  },
  {
   "situacion": "Último mensaje de cierre",
   "cuando": "Cierre formal del proceso por falta de avance",
   "texto": "Hola [nombre], te saluda Damian de Loggro 😊 Muchas gracias por el tiempo y el interés que le dedicaste a Loggro.\n\nDejo tu proceso en pausa por ahora, pero si quieres retomarlo solo respóndeme con un \"sí\" y seguimos justo donde quedamos 🙌\n\nY si prefieres, puedes agendar directo aquí:[AGENDA]"
  }
 ]
};
