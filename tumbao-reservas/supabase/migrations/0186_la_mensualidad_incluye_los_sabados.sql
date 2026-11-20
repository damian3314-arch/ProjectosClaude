-- 0186 · La mensualidad incluye la Rumba terapia de los sábados.
-- Damián (15 oct): «la mensualidad permite reservar para ingresar a las clases de los sábados. Está incluido».
-- Timba lo lee en su prompt (ventas.js). Esto se lo agrega al asistente general (ajustes.asistente_info), una sola vez.
-- OJO al aplicarla con la herramienta de Supabase: sin punto y coma dentro del texto.
update ajustes
   set valor = valor || ' La mensualidad incluye las clases de lunes a sábado, también la Rumba terapia de los sábados, a la que se entra reservando.'
 where clave = 'asistente_info'
   and valor not like '%mensualidad incluye%';
