-- ---------------------------------------------------------------------
-- 0057 — Varios depósitos que son un solo pago
--
-- EL CASO, DEL 28 DE AGOSTO
-- El bot de WhatsApp le dijo a una clienta que había plan de media
-- mensualidad. No existe. La señora consignó $85.000 por ese plan
-- inventado; recepción le explicó, y consignó $40.000 más para completar
-- los $125.000 de la mensualidad de verdad.
--
-- En la caja no había forma de decir eso. `caja_registrar` exige que el
-- movimiento no valga más que el depósito al que se enlaza, y
-- `caja_movimientos` tiene una sola columna `pago_id`. Las únicas
-- salidas eran dos líneas —una "media mensualidad" de $85.000 y un
-- "otro ingreso" de $40.000, que en la tirilla no dicen que son la misma
-- persona pagando la misma cosa— o dejar los $40.000 sin dueño.
--
-- LA 0039 RESOLVIÓ EL CASO CONTRARIO
-- Ahí un depósito de $30.000 pagaba dos clases de $15.000: UN depósito,
-- VARIOS cobros. Esto es al revés: VARIOS depósitos, UN cobro.
--
-- LO QUE HACE
-- Un depósito se puede marcar como PARTE de otro. No se fusionan las
-- filas ni se suman los valores en la base: los dos siguen ahí con lo
-- que de verdad mandó el banco. Lo único que cambia es que la caja los
-- mira juntos: el grupo tiene un saldo de $125.000 y se cobra de una.
--
-- POR QUÉ NO SE TOCA `valor_cop` NI SE BORRA NADA
-- "Bancolombia reportó hoy" sale de `sum(valor_cop)` sobre `pagos`, sin
-- mirar consumido ni usado. Si se fusionaran las filas de verdad, esa
-- cifra dejaría de cuadrar contra el extracto. Dos transferencias
-- llegaron: el extracto dice dos, y la tirilla tiene que poder decir
-- dos. Lo que se agrupa es el COBRO, no lo que hizo el banco.
--
-- POR QUÉ EL GRUPO ENTERO QUEDA `consumido`
-- Mismo motivo que en la 0039: `consumido` le dice al cruce automático
-- de reservas "de este no te ocupes". Si la cabeza del grupo siguiera
-- libre, el cruce podría adjudicarle los $85.000 a una reserva y
-- llevarse media mensualidad de alguien. Un grupo se reparte a mano,
-- mirándolo, que es justo lo que pasó aquí.
--
-- SE PUEDE DESHACER
-- `caja_separar_pago` devuelve un depósito a estar solo. Esto lo va a
-- usar una persona con prisa en el mostrador; equivocarse juntando dos
-- que no eran no puede ser un camino sin regreso.
-- ---------------------------------------------------------------------

alter table pagos add column if not exists fusionado_en uuid references pagos(id);

comment on column pagos.fusionado_en is
  'Este depósito es parte de otro: los dos juntos son un solo pago. '
  'Null = va solo. La cabeza del grupo tiene fusionado_en null y al '
  'menos un depósito apuntándole.';

create index if not exists pagos_fusionado_en_idx
  on pagos (fusionado_en) where fusionado_en is not null;

-- Cuánta plata le queda SIN ASIGNAR al grupo: lo que le queda a la
-- cabeza más lo que les queda a sus partes. Para un depósito solo es
-- exactamente lo de siempre (valor - usado), así que se puede usar en
-- todas partes sin distinguir casos.
create or replace function saldo_grupo(p_id uuid)
returns int
language sql
stable
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
  select coalesce(sum(x.valor_cop - x.usado_cop), 0)::int
    from pagos x
   where x.id = p_id or x.fusionado_en = p_id;
$$;

comment on function saldo_grupo(uuid) is
  'Lo que le queda sin asignar a un depósito contando sus partes. '
  'Para uno que va solo es valor_cop - usado_cop.';

