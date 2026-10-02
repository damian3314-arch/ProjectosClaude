-- 0135 · Se le espera 3 días a quien vence; pasado ese plazo, recepción recibe la tarea de avisar a la fila
--
-- Damián (2 oct): «A la gente le vamos a esperar 3 días luego de su vencimiento. No
-- avisemos a nadie de cupo antes. Si a los 3 días no pagan, se libera el cupo y se
-- deja la tarea de avisarle al que está en lista de espera que ya puede pagar. El
-- objetivo es mantener el tope de 23 mensualidades en 6 pm y 7 pm. Y ofrécele a la
-- persona las tiqueteras.»
--
-- 1 · GRACIA
--   ajustes.mensualidad_gracia_dias = 3. Una mensualidad vencida sigue OCUPANDO su
--   cupo hasta fin + 3 días (mensualidad_cupos y premium_cupos_horario). Se cuenta
--   por persona (celular), no por fila: quien renueva tiene la fila vieja y la nueva
--   a la vez y no puede contar doble.
--   Mientras corre la gracia nadie recibe aviso de cupo: el cupo simplemente no está
--   libre, y premium_puede_pagar (0133) no deja pagar.
--
-- 2 · LA TAREA (una nota a recepción, 8:20 am de lunes a sábado)
--   mensualidad_cupo_liberado_texto(hora) arma el texto; mensualidad_cupo_liberado_tareas()
--   lo manda con nota_recepcion SOLO si, en un horario con tope (6 pm y 7 pm):
--     · quedó un cupo libre (tope − ocupadas > 0), y
--     · hay alguien en lista de espera, o alguien terminó su gracia sin renovar.
--   La nota dice: quién no renovó (para ofrecerle la tiquetera), quién sigue en la
--   fila y en qué orden (primero quien cumple los requisitos, después por llegada),
--   si esa persona ya pagó, y qué hacer. El sistema NO le escribe a ningún cliente.
--   Se manda una sola vez por combinación (horario + fila + cupos): no insiste.

insert into ajustes (clave, valor, nota) values
  ('mensualidad_gracia_dias', '3',
   'Días que se le guarda el cupo a una mensualidad vencida antes de liberarlo. 0135.')
on conflict (clave) do nothing;

