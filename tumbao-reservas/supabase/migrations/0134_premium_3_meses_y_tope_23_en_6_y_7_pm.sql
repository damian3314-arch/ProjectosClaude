-- 0134 · Premium: 3 meses seguidos bastan; tope de 23 en 6 pm y 7 pm; 7 am abierto
--
-- Damián (2 oct): «4 meses seguidos de mensualidad es bastante; con 3 ya es
-- suficiente, pero respetando siempre el tope: máximo 23 mensualidades para las
-- 6 pm y las 7 pm, y a las 7 am todos los que lleguen.»
--
--   · premium_min_meses: 4 → 3. Los demás requisitos (haber pagado plan este mes
--     o el anterior; o suelta constante 90 días) no cambian.
--   · premium_topes (nuevo): tope POR HORARIO, con la misma forma de
--     mensualidad_topes: «07:00=99,18:00=23,19:00=23». premium_cupo_max (25)
--     queda de respaldo para un horario que no aparezca. El 7 am se deja en 99:
--     ahí no se limita por requisitos ni por cupo premium (el aforo de la sala
--     lo sigue cuidando mensualidad_topes: 07:00=35).
--   · premium_cupos_horario() y, por tanto, premium_puede_pagar() (0133) leen el
--     tope de cada horario.

update ajustes set valor = '3' where clave = 'premium_min_meses';

insert into ajustes (clave, valor, nota) values
  ('premium_topes', '07:00=99,18:00=23,19:00=23',
   'Tope de mensualidades por horario para quien entra por requisitos (6 pm y 7 pm: 23; 7 am: sin tope práctico). 0134.')
on conflict (clave) do update set valor = excluded.valor;

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
           (select (now() at time zone 'America/Bogota')::date) hoy),
  horas as (
    select btrim(h) hr
      from unnest(string_to_array(coalesce((select valor from ajustes where clave = 'mensualidad_horas'), '07:00,18:00,19:00'), ',')) h
  ),
  por_hora as (
    select hr, c.hoy, c.minimo,
           coalesce((select btrim(split_part(t, '=', 2))::int
                       from unnest(string_to_array(c.topes, ',')) t
                      where btrim(split_part(t, '=', 1)) = hr limit 1), c.tope_base) tope
      from horas, cfg c
  )
  select coalesce(jsonb_object_agg(hr, jsonb_build_object(
           'tope', p.tope,
           'ocupados_hoy', (select count(*) from membresias m where m.fin >= p.hoy and to_char(m.hora, 'HH24:MI') = hr),
           'libres', greatest(p.tope - (select count(*) from membresias m where m.fin >= p.hoy and to_char(m.hora, 'HH24:MI') = hr), 0),
           'minimo_buscado', p.minimo)),
         '{}'::jsonb)
    from por_hora p
$$;
revoke all on function public.premium_cupos_horario() from public, anon, authenticated;

-- premium_puede_pagar (0133): el tope sale de cada horario
create or replace function public.premium_puede_pagar(p_celular text, p_documento text, p_hora time)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_hasta date := nullif((select valor from ajustes where clave = 'premium_vigente_hasta'), '')::date;
  v_max int; v_ocup int; v_dato text; ev jsonb;
begin
  if v_hasta is not null and v_hasta < (now() at time zone 'America/Bogota')::date then return false; end if;

  v_max := (premium_cupos_horario() -> to_char(p_hora, 'HH24:MI') ->> 'tope')::int;
  select (h ->> 'ocupadas')::int into v_ocup
    from jsonb_array_elements(mensualidad_cupos() -> 'horas') h
   where h ->> 'hora' = to_char(p_hora, 'HH24:MI');
  if v_max is null or v_ocup is null or v_ocup >= v_max then return false; end if;

  foreach v_dato in array array[nullif(btrim(coalesce(p_celular, '')), ''), nullif(btrim(coalesce(p_documento, '')), '')] loop
    continue when v_dato is null;
    ev := premium_evaluar(v_dato);
    if (ev ->> 'encontradas')::int = 1
       and ev -> 'personas' -> 0 ->> 'veredicto' = 'aplica'
       and ev -> 'personas' -> 0 ->> 'encontrada_por' in ('celular', 'documento') then
      return true;
    end if;
  end loop;
  return false;
end;
$$;
revoke all on function public.premium_puede_pagar(text, text, time) from public, anon, authenticated;
