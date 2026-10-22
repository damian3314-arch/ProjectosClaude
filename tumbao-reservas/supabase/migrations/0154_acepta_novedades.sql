-- 0154 · Casilla opcional «Quiero recibir novedades y promociones de Tumbao por WhatsApp»
--
-- Hito del Plan Tumbao (7 oct, autorizado por Damián el 27 sep): la autorización de datos de las páginas
-- (habeas data) cubre contactar por WhatsApp para gestionar la reserva, la mensualidad o la tiquetera. Las
-- novedades y promociones son otra cosa y piden su propio sí, opcional y desmarcado.
--
-- Se guarda por persona (celular) y no por reserva: así vale para todas sus compras y se puede retirar en un
-- solo lugar. Una tabla aparte, aditiva, sin tocar reservas, mensualidad_solicitudes ni tiqueteras.
--   · fuente: de qué formulario vino el sí ('reserva', 'mensualidad' o 'tiquetera').
--   · retirado_at: para cuando alguien pida dejar de recibirlas (SALIR sigue mandando: wa_bajas).
-- Solo el Worker (service role) escribe, por registrar_acepta_novedades(); nadie más ve la tabla.

create table if not exists public.acepta_novedades (
  telefono    text primary key check (telefono ~ '^3[0-9]{9}$'),
  aceptado_at timestamptz not null default now(),
  fuente      text not null check (fuente in ('reserva', 'mensualidad', 'tiquetera')),
  retirado_at timestamptz
);
alter table public.acepta_novedades enable row level security;
revoke all on table public.acepta_novedades from public, anon, authenticated;

create or replace function public.registrar_acepta_novedades(p_telefono text, p_fuente text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare t text := right(regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g'), 10);
begin
  if t !~ '^3[0-9]{9}$' or p_fuente not in ('reserva', 'mensualidad', 'tiquetera') then
    return false;
  end if;
  insert into acepta_novedades (telefono, fuente) values (t, p_fuente)
  on conflict (telefono) do update set aceptado_at = now(), fuente = excluded.fuente, retirado_at = null;
  return true;
end;
$$;
revoke all on function public.registrar_acepta_novedades(text, text) from public, anon, authenticated;
