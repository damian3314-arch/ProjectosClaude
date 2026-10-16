-- 0144 · La función ventas_ronda(boolean) de 0142 se renombra (no se borra todavía)
--
-- Dejarla con el mismo nombre hacía ambigua la llamada ventas_ronda(true). Damián autorizó
-- borrarla (5 oct), pero la herramienta de Supabase se cuelga con cualquier DROP (pide una
-- confirmación que una sesión sin pantalla no puede dar), así que se renombra: queda inerte.
-- Para borrarla del todo, desde el SQL editor de Supabase:
--   drop function public.ventas_ronda_vieja(boolean);

alter function public.ventas_ronda(boolean) rename to ventas_ronda_vieja;
comment on function public.ventas_ronda_vieja(boolean) is
  'Sobrante de 0142, sin uso. Borrar: drop function public.ventas_ronda_vieja(boolean);';
