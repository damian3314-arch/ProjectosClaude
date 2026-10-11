-- =====================================================================
-- 0047 — Login de verdad, con tres roles
--
-- HASTA HOY
-- Un solo token plano abría todo el panel. Quien lo tuviera podía
-- cerrar caja, cambiar el horario o emitir otro token, sin distinción.
-- Servía cuando solo entraba una persona (recepción); deja de servir en
-- cuanto entran varias con responsabilidades distintas.
--
-- DESDE AHORA
-- Se entra con correo y contraseña. La contraseña la valida Supabase
-- Auth — el Worker se la pasa una vez para el login y nunca la guarda.
-- Lo que se guarda aquí es el REPARTO: qué correo tiene qué rol.
--
--   propietario    - todo, incluido dar de alta gente y fijar su rol
--   administrador  - el día a día: horario, validar pagos, caja
--   cajero         - solo caja: apuntar a mano, validar, abrir/cerrar
--
-- Los admin_tokens que ya existen (el de Recepción) siguen funcionando
-- exactamente igual: un token sin rol asignado (rol is null) sigue con
-- acceso total, como siempre lo tuvo. Esta migración no le quita nada
-- a nadie; solo abre la puerta para que los nuevos token vengan con un
-- rol, y le pone un candado nuevo a lo poco que un cajero no debería
-- poder tocar (el horario).
-- =====================================================================


-- ---------------------------------------------------------------------
-- El reparto: qué correo tiene qué rol
-- ---------------------------------------------------------------------
create table if not exists admin_usuarios (
  id          uuid primary key default extensions.gen_random_uuid(),
  user_id     uuid unique references auth.users(id) on delete set null,
  email       text not null unique,
  nombre      text not null,
  rol         text not null check (rol in ('propietario','administrador','cajero')),
  activo      boolean not null default true,
  creado_at   timestamptz not null default now()
);

comment on table admin_usuarios is
  'Quién puede entrar al panel y con qué rol. La contraseña vive en Supabase Auth, no aquí.';

comment on column admin_usuarios.user_id is
  'null hasta el primer login: se propone el usuario por correo antes de que exista la cuenta de Auth, y se liga solo la primera vez que entra.';

alter table admin_usuarios enable row level security;


alter table admin_tokens add column if not exists rol text
  check (rol is null or rol in ('propietario','administrador','cajero'));
alter table admin_tokens add column if not exists usuario_id uuid
  references admin_usuarios(id) on delete set null;

comment on column admin_tokens.rol is
  'null = token de antes de los roles (el de Recepción); sigue con acceso total. Los nuevos token siempre traen uno.';


-- ---------------------------------------------------------------------
-- verificar_token_admin_rol — como verificar_token_admin, pero además
-- dice con qué rol. No reemplaza al original: las funciones que ya
-- existían y nunca pidieron rol siguen intactas.
-- ---------------------------------------------------------------------
create or replace function verificar_token_admin_rol(p_token text)
returns table(id uuid, rol text, nombre text, usuario_id uuid)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_id uuid;
begin
  v_id := verificar_token_admin(p_token);
  if v_id is null then
    return;
  end if;
  return query
    select t.id, t.rol, t.nombre, t.usuario_id from admin_tokens t where t.id = v_id;
end;
$$;


-- ---------------------------------------------------------------------
-- Login: correo + contraseña ya validados por Supabase Auth (el Worker
-- llama antes a /auth/v1/token) entran aquí con el user_id que Auth
-- entregó, y salen con un token de panel ya con su rol pegado.
-- ---------------------------------------------------------------------
create or replace function admin_token_para_usuario(p_user_id uuid, p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_usuario admin_usuarios%rowtype;
  v_token   text;
begin
  select * into v_usuario
    from admin_usuarios
   where user_id = p_user_id
      or (user_id is null and lower(email) = lower(coalesce(p_email, '')))
   limit 1;

  if v_usuario.id is null then
    return jsonb_build_object('ok', false, 'error', 'sin_acceso',
      'mensaje', 'Ese correo no tiene un perfil en el panel. Pide que te den de alta.');
  end if;

  if not v_usuario.activo then
    return jsonb_build_object('ok', false, 'error', 'inactivo',
      'mensaje', 'Tu acceso está desactivado. Habla con quien administra el panel.');
  end if;

  if v_usuario.user_id is null then
    update admin_usuarios set user_id = p_user_id where id = v_usuario.id;
  end if;

  v_token := translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_');

  insert into admin_tokens (nombre, token_hash, rol, usuario_id)
  values (v_usuario.nombre, hash_token(v_token), v_usuario.rol, v_usuario.id);

  return jsonb_build_object('ok', true, 'token', v_token,
    'rol', v_usuario.rol, 'nombre', v_usuario.nombre);
end;
$$;


-- ---------------------------------------------------------------------
-- Gestión de usuarios — solo el propietario
-- ---------------------------------------------------------------------
create or replace function admin_listar_usuarios(p_token text)
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
           'tiene_acceso', u.user_id is not null,
           'ultimo_uso', (select max(t.ultimo_uso) from admin_tokens t where t.usuario_id = u.id)
         ) order by u.nombre), '[]'::jsonb)
    into v_lista
    from admin_usuarios u;

  return jsonb_build_object('ok', true, 'usuarios', v_lista);
end;
$$;


