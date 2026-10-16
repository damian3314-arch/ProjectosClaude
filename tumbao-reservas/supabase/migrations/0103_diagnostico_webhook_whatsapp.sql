-- 0103 · Cuenta cuántas veces toca Meta el webhook y si la firma sirvió.
--
-- 28 sep: Damián escribió al asistente y no contestó; wa_mensajes seguía
-- vacía. Para saber si Meta no está mandando nada (app en modo
-- Desarrollo) o si manda y la firma no cuadra, sin guardar contenido.
create or replace function public.wa_diag_webhook(p_firma_ok boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v jsonb;
begin
  select valor::jsonb into v from ajustes where clave = 'wa_webhook_diag';
  v := coalesce(v, '{}'::jsonb);
  v := v || jsonb_build_object(
    'ultimo', to_char(now() at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
    'firma_ok', coalesce((v->>'firma_ok')::int, 0) + case when p_firma_ok then 1 else 0 end,
    'firma_mala', coalesce((v->>'firma_mala')::int, 0) + case when p_firma_ok then 0 else 1 end);
  insert into ajustes (clave, valor, nota)
  values ('wa_webhook_diag', v::text, 'Cuántas veces llegó Meta al webhook y si la firma sirvió. 0103.')
  on conflict (clave) do update set valor = excluded.valor, updated_at = now();
end;
$$;
revoke all on function public.wa_diag_webhook(boolean) from public, anon, authenticated;
grant execute on function public.wa_diag_webhook(boolean) to service_role;
