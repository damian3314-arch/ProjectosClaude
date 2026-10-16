-- ---------------------------------------------------------------------
-- 0041 — Al abrir la semana, recalcular los cupos
--
-- LO QUE PASÓ, A LOS DOS MINUTOS DE ESTRENAR LA 0040
-- `abrir_semana()` abrió la semana del 17 y la página se puso a ofrecer
-- **30 cupos** en las clases de entre semana. El aforo es 30, sí, pero
-- de esos ya hay 20 apartados por afiliados con plan a las 7 am. Los
-- libres eran 12.
--
-- O sea que durante un rato la página estuvo vendiendo cupos que no
-- existen — exactamente lo que el sistema entero existe para no hacer.
--
-- POR QUÉ
-- `generar_horario()` crea la clase con `cupo_total = aforo` y nada más.
-- Los cupos de verdad salen de `recalcular_cupos()`, que resta los
-- afiliados activos de cada horario. Esa función solo la llamaba la
-- importación de afiliados, que corre a las 9:30 pm.
--
-- Antes esto no se notaba porque las clases las creaba una persona desde
-- el panel y la corrección llegaba esa misma noche, con la semana
-- todavía lejos. Al automatizar la apertura, el hueco quedó a la vista:
-- la semana se abre el sábado a las 7 am y hasta la noche mentía.
--
-- LO QUE HACE
-- `abrir_semana()` recalcula los cupos justo después de generar. Es una
-- línea, y es la diferencia entre abrir una semana y abrirla bien.
--
-- Se reemplaza la función entera a propósito: nació en la 0040, hace
-- unas horas, y nadie más la ha tocado. No aplica la advertencia de
-- `aplicar/LEEME-ANTES-DE-PEGAR.md`, que es para funciones con historia.
-- ---------------------------------------------------------------------

create or replace function abrir_semana()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_hoy     date := (now() at time zone 'America/Bogota')::date;
  v_lunes   date;
  v_domingo date;
  v_creadas int;
  v_cupos   jsonb;
  v_fest    jsonb;
begin
  -- El lunes que VIENE. Si hoy es lunes, el de la otra semana: esta ya
  -- está abierta y lo que falta es la siguiente.
  v_lunes := v_hoy + ((8 - extract(isodow from v_hoy)::int) % 7);
  if v_lunes = v_hoy then
    v_lunes := v_hoy + 7;
  end if;
  v_domingo := v_lunes + 6;

  -- Por si la semana cruza de año.
  perform sembrar_festivos(extract(year from v_lunes)::int);
  perform sembrar_festivos(extract(year from v_domingo)::int);

  v_creadas := generar_horario(v_lunes, v_domingo);

  -- Sin esto la clase nace con el aforo entero como cupo libre, y la
  -- página ofrece los puestos que ya son de los afiliados. Va SIEMPRE,
  -- aunque no se haya creado ninguna clase: si alguien cambió de plan
  -- desde anoche, los números de la semana entrante también cambian.
  v_cupos := recalcular_cupos();

  select coalesce(jsonb_agg(jsonb_build_object(
           'fecha', f.fecha, 'nombre', f.nombre) order by f.fecha), '[]'::jsonb)
    into v_fest
    from festivos f
   where f.fecha between v_lunes and v_domingo;

  return jsonb_build_object(
    'ok', true,
    'desde', v_lunes,
    'hasta', v_domingo,
    'clases_creadas', v_creadas,
    'festivos', v_fest,
    'cupos', v_cupos,
    -- Cuántas clases quedaron en pie esa semana, hayan sido creadas
    -- ahora o antes. Es lo que hay que mirar para saber si la semana
    -- está lista, no cuántas se crearon.
    'clases_en_la_semana', (
      select count(*)::int from clases c
       where (c.fecha_hora at time zone 'America/Bogota')::date
             between v_lunes and v_domingo),
    -- Clases cuyo cupo NO cuadra con aforo − afiliados. Si sale algo
    -- distinto de cero, el recálculo no las alcanzó y la página está
    -- ofreciendo puestos que ya tienen dueño: el workflow se entera el
    -- sábado en vez de que lo descubra un cliente.
    --
    -- No sirve mirar "activos_plan = 0": una clase puede tener cero
    -- afiliados de verdad, y entonces ofrecer el aforo entero es
    -- correcto. Lo que se comprueba es la resta, no el resultado.
    'cupos_que_no_cuadran', (
      select count(*)::int from clases c
       where (c.fecha_hora at time zone 'America/Bogota')::date
             between v_lunes and v_domingo
         and c.cupo_manual is null        -- forzado a mano, manda ese
         and c.cupo_miembros is null      -- el sábado va partido, otra cuenta
         and c.cupo_total is distinct from
             greatest(c.aforo - coalesce(c.activos_plan, 0), 0)));
end;
$$;

revoke execute on function abrir_semana() from public, anon, authenticated;
grant  execute on function abrir_semana() to service_role;
