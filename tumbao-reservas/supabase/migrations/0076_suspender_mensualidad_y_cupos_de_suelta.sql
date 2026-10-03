-- 0076 · Mensualidad suspendida en 6pm y 7pm, y los cupos de suelta
--        desde el 15 de septiembre.
--
-- Dos órdenes de Damián, el 8 de septiembre, después de ver que el 7:00
-- pm tenía 28 mensualidades comprometidas en un salón de 35:
--
--   «Por el momento hasta nueva orden suspendidas las mensualidades de
--    6 pm y 7 pm, quedan en lista de espera.»
--
--   «Para la página de reservas clase suelta, a partir del 15 de
--    septiembre colocar los cupos como me sugieres, pero súbele uno a
--    cada horario.»
--
-- ── 1. LA SUSPENSIÓN ────────────────────────────────────────────────
--
-- `mensualidad_topes` (que abrió la 0074) en 0 para esas dos horas. Con
-- tope 0, `libres` da 0 siempre, y `mensualidad_solicitar` ya sabe qué
-- hacer con eso: la solicitud nace en `lista_espera` en vez de
-- `esperando_pago`. Nadie más puede pagar mensualidad ahí, y quien
-- entre a la página queda en la cola, que es exactamente lo pedido.
--
-- No se toca a nadie que ya tenga mensualidad: las 28 del 7pm y las 25
-- del 6pm siguen intactas. Esto solo cierra la venta hacia adelante.
--
-- Se hace con tope 0 y no borrando la hora de `mensualidad_horas`
-- porque quitarla de ahí haría que la página ni siquiera la enseñe, y
-- entonces no habría dónde apuntarse a la lista de espera — que es lo
-- único que Damián sí quiere que siga pasando.
--
-- Las 7:00 am NO se tocan: siguen en 25, y son donde hay que vender.
--
-- ── 2. LOS CUPOS DE CLASE SUELTA ────────────────────────────────────
--
-- De la demanda real medida sobre un mes (reservas + quienes llegan y
-- pagan en puerta sin reservar), tomando el P80 —cubre 4 de cada 5
-- sesiones— y sumando uno, como pidió:
--
--   07:00  P80 1  → sugerido 3  → 4
--   18:00  P80 7  → sugerido 9  → 10
--   19:00  P80 11 → sugerido 11 → 12
--
-- Los sábados no entran: no tienen mensualidad, el salón entero es de
-- clase suelta y ya están en 35 por `cupo_manual`.
--
-- CÓMO SE APLICA A CLASES QUE TODAVÍA NO EXISTEN. El 8 de septiembre
-- solo hay clases hasta el 12; las del 15 en adelante nacen cuando
-- alguien guarda esa semana en el panel. Por eso esto no se escribe
-- clase por clase —no habría dónde— sino como una regla que consultan
-- los dos únicos sitios que fijan el cupo:
--
--   `admin_guardar_semana`  cuando la clase nace o se re-guarda.
--   `recalcular_cupos`      que corre en cada importación de membresías
--                           (la llama `importar_membresias`), o sea al
--                           menos una vez al día.
--
-- LA REGLA MANDA SOBRE `cupo_manual`, a propósito. `cupo_manual` era el
-- parche con el que se topaban clases a mano por no haber una política;
-- ahora la política existe y es de quien manda. Si hiciera falta una
-- excepción para una clase suelta después del 15, se pone quitando esa
-- hora de `suelta_cupos` o cambiando el ajuste — un solo sitio.
--
-- Lo que NO cede es `cupo_tomado`: el cupo nunca baja de lo ya
-- reservado, o la tabla quedaría en un estado imposible.

-- ── Los ajustes ──────────────────────────────────────────────────────
insert into ajustes (clave, valor) values
  ('mensualidad_topes',  '18:00=0,19:00=0'),
  ('suelta_cupos',       '07:00=4,18:00=10,19:00=12'),
  ('suelta_cupos_desde', '2026-09-15')
on conflict (clave) do update set valor = excluded.valor;

-- ── La regla, en un solo sitio ───────────────────────────────────────
-- Devuelve el cupo de clase suelta que le toca a una clase por su hora,
-- o null si no hay regla para esa hora o si la clase es anterior a la
-- fecha de corte. Null significa «como siempre», así que sin los
-- ajustes de arriba nada cambia.
create or replace function public.cupo_suelta_de(p_fecha timestamptz)
returns int
language sql
stable
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
  select (select btrim(split_part(t, '=', 2))::int
            from unnest(string_to_array(
                   coalesce((select valor from ajustes where clave = 'suelta_cupos'), ''),
                   ',')) as t
           where btrim(split_part(t, '=', 1))
                 = to_char(p_fecha at time zone 'America/Bogota', 'HH24:MI')
           limit 1)
   where (p_fecha at time zone 'America/Bogota')::date
         >= coalesce((select valor::date from ajustes where clave = 'suelta_cupos_desde'),
                     'infinity'::date);
