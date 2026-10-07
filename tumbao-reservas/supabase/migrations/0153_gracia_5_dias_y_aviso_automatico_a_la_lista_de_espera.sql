-- 0153 · Gracia de 5 días y aviso automático a la lista de espera (6 pm y 7 pm, tope 23)
--
-- Damián (7 oct): «a la gente se le puede esperar 5 días como máximo para que renueve y se le guarda el
-- puesto; pasados esos 5 días se debe avisar al primero de la lista para que pague, y habilitarlo en la
-- página. Quiero garantizar un máximo de 23 mensualidades en 6 pm y 7 pm; el resto es para sueltas.»
--
-- Lo que ya existía y se conserva: el cupo se cuenta por persona hasta fin + gracia (0135); la página deja
-- pagar solo a quien cumple los requisitos y le toca por orden (premium_puede_pagar, 0133); el tope de
-- 23 por horario (premium_topes, 0134); la nota a recepción de las 8:20 (0135).
--
-- Lo nuevo:
--   1 · mensualidad_gracia_dias = 5. Las funciones de ventas tenían «fin + 3» fijo (ventas_candidatos,
--       ventas_candidatos_historial, ventas_perfil, campana_tiquetera_frecuentes2): ahora leen el ajuste,
--       para que el bot no le venda a quien todavía tiene su cupo guardado.
--   2 · mensualidad_avisar_lista_espera() (9:10 am, lunes a sábado):
--         · si un horario con tope (6 pm o 7 pm) tiene cupo libre, le escribe por WhatsApp a quien le toca
--           (el primero de mensualidad_fila que PUEDE pagar hoy: premium_puede_pagar), con la plantilla
--           ventas_apertura y una conversación de ventas con origen 'lista_espera' (el bot responde dudas
--           y manda a tumbaobaila.com/mensualidad; si no, pasa a recepción: 301 783 3550);
--         · la persona avisada tiene lista_espera_horas_para_pagar (48 h) para pagar; si no paga, su
--           solicitud pasa a 'anulada' y el aviso sigue con la siguiente (poner 0 en el ajuste = no rota);
--         · deja una nota a recepción con lo que hizo;
--         · alerta a recepción si algún horario con tope tiene más ocupadas que el tope.
--       Se apaga con ajustes.wa_lista_espera_auto = 'apagado'.
--   3 · ventas_perfil suma 'lista_espera' ({hora, libres, puede_pagar}) para que el bot hable del horario
--       correcto (6 pm o 7 pm) y solo prometa lo que la página deja pagar.
--   4 · La nota de las 8:20 dice que el sistema ya avisa por WhatsApp.

insert into ajustes (clave, valor, nota) values
  ('mensualidad_gracia_dias', '5', 'Días que se le guarda el cupo a una mensualidad vencida antes de liberarlo. 0153 (antes 3).'),
  ('wa_lista_espera_auto', 'encendido', 'Avisa por WhatsApp a quien le toca de la lista de espera cuando se libera un cupo de 6 pm o 7 pm. 0153.'),
  ('lista_espera_horas_para_pagar', '48', 'Horas que tiene quien recibió el aviso de cupo para pagar; después pasa a la siguiente (0 = no rota). 0153.')
on conflict (clave) do nothing;
update ajustes set valor = '5' where clave = 'mensualidad_gracia_dias' and valor = '3';

-- ── 1 · la gracia sale del ajuste en todas las funciones de ventas ─────────────────────────────────────
do $mig$
declare
  v_expr text := $e$fin + coalesce(nullif((select valor from ajustes where clave = 'mensualidad_gracia_dias'), '')::int, 3)$e$;
  r record; v_def text;
begin
  for r in
    select p.oid, p.proname from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('ventas_candidatos', 'ventas_candidatos_historial', 'ventas_perfil', 'campana_tiquetera_frecuentes2')
       and p.prosrc like '%fin + 3%'
  loop
    v_def := replace(pg_get_functiondef(r.oid), 'fin + 3', v_expr);
    execute v_def;
  end loop;

  -- ventas_perfil: a quien se le abrió desde la lista de espera, el bot sabe de qué horario y si puede pagar
  v_def := pg_get_functiondef('public.ventas_perfil(text)'::regprocedure);
  if position('''lista_espera''' in v_def) = 0 then
    if position('''paquetes_tiquetera'', tiquetera_paquetes());' in v_def) = 0 then
      raise exception 'ventas_perfil: no encuentro el texto a cambiar';
    end if;
    v_def := replace(v_def, '''paquetes_tiquetera'', tiquetera_paquetes());',
      $r$'paquetes_tiquetera', tiquetera_paquetes(),
    'lista_espera', (select jsonb_build_object('hora', c.oferta ->> 'hora',
                            'libres', coalesce((premium_cupos_horario() -> (c.oferta ->> 'hora') ->> 'libres')::int, 0),
                            'puede_pagar', coalesce(premium_puede_pagar(t, null, (c.oferta ->> 'hora')::time), false))
                       from ventas_chats c
                      where c.telefono = t and c.oferta ->> 'origen' = 'lista_espera' and c.oferta ? 'hora'
                        and c.estado in ('abierta', 'conversando')
                      order by c.id desc limit 1));$r$);
    execute v_def;
  end if;