-- La lista de "plata sin dueño" pasa por aquí. Las partes no se
-- muestran solas —ya están representadas por su cabeza— y una cabeza se
-- muestra aunque esté `consumido`, porque en un grupo eso solo quiere
-- decir "no lo cruces automáticamente", no "ya se gastó".
create or replace view pagos_sin_asignar as
  select p.*, saldo_grupo(p.id) as saldo_grupo_cop,
         exists (select 1 from pagos h where h.fusionado_en = p.id) as es_grupo
    from pagos p
   where p.fusionado_en is null
     and saldo_grupo(p.id) > 0
     and (not p.consumido
          or p.usado_cop > 0
          or exists (select 1 from pagos h where h.fusionado_en = p.id));

comment on view pagos_sin_asignar is
  'Depósitos con plata todavía sin adjudicar, ya agrupados. Una fila '
  'por grupo, con saldo_grupo_cop = lo que queda entre todas sus partes.';

-- Gastar del grupo: primero la cabeza, después las partes de la más
-- vieja a la más nueva. El orden importa poco para la plata pero mucho
-- para leerlo después: se gasta en el orden en que el banco los recibió.
create or replace function gastar_del_grupo(p_id uuid, p_valor int)
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_falta int := p_valor;
  v_toma  int;
  r       record;
begin
  for r in
    select x.id, x.valor_cop - x.usado_cop as saldo
      from pagos x
     where x.id = p_id or x.fusionado_en = p_id
     order by (x.id <> p_id), x.fecha_pago
     for update
  loop
    exit when v_falta <= 0;
    v_toma := least(v_falta, greatest(r.saldo, 0));
    if v_toma > 0 then
      update pagos
         set usado_cop = usado_cop + v_toma,
             -- Igual que en la 0039: apenas se le muerde un pedazo sale
             -- del cruce automático. Lo que quede se reparte a mano.
             consumido = true
       where id = r.id;
      v_falta := v_falta - v_toma;
    end if;
  end loop;

  if v_falta > 0 then
    raise exception 'al grupo % no le alcanzaba: faltaron %', p_id, v_falta;
  end if;
end;
$$;

-- Devolver al grupo lo que se le había quitado, al revés: se le
-- devuelve primero a la última parte que puso. Así anular deja el grupo
-- como estaba antes de registrar, no repartido de otra forma.
create or replace function devolver_al_grupo(p_id uuid, p_valor int)
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_falta int := p_valor;
  v_da    int;
  r       record;
begin
  for r in
    select x.id, x.usado_cop, x.fusionado_en,
           exists (select 1 from pagos h where h.fusionado_en = x.id) as tiene_partes
      from pagos x
     where x.id = p_id or x.fusionado_en = p_id
     order by (x.id = p_id), x.fecha_pago desc
     for update
  loop
    exit when v_falta <= 0;
    v_da := least(v_falta, r.usado_cop);
    if v_da > 0 then
      update pagos
         set usado_cop = usado_cop - v_da,
             -- Un depósito que sigue en un grupo NO vuelve a quedar
             -- libre para el cruce automático aunque se le devuelva
             -- todo: sigue siendo parte de algo que se reparte a mano.
             consumido = case
               when r.fusionado_en is not null or r.tiene_partes then true
               else (usado_cop - v_da) > 0 end
       where id = r.id;
      v_falta := v_falta - v_da;
    end if;
  end loop;
end;
$$;