$function$;

revoke all on function public.cupo_suelta_de(timestamptz) from public, anon;
grant execute on function public.cupo_suelta_de(timestamptz) to service_role;

-- ── Los dos sitios que fijan el cupo ─────────────────────────────────
do $mig$
declare
  v_src   text;
  v_new   text;
  v_ancla text;
  v_rep   text;
begin
  ------------------------------------------------------------------ 1
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'recalcular_cupos';
  if v_src is null then
    raise exception '0076: no existe public.recalcular_cupos';
  end if;

  if position('0076:' in v_src) = 0 then
    v_new := v_src;

    -- La fecha hace falta para preguntarle a la regla.
    v_ancla := E'    select c.id,\n           c.aforo,\n           c.cupo_tomado,\n           c.cupo_manual,';
    if position(v_ancla in v_new) = 0 then
      raise exception '0076: no se encontro el select de calculo';
    end if;
    v_new := replace(v_new, v_ancla,
      E'    select c.id,\n           c.fecha_hora,   -- 0076: para preguntarle a cupo_suelta_de\n' ||
      E'           c.aforo,\n           c.cupo_tomado,\n           c.cupo_manual,');

    v_ancla := E'             coalesce(k.cupo_manual, greatest(k.aforo - k.activos, 0))';
    if position(v_ancla in v_new) = 0 then
      raise exception '0076: no se encontro la meta de objetivo';
    end if;
    v_new := replace(v_new, v_ancla,
      E'             -- 0076: la regla del 15 de septiembre manda sobre el\n' ||
      E'             -- cupo puesto a mano. cupo_tomado sigue mandando\n' ||
      E'             -- sobre todo: el cupo no baja de lo ya reservado.\n' ||
      E'             coalesce(cupo_suelta_de(k.fecha_hora), k.cupo_manual,\n' ||
      E'                      greatest(k.aforo - k.activos, 0))');

    v_ancla := E'               coalesce(o.cupo_manual, greatest(o.aforo - o.activos, 0)) as ideal,';
    if position(v_ancla in v_new) = 0 then
      raise exception '0076: no se encontro el ideal de aplicado';
    end if;
    v_new := replace(v_new, v_ancla,
      E'               coalesce(cupo_suelta_de(o.fecha_hora), o.cupo_manual,\n' ||
      E'                        greatest(o.aforo - o.activos, 0)) as ideal,');

    v_new := replace(v_new, E'AS $function$\ndeclare',
      E'AS $function$\n-- 0076: el cupo de suelta puede venir de una regla por hora.\ndeclare');
    execute v_new;
  else
    raise notice '0076: recalcular_cupos ya parcheada';
  end if;

  ------------------------------------------------------------------ 2
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_guardar_semana';
  if v_src is null then
    raise exception '0076: no existe public.admin_guardar_semana';
  end if;

  if position('0076:' in v_src) > 0 then
    raise notice '0076: admin_guardar_semana ya parcheada';
    return;
  end if;
  v_new := v_src;

  -- Al nacer la clase.
  v_ancla := E'          v_momento, 60,\n          coalesce(v_cupo_manual, v_aforo),';
  if position(v_ancla in v_new) = 0 then
    raise exception '0076: no se encontro el insert de clases';
  end if;
  v_new := replace(v_new, v_ancla,
    E'          v_momento, 60,\n' ||
    E'          -- 0076: la regla del 15 de septiembre, si aplica.\n' ||
    E'          coalesce(cupo_suelta_de(v_momento), v_cupo_manual, v_aforo),');

  -- Y cada vez que se re-guarda la semana.
  v_ancla :=
    E'           cupo_total  = greatest(cupo_tomado,\n' ||
    E'                                  coalesce(v_cupo_manual,\n' ||
    E'                                           greatest(v_aforo - activos_plan, 0))),';
  if position(v_ancla in v_new) = 0 then
    raise exception '0076: no se encontro el update de clases';
  end if;
  v_new := replace(v_new, v_ancla,
    E'           cupo_total  = greatest(cupo_tomado,\n' ||
    E'                                  coalesce(cupo_suelta_de(v_momento), v_cupo_manual,\n' ||
    E'                                           greatest(v_aforo - activos_plan, 0))),');

  v_new := replace(v_new, E'AS $function$\ndeclare',
    E'AS $function$\n-- 0076: el cupo de suelta puede venir de una regla por hora.\ndeclare');
  execute v_new;
end
$mig$;

-- Se aplica a lo que ya existe. Hoy no hay clases del 15 en adelante,
-- así que esto no mueve nada — corre igual para que la migración deje
-- el estado consistente el día que sí las haya.
select recalcular_cupos();
