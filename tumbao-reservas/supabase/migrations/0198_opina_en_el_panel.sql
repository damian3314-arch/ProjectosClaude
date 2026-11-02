-- 0198 · «Opina» en el panel (2 nov). El Worker de opiniones necesita saber el rol de quien abre la sección: este RPC (que solo el Worker de la caja
-- llama con la llave de servicio) devuelve el rol de un token del panel. Aplicada en vivo.
create or replace function public.admin_quien_soy(p_token text)
returns jsonb language plpgsql security definer set search_path to 'public','extensions','pg_temp' as $f$
declare v record;
begin
  select * into v from verificar_token_admin_rol(p_token);
  if v.id is null then return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO'); end if;
  return jsonb_build_object('ok', true, 'rol', v.rol);
end $f$;
