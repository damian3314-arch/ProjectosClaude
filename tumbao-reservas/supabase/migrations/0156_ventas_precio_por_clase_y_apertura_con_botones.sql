-- 0156 · Precio por clase de la mensualidad y apertura de ventas con botones de horario (prueba A/B)
--
-- Damián (7 oct): «la mensualidad da clases de lunes a sábado, sin domingos ni festivos. El mensaje con botones
-- está bueno. ¿Poner enlace en el mensaje es más caro? ¿Hay riesgo de bloqueo?»
--
--   1 · mensualidad_clases_mes = 25 (entre 23 y 26 según el mes: lunes a sábado menos festivos). ventas_perfil
--       suma mensualidad_por_clase = valor ÷ clases, a $100 (≈ $5.000). El bot lo dice como «alrededor de»,
--       contra los $15.000 de la suelta; es la cuenta del producto, no un descuento.
--   2 · Plantilla ventas_horario (MARKETING, botones 7:00 am / 6:00 pm / 7:00 pm / No quiero más mensajes, SIN
--       enlace). El enlace va en la respuesta, dentro de la ventana de 24 h. ventas_ronda reparte las
--       aperturas entre ventas_apertura y la plantilla de ajustes.ventas_plantilla_b (por número de chat, par o
--       impar) SOLO cuando ese ajuste tiene valor: hoy está vacío, así que nada cambia hasta que Meta la apruebe.

insert into ajustes (clave, valor, nota) values
  ('mensualidad_clases_mes', '25', 'Clases que da la mensualidad al mes (lunes a sábado sin domingos ni festivos: entre 23 y 26). Solo para decir el precio por clase «alrededor de». 0156.'),
  ('ventas_plantilla_b', '', 'Plantilla B de la apertura de ventas (prueba A/B por número de chat). Vacío = solo ventas_apertura. 0156.')
on conflict (clave) do nothing;

do $mig$
declare v_def text;
begin
  -- ventas_perfil: precio por clase de la mensualidad
  v_def := pg_get_functiondef('public.ventas_perfil(text)'::regprocedure);
  if position('mensualidad_por_clase' in v_def) = 0 then
    if position('''paquetes_tiquetera'', tiquetera_paquetes(),' in v_def) = 0 then raise exception 'ventas_perfil: no encuentro el texto a cambiar'; end if;
    v_def := replace(v_def, '''paquetes_tiquetera'', tiquetera_paquetes(),',
      $r$'mensualidad_por_clase', (select (round(coalesce(nullif((select valor from ajustes where clave = 'mensualidad_valor_cop'), '')::int, 125000)::numeric
                                                 / greatest(coalesce(nullif((select valor from ajustes where clave = 'mensualidad_clases_mes'), '')::int, 25), 1) / 100) * 100)::int),
    'paquetes_tiquetera', tiquetera_paquetes(),$r$);
    execute v_def;
  end if;

  -- ventas_ronda: reparte la apertura entre A (ventas_apertura) y B (ventas_plantilla_b) cuando B existe
  v_def := pg_get_functiondef('public.ventas_ronda(boolean, timestamptz)'::regprocedure);
  if position('ventas_plantilla_b' in v_def) = 0 then
    if position('''campana'', c.telefono, ''ventas_apertura'',' in v_def) = 0 then raise exception 'ventas_ronda: no encuentro el texto a cambiar'; end if;
    v_def := replace(v_def, '''campana'', c.telefono, ''ventas_apertura'',',
      $r$'campana', c.telefono,
           case when coalesce((select valor from ajustes where clave = 'ventas_plantilla_b'), '') <> '' and c.id % 2 = 1
                then (select valor from ajustes where clave = 'ventas_plantilla_b') else 'ventas_apertura' end,$r$);
    execute v_def;
  end if;

  -- wa_tomar_ventas: la «apertura» que lee el bot sale de cualquiera de las dos plantillas
  v_def := pg_get_functiondef('public.wa_tomar_ventas(bigint)'::regprocedure);
  if position('ventas_horario' in v_def) = 0 then
    if position('a.plantilla = ''ventas_apertura''' in v_def) = 0 then raise exception 'wa_tomar_ventas: no encuentro el texto a cambiar'; end if;
    v_def := replace(v_def, 'a.plantilla = ''ventas_apertura''', 'a.plantilla in (''ventas_apertura'', ''ventas_horario'')');
    execute v_def;
  end if;
end
$mig$;
