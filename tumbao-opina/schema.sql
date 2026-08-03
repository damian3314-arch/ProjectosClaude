-- Base del bot de opiniones. Vive en Cloudflare D1 (SQLite).
--
-- D1 es la verdad, no Google Sheets. Si Google tiene un hipo justo
-- cuando alguien termina de contar por qué se quiere ir, esa respuesta
-- se pierde y nadie se entera nunca. Aquí queda guardada siempre, y la
-- hoja se sincroniza después.

create table if not exists conversaciones (
  id            text primary key,          -- uuid que genera el navegador
  nombre        text,
  telefono      text,
  -- 'queja' | 'sugerencia' | 'elogio' | 'mixto'. Lo decide el LLM al
  -- cerrar, no la persona: nadie se autoclasifica bien.
  tipo          text,
  resumen       text,                      -- lo que dijo, condensado
  urgente       integer not null default 0, -- 1 = mirar hoy, no el lunes
  motivo_urgente text,
  transcripcion text,                      -- la conversación completa, en crudo
  turnos        integer not null default 0,
  empezada_at   text not null,
  cerrada_at    text,
  -- 0 mientras conversa, 1 cuando el bot dio por terminado. Las abiertas
  -- también sirven: una que se cortó en la pregunta 2 ya dice algo.
  completa      integer not null default 0,
  -- Se marca cuando la fila ya viajó a Google Sheets. Permite
  -- resincronizar sin duplicar.
  en_hoja       integer not null default 0
);

create index if not exists conversaciones_por_fecha
  on conversaciones (empezada_at desc);

create index if not exists conversaciones_sin_sincronizar
  on conversaciones (en_hoja) where en_hoja = 0;

-- Cada mensaje suelto, por si algún día hace falta releer una
-- conversación entera sin depender del resumen del LLM.
create table if not exists mensajes (
  id            integer primary key autoincrement,
  conversacion  text not null references conversaciones(id),
  de            text not null,             -- 'persona' | 'bot'
  texto         text not null,
  -- 'texto' | 'voz' | 'imagen'. Si vino de una nota de voz, `texto` ya
  -- es la transcripción: el audio no se guarda.
  medio         text not null default 'texto',
  creado_at     text not null
);

create index if not exists mensajes_por_conversacion
  on mensajes (conversacion, id);
