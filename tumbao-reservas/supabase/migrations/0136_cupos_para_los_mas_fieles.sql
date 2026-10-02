-- 0136 · Los cupos de mensualidad son para los clientes más fieles; recepción recibe UNA instrucción al día
--
-- Damián (2 oct): «recepción no debe recibir un montón de notas, solo una instrucción
-- clara. El objetivo es dar los cupos de mensualidad como fidelidad, a la gente que ha
-- sido buen cliente, porque le sale muy económico pagar el mes.»
--
-- 1 · LA FILA SE ORDENA POR FIDELIDAD (mensualidad_fila)
--     Solo entra a un cupo quien CUMPLE los requisitos (0129/0134). Entre quienes cumplen:
--     más meses seguidos pagando plan → más meses con plan en total → más visitas de clase
--     suelta → quien se apuntó primero. Quien no cumple no recibe cupo por la fila: se le
--     ofrece tiquetera (una excepción la decide Damián a mano).
-- 2 · NADIE SE COLA (premium_puede_pagar)
--     Con un horario cerrado, quien se apunta solo puede pagar de una si, comparado con la
--     fila y sus cupos libres, le toca un cupo por fidelidad. Si hay 1 cupo y 2 más fieles
--     esperando, la persona nueva queda en la fila.
-- 3 · UNA SOLA NOTA AL DÍA (mensualidad_cupo_liberado_tareas, 8:20 am lunes a sábado)
--     Junta los horarios 6 pm y 7 pm en un solo mensaje corto: a quién avisarle que ya hay
--     cupo y debe pagar su mensualidad, y a quién ofrecerle tiquetera. No lista a quienes
--     no renovaron. Si nada cambió, no repite (y como mucho una vez por semana).
--     El sistema no le escribe a ningún cliente.

create or replace function public.mensualidad_fila(p_hora time)
returns table (orden int, id uuid, nombre text, celular text, aplica boolean,
               racha int, meses int, visitas int, creada timestamptz)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with f as (
    select s.id, s.nombre, s.celular, s.creado_at,
           premium_evaluar(s.celular) -> 'personas' -> 0 as p
      from mensualidad_solicitudes s
     where s.hora = p_hora and s.estado = 'lista_espera' and s.creado_at > now() - interval '90 days'
  ), g as (
    select f.*,
           coalesce((p ->> 'veredicto') = 'aplica', false) as ap,
           coalesce((p ->> 'meses_seguidos_pagando_plan')::int, 0) as r,
           coalesce((p ->> 'meses_con_plan_en_total')::int, 0) as m,
           coalesce((p -> 'clases_sueltas' ->> 'visitas')::int, 0) as v
      from f
  )
  select (row_number() over (order by g.ap desc, g.r desc, g.m desc, g.v desc, g.creado_at))::int,
         g.id, g.nombre, g.celular, g.ap, g.r, g.m, g.v, g.creado_at
    from g
$$;
revoke all on function public.mensualidad_fila(time) from public, anon, authenticated;

create or replace function public.premium_puede_pagar(p_celular text, p_documento text, p_hora time)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_hasta date := nullif((select valor from ajustes where clave = 'premium_vigente_hasta'), '')::date;
  v_max int; v_ocup int; v_libres int; v_dato text; ev jsonb; per jsonb; v_rank int;
begin
  if v_hasta is not null and v_hasta < (now() at time zone 'America/Bogota')::date then return false; end if;

  v_max := (premium_cupos_horario() -> to_char(p_hora, 'HH24:MI') ->> 'tope')::int;
  select (h ->> 'ocupadas')::int into v_ocup
    from jsonb_array_elements(mensualidad_cupos() -> 'horas') h
   where h ->> 'hora' = to_char(p_hora, 'HH24:MI');
  if v_max is null or v_ocup is null or v_ocup >= v_max then return false; end if;
  v_libres := v_max - v_ocup;

  foreach v_dato in array array[nullif(btrim(coalesce(p_celular, '')), ''), nullif(btrim(coalesce(p_documento, '')), '')] loop
    continue when v_dato is null;
    ev := premium_evaluar(v_dato);
    per := ev -> 'personas' -> 0;
    if (ev ->> 'encontradas')::int = 1
       and per ->> 'veredicto' = 'aplica'
       and per ->> 'encontrada_por' in ('celular', 'documento') then
      -- ¿le toca un cupo por fidelidad, comparada con la fila?
      with todos as (
        select f.celular, f.racha, f.meses, f.visitas, f.creada from mensualidad_fila(p_hora) f where f.aplica
        union all
        select p_celular,
               coalesce((per ->> 'meses_seguidos_pagando_plan')::int, 0),
               coalesce((per ->> 'meses_con_plan_en_total')::int, 0),
               coalesce((per -> 'clases_sueltas' ->> 'visitas')::int, 0), now()
         where not exists (select 1 from mensualidad_fila(p_hora) f where f.celular = p_celular)
      ), r as (
        select t.celular, row_number() over (order by t.racha desc, t.meses desc, t.visitas desc, t.creada) o from todos t
      )
      select o into v_rank from r where r.celular = p_celular;
      return coalesce(v_rank, 1) <= v_libres;
    end if;
  end loop;
  return false;