end
$mig$;

-- ── 2 · el aviso automático ────────────────────────────────────────────────────────────────────────────
create or replace function public.mensualidad_avisar_lista_espera()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  hoy date := (now() at time zone 'America/Bogota')::date;
  v_horas int := coalesce(nullif((select valor from ajustes where clave = 'lista_espera_horas_para_pagar'), '')::int, 48);
  v_hold interval;
  v_hora text; v_etq text; v_tope int; v_ocup int; v_libres int;
  r record; v_tel text; v_nombre text; v_chat bigint; v_n int := 0; v_anuladas int := 0; v_alertas int := 0;
  v_ids uuid[];
begin
  if coalesce((select valor from ajustes where clave = 'wa_lista_espera_auto'), 'encendido') <> 'encendido' then
    return jsonb_build_object('ok', true, 'activo', false);
  end if;
  -- Ley 2300: sin mercadeo domingos ni festivos (el despachador además retiene fuera de horario).
  if extract(isodow from hoy) = 7 or exists (select 1 from festivos where fecha = hoy) then
    return jsonb_build_object('ok', true, 'activo', true, 'motivo', 'dia_sin_envio');
  end if;
  v_hold := case when v_horas > 0 then make_interval(hours => v_horas) else interval '10 years' end;

  for v_hora in
    select btrim(split_part(t, '=', 1))
      from unnest(string_to_array(coalesce((select valor from ajustes where clave = 'premium_topes'), ''), ',')) t
     where btrim(split_part(t, '=', 2))::int <= 50
     order by 1
  loop
    v_etq := ltrim(to_char(v_hora::time, 'HH12:MI am'), '0');
    v_tope := (premium_cupos_horario() -> v_hora ->> 'tope')::int;

    -- (a) quien recibió el aviso y no pagó a tiempo deja su turno a la siguiente
    if v_horas > 0 then
      select coalesce(array_agg(s.id), '{}') into v_ids
        from mensualidad_solicitudes s
       where s.hora = v_hora::time and s.estado = 'lista_espera'
         and exists (select 1 from ventas_chats c
                      where c.telefono = right(regexp_replace(coalesce(s.celular, ''), '\D', '', 'g'), 10)
                        and c.oferta ->> 'origen' = 'lista_espera' and c.oferta ->> 'hora' = v_hora
                        and c.abierta_at < now() - v_hold);
      if cardinality(v_ids) > 0 then
        update mensualidad_solicitudes
           set estado = 'anulada',
               nota = coalesce(nota || ' · ', '') || 'No pagó en ' || v_horas || ' h tras el aviso de cupo (automático, ' || hoy || ')'
         where id = any(v_ids);
        v_anuladas := v_anuladas + cardinality(v_ids);
        perform nota_recepcion('Lista de espera ' || v_etq || ': pasó a la siguiente',
          'Quien recibió el aviso de cupo no pagó en ' || v_horas || ' horas; su solicitud quedó anulada y el aviso sigue con la siguiente persona. Si quiere volver, que se apunte de nuevo en tumbaobaila.com/mensualidad.',
          'lista-espera-vencida:' || v_hora || ':' || hoy);
      end if;
    end if;

    -- (b) tope superado: solo se avisa, no se toca nada
    select (h ->> 'ocupadas')::int into v_ocup
      from jsonb_array_elements(mensualidad_cupos() -> 'horas') h where h ->> 'hora' = v_hora;
    if v_ocup > v_tope then
      v_alertas := v_alertas + nota_recepcion('⚠️ Mensualidades por encima del tope a las ' || v_etq,
        'Hay ' || v_ocup || ' mensualidades a las ' || v_etq || ' y el tope es ' || v_tope || '. No se vende ninguna más en ese horario hasta que bajen; revisa quién vence y quién renovó.',
        'tope-superado:' || v_hora || ':' || hoy);
    end if;

    -- (c) cupo libre: se le escribe a quien le toca
    v_libres := coalesce(v_tope, 0) - coalesce(v_ocup, 0);
    continue when v_libres <= 0;

    for r in select f.* from mensualidad_fila(v_hora::time) f where f.aplica order by f.orden loop
      exit when v_libres <= 0;
      v_tel := right(regexp_replace(coalesce(r.celular, ''), '\D', '', 'g'), 10);
      continue when v_tel !~ '^3[0-9]{9}$' or wa_es_dueno(v_tel)
                 or exists (select 1 from wa_bajas b where b.telefono = v_tel);
      -- ya recibió el aviso y su plazo sigue corriendo: tiene el cupo apartado, no se le insiste
      if exists (select 1 from ventas_chats c
                  where c.telefono = v_tel and c.oferta ->> 'origen' = 'lista_espera' and c.oferta ->> 'hora' = v_hora
                    and c.abierta_at >= now() - v_hold) then
        v_libres := v_libres - 1;
        continue;
      end if;
      -- solo a quien la página deja pagar hoy (cumple requisitos y le toca por orden)
      continue when not coalesce(premium_puede_pagar(r.celular, null, v_hora::time), false);

      v_nombre := coalesce(nullif(initcap(split_part(btrim(r.nombre), ' ', 1)), ''), 'amigo(a)');
      select id into v_chat from ventas_chats
       where telefono = v_tel and estado in ('abierta', 'conversando') order by id desc limit 1;
      if v_chat is null then
        insert into ventas_chats (telefono, nombre, objetivo, oferta)
        values (v_tel, v_nombre, 'mensualidad_6pm', jsonb_build_object('origen', 'lista_espera', 'hora', v_hora));
      else
        update ventas_chats set objetivo = 'mensualidad_6pm', estado = 'abierta',
               oferta = coalesce(oferta, '{}'::jsonb) || jsonb_build_object('origen', 'lista_espera', 'hora', v_hora),
               abierta_at = now()
         where id = v_chat;
      end if;
      insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
      values ('ventas:' || v_tel || ':lista_espera:' || to_char(hoy, 'YYYYMMDD'), 'campana', v_tel, 'ventas_apertura',
              jsonb_build_array(v_nombre,
                'Se liberó un cupo de mensualidad en el horario de ' || v_etq || ' y, como estabas en la lista de espera, eres la primera persona a quien se lo ofrecemos 🧡'),
              now() + interval '6 hours')
      on conflict (clave) do nothing;
      perform nota_recepcion('Lista de espera ' || v_etq || ': se le avisó por WhatsApp',
        coalesce(r.nombre, 'Sin nombre') || ' (' || v_tel || ') recibió el aviso de que hay cupo a las ' || v_etq
        || '. Puede pagar en tumbaobaila.com/mensualidad y tiene ' || case when v_horas > 0 then v_horas || ' horas' else 'todo el tiempo' end
        || ' para hacerlo; si escribe con dudas, el asistente le responde y, si hace falta, te pasa la conversación.',
        'lista-espera-aviso:' || v_hora || ':' || v_tel || ':' || hoy);
      v_libres := v_libres - 1;
      v_n := v_n + 1;
    end loop;
  end loop;

  return jsonb_build_object('ok', true, 'activo', true, 'avisados', v_n, 'anuladas', v_anuladas, 'alertas', v_alertas);
