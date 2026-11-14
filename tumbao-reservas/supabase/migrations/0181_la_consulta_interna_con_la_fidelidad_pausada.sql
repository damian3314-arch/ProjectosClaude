-- 0181 · La consulta interna «¿puedo procesar a Fulana?» respeta la pausa de la fidelidad
--
-- Con premium_fidelidad = 'pausada' (0180) nadie tiene que cumplir requisitos: todo cupo libre se vende a quien pague.
-- mensualidad_decision() es lo que el asistente interno le contesta a recepción; si siguiera diciendo «NO aplica», el
-- equipo le negaría la mensualidad a quien sí puede pagar en la página. Con la pausa:
--   · quien tiene historial: la respuesta depende solo del cupo del horario (el que muestra la página);
--   · quien no tiene historial o no se encuentra: se le aclara que igual puede pagar si hay cupo.
-- Con la fidelidad activa, todo se contesta como antes.

do $mig$
declare
  d text;
  nuevo text;
begin
  d := pg_get_functiondef('public.mensualidad_decision(text,text)'::regprocedure);
  if position('premium_pausado' in d) > 0 then
    raise notice '0181: mensualidad_decision ya respetaba la pausa';
    return;
  end if;
  nuevo := d;

  -- no se encuentra
  nuevo := replace(nuevo,
    $a$'respuesta', '❓ No la encuentro con ese dato. Pídele el celular o la cédula completa (o prueba con el otro dato).');$a$,
    $b$'respuesta', '❓ No la encuentro con ese dato. Pídele el celular o la cédula completa (o prueba con el otro dato).'
        || case when premium_pausado() then ' Ojo: la fidelidad está pausada, así que aunque no tenga historial puede pagar en la página si hay cupo en el horario.' else '' end);$b$);

  -- encontrada pero sin historial
  nuevo := replace(nuevo,
    $a$'respuesta', '❓ ' || v_nombre || ': no tiene historial con ese dato. Pídele el otro (celular o cédula).');$a$,
    $b$'respuesta', '❓ ' || v_nombre || ': no tiene historial con ese dato. Pídele el otro (celular o cédula).'
        || case when premium_pausado() then ' Ojo: la fidelidad está pausada, así que puede pagar en la página si hay cupo en el horario.' else '' end);$b$);

  -- con historial: solo cuenta el cupo del horario
  nuevo := replace(nuevo,
    $a$  if v_ver = 'aplica' then
    if v_hora is null then$a$,
    $b$  if premium_pausado() then
    if v_hora is null then
      v_resp := '✅ ' || v_nombre || ' (…' || v_tel4 || '): la fidelidad está pausada, no hay requisitos. Dime en qué horario la quieren (7 am, 6 pm o 7 pm) para decirte si hay cupo.';
    else
      select (h ->> 'libres')::int into v_libres
        from jsonb_array_elements(mensualidad_cupos() -> 'horas') h where h ->> 'hora' = v_hora;
      v_resp := case when coalesce(v_libres, 0) > 0
        then '✅ ' || v_nombre || ' (…' || v_tel4 || ') SÍ puede: la fidelidad está pausada y hay ' || v_libres || ' cupo(s) libre(s) a las ' || v_etq
             || '. Que pague su mensualidad en la página (escanea el QR) y se registra en AdminGym.'
        else '⏳ ' || v_nombre || ' (…' || v_tel4 || '): las ' || v_etq || ' están completas (contando los 5 días de gracia). Que se apunte a la lista de espera en tumbaobaila.com/mensualidad; mientras tanto, tiquetera o clase suelta.'
        end;
    end if;
    return jsonb_build_object('ok', true, 'estado', 'puede', 'persona', per, 'horario', v_hora, 'libres', v_libres,
      'respuesta', v_resp || coalesce(v_pago, ''));
  end if;

  if v_ver = 'aplica' then
    if v_hora is null then$b$);

  if (length(nuevo) - length(replace(nuevo, 'premium_pausado', ''))) / length('premium_pausado') <> 3 then
    raise exception '0181: no encontré los tres puntos de mensualidad_decision';
  end if;
  execute nuevo;
end
$mig$;

-- La nota de recepción de las 8:20 am («qué hacer hoy») también: con la fidelidad pausada, quien está en la fila y
-- tiene cupo recibe el aviso de «ya hay cupo, paga tu mensualidad» (no el de «ofréceles tiquetera»).
do $mig$
declare
  d text;
  nuevo text;
begin
  d := pg_get_functiondef('public.mensualidad_cupo_liberado_texto(text)'::regprocedure);
  if position('premium_pausado' in d) > 0 then
    raise notice '0181: mensualidad_cupo_liberado_texto ya respetaba la pausa';
    return;
  end if;
  nuevo := replace(d, 'x.aplica and x.orden <= v_libres', '(x.aplica or premium_pausado()) and x.orden <= v_libres');
  if (length(nuevo) - length(replace(nuevo, 'premium_pausado', ''))) / length('premium_pausado') <> 2 then
    raise exception '0181: no encontré los dos puntos de mensualidad_cupo_liberado_texto';
  end if;
  execute nuevo;
end
$mig$;
