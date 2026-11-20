-- 0168 · Recepción puede apuntar «con plan» a quien AdminGym todavía no muestra.
--
-- Damián (10 oct): la mensualidad de Daniela Jaimes no sale en AdminGym (se arregla mañana) y recepción necesita
-- apuntarla a mano. En «Apuntar a alguien → Tiene plan» el sistema contestaba MEMBRESIA_NO_ENCONTRADA («ese celular no
-- está en la lista de afiliados») porque tomar_cupo exige una mensualidad vigente en el espejo de AdminGym, y no había
-- forma de seguir.
--
-- Qué cambia:
--   · admin_crear_reserva acepta un medio nuevo, 'plan_manual', SOLO con tipo 'miembro'. Es la confirmación explícita de
--     recepción: «ya sé que no sale en AdminGym, apúntala con plan igual».
--   · Para eso avisa a tomar_cupo con un ajuste LOCAL a la transacción (tumbao.plan_manual = '1'). tomar_cupo no cambia de
--     firma ni de permisos: sigue solo para service_role, y el ajuste solo lo pone admin_crear_reserva, que exige token de
--     administrador. Desde la página pública no hay forma de activarlo.
--   · Con ese aviso, si no hay mensualidad, tomar_cupo NO la rechaza: la reserva sale tipo 'miembro', confirmada, sin cobro y
--     sin membresia_id. No sabe a qué hora es su plan, así que no aplica el «tu plan ya te cubre esta clase» ni el cambio de
--     horario. Lo demás sigue igual: aforo, cupo de miembros del sábado, clase cancelada o pasada.
--   · La reserva queda marcada para poder revisarla después: pagador_nombre = «Plan a mano (no estaba en AdminGym)» (+ la nota).
--
-- Lo que NO hace: no crea una mensualidad en el espejo (importar_membresias lo reemplaza todo cada día, así que se perdería) y
-- por eso su cupo de plan no cuenta en los topes de la página de mensualidad hasta que AdminGym la traiga.
--
-- Se parchea sobre la definición viva con anclas exactas, y si una ancla no aparece se detiene sin tocar nada.

do $m$
declare
  d text;
  n text;
  v_firma_tomar regprocedure := 'public.tomar_cupo(uuid,text,text,text,text,text,text)'::regprocedure;
  v_firma_admin regprocedure := 'public.admin_crear_reserva(text,uuid,text,text,text,text,text)'::regprocedure;
begin
  ----------------------------------------------------------------------
  -- tomar_cupo
  ----------------------------------------------------------------------
  d := pg_get_functiondef(v_firma_tomar);
  if position('tumbao.plan_manual' in d) = 0 then
    n := d;

    if position($a$  v_clase     clases%rowtype;$a$ in n) = 0 then raise exception '0168: falta el ancla 1 de tomar_cupo'; end if;
    n := replace(n, $a$  v_clase     clases%rowtype;$a$,
                    $a$  v_clase     clases%rowtype;
  -- 0168: recepción confirmó «apúntala con plan igual» aunque no salga en AdminGym.
  v_manual    boolean := false;$a$);

    if position($a$    if not found then
      return jsonb_build_object('ok', false, 'error', 'MEMBRESIA_NO_ENCONTRADA',$a$ in n) = 0 then raise exception '0168: falta el ancla 2 de tomar_cupo'; end if;
    n := replace(n, $a$    if not found then
      return jsonb_build_object('ok', false, 'error', 'MEMBRESIA_NO_ENCONTRADA',$a$,
                    $a$    if not found and coalesce(current_setting('tumbao.plan_manual', true), '') = '1' then
      v_manual := true;
    elsif not found then
      return jsonb_build_object('ok', false, 'error', 'MEMBRESIA_NO_ENCONTRADA',$a$);

    if position($a$    if not v_es_sabado then
      if v_memb.hora = v_hora then$a$ in n) = 0 then raise exception '0168: falta el ancla 3 de tomar_cupo'; end if;
    n := replace(n, $a$    if not v_es_sabado then
      if v_memb.hora = v_hora then$a$,
                    $a$    if not v_es_sabado and not v_manual then
      if v_memb.hora = v_hora then$a$);

    execute n;
  end if;

  ----------------------------------------------------------------------
  -- admin_crear_reserva
  ----------------------------------------------------------------------
  d := pg_get_functiondef(v_firma_admin);
  if position('plan_manual' in d) = 0 then
    n := d;

    if position($a$v_medio not in ('efectivo', 'transferencia', 'en_puerta') then$a$ in n) = 0 then raise exception '0168: falta el ancla 1 de admin_crear_reserva'; end if;
    n := replace(n, $a$v_medio not in ('efectivo', 'transferencia', 'en_puerta') then$a$,
                    $a$v_medio not in ('efectivo', 'transferencia', 'en_puerta', 'plan_manual') then$a$);

    if position($a$  v_r := tomar_cupo(p_clase_id, btrim(p_nombre), v_tel, null,$a$ in n) = 0 then raise exception '0168: falta el ancla 2 de admin_crear_reserva'; end if;
    n := replace(n, $a$  v_r := tomar_cupo(p_clase_id, btrim(p_nombre), v_tel, null,$a$,
                    $a$  -- 0168: «apúntala con plan igual»: solo con plan, y solo dura esta transacción.
  if v_medio = 'plan_manual' then
    if p_tipo <> 'miembro' then
      return jsonb_build_object('ok', false, 'error', 'MEDIO_INVALIDO',
        'mensaje', 'Apuntar a mano con plan solo aplica a quien tiene plan.');
    end if;
    perform set_config('tumbao.plan_manual', '1', true);
  end if;

  v_r := tomar_cupo(p_clase_id, btrim(p_nombre), v_tel, null,$a$);

    if position($a$  if (v_r->>'ok')::boolean is not true then
    return v_r;$a$ in n) = 0 then raise exception '0168: falta el ancla 3 de admin_crear_reserva'; end if;
    n := replace(n, $a$  if (v_r->>'ok')::boolean is not true then
    return v_r;$a$,
                    $a$  perform set_config('tumbao.plan_manual', '', true);

  if (v_r->>'ok')::boolean is not true then
    return v_r;$a$);

    if position($a$  v_precio := coalesce((v_r->>'precio_cop')::int, 0);$a$ in n) = 0 then raise exception '0168: falta el ancla 4 de admin_crear_reserva'; end if;
    n := replace(n, $a$  v_precio := coalesce((v_r->>'precio_cop')::int, 0);$a$,
                    $a$  -- 0168: la marca para revisarla cuando AdminGym la traiga.
  if v_medio = 'plan_manual' then
    update reservas
       set pagador_nombre = left('Plan a mano (no estaba en AdminGym)'
                                 || coalesce(' · ' || nullif(btrim(p_nota), ''), ''), 80)
     where codigo = v_cod;
  end if;

  v_precio := coalesce((v_r->>'precio_cop')::int, 0);$a$);

    if position($a$    'cobra_en_puerta', v_puerta,$a$ in n) = 0 then raise exception '0168: falta el ancla 5 de admin_crear_reserva'; end if;
    n := replace(n, $a$    'cobra_en_puerta', v_puerta,$a$,
                    $a$    'cobra_en_puerta', v_puerta,
    'plan_manual', coalesce(v_medio = 'plan_manual', false),$a$);

    execute n;
  end if;
end
$m$;
