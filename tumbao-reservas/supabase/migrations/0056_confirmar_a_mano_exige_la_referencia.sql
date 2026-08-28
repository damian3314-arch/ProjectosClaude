-- ---------------------------------------------------------------------
-- 0056 — Confirmar a mano exige la referencia del comprobante
--
-- POR QUÉ
-- "Confirmar igual" era un solo clic, sin pedir nada. La cajera podía
-- darle a ojo, y de hecho es como entraron a la caja reservas cuya plata
-- nunca apareció: en el histórico hay 23 apuntadas sin ningún rastro de
-- pago. La decisión de la dueña es que no se confirme sin tener el
-- comprobante delante.
--
-- POR QUÉ LA REFERENCIA Y NO LA FOTO
-- Se pidió "la imagen del pago". La imagen no se puede exigir todavía:
-- hoy no hay forma de subirla —comprobante_url está vacío en las 17
-- reservas que han pasado por validación— y montarlo es otra cosa. Pero
-- además la referencia es mejor control que la foto:
--
--   · da el mismo freno: para teclearla hay que tener el comprobante
--   · SÍ se puede verificar después, buscándola en el extracto
--   · sale en la línea "Por revisar" de la tirilla del cierre
--   · y permite lo de abajo, que la foto no permitía
--
-- Una foto, en cambio, puede ser vieja o editada, y el propio panel ya
-- lo decía: "la foto del comprobante no comprueba nada".
--
-- EL MISMO COMPROBANTE NO SE USA DOS VECES
-- Al exigir la referencia se puede comprobar que no esté ya aplicada a
-- otra reserva. Antes no había con qué: dos personas podían mandar la
-- misma captura y las dos quedaban confirmadas. Ahora la segunda avisa.
-- Los grupos quedan fuera de la comprobación a propósito: comparten un
-- solo depósito, y es el mismo criterio del índice
-- reservas_referencia_unica, que exime a los miembros de un grupo.
--
-- LA REFERENCIA NO PISA LA DEL CLIENTE
-- Si la reserva ya traía una (la que tecleó quien pagó), se conserva. La
-- de la cajera solo llena el hueco cuando no había ninguna.
--
-- NO ES OBLIGATORIA AQUÍ
-- El parámetro va con DEFAULT null y la función sigue confirmando sin
-- él. Quien exige la referencia es el panel, que es donde está la
-- cajera. Así, cruzar desde la cola con "Es este" —que enlaza un
-- depósito REAL del banco, mejor prueba que cualquier referencia— sigue
-- funcionando sin escribir nada.
-- ---------------------------------------------------------------------
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_confirmar'
     and pg_get_function_identity_arguments(p.oid) = 'p_token text, p_codigo text, p_pago_id uuid';
  if v_def is null then
    raise exception 'no existe admin_confirmar(text, text, uuid)';
  end if;
  if position('0056:' in v_def) > 0 then
    raise notice 'ya estaba aplicada';
    return;
  end if;

  -- 1. El parámetro nuevo, al final y con DEFAULT: PostgREST resuelve
  -- por los argumentos que recibe, así que quien no lo mande sigue
  -- funcionando igual.
  v_def := replace(v_def,
    'admin_confirmar(p_token text, p_codigo text, p_pago_id uuid DEFAULT NULL::uuid)',
    'admin_confirmar(p_token text, p_codigo text, p_pago_id uuid DEFAULT NULL::uuid, ' ||
    'p_referencia text DEFAULT NULL::text)');

  -- 2. La comprobación de comprobante repetido, justo antes de tocar el
  -- pago. Va después de calcular v_grupo porque necesita saber cuál es.
  v_def := replace(v_def,
    '  if p_pago_id is not null then',
    '  -- 0056: el mismo comprobante no se aplica a dos reservas. Los' || E'\n' ||
    '  -- miembros de un grupo si lo comparten: pagan con un solo' || E'\n' ||
    '  -- deposito, igual que en el indice reservas_referencia_unica.' || E'\n' ||
    '  if nullif(btrim(coalesce(p_referencia, '''')), '''') is not null' || E'\n' ||
    '     and exists (select 1 from reservas' || E'\n' ||
    '                  where upper(btrim(referencia_pago)) = upper(btrim(p_referencia))' || E'\n' ||
    '                    and coalesce(grupo_id, id) <> v_grupo) then' || E'\n' ||
    '    return jsonb_build_object(''ok'', false, ''error'', ''REFERENCIA_REPETIDA'',' || E'\n' ||
    '      ''mensaje'', ''Ese comprobante ya se uso en otra reserva. Revisa que no ''' || E'\n' ||
    '                  ''sea el mismo pago contado dos veces.'');' || E'\n' ||
    '  end if;' || E'\n\n' ||
    '  if p_pago_id is not null then');

  -- 3. Guardarla, sin pisar la que dio el cliente.
  v_def := replace(v_def,
    '           pago_id = coalesce(p_pago_id, pago_id),',
    '           pago_id = coalesce(p_pago_id, pago_id),' || E'\n' ||
    '           -- 0056: solo llena el hueco. La que tecleo quien pago' || E'\n' ||
    '           -- manda sobre la de la cajera.' || E'\n' ||
    '           referencia_pago = coalesce(referencia_pago,' || E'\n' ||
    '                                      nullif(btrim(p_referencia), '''')),');

  execute v_def;

  -- Anadir un parametro no reemplaza la funcion: crea una sobrecarga. Con
  -- las dos vivas, una llamada de tres argumentos queda ambigua y
  -- PostgREST devuelve error. Se borra la vieja en la misma transaccion,
  -- asi que no hay un instante sin funcion.
  drop function if exists public.admin_confirmar(text, text, uuid);
end $$;

-- LOS PERMISOS NO VIAJAN CON LA FIRMA
-- 0017 le habia quitado el execute a public/anon/authenticated, pero ese
-- revoke iba pegado a la firma vieja de tres argumentos. Al nacer la de
-- cuatro nace limpia, y limpia quiere decir que public la puede ejecutar:
-- quedaria expuesta por PostgREST con la llave anon, como no lo esta
-- ninguna otra admin_*. Se repite aqui el mismo par de 0017.
revoke execute on function admin_confirmar(text, text, uuid, text)
  from public, anon, authenticated;
grant  execute on function admin_confirmar(text, text, uuid, text)
  to service_role;