-- Juntar dos o más depósitos en uno solo. La cabeza es el más viejo: es
-- el que la persona mandó primero, y es como lo va a contar quien
-- reclame ("pagué 85 y después 40").
create or replace function caja_fusionar_pagos(p_token text, p_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_admin  uuid;
  v_cabeza uuid;
  v_n      int;
  v_total  int;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select count(distinct x) into v_n from unnest(coalesce(p_ids, '{}')) as x;
  if v_n < 2 then
    return jsonb_build_object('ok', false, 'error', 'FALTAN_DEPOSITOS',
      'mensaje', 'Hay que escoger al menos dos depósitos para juntarlos.');
  end if;
  if v_n > 10 then
    return jsonb_build_object('ok', false, 'error', 'DEMASIADOS',
      'mensaje', 'Diez depósitos es el tope. Si de verdad son más, revísalo con calma.');
  end if;

  if exists (select 1 from unnest(p_ids) as x
              where not exists (select 1 from pagos p where p.id = x)) then
    return jsonb_build_object('ok', false, 'error', 'PAGO_NO_EXISTE');
  end if;

  -- Ninguno puede venir ya de un grupo: juntar grupos de grupos hace
  -- que nadie sepa qué pagó qué. Primero se separa, después se junta.
  if exists (select 1 from pagos p
              where p.id = any(p_ids)
                and (p.fusionado_en is not null
                     or exists (select 1 from pagos h where h.fusionado_en = p.id))) then
    return jsonb_build_object('ok', false, 'error', 'YA_ESTA_EN_GRUPO',
      'mensaje', 'Alguno de esos depósitos ya está junto con otro. '
                 'Sepáralo primero si quieres rehacer el grupo.');
  end if;

  -- Nada que ya se haya adjudicado, ni entero ni a pedazos: esa plata
  -- ya tiene dueño en algún lado y moverla aquí la contaría dos veces.
  if exists (select 1 from pagos p
              where p.id = any(p_ids) and (p.usado_cop > 0 or p.consumido)) then
    return jsonb_build_object('ok', false, 'error', 'PAGO_YA_USADO',
      'mensaje', 'Alguno de esos depósitos ya está adjudicado. Recarga la lista.');
  end if;

  select p.id into v_cabeza
    from pagos p where p.id = any(p_ids)
   order by p.fecha_pago, p.id limit 1;

  update pagos
     set fusionado_en = v_cabeza,
         -- Sale del cruce automático: un grupo se reparte a mano.
         consumido = true
   where id = any(p_ids) and id <> v_cabeza;

  update pagos set consumido = true where id = v_cabeza;

  select saldo_grupo(v_cabeza) into v_total;

  return jsonb_build_object('ok', true, 'pago_id', v_cabeza,
                            'partes', v_n, 'total_cop', v_total);
end;
$$;

-- Deshacerlo. Se puede separar una parte suelta o, pasando la cabeza,
-- desarmar el grupo entero.
create or replace function caja_separar_pago(p_token text, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_admin uuid;
  v_pago  pagos%rowtype;
  v_n     int;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_pago from pagos where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'PAGO_NO_EXISTE');
  end if;

  -- Si al grupo ya se le cobró algo, separarlo dejaría movimientos
  -- apuntando a una repartición que ya no existe. Primero se anula el
  -- cobro, que para eso está `caja_anular`.
  if exists (select 1 from pagos x
              where (x.id = coalesce(v_pago.fusionado_en, p_id)
                     or x.fusionado_en = coalesce(v_pago.fusionado_en, p_id))
                and x.usado_cop > 0) then
    return jsonb_build_object('ok', false, 'error', 'GRUPO_YA_COBRADO',
      'mensaje', 'A ese grupo ya se le registró un ingreso. Anula primero '
                 'el movimiento en la caja y vuelve a intentarlo.');
  end if;

  if v_pago.fusionado_en is not null then
    update pagos set fusionado_en = null, consumido = false where id = p_id;
    v_n := 1;
    -- Si la cabeza se quedó sola, ya no es grupo: vuelve a estar libre.
    update pagos set consumido = false
     where id = v_pago.fusionado_en
       and not exists (select 1 from pagos h where h.fusionado_en = v_pago.fusionado_en);
  else
    update pagos set fusionado_en = null, consumido = false
     where fusionado_en = p_id;
    get diagnostics v_n = row_count;
    if v_n = 0 then
      return jsonb_build_object('ok', false, 'error', 'NO_ES_GRUPO',
        'mensaje', 'Ese depósito no está junto con ningún otro.');
    end if;
    update pagos set consumido = false where id = p_id;
  end if;

  return jsonb_build_object('ok', true, 'separados', v_n);
end;
$$;

revoke execute on function saldo_grupo(uuid), gastar_del_grupo(uuid, int),
                           devolver_al_grupo(uuid, int),
                           caja_fusionar_pagos(text, uuid[]),
                           caja_separar_pago(text, uuid)
  from public, anon, authenticated;
grant  execute on function saldo_grupo(uuid), gastar_del_grupo(uuid, int),
                           devolver_al_grupo(uuid, int),
                           caja_fusionar_pagos(text, uuid[]),
                           caja_separar_pago(text, uuid)
  to service_role;
revoke all on pagos_sin_asignar from public, anon, authenticated;
grant  select on pagos_sin_asignar to service_role;

-- ---------------------------------------------------------------------
-- Los parches a las funciones que ya existen. Se parchea el texto en vez
-- de reescribirlas enteras por lo mismo que la 0039, la 0055 y la 0056:
-- hay arreglos aplicados en producción que no están en el repositorio, y
-- reemplazar la función entera los borraría en silencio.
-- ---------------------------------------------------------------------
do $$
declare
  v_def text;
begin
  ------------------------------------------------------------------
  -- caja_registrar: el tope y el gasto pasan a ser del GRUPO
  ------------------------------------------------------------------
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_registrar';
  if v_def is null then raise exception 'no existe caja_registrar'; end if;

  if position('0057:' in v_def) = 0 then
    v_def := replace(v_def,
      'if v_pago.valor_cop - v_pago.usado_cop <= 0 then',
      '-- 0057: el saldo es el del grupo. Para un deposito solo,' || E'\n' ||
      '    -- saldo_grupo() da exactamente valor_cop - usado_cop.' || E'\n' ||
      '    if saldo_grupo(p_pago_id) <= 0 then');

    v_def := replace(v_def,
      'if p_valor > v_pago.valor_cop - v_pago.usado_cop then',
      'if p_valor > saldo_grupo(p_pago_id) then');
    v_def := replace(v_def,
      'to_char(v_pago.valor_cop - v_pago.usado_cop, ''FM999G999G999'')',
      'to_char(saldo_grupo(p_pago_id), ''FM999G999G999'')');

    -- Se cambia el UPDATE entero, con sus comentarios, por la llamada.
    -- Dejar el viejo apagado con un `if false` seria dejar dentro de la
    -- funcion una copia que ya no corre y que el siguiente que la lea va
    -- a creer que si.
    v_def := replace(v_def,
      '    update pagos' || E'\n' ||
      '       set usado_cop = usado_cop + p_valor,' || E'\n' ||
      '           -- Se marca consumido apenas se le usa un pedazo: es lo' || E'\n' ||
      '           -- que saca al depósito del cruce automático de reservas,' || E'\n' ||
      '           -- que se lo adjudicaría entero. Lo que le quede se' || E'\n' ||
      '           -- reparte a mano desde la caja.' || E'\n' ||
      '           consumido = true' || E'\n' ||
      '     where id = p_pago_id;',
      '    -- 0057: se reparte entre la cabeza del grupo y sus partes.' || E'\n' ||
      '    -- Para un deposito solo es el mismo update de antes.' || E'\n' ||
      '    perform gastar_del_grupo(p_pago_id, p_valor);');

    execute v_def;
    raise notice '0057: caja_registrar parcheada';
  end if;

  ------------------------------------------------------------------
  -- caja_anular: devolver tambien reparte
  ------------------------------------------------------------------
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_anular';
  if position('0057:' in v_def) = 0 then
    v_def := replace(v_def,
      '    update pagos' || E'\n' ||
      '       set usado_cop = greatest(usado_cop - v_mov.valor_cop, 0),' || E'\n' ||
      '           consumido = greatest(usado_cop - v_mov.valor_cop, 0) > 0' || E'\n' ||
      '     where id = v_mov.pago_id;',
      '    -- 0057: se le devuelve al grupo, en orden inverso al que se' || E'\n' ||
      '    -- gasto, para que quede como estaba antes de registrar.' || E'\n' ||
      '    perform devolver_al_grupo(v_mov.pago_id, v_mov.valor_cop);');
    execute v_def;
    raise notice '0057: caja_anular parcheada';
  end if;

  ------------------------------------------------------------------
  -- caja_del_dia: contar y listar por grupo
  ------------------------------------------------------------------
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if position('0057:' in v_def) = 0 then
    -- 1. Lo que reporto el banco se separa de lo que sigue sin dueno.
    -- Iban en un solo select y ahora miran cosas distintas: el primero
    -- TODOS los pagos del dia (es el extracto), el segundo los grupos.
    v_def := replace(v_def,
      '  select coalesce(sum(valor_cop), 0), max(fecha_pago),' || E'\n' ||
      '         coalesce(sum(valor_cop - usado_cop)' || E'\n' ||
      '                  filter (where valor_cop > usado_cop and (not consumido or usado_cop > 0)), 0),' || E'\n' ||
      '         count(*) filter (where valor_cop > usado_cop and (not consumido or usado_cop > 0))' || E'\n' ||
      '    into v_recibido, v_ultimo, v_libre_hoy, v_libre_hoy_n' || E'\n' ||
      '    from pagos where fecha_pago >= v_desde and fecha_pago < v_hasta;',
      '  -- 0057: lo que reporto el banco va sobre TODOS los pagos del' || E'\n' ||
      '  -- dia. Es el extracto: no depende de a quien se le adjudico ni' || E'\n' ||
      '  -- de si dos transferencias se juntaron en un solo cobro.' || E'\n' ||
      '  select coalesce(sum(valor_cop), 0), max(fecha_pago)' || E'\n' ||
      '    into v_recibido, v_ultimo' || E'\n' ||
      '    from pagos where fecha_pago >= v_desde and fecha_pago < v_hasta;' || E'\n\n' ||
      '  -- Lo que sigue sin dueno se cuenta por GRUPO: dos transferencias' || E'\n' ||
      '  -- juntas son una sola cosa por reclamar, no dos.' || E'\n' ||
      '  select coalesce(sum(saldo_grupo_cop), 0), count(*)' || E'\n' ||
      '    into v_libre_hoy, v_libre_hoy_n' || E'\n' ||
      '    from pagos_sin_asignar' || E'\n' ||
      '   where fecha_pago >= v_desde and fecha_pago < v_hasta;');

    -- 2. El contador de la ventana. De paso deja de sumar valor_cop y
    -- pasa a sumar el SALDO: un deposito de 30.000 al que ya se le
    -- cobraron 15.000 contaba entero, y no es cierto que sigan sin
    -- dueno 30.000. El de hoy (arriba) ya sumaba el saldo, asi que las
    -- dos cifras ademas dejan de contradecirse.
    v_def := replace(v_def,
      '  select coalesce(sum(valor_cop), 0), count(*)' || E'\n' ||
      '    into v_libre, v_libre_n' || E'\n' ||
      '    from pagos' || E'\n' ||
      '   where valor_cop > usado_cop and (not consumido or usado_cop > 0)' || E'\n' ||
      '     and fecha_pago >= v_corte;',
      '  select coalesce(sum(saldo_grupo_cop), 0), count(*)' || E'\n' ||
      '    into v_libre, v_libre_n' || E'\n' ||
      '    from pagos_sin_asignar' || E'\n' ||
      '   where fecha_pago >= v_corte;');

    -- 3. La lista. El saldo pasa a ser el del grupo y se dice de que
    -- partes se compone, para que la cajera vea las dos transferencias.
    v_def := replace(v_def,
      '               ''saldo_cop'', p.valor_cop - p.usado_cop) as x',
      '               ''saldo_cop'', p.saldo_grupo_cop,' || E'\n' ||
      '               ''es_grupo'', p.es_grupo,' || E'\n' ||
      '               ''partes'', case when not p.es_grupo then ''[]''::jsonb else' || E'\n' ||
      '                 coalesce((select jsonb_agg(jsonb_build_object(' || E'\n' ||
      '                             ''pago_id'', h.id, ''valor_cop'', h.valor_cop,' || E'\n' ||
      '                             ''remitente'', h.remitente,' || E'\n' ||
      '                             ''cuando'', to_char(h.fecha_pago at time zone ''America/Bogota'',' || E'\n' ||
      '                                                ''DD/MM HH24:MI''))' || E'\n' ||
      '                           order by h.fecha_pago)' || E'\n' ||
      '                     from pagos h' || E'\n' ||
      '                    where h.id = p.id or h.fusionado_en = p.id), ''[]''::jsonb) end) as x');

    v_def := replace(v_def,
      '        from pagos p' || E'\n' ||
      '       where p.valor_cop > p.usado_cop' || E'\n' ||
      '         and (not p.consumido or p.usado_cop > 0)' || E'\n' ||
      '         and p.fecha_pago >= v_corte',
      '        from pagos_sin_asignar p' || E'\n' ||
      '       where p.fecha_pago >= v_corte');

    execute v_def;
    raise notice '0057: caja_del_dia parcheada';
  end if;

  ------------------------------------------------------------------
  -- admin_pendientes: el tablero tambien lista por grupo
  ------------------------------------------------------------------
  -- Sin esto, juntar dos depositos los haria DESAPARECER del tablero:
  -- la cabeza queda `consumido` y ese es justo el filtro de esta lista.
  -- La cajera junta dos y se le esfuman; peor que no poder juntarlos.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_pendientes';
  if position('0057:' in v_def) = 0 then
    v_def := replace(v_def,
      '             ''cuando'',    to_char(p.fecha_pago at time zone ''America/Bogota'',' || E'\n' ||
      '                                  ''DD/MM HH24:MI'')) as y',
      '             ''cuando'',    to_char(p.fecha_pago at time zone ''America/Bogota'',' || E'\n' ||
      '                                  ''DD/MM HH24:MI''),' || E'\n' ||
      '             -- 0057: si son varios juntos, el valor que importa es' || E'\n' ||
      '             -- el del grupo; valor_cop sigue siendo el de esta fila.' || E'\n' ||
      '             ''saldo_cop'', p.saldo_grupo_cop,' || E'\n' ||
      '             ''es_grupo'',  p.es_grupo,' || E'\n' ||
      '             ''partes'',    case when not p.es_grupo then ''[]''::jsonb else' || E'\n' ||
      '               coalesce((select jsonb_agg(jsonb_build_object(' || E'\n' ||
      '                           ''pago_id'', h.id, ''valor_cop'', h.valor_cop,' || E'\n' ||
      '                           ''remitente'', h.remitente,' || E'\n' ||
      '                           ''cuando'', to_char(h.fecha_pago at time zone ''America/Bogota'',' || E'\n' ||
      '                                              ''DD/MM HH24:MI''))' || E'\n' ||
      '                         order by h.fecha_pago)' || E'\n' ||
      '                   from pagos h' || E'\n' ||
      '                  where h.id = p.id or h.fusionado_en = p.id), ''[]''::jsonb) end) as y');

    v_def := replace(v_def,
      '      from pagos p' || E'\n' ||
      '     where not p.consumido' || E'\n' ||
      '       and p.fecha_pago >= greatest(v_desde, now() - interval ''3 days'')',
      '      from pagos_sin_asignar p' || E'\n' ||
      '     where p.fecha_pago >= greatest(v_desde, now() - interval ''3 days'')');

    execute v_def;
    raise notice '0057: admin_pendientes parcheada';
  end if;
end $$;
