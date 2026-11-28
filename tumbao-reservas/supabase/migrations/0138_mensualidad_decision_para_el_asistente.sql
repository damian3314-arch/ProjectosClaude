-- 0138 · mensualidad_decision(): la respuesta lista para «¿puedo procesar la mensualidad de X?»
--
-- Damián (2 oct): «enséñale al bot nuevo de WhatsApp todo lo último del control de
-- mensualidades, de quién aplica y quién no; recepción le puede escribir y preguntar
-- por una persona por si tiene dudas para procesar la mensualidad».
--
-- Una sola consulta de SOLO LECTURA que junta lo que recepción necesita saber:
--   · quién es (por celular, cédula o nombre; con varias coincidencias no adivina),
--   · si aplica y por qué (premium_evaluar, 0129/0134),
--   · el horario (el que pide o el habitual) con su tope, ocupados y cupos libres
--     (cuenta los 3 días de gracia, 0135),
--   · su lugar en la fila de espera por fidelidad (0136) y si ya pagó,
--   · y una frase de respuesta ('respuesta') con lo que hay que hacer.
-- No escribe nada ni le escribe a nadie.

-- Dos nombres «se parecen» si comparten al menos dos palabras (o la única que tengan):
-- «Miguelangel Gonzalez» NO es «Genny Paola Gonzalez Vega» aunque compartan un apellido.
create or replace function public.nombres_coinciden(a text, b text)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  with ta as (select distinct t from unnest(string_to_array(norm_nombre(coalesce(a, '')), ' ')) t where length(t) >= 3),
       tb as (select distinct t from unnest(string_to_array(norm_nombre(coalesce(b, '')), ' ')) t where length(t) >= 3)
  select (select count(*) from ta join tb using (t)) >= 1
     and (select count(*) from ta join tb using (t)) >= least(2, (select count(*) from ta), (select count(*) from tb))
$$;

