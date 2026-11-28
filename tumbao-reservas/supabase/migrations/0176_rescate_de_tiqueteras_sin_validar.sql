-- 0176 · Rescate de tiqueteras que quedaron sin validar
--
-- Damián (13 oct): revisando las tiqueteras por validar encontró personas que dijeron «ya pagué» y la plata no entró, y la
-- tiquetera no quedó activa. Nadie se había dado cuenta, y quien paga $96.000 por impulso y no recibe nada se enfría.
-- Pidió: 1) que a esas personas les llegue un mensaje a los ~15 minutos preguntando si pudieron pagar o si necesitan
-- ayuda; 2) que a la clase suelta NO se le haga nada (esa ya pide el comprobante por WhatsApp o lo muestra en la puerta).
--
-- QUÉ HACE tiquetera_recordar_pago() (pg_cron cada 2 minutos de 6 am a 10 pm, hora de Bogotá, igual que 0165):
--   Mira las tiqueteras COMPRADAS EN LÍNEA (no las que arma recepción ni los premios) que siguen en pendiente_pago o
--   pendiente_validacion, 15 minutos o más después de que la persona tocó «ya pagué» (o de que empezó la compra, si no
--   lo tocó), con un tope de 14 horas hacia atrás para no escribirle a compras viejas. Y a cada una, UNA sola vez:
--     a) si la persona REPORTÓ el pago: una nota a Damián (nota_asistente) con quién es, cuánto y cómo activarla.
--        Esa es la causa de fondo: nadie se enteraba de que había plata por validar. No depende de Meta.
--     b) un aviso por WhatsApp a la persona (plantilla de UTILIDAD tiquetera_pago_ayuda, ≈ $3): «¿pudiste hacer el pago?
--        si tuviste un inconveniente respóndeme». Solo con ajustes.wa_recordar_tiquetera = 'encendido'.
--   No se manda nada a quien: ya tiene otra tiquetera confirmada alrededor de esa compra (volvió a intentarlo y pagó, como
--   Dayana), pidió SALIR, es dueña/o, o no tiene celular válido. Tope de uno por persona al día.
--
-- La CLASE SUELTA no entra aquí: este archivo solo toca la tabla tiqueteras.
--
-- ajustes.wa_recordar_tiquetera nace en 'esperando_plantilla': el Worker lo pasa solo a 'encendido' cuando Meta apruebe
-- la plantilla (wa_recordar_tiquetera_activar). Con 'apagado' no sale nada por WhatsApp (la nota a Damián sí).
--
-- Además:
--   · Si la tiquetera se confirma entre que se encoló el aviso y se envió, el aviso se cancela solo (trigger).
--   · ventas_perfil: «tiquetera vigente» ahora es la CONFIRMADA. Antes bastaba con que la persona hubiera tocado «ya pagué»
--     (pagado_en), así que el asistente le decía «ya tienes tiquetera» a quien no la tenía activa, y no reconocía a las
--     confirmadas por el banco (que quedan con pagado_en vacío). Se suma 'tiquetera_pendiente' para que el asistente sepa.
--   · campana_tiquetera_constancia: el mismo arreglo en su filtro de «ya tiene tiquetera».
-- Aditivo salvo las dos funciones reemplazadas (cada una falla si no encuentra la línea que cambia).

insert into ajustes (clave, valor, nota) values
  ('wa_recordar_tiquetera', 'esperando_plantilla',
   'Aviso por WhatsApp a quien compró una tiquetera, tocó «ya pagué» y a los 15 min sigue sin activarse (una vez). esperando_plantilla → el Worker lo pasa a encendido cuando Meta aprueba tiquetera_pago_ayuda; encendido / apagado. 0176.')
on conflict (clave) do nothing;

