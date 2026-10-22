-- 0172 · El centinela ya no avisa «envíos atascados» por campañas que la cola retiene A PROPÓSITO
--
-- Las campañas (wa_avisos.tipo = 'campana') solo salen en horario de mercadeo (wa_horario_mercadeo: lun-vie 9-19, sáb 9-13,
-- nunca domingos ni festivos). La tiquetera por constancia (0171) se encoló el sábado 10 de oct en la noche y sale el martes 13
-- a las 9:05; el centinela la contaba como «atascada» (más de 30 minutos pendiente) y mandó la alerta el 11 y el 12 a las 7 am.
-- Ahora cola_atascada solo cuenta una campaña pendiente si es horario de mercadeo (ahí sí debería estar saliendo).
-- Parche en vivo con pg_get_functiondef + replace (solo la condición de cola_atascada). Nada destructivo.

do $do$
declare d text; a text := $a$where estado = 'pendiente' and creado_at < now() - interval '30 minutes'$a$;
begin
  d := pg_get_functiondef('public.centinela_datos'::regproc);
  if position('wa_horario_mercadeo' in d) > 0 then return; end if;
  if position(a in d) = 0 then raise exception 'ancla no encontrada'; end if;
  d := replace(d, a, a || $b$ and (tipo <> 'campana' or wa_horario_mercadeo())$b$);
  execute d;
end
$do$;