exception when others then
  raise warning 'mensualidad_avisar_lista_espera: %', sqlerrm;
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;
revoke all on function public.mensualidad_avisar_lista_espera() from public, anon, authenticated;

-- 9:10 am Bogotá (14:10 UTC), lunes a sábado: después de la nota de recepción (8:20) y dentro del horario de mercadeo
do $cron$
begin
  perform cron.unschedule('tumbao-cupo-lista-espera');
exception when others then null;
end
$cron$;
select cron.schedule('tumbao-cupo-lista-espera', '10 14 * * 1-6', 'select public.mensualidad_avisar_lista_espera()');

-- ── 4 · la nota de las 8:20 sabe que el aviso ya sale solo ────────────────────────────────────────────
do $mig$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.mensualidad_cupo_liberado_texto(text)'::regprocedure);
  if position('El sistema ya les avisa por WhatsApp' in v_def) > 0 then return; end if;
  if position('Avísales que ya hay cupo y que paguen su mensualidad (' in v_def) = 0 then
    raise exception 'mensualidad_cupo_liberado_texto: no encuentro el texto a cambiar';
  end if;
  v_def := replace(v_def, 'Avísales que ya hay cupo y que paguen su mensualidad (',
                   'El sistema ya les avisa por WhatsApp a las 9:10 am (si no pagan en 48 h pasa a la siguiente). Si quieres adelantarte, avísales que ya hay cupo y que paguen su mensualidad (');
  execute v_def;
end
$mig$;