create or replace function admin_crear_usuario(
  p_token text, p_nombre text, p_email text, p_rol text, p_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin record;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if v_admin.rol is distinct from 'propietario' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO',
      'mensaje', 'Solo el propietario da de alta usuarios.');
  end if;

  if coalesce(trim(p_nombre), '') = '' or coalesce(trim(p_email), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'FALTA_DATO',
      'mensaje', 'Falta el nombre o el correo.');
  end if;
  if p_rol not in ('propietario', 'administrador', 'cajero') then
    return jsonb_build_object('ok', false, 'error', 'ROL_INVALIDO');
  end if;

  insert into admin_usuarios (user_id, email, nombre, rol)
  values (p_user_id, lower(trim(p_email)), trim(p_nombre), p_rol);

  return jsonb_build_object('ok', true);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'YA_EXISTE',
      'mensaje', 'Ese correo ya tiene un perfil en el panel.');
end;
$$;


create or replace function admin_cambiar_estado_usuario(p_token text, p_id uuid, p_activo boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin record;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if v_admin.rol is distinct from 'propietario' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO');
  end if;

  update admin_usuarios set activo = p_activo where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  -- Al desactivar, se le cae la sesión que ya tenía abierta: sin esto
  -- alguien a quien se le acaba de quitar el acceso sigue adentro hasta
  -- que cierre el navegador por su cuenta.
  if not p_activo then
    update admin_tokens set activo = false where usuario_id = p_id;
  end if;

  return jsonb_build_object('ok', true);
end;
$$;


create or replace function admin_cambiar_rol_usuario(p_token text, p_id uuid, p_rol text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin record;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if v_admin.rol is distinct from 'propietario' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO');
  end if;
  if p_rol not in ('propietario', 'administrador', 'cajero') then
    return jsonb_build_object('ok', false, 'error', 'ROL_INVALIDO');
  end if;

  update admin_usuarios set rol = p_rol where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;

  return jsonb_build_object('ok', true);
end;
$$;


-- ---------------------------------------------------------------------
-- El primer propietario — sin token, porque todavía no hay ninguno
--
-- Se cierra ella sola: en cuanto exista una fila en admin_usuarios deja
-- de aceptar nada, así que solo sirve para el arranque y no queda como
-- una puerta abierta de por vida.
-- ---------------------------------------------------------------------
create or replace function admin_bootstrap_propietario(p_email text, p_nombre text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if exists (select 1 from admin_usuarios) then
    return jsonb_build_object('ok', false, 'error', 'YA_HAY_USUARIOS',
      'mensaje', 'Ya hay usuarios dados de alta. Pide que te den acceso.');
  end if;
  if coalesce(trim(p_email), '') = '' or coalesce(trim(p_nombre), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'FALTA_DATO');
  end if;

  insert into admin_usuarios (email, nombre, rol)
  values (lower(trim(p_email)), trim(p_nombre), 'propietario');

  return jsonb_build_object('ok', true);
end;
$$;


revoke execute on function admin_bootstrap_propietario(text, text) from public, anon, authenticated;
grant execute on function admin_bootstrap_propietario(text, text)  to service_role;

revoke execute on function verificar_token_admin_rol(text)         from public, anon, authenticated;
revoke execute on function admin_token_para_usuario(uuid, text)    from public, anon, authenticated;
revoke execute on function admin_listar_usuarios(text)             from public, anon, authenticated;
revoke execute on function admin_crear_usuario(text, text, text, text, uuid) from public, anon, authenticated;
revoke execute on function admin_cambiar_estado_usuario(text, uuid, boolean) from public, anon, authenticated;
revoke execute on function admin_cambiar_rol_usuario(text, uuid, text)       from public, anon, authenticated;

grant execute on function verificar_token_admin_rol(text)         to service_role;
grant execute on function admin_token_para_usuario(uuid, text)    to service_role;
grant execute on function admin_listar_usuarios(text)             to service_role;
grant execute on function admin_crear_usuario(text, text, text, text, uuid) to service_role;
grant execute on function admin_cambiar_estado_usuario(text, uuid, boolean) to service_role;
grant execute on function admin_cambiar_rol_usuario(text, uuid, text)       to service_role;


-- ---------------------------------------------------------------------
-- El único candado que se le pone a un rol sobre una función que ya
-- existía: el cajero no toca el horario. Se parchea sobre
-- pg_get_functiondef en vez de reescribir la función: es larga, y
-- reescribir de memoria ya salió mal en este proyecto.
-- ---------------------------------------------------------------------
do $$
declare
  v_def text;
  v_a   text;
  v_b   text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_guardar_semana';
  if v_def is null then
    raise exception 'no existe admin_guardar_semana';
  end if;
  if position('El cajero no toca el horario' in v_def) > 0 then
    raise notice 'ya estaba aplicada';
    return;
  end if;

  v_a := 'v_admin := verificar_token_admin(p_token);' || E'\n' ||
         '  if v_admin is null then' || E'\n' ||
         '    return jsonb_build_object(''ok'', false, ''error'', ''NO_AUTORIZADO'');' || E'\n' ||
         '  end if;';
  v_b := v_a || E'\n\n' ||
         '  -- El cajero no toca el horario: solo administra caja y validaciones.' || E'\n' ||
         '  if (select rol from admin_tokens where id = v_admin) = ''cajero'' then' || E'\n' ||
         '    return jsonb_build_object(''ok'', false, ''error'', ''SIN_PERMISO'',' || E'\n' ||
         '      ''mensaje'', ''El cajero no puede tocar el horario. Pide a un administrador.'');' || E'\n' ||
         '  end if;';

  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro el bloque de NO_AUTORIZADO exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  execute v_def;
end $$;