-- ── El Worker llama a esto: devuelve el estado y, si Meta ya aprobó la plantilla, lo enciende ──────────────────────
create or replace function public.wa_recordar_tiquetera_activar(p_aprobada boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v text;
begin
  if p_aprobada then
    update ajustes set valor = 'encendido' where clave = 'wa_recordar_tiquetera' and valor = 'esperando_plantilla';
  end if;
  select valor into v from ajustes where clave = 'wa_recordar_tiquetera';
  return jsonb_build_object('estado', coalesce(v, 'apagado'));
end;
$$;
revoke all on function public.wa_recordar_tiquetera_activar(boolean) from public, anon, authenticated;
grant execute on function public.wa_recordar_tiquetera_activar(boolean) to service_role;

-- ── La función principal ─────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.tiquetera_recordar_pago(p_ejecutar boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_encendido boolean := coalesce((select valor from ajustes where clave = 'wa_recordar_tiquetera'), 'apagado') = 'encendido';
  v_cand int := 0; v_avisos int := 0; v_notas int := 0; v_k int;
  r record;
  v_precio text; v_hora text; v_dia text;
begin
  for r in
    select t.id, t.codigo, btrim(coalesce(t.nombre, '')) nombre,
           initcap(split_part(btrim(coalesce(t.nombre, '')), ' ', 1)) primer,
           right(regexp_replace(coalesce(t.telefono, ''), '\D', '', 'g'), 10) tel,
           t.clases_totales, t.precio_cop, t.estado,
           (t.pagado_en is not null or t.estado = 'pendiente_validacion') reporto,
           coalesce(t.pagado_en, t.creada_en) ref
      from tiqueteras t
     where t.estado in ('pendiente_pago', 'pendiente_validacion')
       and t.creada_por is null and t.premio_de is null
       and coalesce(t.pagado_en, t.creada_en) <= now() - interval '15 minutes'
       and coalesce(t.pagado_en, t.creada_en) >= now() - interval '14 hours'
       and not exists (select 1 from tiqueteras o
                        where o.id <> t.id and o.estado = 'confirmada'
                          and right(regexp_replace(coalesce(o.telefono, ''), '\D', '', 'g'), 10)
                            = right(regexp_replace(coalesce(t.telefono, ''), '\D', '', 'g'), 10)
                          and o.creada_en > t.creada_en - interval '6 hours')
     order by coalesce(t.pagado_en, t.creada_en)
  loop
    v_cand := v_cand + 1;
    continue when not p_ejecutar;

    -- a) El aviso por WhatsApp a la persona (una vez por tiquetera, y una por persona cada 24 horas).
    v_k := 0;
    if v_encendido and r.tel ~ '^3[0-9]{9}$' and not wa_es_dueno(r.tel)
       and not exists (select 1 from wa_bajas b where b.telefono = r.tel)
       and not exists (select 1 from wa_avisos a
                        where a.telefono = r.tel and a.tipo = 'recordatorio_tiquetera'
                          and a.creado_at > now() - interval '24 hours') then
      insert into wa_avisos (clave, tipo, telefono, plantilla, variables, datos, vence_at)
      values ('recordatorio_tiquetera:' || r.id, 'recordatorio_tiquetera', r.tel, 'tiquetera_pago_ayuda',
              jsonb_build_array(coalesce(nullif(r.primer, ''), 'amigo(a)'),
                                'tu tiquetera de ' || r.clases_totales || ' clases'),
              jsonb_build_object('tiquetera_id', r.id),
              now() + interval '2 hours')
      on conflict (clave) do nothing;
      get diagnostics v_k = row_count;
      v_avisos := v_avisos + v_k;
    end if;

    -- b) La nota a Damián, solo si la persona dijo que pagó (ahí puede haber plata sin validar).
    if r.reporto then
      v_precio := replace(to_char(coalesce(r.precio_cop, 0), 'FM999,999,999'), ',', '.');
      select wa_hora_texto((r.ref at time zone 'America/Bogota')::time) into v_hora;
      v_dia := case when (r.ref at time zone 'America/Bogota')::date = (now() at time zone 'America/Bogota')::date
                    then 'hoy' else wa_fecha_texto((r.ref at time zone 'America/Bogota')::date) end;
      v_notas := v_notas + coalesce(nota_asistente(
        'Tiquetera sin validar: ' || coalesce(nullif(r.primer, ''), r.tel),
        r.nombre || ' (' || r.tel || ') compró la tiquetera de ' || r.clases_totales || ' clases ($' || v_precio
          || ') y dijo que ya pagó (' || v_dia || ' a las ' || v_hora || '), pero el pago no cruzó con el banco y su tiquetera NO está activa.'
          || E'\n\nPara activarla: panel → Tiqueteras → su nombre → Activar, con el depósito del banco o la referencia del comprobante. '
          || 'Apenas la actives, le llega solo su aviso de tiquetera activa con el código.'
          || E'\n\n' || case when v_k > 0 then 'Ya le mandé un WhatsApp preguntando si pudo pagar o necesita ayuda.'
                             when v_encendido then 'No le mandé WhatsApp (ya le escribí hoy, pidió no recibir mensajes o no tiene celular válido).'
                             else 'Todavía no le puedo escribir por WhatsApp: el mensaje está esperando la aprobación de Meta.' end,
        'tiq-sin-validar:' || r.id), 0);
    end if;
  end loop;

  return jsonb_build_object('candidatos', v_cand, 'avisos', v_avisos, 'notas', v_notas,
                            'whatsapp', case when v_encendido then 'encendido' else 'apagado' end,
                            'ejecutado', p_ejecutar);
