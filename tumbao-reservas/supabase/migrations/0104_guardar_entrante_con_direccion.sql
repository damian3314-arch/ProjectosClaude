-- 0104 · wa_guardar_entrante no guardaba nada.
--
-- El INSERT de la 0102 nombraba seis columnas y daba cinco valores: le
-- faltaba 'entrante' para `direccion`. Cada mensaje que llegaba al
-- número fallaba al guardarse y se perdía (el webhook lo registraba con
-- firma válida, pero wa_mensajes seguía vacía). Las pruebas del Worker
-- no lo vieron porque simulaban la base. Probado contra la base real,
-- dentro de una transacción que se deshizo.
create or replace function public.wa_guardar_entrante(p_wa_msg_id text, p_tel text,
                                                      p_nombre text, p_tipo text, p_texto text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id bigint;
begin
  insert into wa_mensajes (wa_msg_id, telefono, nombre, direccion, tipo, texto)
  values (p_wa_msg_id, regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'),
          left(p_nombre, 120), 'entrante', coalesce(p_tipo, 'text'), left(p_texto, 4000))
  on conflict (wa_msg_id) do nothing
  returning id into v_id;
  if v_id is null then return jsonb_build_object('nuevo', false); end if;
  return jsonb_build_object('nuevo', true, 'id', v_id, 'dueno', wa_es_dueno(p_tel),
    'responder', coalesce((select valor from ajustes where clave = 'wa_respuesta_auto'), 'apagado') = 'encendido');
end;
$$;
