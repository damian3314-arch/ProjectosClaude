-- ---------------------------------------------------------------------
-- Confirmar a mano exige la referencia — prueba de humo (0056)
--
-- "Confirmar igual" era un clic sin nada detrás. La decisión de la dueña
-- es que la cajera no confirme sin tener el comprobante delante, así que
-- ahora el panel pide la referencia que aparece en él.
--
-- Lo que esta prueba defiende, además de que se guarde: que el mismo
-- comprobante no se pueda aplicar a dos reservas distintas, y que la
-- referencia que tecleó quien pagó no se pise con la de la cajera.
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on
set client_min_messages = notice;

create temp table fallos (que text, esperado text, obtenido text);
create or replace function chk(que text, obtenido anyelement, esperado anyelement)
returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then
    insert into fallos values (que, esperado::text, coalesce(obtenido::text,'(null)'));
    raise notice '  x %  (esperaba %, llegó %)', que, esperado, coalesce(obtenido::text,'null');
  else
    raise notice '  v %', que;
  end if;
end $$;

create temp table ctx (token text);
insert into ctx select crear_token_admin('cajera de prueba 0056')->>'token';
create or replace function tk() returns text language sql stable as $$ select token from ctx $$;
create or replace function hoy() returns date language sql stable as
  $$ select (now() at time zone 'America/Bogota')::date $$;
update ajustes set valor = (hoy() - 60)::text where clave = 'inicio_produccion';

insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('a1111111-0000-4000-8000-000000000001','Clase de manana','Prof',
        (hoy() + 1 + time '18:00') at time zone 'America/Bogota', 30, 15000);

insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, created_at)
values ('a2222222-0000-4000-8000-000000000001','REF-01','a1111111-0000-4000-8000-000000000001',
        'Uno Sinref','3500000001','pendiente_validacion','suelta','formulario', now()),
       ('a2222222-0000-4000-8000-000000000002','REF-02','a1111111-0000-4000-8000-000000000001',
        'Dos Sinref','3500000002','pendiente_validacion','suelta','formulario', now()),
       ('a2222222-0000-4000-8000-000000000003','REF-03','a1111111-0000-4000-8000-000000000001',
        'Tres Conref','3500000003','pendiente_validacion','suelta','formulario', now());
update reservas set referencia_pago = 'LA-DEL-CLIENTE'
 where codigo = 'REF-03';

\echo ''
\echo '-- La cajera teclea la referencia del comprobante -----------------------'
select chk('confirma con referencia',
  admin_confirmar(tk(), 'REF-01', null, 'M14537967')->>'estado', 'confirmada');
select chk('y queda guardada para buscarla en el extracto',
  (select referencia_pago from reservas where codigo='REF-01'), 'M14537967');

\echo ''
\echo '-- EL MISMO COMPROBANTE NO SE USA DOS VECES -----------------------------'
-- Dos personas mandando la misma captura: antes las dos quedaban
-- confirmadas y la plata se contaba dos veces.
select chk('la segunda reserva con la misma referencia se rechaza',
  admin_confirmar(tk(), 'REF-02', null, 'M14537967')->>'error', 'REFERENCIA_REPETIDA');
select chk('y esa reserva NO se confirmo',
  (select estado::text from reservas where codigo='REF-02'), 'pendiente_validacion');
select chk('da igual como se escriba (mayusculas, espacios)',
  admin_confirmar(tk(), 'REF-02', null, '  m14537967  ')->>'error', 'REFERENCIA_REPETIDA');

\echo ''
\echo '-- La del cliente manda sobre la de la cajera ---------------------------'
select chk('confirma',
  admin_confirmar(tk(), 'REF-03', null, 'OTRA-DISTINTA')->>'estado', 'confirmada');
select chk('y conserva la que tecleo quien pago',
  (select referencia_pago from reservas where codigo='REF-03'), 'LA-DEL-CLIENTE');

\echo ''
\echo '-- Sin referencia sigue funcionando: es lo que usa "Es este" ------------'
-- Cruzar con un deposito real del banco es mejor prueba que cualquier
-- referencia, asi que ese camino no puede quedar bloqueado.
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, created_at)
values ('a2222222-0000-4000-8000-000000000004','REF-04','a1111111-0000-4000-8000-000000000001',
        'Cuatro Deposito','3500000004','pendiente_validacion','suelta','formulario', now());
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila)
values ('a3333333-0000-4000-8000-000000000001','Bancolombia',15000,now(),
        'CUATRO DEPOSITO','1096803067','h-ref-1');
select chk('confirma enlazando el deposito, sin referencia',
  admin_confirmar(tk(), 'REF-04', 'a3333333-0000-4000-8000-000000000001', null)->>'estado',
  'confirmada');
select chk('y el deposito queda consumido',
  (select consumido from pagos where id='a3333333-0000-4000-8000-000000000001'), true);

\echo ''
\echo '-- Un grupo SI comparte comprobante: pagan con un solo deposito ---------'
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen,
                      grupo_id, created_at)
values ('a2222222-0000-4000-8000-000000000005','REF-05','a1111111-0000-4000-8000-000000000001',
        'Grupo Uno','3500000005','pendiente_validacion','suelta','web',
        'a2222222-0000-4000-8000-000000000005', now()),
       ('a2222222-0000-4000-8000-000000000006','REF-06','a1111111-0000-4000-8000-000000000001',
        'Grupo Dos','3500000006','pendiente_validacion','suelta','web',
        'a2222222-0000-4000-8000-000000000005', now());

select chk('el grupo se confirma entero con una sola referencia',
  (admin_confirmar(tk(), 'REF-05', null, 'DEL-GRUPO-9')->>'cupos')::int, 2);
select chk('y las dos la llevan',
  (select count(*)::int from reservas
    where grupo_id='a2222222-0000-4000-8000-000000000005'
      and referencia_pago='DEL-GRUPO-9'), 2);

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
