-- 0160 · Informes diarios en dos tamaños: tranqui (muy corto) y completo (el de siempre)
--
-- Damián (9 oct): «el reporte es muy bueno, pero a veces me siento infotoxicado... que algunos días sea más tranqui,
-- solo cómo estuvo el día pero muy resumido, y otros días con todo el detalle».
--
-- ajustes.informe_modo:
--   'mixto'    (por defecto) calendario fijo: completos el lunes y el miércoles en la mañana (a quién buscar y qué
--              vence) y el viernes en la noche (cierre de la semana con insights); todos los demás, tranquilos;
--   'tranqui'  todos tranquilos;
--   'completo' todos completos, como hasta ahora.
-- Se cambia por WhatsApp («informes tranquilos / mixtos / completos») con informe_modo_cambiar(). Quien escriba
-- «detalle» recibe el informe completo en ese momento. Las alertas (cierre sin hacer, efectivo descuadrado, ventas por
-- debajo de la mitad, muchos vencimientos) las decide el código y salen aunque el informe sea tranqui.

insert into ajustes (clave, valor, nota) values
  ('informe_modo', 'mixto', 'Informes diarios: mixto (calendario), tranqui (todos cortos) o completo (todos largos). 0160.')
on conflict (clave) do nothing;

create or replace function public.informe_modo_cambiar(p_modo text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_modo not in ('mixto', 'tranqui', 'completo') then
    raise exception 'modo inválido: %', p_modo;
  end if;
  update ajustes set valor = p_modo where clave = 'informe_modo';
  if not found then
    insert into ajustes (clave, valor, nota) values ('informe_modo', p_modo, 'Informes diarios: mixto, tranqui o completo. 0160.');
  end if;
  return p_modo;
end;
$$;
revoke all on function public.informe_modo_cambiar(text) from public, anon, authenticated;
