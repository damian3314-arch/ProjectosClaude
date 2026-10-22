-- ---------------------------------------------------------------------
-- La invitación que no llegó — prueba de humo
--
-- EL CASO REAL, del 24 de agosto de 2026:
--
--   19:14  damian3314@gmail.com   → cuenta creada en Auth, invitación enviada
--   19:48  bailatumbao@gmail.com  → fila en admin_usuarios, NADA en auth.users
--   19:49  tanyizgus@hotmail.com  → fila en admin_usuarios, NADA en auth.users
--
-- GoTrue crea la cuenta y manda el correo en la misma operación: si el
-- envío falla, deshace la creación. El correo falló y se llevó la cuenta.
--
-- Lo que hizo que nadie se enterara durante tres semanas no fue el fallo
-- del correo, sino que `tiene_acceso` —`user_id is not null`— decía lo
-- mismo en tres situaciones que piden cosas distintas:
--
--   · la cuenta no existe            → hay que volver a invitar
--   · existe y no tiene contraseña   → hay que reenviar el enlace
--   · puso clave y no ha entrado     → no hay nada que hacer
--
-- `user_id` se rellena en el PRIMER LOGIN, así que por definición no
-- puede distinguir ninguno de los tres. La 0081 añadió `estado`, leído
-- de auth.users, y esto comprueba que dice la verdad.
--
--   psql -d <base> -f humo-invitacion.sql
--
-- No escribe nada: todo va dentro de una transacción que se deshace.
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on
set client_min_messages = notice;

begin;

create temp table fallos (que text, esperado text, obtenido text) on commit drop;

create or replace function pg_temp.chk(que text, obtenido anyelement, esperado anyelement)
returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then
    insert into fallos values (que, esperado::text, coalesce(obtenido::text, '(null)'));
    raise notice '  x %  (esperaba %, llegó %)', que, esperado, coalesce(obtenido::text, 'null');
  else
    raise notice '  v %', que;
  end if;
end $$;

create temp table ctx (token text) on commit drop;
insert into ctx select crear_token_admin('invitacion de prueba')->>'token';
create or replace function pg_temp.tk() returns text language sql stable as
  $$ select token from ctx $$;
-- crear_token_admin no pone rol. Estas dos funciones solo las puede
-- llamar un propietario, así que el token de prueba tiene que serlo.
update admin_tokens set rol = 'propietario'
 where token_hash = hash_token((select token from ctx));

create or replace function pg_temp.estado_de(p_email text) returns text
language sql stable as $$
  select x->>'estado'
    from jsonb_array_elements(
           (admin_listar_usuarios(pg_temp.tk()))->'usuarios') x
   where lower(x->>'email') = lower(p_email);
$$;

\echo ''
\echo '-- 1. Cada estado se dice por su nombre -----------------------------'
-- Se comprueba contra auth.users y no contra una lista escrita a mano:
-- así la prueba sigue valiendo cuando Luisa y Tanya por fin entren.

select pg_temp.chk('el estado de cada quien coincide con lo que dice Auth',
  (select coalesce(string_agg(u.email || ': dice ' || coalesce(pg_temp.estado_de(u.email), 'nada')
                              || ' y deberia ' || esperado, '; '), '(cuadran todos)')
     from (select u.email,
                  case when a.id is null then 'sin_invitar'
                       when length(coalesce(a.encrypted_password, '')) = 0 then 'invitado'
                       when a.last_sign_in_at is null then 'listo'
                       else 'activo' end as esperado
             from admin_usuarios u
             left join auth.users a on lower(a.email) = lower(u.email)) u
    where pg_temp.estado_de(u.email) is distinct from u.esperado),
  '(cuadran todos)');

-- Y el caso que destapó todo esto: quien no tiene cuenta en Auth no
-- puede aparecer como si solo le faltara entrar.
select pg_temp.chk('sin cuenta en Auth el estado es sin_invitar, nunca otro',
  (select count(*) from admin_usuarios u
    where not exists (select 1 from auth.users a where lower(a.email) = lower(u.email))
      and pg_temp.estado_de(u.email) <> 'sin_invitar'), 0::bigint);

\echo ''
\echo '-- 2. A quién hay que invitar, y cómo -------------------------------'
-- `en_auth` es lo que decide la ruta: sin cuenta hay que crearla
-- (`invite`); con cuenta hay que mandar el enlace de contraseña
-- (`recover`), porque un `invite` sobre una cuenta que ya existe
-- devuelve error y no manda nada.

select pg_temp.chk('en_auth dice la verdad para todos',
  (select count(*) from admin_usuarios u
    where ((admin_usuario_a_invitar(pg_temp.tk(), u.id))->>'en_auth')::boolean
       is distinct from exists (select 1 from auth.users a
                                 where lower(a.email) = lower(u.email))), 0::bigint);

select pg_temp.chk('y devuelve el correo al que hay que mandarlo',
  (select count(*) from admin_usuarios u
    where (admin_usuario_a_invitar(pg_temp.tk(), u.id))->>'email'
       is distinct from u.email), 0::bigint);

\echo ''
\echo '-- 3. No se invita a quien no puede entrar --------------------------'
-- Mandarle a poner contraseña a alguien desactivado es mandarle a hacer
-- un trámite que acaba en «tu acceso está desactivado».

create temp table victima as
  select id, activo from admin_usuarios order by email limit 1;
update admin_usuarios set activo = false where id = (select id from victima);

select pg_temp.chk('a alguien desactivado se le dice que no',
  (admin_usuario_a_invitar(pg_temp.tk(), (select id from victima)))->>'error', 'INACTIVO');

update admin_usuarios set activo = (select activo from victima)
 where id = (select id from victima);

select pg_temp.chk('un id que no existe no se inventa a nadie',
  (admin_usuario_a_invitar(pg_temp.tk(),
     '00000000-0000-4000-8000-000000000000'))->>'error', 'NO_EXISTE');

\echo ''
\echo '-- 4. Solo el propietario -------------------------------------------'
-- El Worker tiene la llave de servicio, que abre todo. Si el permiso se
-- decidiera allí, no habría nadie comprobándolo.

create temp table ctx2 (token text) on commit drop;
insert into ctx2 select crear_token_admin('cajera de prueba')->>'token';
update admin_tokens set rol = 'cajero'
 where token_hash = hash_token((select token from ctx2));

select pg_temp.chk('un cajero no puede invitar',
  (admin_usuario_a_invitar((select token from ctx2),
     (select id from admin_usuarios order by email limit 1)))->>'error', 'SIN_PERMISO');
select pg_temp.chk('ni ver la lista de usuarios',
  (admin_listar_usuarios((select token from ctx2)))->>'error', 'SIN_PERMISO');
select pg_temp.chk('y un token inventado, menos',
  (admin_usuario_a_invitar('esto-no-es-un-token',
     (select id from admin_usuarios order by email limit 1)))->>'error', 'NO_AUTORIZADO');

\echo ''
\echo '-- 5. La lista no deja de traer lo de antes -------------------------'
-- Un panel viejo en caché sigue leyendo `tiene_acceso`. Quitárselo sería
-- dejar sin lista a los navegadores del mostrador hasta que alguien los
-- recargue a mano.

select pg_temp.chk('tiene_acceso sigue viniendo',
  (select count(*) from jsonb_array_elements(
            (admin_listar_usuarios(pg_temp.tk()))->'usuarios') x
    where x->'tiene_acceso' is null), 0::bigint);

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;

-- Los dos tokens de prueba y el activo que se tocó se van con esto.
rollback;