-- ── 1 · gracia en el conteo de cupos ───────────────────────────────────
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.mensualidad_cupos()'::regprocedure) into v_src;
  if position('v_gracia' in v_src) > 0 then return; end if;

  v_new := replace(v_src,
    'declare v_tope int; v_horas text; v_valor int; v_out jsonb;',
    'declare v_tope int; v_horas text; v_valor int; v_out jsonb;
  v_gracia int := coalesce(nullif((select valor from ajustes where clave = ''mensualidad_gracia_dias''), '''')::int, 3);');
  if v_new = v_src then raise exception '0135: no encontré el declare de mensualidad_cupos'; end if;

  v_src := v_new;
  v_new := replace(v_src,
    '(select count(*) from membresias m
             where m.hora = h.hora and current_date between m.inicio and m.fin)::int as activas,',
    '(select count(distinct coalesce(nullif(right(regexp_replace(coalesce(m.celular, ''''), ''\D'', '''', ''g''), 10), ''''), m.id::text))
              from membresias m
             where m.hora = h.hora and current_date between m.inicio and m.fin + v_gracia)::int as activas,');
  if v_new = v_src then raise exception '0135: no encontré el conteo de activas'; end if;

  execute v_new;
end
$mig$;

create or replace function public.premium_cupos_horario()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with cfg as (
    select coalesce((select valor from ajustes where clave = 'premium_cupo_max'), '25')::int tope_base,
           coalesce((select valor from ajustes where clave = 'premium_topes'), '') topes,
           coalesce((select valor from ajustes where clave = 'premium_cupo_min'), '20')::int minimo,
           coalesce(nullif((select valor from ajustes where clave = 'mensualidad_gracia_dias'), '')::int, 3) gracia,
           (select (now() at time zone 'America/Bogota')::date) hoy),
  horas as (
    select btrim(h) hr
      from unnest(string_to_array(coalesce((select valor from ajustes where clave = 'mensualidad_horas'), '07:00,18:00,19:00'), ',')) h
  ),
  por_hora as (
    select hr, c.hoy, c.minimo, c.gracia,
           coalesce((select btrim(split_part(t, '=', 2))::int
                       from unnest(string_to_array(c.topes, ',')) t
                      where btrim(split_part(t, '=', 1)) = hr limit 1), c.tope_base) tope,
           (select count(distinct coalesce(nullif(right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10), ''), m.id::text))
              from membresias m
             where m.fin + c.gracia >= c.hoy and to_char(m.hora, 'HH24:MI') = hr) ocupados
      from horas, cfg c
  )
  select coalesce(jsonb_object_agg(hr, jsonb_build_object(
           'tope', p.tope,
           'ocupados_hoy', p.ocupados,
           'libres', greatest(p.tope - p.ocupados, 0),
           'minimo_buscado', p.minimo)),
         '{}'::jsonb)
    from por_hora p
$$;
revoke all on function public.premium_cupos_horario() from public, anon, authenticated;

-- ── 2 · la tarea para recepción ────────────────────────────────────────
create or replace function public.mensualidad_cupo_liberado_texto(p_hora text)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  hoy date := (now() at time zone 'America/Bogota')::date;
  v_gracia int := coalesce(nullif((select valor from ajustes where clave = 'mensualidad_gracia_dias'), '')::int, 3);
  v_tope int := (premium_cupos_horario() -> p_hora ->> 'tope')::int;
  v_ocup int; v_libres int; v_etq text; v_no_renovaron text; v_fila text; v_tiq text; v_n int;
begin
  select (h ->> 'ocupadas')::int into v_ocup
    from jsonb_array_elements(mensualidad_cupos() -> 'horas') h where h ->> 'hora' = p_hora;
  v_libres := coalesce(v_tope, 0) - coalesce(v_ocup, 0);
  if v_libres <= 0 then return null; end if;
  v_etq := ltrim(to_char(p_hora::time, 'HH12:MI am'), '0');

  -- quienes terminaron su gracia en los últimos 2 días y no renovaron
  select string_agg(distinct coalesce(m.afiliado, 'Sin nombre') || ' (' || coalesce(nullif(m.celular, ''), 's/celular') || ')', ', ')
    into v_no_renovaron
    from membresias m
   where to_char(m.hora, 'HH24:MI') = p_hora
     and m.fin + v_gracia < hoy and m.fin + v_gracia >= hoy - 2
     and not exists (select 1 from membresias n
                      where n.id <> m.id
                        and right(regexp_replace(coalesce(n.celular, ''), '\D', '', 'g'), 10) = right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10)
                        and n.fin + v_gracia >= hoy - 2 and n.fin > m.fin);

  -- la fila: primero quien cumple los requisitos, después por llegada
  select string_agg(x.linea, E'\n' order by x.orden), count(*)
    into v_fila, v_n
    from (
      select row_number() over (order by (premium_evaluar(s.celular) -> 'personas' -> 0 ->> 'veredicto') = 'aplica' desc, s.creado_at) orden,
             s.nombre || ' (' || s.celular || ') — '
             || case when (premium_evaluar(s.celular) -> 'personas' -> 0 ->> 'veredicto') = 'aplica' then 'cumple los requisitos'
                     else 'NO cumple los requisitos (solo con excepción de Damián)' end
             || coalesce((select ' · YA PAGÓ $' || replace(to_char(p.valor_cop, 'FM999,999,999'), ',', '.') || ' el ' || to_char(p.fecha_pago, 'DD/MM')
                            from pagos p
                           where p.valor_cop >= 100000 and p.fecha_pago >= s.creado_at - interval '3 days'
                             and similitud_nombre(s.nombre, p.remitente) >= 0.5
                           order by p.fecha_pago desc limit 1), '') as linea
        from mensualidad_solicitudes s
       where s.hora = p_hora::time and s.estado = 'lista_espera' and s.creado_at > now() - interval '90 days'
    ) x;

  if v_no_renovaron is null and v_n = 0 then return null; end if;

  select string_agg(((p ->> 'clases') || ' clases $' || replace(to_char((p ->> 'precio_cop')::int, 'FM999,999,999'), ',', '.')), ' o ')
    into v_tiq from jsonb_array_elements(tiquetera_paquetes()) p;

  return '🔓 Se liberó cupo de mensualidad a las ' || v_etq || ' (' || v_libres || ' libre(s); tope ' || v_tope || ').'
    || case when v_no_renovaron is not null
            then E'\n\nNo renovaron (pasaron los ' || v_gracia || ' días): ' || v_no_renovaron
                 || E'.\n→ Ofréceles la tiquetera: ' || coalesce(v_tiq, 'consulta los paquetes') || ' (30 días).'
            else '' end
    || case when v_n > 0
            then E'\n\nLista de espera de las ' || v_etq || E' (en este orden):\n' || v_fila
                 || E'\n→ Avísale a la primera que ya puede pagar su mensualidad. Si cumple los requisitos, que se apunte de nuevo en tumbaobaila.com/mensualidad y verá el pago. Si ya había pagado, solo regístrala. A quien no cumpla y no tenga excepción, ofrécele la tiquetera: '
                 || coalesce(v_tiq, 'consulta los paquetes') || '.'
            else '' end;
end;
$$;
revoke all on function public.mensualidad_cupo_liberado_texto(text) from public, anon, authenticated;

create or replace function public.mensualidad_cupo_liberado_tareas()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hora text; v_texto text; v_n int := 0; v_clave text;
begin
  -- los horarios con tope de requisitos (6 pm y 7 pm); el 7 am no tiene fila
  for v_hora in
    select h from (select btrim(split_part(t, '=', 1)) h, btrim(split_part(t, '=', 2))::int tope
                     from unnest(string_to_array(coalesce((select valor from ajustes where clave = 'premium_topes'), ''), ',')) t) z
     where tope <= 50 order by h
  loop
    v_texto := mensualidad_cupo_liberado_texto(v_hora);
    continue when v_texto is null;
    -- una sola vez por combinación de horario + texto
    v_clave := 'cupo-liberado:' || v_hora || ':' || md5(v_texto);
    v_n := v_n + nota_recepcion('🔓 Cupo de mensualidad liberado', v_texto, v_clave);
  end loop;
  return v_n;
end;
$$;
revoke all on function public.mensualidad_cupo_liberado_tareas() from public, anon, authenticated;

do $cron$
begin
  perform cron.unschedule('tumbao-cupo-liberado');
exception when others then null;
end
$cron$;
-- 8:20 am Bogotá (13:20 UTC), lunes a sábado
select cron.schedule('tumbao-cupo-liberado', '20 13 * * 1-6', 'select public.mensualidad_cupo_liberado_tareas()');
