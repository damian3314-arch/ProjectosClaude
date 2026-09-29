-- 0117 · Descartar una tiquetera de la página que nunca se pagó.
--
-- Damián, 29 sep: «Ese caso Rufi, no pagó: el sistema debe permitir
-- descartar, invalidar el código o algo para sacar ese registro. Al
-- parecer se equivocó: quería comprar la mensualidad y terminó dando que
-- pagó tiquetera.»
--
--   · Estado nuevo 'descartada': sale de «por validar», del centinela y
--     de las activas; el código nunca sirvió para reservar (tomar_cupo
--     exige 'confirmada') y así queda para siempre.
--   · Se guarda el motivo en tiqueteras.nota y quién la descartó.
--   · Solo se descarta lo que NO está confirmado: una tiquetera pagada no
--     se borra desde aquí (su plata ya está en el cierre).

alter table public.tiqueteras drop constraint if exists tiqueteras_estado_ck;
alter table public.tiqueteras add constraint tiqueteras_estado_ck
  check (estado in ('pendiente_pago', 'pendiente_validacion', 'confirmada', 'descartada'));

alter table public.tiqueteras
  add column if not exists nota text,
  add column if not exists descartada_por uuid references public.admin_tokens(id),
  add column if not exists descartada_at timestamptz;

create or replace function public.admin_tiquetera_descartar(p_token text, p_id bigint, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_admin uuid; v_t tiqueteras%rowtype;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  select * into v_t from tiqueteras where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE', 'mensaje', 'Esa tiquetera no existe. Recarga la lista.');
  end if;
  if v_t.estado = 'confirmada' then
    return jsonb_build_object('ok', false, 'error', 'YA_CONFIRMADA',
      'mensaje', 'Esa tiquetera ya está pagada y activa: no se descarta desde aquí.');
  end if;
  update tiqueteras
     set estado = 'descartada', activa = false,
         nota = nullif(btrim(coalesce(p_motivo, '')), ''),
         descartada_por = v_admin, descartada_at = now()
   where id = p_id;
  return jsonb_build_object('ok', true, 'id', v_t.id, 'nombre', v_t.nombre);
end;
$$;
revoke all on function public.admin_tiquetera_descartar(text, bigint, text) from public, anon, authenticated;

-- Rufi (id 8): Damián confirmó el 29 sep que no pagó; quería mensualidad.
update public.tiqueteras
   set estado = 'descartada', activa = false,
       nota = 'No pagó: se equivocó, quería comprar mensualidad (Damián, 29 sep).',
       descartada_at = now()
 where id = 8 and estado <> 'confirmada';
