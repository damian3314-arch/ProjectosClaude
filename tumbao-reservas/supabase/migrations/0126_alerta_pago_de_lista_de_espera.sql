-- 0126 · El aviso a recepción distingue el pago de alguien que está en LISTA DE ESPERA
--
-- 30 sep: Leidy Muñoz (7 pm) y Genny González (6 pm) estaban apuntadas en la
-- lista de espera de mensualidad —horarios cerrados— y transfirieron $125.000
-- cada una. El aviso de las 0124 les dijo a recepción «Si es una mensualidad,
-- regístrala en Caja y pásala a AdminGym», y eso habría dado un cupo donde no
-- hay. Una persona en lista de espera NO tiene derecho a pagar: ese pago hay
-- que devolverlo o ubicarlo, y lo decide Damián.
--
-- Ahora, si el remitente de un pago sin asignar coincide con alguien apuntado
-- en la lista de espera (últimos 14 días, dos palabras del nombre en común),
-- el aviso lo dice con todas las letras y NO sugiere pasarlo a AdminGym.
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.alertas_recepcion()'::regprocedure) into v_src;
  if position('lista de espera de las' in v_src) > 0 then return; end if;

  v_new := replace(v_src,
    'order by m.fin limit 1) parece',
    'order by m.fin limit 1) parece,
           (select ''lista de espera de las '' || lower(to_char(s.hora::time, ''FMHH12:MI am''))
              from mensualidad_solicitudes s
             where s.estado = ''lista_espera''
               and s.creado_at > now() - interval ''14 days''
               and cardinality(array(
                     select t from unnest(string_to_array(norm_nombre(p.remitente), '' '')) t where length(t) >= 3
                     intersect
                     select t from unnest(string_to_array(norm_nombre(s.nombre), '' '')) t where length(t) >= 3)) >= 2
             order by s.creado_at desc limit 1) espera');
  if v_new = v_src then raise exception '0126: no encontré el final de la pista'; end if;

  v_src := v_new;
  v_new := replace(v_src,
    '|| case when r.parece is not null then E''\n   Parece la renovación de '' || r.parece else '''' end);',
    '|| case when r.espera is not null
                then E''\n   ⚠️ Estaba en la '' || r.espera || E'': NO es una compra, no tenía cupo. No la pases a AdminGym; consulta con Damián.''
                when r.parece is not null then E''\n   Parece la renovación de '' || r.parece else '''' end);');
  if v_new = v_src then raise exception '0126: no encontré la línea del aviso'; end if;

  -- El cierre del bloque de pagos también sugería pasarlo a AdminGym.
  v_src := v_new;
  v_new := replace(v_src,
    '|| E''\nSi es una mensualidad, regístrala en Caja y pásala a AdminGym.'' || E''\n\n'';',
    '|| E''\nSi es una mensualidad de alguien que YA tiene plan, regístrala en Caja y pásala a AdminGym. Si dice lista de espera, no la registres.'' || E''\n\n'';');
  if v_new = v_src then raise exception '0126: no encontré el cierre del bloque de pagos'; end if;

  execute v_new;
end
$mig$;