end;
$$;
revoke all on function public.tiquetera_recordar_pago(boolean) from public, anon, authenticated;
grant execute on function public.tiquetera_recordar_pago(boolean) to service_role;

-- Cada 2 minutos de 6:00 a 21:58 Bogotá (11:00-02:58 UTC).
do $cron$
begin
  perform cron.unschedule('tumbao-recordar-tiquetera');
exception when others then null;
end
$cron$;
select cron.schedule('tumbao-recordar-tiquetera', '*/2 11-23,0-2 * * *', 'select public.tiquetera_recordar_pago()');

-- ── Si la tiquetera se confirma antes de que salga el aviso, el aviso se cancela ───────────────────────────────────
create or replace function public.tiquetera_cancela_recordatorio()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update wa_avisos set estado = 'omitido', motivo = 'ya_activa'
   where clave = 'recordatorio_tiquetera:' || new.id and estado = 'pendiente';
  return new;
exception when others then
  raise warning 'tiquetera_cancela_recordatorio: %', sqlerrm;
  return new;
end;
$$;
create or replace trigger tiquetera_cancela_recordatorio
  after update of estado on public.tiqueteras
  for each row when (new.estado = 'confirmada' and old.estado is distinct from 'confirmada')
  execute function public.tiquetera_cancela_recordatorio();

-- ── ventas_perfil: «tiquetera vigente» es la CONFIRMADA, y se suma la pendiente ───────────────────────────────────
do $$
declare
  v_def text := pg_get_functiondef('public.ventas_perfil(text)'::regprocedure);
  a1 text := $v$and tq.pagado_en is not null and tq.vence_el >= hoy and tq.clases_usadas < tq.clases_totales$v$;
  b1 text := $v$and tq.estado = 'confirmada' and tq.vence_el >= hoy and tq.clases_usadas < tq.clases_totales$v$;
  a2 text := $v$v_plan jsonb; v_tq jsonb;$v$;
  b2 text := $v$v_plan jsonb; v_tq jsonb; v_tp jsonb;$v$;
  a3 text := E'  return jsonb_build_object(\n    ''nombre'', r.nombre,';
  b3 text := E'  select jsonb_build_object(''clases'', tp.clases_totales, ''precio_cop'', tp.precio_cop, ''reporto_pago'', tp.pagado_en is not null or tp.estado = ''pendiente_validacion'') into v_tp\n'
          || E'    from tiqueteras tp where right(regexp_replace(tp.telefono, ''\\D'', '''', ''g''), 10) = t\n'
          || E'     and tp.estado in (''pendiente_pago'', ''pendiente_validacion'') and tp.premio_de is null\n'
          || E'     and coalesce(tp.pagado_en, tp.creada_en) >= now() - interval ''14 hours''\n'
          || E'   order by tp.creada_en desc limit 1;\n\n'
          || E'  return jsonb_build_object(\n    ''nombre'', r.nombre, ''tiquetera_pendiente'', v_tp,';
begin
  if position('''tiquetera_pendiente''' in v_def) > 0 then
    raise notice '0176: ventas_perfil ya cambiada';
    return;
  end if;
  if position(a1 in v_def) = 0 or position(a2 in v_def) = 0 or position(a3 in v_def) = 0 then
    raise exception '0176: no encontré las líneas de ventas_perfil que cambian';
  end if;
  execute replace(replace(replace(v_def, a1, b1), a2, b2), a3, b3);
end $$;

-- ── La campaña de constancia: «ya tiene tiquetera» = confirmada, o pagó y está por validar ─────────────────────────
do $$
declare
  v_def text := pg_get_functiondef('public.campana_tiquetera_constancia(boolean)'::regprocedure);
  a text := $v$and t.pagado_en is not null and t.vence_el >= hoy$v$;
  b text := $v$and (t.estado in ('confirmada', 'pendiente_validacion') or t.pagado_en is not null) and t.vence_el >= hoy$v$;
begin
  if position(b in v_def) > 0 then
    raise notice '0176: campana_tiquetera_constancia ya cambiada';
    return;
  end if;
  if position(a in v_def) = 0 then
    raise exception '0176: no encontré el filtro de tiquetera en campana_tiquetera_constancia';
  end if;
  execute replace(v_def, a, b);
end $$;
