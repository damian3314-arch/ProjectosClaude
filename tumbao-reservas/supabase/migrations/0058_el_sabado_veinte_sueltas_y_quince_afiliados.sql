-- ---------------------------------------------------------------------
-- 0058 — El sábado: 20 sueltas y 15 afiliados
--
-- LO QUE SE PIDE
-- Cambiar el reparto del sábado a 20 puestos de clase suelta y 15 de
-- afiliados. La 0020 ya dejó dicho que esto iba a pasar: "15 y 15 es una
-- decisión de negocio que puede cambiar a 20 y 10 sin avisar. Un número
-- guardado se cambia; una fórmula hay que reescribirla". Pero el número
-- no estaba guardado del todo: `generar_horario` lo calculaba como
-- `p_aforo / 2`, o sea seguía siendo una fórmula.
--
-- EL LÍO QUE HABÍA, Y QUE ES EL QUE CONFUNDE EN EL PANEL
-- En los sábados de producción convivían CUATRO números distintos:
--
--   aforo          30   (el techo de la sala)
--   cupo_total     35   (el techo de verdad: es el que corta en tomar_cupo)
--   cupo_manual    35   (puesto a mano para que el recálculo no lo baje)
--   reparto     15+15   (los dos lados, que suman 30)
--
-- Con eso, cinco puestos del techo no se podían vender por ningún lado,
-- y el panel enseñaba a la vez "23 libres" (35 − 12) y un reparto donde
-- del lado de sueltas quedaban 9. Quien leyera "23 libres" le abría la
-- puerta a gente que no cabía.
--
-- Ahora los tres números que mandan concuerdan por construcción:
-- 15 + 20 = 35 = cupo_total = aforo del sábado.
--
-- POR QUÉ EL SÁBADO TIENE AFORO PROPIO
-- Entre semana el afiliado no reserva: su puesto ya viene descontado del
-- aforo, y por eso `recalcular_cupos` hace `aforo - activos`. El sábado
-- sí reserva, así que los dos lados tienen que caber enteros en la sala.
-- Vender 35 el sábado no es nuevo —cupo_manual llevaba tiempo en 35—;
-- lo nuevo es que el aforo lo diga en vez de contradecirlo.
--
-- POR QUÉ SE FIJA TAMBIÉN cupo_manual
-- `recalcular_cupos` corre cada noche y hace
-- `cupo_total = greatest(cupo_tomado, coalesce(cupo_manual, aforo - activos))`.
-- Sin `cupo_manual`, cada sábado nuevo amanecía con el techo bajado por
-- los afiliados activos, y alguien tenía que volver a ponerlo a mano.
-- Eso es exactamente lo que ya había pasado: los sábados de esta semana
-- tenían cupo_manual = 35 puesto a dedo.
-- ---------------------------------------------------------------------

do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'generar_horario';
  if v_def is null then raise exception 'no existe generar_horario'; end if;

  if position('0058:' in v_def) > 0 then
    raise notice '0058: generar_horario ya estaba parcheada';
  else
    v_def := replace(v_def,
      '    insert into clases (nombre, profesor, fecha_hora, duracion_min,' || E'\n' ||
      '                        cupo_total, precio_cop, lugar, aforo, activa,' || E'\n' ||
      '                        cupo_miembros, cupo_sueltas)',
      '    insert into clases (nombre, profesor, fecha_hora, duracion_min,' || E'\n' ||
      '                        cupo_total, precio_cop, lugar, aforo, activa,' || E'\n' ||
      '                        cupo_miembros, cupo_sueltas, cupo_manual)');

    v_def := replace(v_def,
      '           60, p_aforo, p_precio_cop, p_lugar, p_aforo, true,' || E'\n' ||
      '           -- Solo el sábado se parte. Entre semana el afiliado ni' || E'\n' ||
      '           -- siquiera reserva: su puesto ya está descontado del aforo.' || E'\n' ||
      '           case when 6 = any(h.dows) then p_aforo / 2 end,' || E'\n' ||
      '           case when 6 = any(h.dows) then p_aforo - p_aforo / 2 end',
      '           60,' || E'\n' ||
      '           -- 0058: el sabado el techo es la SUMA de los dos lados.' || E'\n' ||
      '           -- Antes cupo_total era el aforo y el reparto aforo/2, asi' || E'\n' ||
      '           -- que los lados sumaban 30 contra un techo de 35 y cinco' || E'\n' ||
      '           -- puestos no se podian vender por ningun lado.' || E'\n' ||
      '           case when 6 = any(h.dows) then 15 + 20 else p_aforo end,' || E'\n' ||
      '           p_precio_cop, p_lugar,' || E'\n' ||
      '           case when 6 = any(h.dows) then 15 + 20 else p_aforo end, true,' || E'\n' ||
      '           -- Solo el sábado se parte. Entre semana el afiliado ni' || E'\n' ||
      '           -- siquiera reserva: su puesto ya está descontado del aforo.' || E'\n' ||
      '           -- Numeros literales y no una formula: es una decision de' || E'\n' ||
      '           -- negocio, y la 0020 ya avisaba que iba a cambiar sola.' || E'\n' ||
      '           case when 6 = any(h.dows) then 15 end,' || E'\n' ||
      '           case when 6 = any(h.dows) then 20 end,' || E'\n' ||
      '           -- Sin esto el recalculo nocturno le baja el techo a' || E'\n' ||
      '           -- aforo - activos y hay que volver a ponerlo a mano.' || E'\n' ||
      '           case when 6 = any(h.dows) then 15 + 20 end');

    if position('0058:' in v_def) = 0 then
      raise exception '0058: los anclajes de generar_horario no encajaron';
    end if;
    execute v_def;
    raise notice '0058: generar_horario parcheada';
  end if;
end $$;

-- Los sábados que ya están abiertos. Solo hacia adelante: los pasados se
-- dejan como fueron, que es lo que de verdad se vendió ese día.
update clases
   set cupo_miembros = 15,
       cupo_sueltas  = 20,
       aforo         = 35,
       cupo_manual   = 35,
       -- Nunca por debajo de lo ya tomado: si alguien vendió de más, se
       -- respeta lo vendido en vez de dejar una clase sobrevendida.
       cupo_total    = greatest(cupo_tomado, 35)
 where extract(dow from fecha_hora at time zone 'America/Bogota') = 6
   and fecha_hora >= (now() at time zone 'America/Bogota')::date;
