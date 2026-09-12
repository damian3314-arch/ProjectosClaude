-- 0081 · La lista de usuarios dice en qué punto está cada persona.
--
-- LO QUE PASÓ DE VERDAD
-- Damián: «hasta ahora solo está activo el usuario de damian3314@gmail.com,
-- los otros no funcionan y no les ha llegado el mensaje para asignar la
-- clave de ingreso».
--
-- Mirado contra producción, el 24 de agosto quedó así:
--
--   19:14  damian3314@gmail.com   → usuario creado en Auth, invitación enviada
--   19:48  bailatumbao@gmail.com  → fila en admin_usuarios, NADA en auth.users
--   19:49  tanyizgus@hotmail.com  → fila en admin_usuarios, NADA en auth.users
--
-- Las dos últimas no es que el correo se perdiera en el camino: el
-- usuario de Auth NUNCA SE CREÓ. GoTrue crea la cuenta y manda el correo
-- en la misma operación, y si el envío falla deshace la creación. O sea
-- que el correo falló y se llevó la cuenta con él. El Worker ya decía
-- «el usuario quedó creado, pero no se pudo mandar el correo de
-- invitación», pero eso aparecía una sola vez en un aviso que se va, y
-- después la lista no volvía a mencionarlo nunca.
--
-- POR QUÉ LA LISTA NO LO DELATABA
-- `tiene_acceso` era `user_id is not null`, y `user_id` se rellena en el
-- PRIMER LOGIN (admin_token_para_usuario lo enlaza por correo). Así que
-- decía exactamente lo mismo —«Invitación pendiente»— en tres casos que
-- no se parecen en nada:
--
--   · nunca se creó la cuenta            → hay que volver a invitar
--   · se creó y no ha puesto clave       → hay que reenviar el enlace
--   · puso clave y no ha entrado todavía → no hay nada que hacer
--
-- Sin distinguirlos no hay forma de saber a quién hay que insistirle, que
-- es justo la pregunta que se hizo Damián.
--
-- LO QUE SE AÑADE
-- `estado`, leído de auth.users, que es quien sabe la verdad:
--
--   sin_invitar  no existe en Auth. La invitación no salió.
--   invitado     existe, sin contraseña. Le falta abrir el enlace.
--   listo        tiene contraseña y nunca ha entrado al panel.
--   activo       ya entró alguna vez.
--
-- Más `invitado_at` y `ultimo_ingreso` para saber de cuándo viene el
-- silencio. `tiene_acceso` se deja tal cual: un panel viejo en caché
-- sigue leyéndolo y no se le puede quitar el suelo.
--
-- Y `admin_usuario_a_invitar`, que es la que usa el Worker antes de
-- tocar Supabase Auth: comprueba en Postgres que quien llama es
-- propietario y devuelve a quién hay que invitar. La regla de permisos
-- no se mueve al Worker —ahí es donde se olvida— sino que se queda
-- donde ya están todas las demás.
--
-- SE REESCRIBE COMPLETA, no se parchea: comprobado que el cuerpo vivo en
-- producción es palabra por palabra el de la 0047. No hay arreglos
-- posteriores que esta migración pueda pisar.

create or replace function public.admin_listar_usuarios(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin record;
  v_lista jsonb;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if v_admin.rol is distinct from 'propietario' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO',
      'mensaje', 'Solo el propietario ve y gestiona los usuarios.');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', u.id, 'nombre', u.nombre, 'email', u.email,
           'rol', u.rol, 'activo', u.activo,
           -- Se queda por compatibilidad con paneles viejos en caché.
           'tiene_acceso', u.user_id is not null,
           'ultimo_uso', (select max(t.ultimo_uso) from admin_tokens t
                           where t.usuario_id = u.id),
           'estado',
             case
               when a.id is null then 'sin_invitar'
               -- GoTrue deja la contraseña vacía hasta que la persona
               -- abre el enlace y la escribe. 60 caracteres es un hash
               -- de bcrypt; cero es «todavía no».
               when length(coalesce(a.encrypted_password, '')) = 0 then 'invitado'
               when a.last_sign_in_at is null then 'listo'
               else 'activo'
             end,
           'invitado_at', a.invited_at,
           'ultimo_ingreso', a.last_sign_in_at
         ) order by u.nombre), '[]'::jsonb)
    into v_lista
    from admin_usuarios u
    -- Por correo y no por user_id a propósito: user_id sigue nulo hasta
    -- el primer login, así que enlazar por ahí volvería a esconder
    -- justamente el caso que esta migración viene a destapar.
    left join auth.users a on lower(a.email) = lower(u.email);

  return jsonb_build_object('ok', true, 'usuarios', v_lista);
end;
$$;

-- Quién hay que invitar, y si quien lo pide tiene derecho a pedirlo.
-- El Worker no puede decidir eso solo: su única credencial es la llave
-- de servicio, que abre todo.
create or replace function public.admin_usuario_a_invitar(p_token text, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin record;
  v_u     admin_usuarios%rowtype;
  v_auth  auth.users%rowtype;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if v_admin.rol is distinct from 'propietario' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO',
      'mensaje', 'Solo el propietario invita.');
  end if;

  select * into v_u from admin_usuarios where id = p_id;
  if v_u.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE',
      'mensaje', 'Ese usuario ya no está en la lista. Recarga la página.');
  end if;

  -- Invitar a alguien desactivado sería mandarle a poner una contraseña
  -- con la que después no va a poder entrar: admin_token_para_usuario lo
  -- rebota por inactivo. Mejor decirlo aquí que dejarle descubrirlo.
  if not v_u.activo then
    return jsonb_build_object('ok', false, 'error', 'INACTIVO',
      'mensaje', 'Está desactivado. Reactívalo antes de invitarlo.');
  end if;

  select * into v_auth from auth.users where lower(email) = lower(v_u.email);

  return jsonb_build_object('ok', true,
    'email',  v_u.email,
    'nombre', v_u.nombre,
    'rol',    v_u.rol,
    -- Decide qué hay que mandar: una invitación nueva, o el enlace de
    -- «pon tu contraseña» para una cuenta que ya existe.
    'en_auth', v_auth.id is not null,
    'tiene_clave', length(coalesce(v_auth.encrypted_password, '')) > 0);
end;
$$;

revoke execute on function public.admin_usuario_a_invitar(text, uuid)
  from public, anon, authenticated;
grant  execute on function public.admin_usuario_a_invitar(text, uuid) to service_role;