end;
$$;
revoke all on function public.premium_puede_pagar(text, text, time) from public, anon, authenticated;

-- La sección de UN horario (null si no hay nada que hacer en él)
create or replace function public.mensualidad_cupo_liberado_texto(p_hora text)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_valor int := coalesce(nullif((select valor from ajustes where clave = 'mensualidad_valor_cop'), '')::int, 125000);
  v_tope int := (premium_cupos_horario() -> p_hora ->> 'tope')::int;
  v_ocup int; v_libres int; v_etq text; v_con_cupo text; v_en_cola text; v_tiq text; v_n int;
begin
  select (h ->> 'ocupadas')::int into v_ocup
    from jsonb_array_elements(mensualidad_cupos() -> 'horas') h where h ->> 'hora' = p_hora;
  v_libres := coalesce(v_tope, 0) - coalesce(v_ocup, 0);
  if v_libres <= 0 then return null; end if;
  v_etq := ltrim(to_char(p_hora::time, 'HH12:MI am'), '0');

  select string_agg('· ' || x.nombre || ' (' || x.celular || ')'
                    || case when x.racha > 0 then ' — ' || x.racha || ' meses seguidos con nosotros' else '' end
                    || x.pago, E'\n' order by x.orden) filter (where x.aplica and x.orden <= v_libres),
         string_agg('· ' || x.nombre || ' (' || x.celular || ')' || x.pago, E'\n' order by x.orden)
                    filter (where not (x.aplica and x.orden <= v_libres)),
         count(*)
    into v_con_cupo, v_en_cola, v_n
    from (
      select f.*, coalesce((select ' · YA PAGÓ el ' || to_char(p.fecha_pago, 'DD/MM') || ', solo regístrala'
                              from pagos p
                             where p.valor_cop >= 100000 and p.fecha_pago >= f.creada - interval '3 days'
                               and similitud_nombre(f.nombre, p.remitente) >= 0.5
                             order by p.fecha_pago desc limit 1), '') as pago
        from mensualidad_fila(p_hora::time) f
    ) x;

  if v_n = 0 then return null; end if;

  select string_agg(((p ->> 'clases') || ' clases $' || replace(to_char((p ->> 'precio_cop')::int, 'FM999,999,999'), ',', '.')), ' u ')
    into v_tiq from jsonb_array_elements(tiquetera_paquetes()) p;

  return v_etq || ' — ' || v_libres || ' cupo(s) libre(s)'
    || case when v_con_cupo is not null
            then E'\n✅ Avísales que ya hay cupo y que paguen su mensualidad ($' || replace(to_char(v_valor, 'FM999,999,999'), ',', '.') || E'):\n' || v_con_cupo
            else '' end
    || case when v_en_cola is not null
            then E'\n🎟️ Ofréceles tiquetera (' || coalesce(v_tiq, 'consulta los paquetes') || E'):\n' || v_en_cola
            else '' end;
end;
$$;
revoke all on function public.mensualidad_cupo_liberado_texto(text) from public, anon, authenticated;

-- El texto completo del día (todos los horarios en uno); null si no hay nada que hacer
create or replace function public.mensualidad_cupo_liberado_mensaje()
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_hora text; v_sec text; v_cuerpo text := '';
begin
  for v_hora in
    select h from (select btrim(split_part(t, '=', 1)) h, btrim(split_part(t, '=', 2))::int tope
                     from unnest(string_to_array(coalesce((select valor from ajustes where clave = 'premium_topes'), ''), ',')) t) z
     where tope <= 50 order by h
  loop
    v_sec := mensualidad_cupo_liberado_texto(v_hora);
    if v_sec is not null then v_cuerpo := v_cuerpo || case when v_cuerpo = '' then '' else E'\n\n' end || v_sec; end if;
  end loop;
  if v_cuerpo = '' then return null; end if;
  return v_cuerpo || E'\n\nCómo avisarles: que entren a tumbaobaila.com/mensualidad y se apunten de nuevo (ahí ven el pago), o pásales los datos de pago por chat. Cuando paguen, regístralas en AdminGym.';
end;
$$;
revoke all on function public.mensualidad_cupo_liberado_mensaje() from public, anon, authenticated;

-- UNA nota al día como máximo, y solo si hay algo que hacer
create or replace function public.mensualidad_cupo_liberado_tareas()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_texto text;
begin
  v_texto := mensualidad_cupo_liberado_mensaje();
  if v_texto is null then return 0; end if;
  -- misma instrucción = no se repite; como mucho una vez por semana
  return nota_recepcion('📌 Mensualidad: qué hacer hoy', v_texto,
           'cupo-liberado:' || md5(v_texto) || ':' || to_char((now() at time zone 'America/Bogota')::date, 'IYYY-IW'));
end;
$$;
revoke all on function public.mensualidad_cupo_liberado_tareas() from public, anon, authenticated;