create or replace function public.mensualidad_decision(p_buscar text, p_hora text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  ev jsonb; per jsonb; n int; v_hora text; v_etq text; v_tope int; v_ocup int; v_libres int;
  v_ver text; v_tel4 text; v_nombre text; v_pos int; v_total_fila int; v_adelante int;
  v_pago text; v_resp text; v_lista text; v_sin_tope boolean;
begin
  if coalesce(btrim(p_buscar), '') = '' then
    return jsonb_build_object('ok', false, 'respuesta', 'Dime el celular, la cédula o el nombre completo de la persona.');
  end if;

  ev := premium_evaluar(btrim(p_buscar));
  n := (ev ->> 'encontradas')::int;

  if n = 0 then
    return jsonb_build_object('ok', true, 'estado', 'sin_historial',
      'respuesta', '❓ No la encuentro con ese dato. Pídele el celular o la cédula completa (o prueba con el otro dato).');
  elsif n > 1 then
    select string_agg(x ->> 'nombre' || ' (…' || (x ->> 'celular_termina_en') || ')', '; ') into v_lista
      from jsonb_array_elements(ev -> 'personas') x;
    return jsonb_build_object('ok', true, 'estado', 'varias', 'opciones', ev -> 'personas',
      'respuesta', '❓ Hay ' || n || ' personas con ese dato: ' || v_lista || '. Dime el celular o la cédula completa para saber cuál es.');
  end if;

  per := ev -> 'personas' -> 0;
  v_ver := per ->> 'veredicto';
  v_nombre := per ->> 'nombre';
  v_tel4 := per ->> 'celular_termina_en';

  v_hora := coalesce(nullif(btrim(p_hora), ''), per ->> 'horario_habitual');
  if v_hora is not null and v_hora !~ '^\d{2}:\d{2}$' then
    v_hora := case lower(btrim(v_hora))
                when '7am' then '07:00' when '7 am' then '07:00' when '7:00 am' then '07:00'
                when '6pm' then '18:00' when '6 pm' then '18:00' when '6:00 pm' then '18:00'
                when '7pm' then '19:00' when '7 pm' then '19:00' when '7:00 pm' then '19:00'
                else v_hora end;
  end if;
  if v_hora is not null and v_hora !~ '^\d{2}:\d{2}$' then v_hora := null; end if;

  if v_ver = 'sin_historial' then
    return jsonb_build_object('ok', true, 'estado', 'sin_historial', 'persona', per,
      'respuesta', '❓ ' || v_nombre || ': no tiene historial con ese dato. Pídele el otro (celular o cédula).');
  end if;

  if v_hora is not null then
    v_etq := ltrim(to_char(v_hora::time, 'HH12:MI am'), '0');
    v_tope := (premium_cupos_horario() -> v_hora ->> 'tope')::int;
    select (h ->> 'ocupadas')::int into v_ocup
      from jsonb_array_elements(mensualidad_cupos() -> 'horas') h where h ->> 'hora' = v_hora;
    v_sin_tope := coalesce(v_tope, 0) >= 50;
    v_libres := case when v_tope is null or v_ocup is null then null else greatest(v_tope - v_ocup, 0) end;

    select f.orden, (select count(*) from mensualidad_fila(v_hora::time) where aplica), count(*) over ()
      into v_pos, v_adelante, v_total_fila
      from mensualidad_fila(v_hora::time) f
     where right(f.celular, 4) = v_tel4 and similitud_nombre(f.nombre, v_nombre) >= 0.4
     limit 1;
  end if;

  select ' Posible pago de $' || replace(to_char(p.valor_cop, 'FM999,999,999'), ',', '.') || ' el ' || to_char(p.fecha_pago, 'DD/MM') || ' (' || p.remitente || ').'
    into v_pago
    from pagos p
   where p.valor_cop >= 100000 and p.fecha_pago > now() - interval '20 days'
     and nombres_coinciden(v_nombre, p.remitente)
   order by p.fecha_pago desc limit 1;

  if v_ver = 'aplica' then
    if v_hora is null then
      v_resp := '✅ ' || v_nombre || ' (…' || v_tel4 || ') SÍ aplica: ' || (per ->> 'razon') || ' Dime en qué horario la quieren (7 am, 6 pm o 7 pm) para decirte si hay cupo.';
    elsif v_sin_tope then
      v_resp := '✅ ' || v_nombre || ' (…' || v_tel4 || ') SÍ aplica: ' || (per ->> 'razon') || ' A las ' || v_etq || ' entran todos los que lleguen (hoy ' || coalesce(v_ocup, 0) || ' ocupados). Se puede procesar.';
    elsif coalesce(v_libres, 0) <= 0 then
      v_resp := '⏳ ' || v_nombre || ' (…' || v_tel4 || ') aplica: ' || (per ->> 'razon') || ' Pero las ' || v_etq || ' están completas (' || coalesce(v_ocup, 0) || ' de ' || v_tope || ', contando los 3 días de gracia). '
                || case when v_pos is not null then 'Está en la lista de espera, lugar ' || v_pos || ' por fidelidad. ' else 'Que se apunte a la lista de espera en tumbaobaila.com/mensualidad. ' end
                || 'Mientras tanto, tiquetera o clase suelta.';
    elsif v_pos is not null and v_pos > v_libres then
      v_resp := '⏳ ' || v_nombre || ' (…' || v_tel4 || ') aplica: ' || (per ->> 'razon') || ' Hay ' || v_libres || ' cupo(s) a las ' || v_etq || ', pero ella es la ' || v_pos || ' de la fila por fidelidad y delante hay quien tiene prioridad. Por ahora no se procesa; ofrécele tiquetera.';
    else
      v_resp := '✅ ' || v_nombre || ' (…' || v_tel4 || ') SÍ aplica: ' || (per ->> 'razon') || ' Hay ' || v_libres || ' cupo(s) libre(s) a las ' || v_etq
                || case when v_pos is not null then ' y le toca por su lugar en la fila (' || v_pos || ')' else '' end
                || '. Se puede procesar: que pague su mensualidad y se registra en AdminGym.';
    end if;
  else
    v_resp := '⛔ ' || v_nombre || ' (…' || v_tel4 || ') NO aplica: ' || (per ->> 'razon') || ' No se le vende mensualidad; ofrécele tiquetera o clase suelta. Solo una excepción de Damián cambia eso.';
  end if;

  return jsonb_build_object('ok', true, 'estado', v_ver, 'persona', per, 'horario', v_hora,
    'tope', v_tope, 'ocupados', v_ocup, 'libres', v_libres, 'lugar_en_la_fila', v_pos,
    'respuesta', v_resp || coalesce(v_pago, ''));
end;
$$;
revoke all on function public.mensualidad_decision(text, text) from public, anon, authenticated;
