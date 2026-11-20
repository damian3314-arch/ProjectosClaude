-- ---------------------------------------------------------------------
-- Login con correo y contraseña, y los tres roles
--
-- LO QUE MIDE
-- Que un correo sin perfil no entre, que el rol viaje pegado al token
-- desde el primer login, que el cajero no pueda tocar el horario ni la
-- gestión de usuarios, que solo el propietario dé de alta gente o
-- cambie roles, y que desactivar a alguien le tumbe la sesión que ya
-- tenía abierta.
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on
set client_min_messages = notice;

do $$
declare
  v_uid_prop   uuid := extensions.gen_random_uuid();
  v_uid_admin  uuid := extensions.gen_random_uuid();
  v_uid_cajero uuid := extensions.gen_random_uuid();
  v_r          jsonb;
  v_tk_prop    text;
  v_tk_admin   text;
  v_tk_cajero  text;
  v_id_admin   uuid;
begin
  delete from admin_tokens;
  delete from admin_usuarios;
  insert into auth.users (id) values (v_uid_prop), (v_uid_admin), (v_uid_cajero);

  -- ═══ 0. El arranque: el primer propietario se da de alta solo ═══
  v_r := admin_bootstrap_propietario('primera@tumbaobaila.com', 'Primera Dueña');
  if (v_r->>'ok') <> 'true' then
    raise exception 'el primer arranque debería funcionar: %', v_r;
  end if;
  v_r := admin_bootstrap_propietario('otra@tumbaobaila.com', 'Otra');
  if (v_r->>'ok') <> 'false' or (v_r->>'error') <> 'YA_HAY_USUARIOS' then
    raise exception 'el arranque debería cerrarse solo tras el primero: %', v_r;
  end if;
  delete from admin_usuarios;
  raise notice '  v el arranque crea al primer propietario y luego se cierra solo';

  -- ═══ 1. Un correo que no está en el reparto no entra ═══
  v_r := admin_token_para_usuario(v_uid_prop, 'nadie@tumbaobaila.com');
  if (v_r->>'ok') <> 'false' or (v_r->>'error') <> 'sin_acceso' then
    raise exception 'un correo sin perfil debería rebotar: %', v_r;
  end if;
  raise notice '  v un correo sin perfil no entra';

  -- ═══ 2. Se da de alta a los tres, sin user_id todavía (como los  ═══
  -- ═══    daría de alta el propietario antes de que nadie entre)  ═══
  insert into admin_usuarios (email, nombre, rol) values
    ('duena@tumbaobaila.com',   'Dueña',   'propietario'),
    ('admin@tumbaobaila.com',   'Admin',   'administrador'),
    ('cajero@tumbaobaila.com',  'Cajero',  'cajero');

  -- ═══ 3. Primer login: se liga el user_id por correo y sale el rol ═══
  v_r := admin_token_para_usuario(v_uid_prop, 'DUENA@tumbaobaila.com');
  if (v_r->>'ok') <> 'true' or (v_r->>'rol') <> 'propietario' then
    raise exception 'la dueña debería entrar como propietario: %', v_r;
  end if;
  v_tk_prop := v_r->>'token';
  if not exists (select 1 from admin_usuarios where email = 'duena@tumbaobaila.com' and user_id = v_uid_prop) then
    raise exception 'el primer login debió ligar el user_id';
  end if;
  raise notice '  v el primer login liga el correo con la cuenta y trae el rol';

  v_tk_admin  := (admin_token_para_usuario(v_uid_admin,  'admin@tumbaobaila.com'))->>'token';
  v_tk_cajero := (admin_token_para_usuario(v_uid_cajero, 'cajero@tumbaobaila.com'))->>'token';

  -- ═══ 4. El cajero no toca el horario ═══
  v_r := admin_guardar_semana(v_tk_cajero, '[]'::jsonb);
  if (v_r->>'ok') <> 'false' or (v_r->>'error') <> 'SIN_PERMISO' then
    raise exception 'el cajero no debería poder guardar el horario: %', v_r;
  end if;
  raise notice '  v el cajero no puede tocar el horario';

  -- ═══ 5. El administrador sí puede ═══
  v_r := admin_guardar_semana(v_tk_admin, '[]'::jsonb);
  if (v_r->>'ok') <> 'true' then
    raise exception 'el administrador sí debería poder guardar el horario: %', v_r;
  end if;
  raise notice '  v el administrador sí puede tocar el horario';

  -- ═══ 6. Un token viejo, sin rol (el de Recepción), sigue con todo ═══
  v_r := admin_guardar_semana((crear_token_admin('Recepción de siempre'))->>'token', '[]'::jsonb);
  if (v_r->>'ok') <> 'true' then
    raise exception 'un token sin rol (el de antes) no debería perder acceso: %', v_r;
  end if;
  raise notice '  v un token de antes de los roles sigue con acceso total';

  -- ═══ 7. Solo el propietario ve y gestiona usuarios ═══
  v_r := admin_listar_usuarios(v_tk_admin);
  if (v_r->>'ok') <> 'false' or (v_r->>'error') <> 'SIN_PERMISO' then
    raise exception 'el administrador no debería poder listar usuarios: %', v_r;
  end if;
  v_r := admin_listar_usuarios(v_tk_cajero);
  if (v_r->>'ok') <> 'false' then
    raise exception 'el cajero no debería poder listar usuarios: %', v_r;
  end if;
  v_r := admin_listar_usuarios(v_tk_prop);
  if (v_r->>'ok') <> 'true' or jsonb_array_length(v_r->'usuarios') <> 3 then
    raise exception 'el propietario debería ver a los 3: %', v_r;
  end if;
  raise notice '  v solo el propietario ve el listado de usuarios';

  -- ═══ 8. Solo el propietario da de alta ═══
  v_r := admin_crear_usuario(v_tk_admin, 'Intrusa', 'intrusa@tumbaobaila.com', 'cajero', null);
  if (v_r->>'ok') <> 'false' then
    raise exception 'el administrador no debería poder crear usuarios: %', v_r;
  end if;
  v_r := admin_crear_usuario(v_tk_prop, 'Nueva Cajera', 'nueva@tumbaobaila.com', 'cajero', null);
  if (v_r->>'ok') <> 'true' then
    raise exception 'el propietario sí debería poder crear usuarios: %', v_r;
  end if;
  select id into v_id_admin from admin_usuarios where email = 'admin@tumbaobaila.com';
  raise notice '  v solo el propietario da de alta usuarios';

  -- ═══ 9. Un correo repetido no se puede volver a dar de alta ═══
  v_r := admin_crear_usuario(v_tk_prop, 'Otra Vez', 'admin@tumbaobaila.com', 'cajero', null);
  if (v_r->>'ok') <> 'false' or (v_r->>'error') <> 'YA_EXISTE' then
    raise exception 'un correo repetido debería rebotar: %', v_r;
  end if;
  raise notice '  v un correo que ya está no se puede repetir';

  -- ═══ 10. Al desactivar a alguien, se le cae la sesión que ya tenía ═══
  v_r := admin_cambiar_estado_usuario(v_tk_prop, v_id_admin, false);
  if (v_r->>'ok') <> 'true' then
    raise exception 'el propietario debería poder desactivar: %', v_r;
  end if;
  v_r := admin_guardar_semana(v_tk_admin, '[]'::jsonb);
  if (v_r->>'ok') <> 'false' or (v_r->>'error') <> 'NO_AUTORIZADO' then
    raise exception 'al administrador desactivado se le debió caer la sesión: %', v_r;
  end if;
  -- Y ya no puede volver a entrar con un login nuevo tampoco.
  v_r := admin_token_para_usuario(v_uid_admin, 'admin@tumbaobaila.com');
  if (v_r->>'ok') <> 'false' or (v_r->>'error') <> 'inactivo' then
    raise exception 'un desactivado no debería poder volver a entrar: %', v_r;
  end if;
  raise notice '  v desactivar tumba la sesión abierta y bloquea el próximo login';

  -- ═══ 11. El propietario puede cambiarle el rol a alguien ═══
  v_r := admin_cambiar_rol_usuario(v_tk_prop, v_id_admin, 'propietario');
  if (v_r->>'ok') <> 'true' then
    raise exception 'el propietario debería poder cambiar roles: %', v_r;
  end if;
  if (select rol from admin_usuarios where id = v_id_admin) <> 'propietario' then
    raise exception 'el rol no quedó cambiado';
  end if;
  raise notice '  v el propietario puede cambiar el rol de alguien';

  raise notice ' ';
  raise notice 'TODO EN VERDE';
end $$;
