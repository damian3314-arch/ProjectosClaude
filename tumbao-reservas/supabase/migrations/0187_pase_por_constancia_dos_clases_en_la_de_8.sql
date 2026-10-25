-- 0187 · Clase adicional por constancia: 1 clase en la tiquetera de 4 y 2 clases en la de 8 (25 oct, Damián)
--
-- Regla: quien completa TODAS las clases de su tiquetera recibe clases adicionales por su constancia, nuevas o viejas:
--   · tiquetera de 4 clases  -> 1 clase adicional
--   · tiquetera de 8 clases  -> 2 clases adicionales
-- Antes era siempre 1. El aviso de WhatsApp de la de 4 sigue siendo la plantilla pase_constancia (ya aprobada). Para la de 8
-- hay una plantilla nueva, pase_constancia_2, que dice cuántas clases son. Mientras Meta no la apruebe
-- (ajustes.wa_pase_constancia_2 = 'apagado') a quien completa la de 8 NO se le escribe: la clase queda creada y la nota a
-- Damián dice que se le avise a mano. Sin semicolones dentro de los textos.

insert into ajustes (clave, valor, nota)
values ('wa_pase_constancia_2', 'apagado',
        'Aviso de las 2 clases adicionales (tiquetera de 8). Se enciende cuando Meta apruebe la plantilla pase_constancia_2 (0187).')
on conflict (clave) do nothing;

create or replace function public.pases_por_constancia()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  hoy      date := (now() at time zone 'America/Bogota')::date;
  n        int  := 0;
  r        record;
  v_id     bigint;
  v_cod    text;
  v_vence  date := ((now() at time zone 'America/Bogota')::date + 30);
  v_tel    text;
  v_nom    text;
  v_baja   boolean;
  v_extra  int;
  v_plant  text;
  v_vars   jsonb;
  v_lineas text[] := '{}';
begin
  if coalesce((select valor from ajustes where clave = 'wa_pase_constancia'), 'apagado')
     <> 'encendido' then
    return 0;
  end if;
  if extract(isodow from hoy) = 7 or exists (select 1 from festivos where fecha = hoy) then
    return 0;
  end if;

  for r in
    select t.id, t.nombre, t.telefono, t.clases_totales
      from tiqueteras t
     where t.estado = 'confirmada'
       and t.premio_de is null
       and not exists (select 1 from tiqueteras p where p.premio_de = t.id)
       and (select count(distinct a.reserva_id)
              from asistencias a join reservas x on x.id = a.reserva_id
             where x.tiquetera_id = t.id) >= t.clases_totales
       and (select max((c.fecha_hora at time zone 'America/Bogota')::date)
              from asistencias a join reservas x on x.id = a.reserva_id
              join clases c on c.id = a.clase_id
             where x.tiquetera_id = t.id) >= hoy - 14
     order by t.id
  loop
    begin
      v_tel := right(regexp_replace(coalesce(r.telefono, ''), '\D', '', 'g'), 10);
      v_nom := coalesce(nullif(initcap(split_part(btrim(r.nombre), ' ', 1)), ''), 'amigo(a)');
      v_extra := case when r.clases_totales >= 8 then 2 else 1 end;

      loop
        v_cod := generar_codigo_reserva();
        exit when not exists (select 1 from tiqueteras where codigo = v_cod);
      end loop;

      insert into tiqueteras (codigo, nombre, telefono, clases_totales, clases_usadas,
                              precio_cop, vence_el, activa, estado, nota, premio_de)
      values (v_cod, r.nombre, r.telefono, v_extra, 0, 0, v_vence, true, 'confirmada',
              'Clase adicional por constancia (completó la tiquetera ' || r.id || ')', r.id)
      on conflict (premio_de) where premio_de is not null do nothing
      returning id into v_id;
      if v_id is null then continue; end if;
      n := n + 1;

      v_baja := v_tel !~ '^3[0-9]{9}$'
                or exists (select 1 from wa_bajas b where b.telefono = v_tel);

      if v_extra = 1 then
        v_plant := 'pase_constancia';
        v_vars := jsonb_build_array(v_nom, r.clases_totales::text, 'Código: ' || v_cod, wa_fecha_texto(v_vence));
      else
        v_plant := 'pase_constancia_2';
        v_vars := jsonb_build_array(v_nom, r.clases_totales::text, v_extra::text || ' clases adicionales',
                                    'Código: ' || v_cod, wa_fecha_texto(v_vence));
        -- sin plantilla aprobada no se escribe: se avisa a mano
        if coalesce((select valor from ajustes where clave = 'wa_pase_constancia_2'), 'apagado') <> 'encendido' then
          v_baja := true;
        end if;
      end if;

      if not v_baja then
        insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
        values ('pase_constancia:' || v_id, 'pase_constancia', v_tel, v_plant, v_vars, now() + interval '3 days')
        on conflict (clave) do nothing;
      end if;

      v_lineas := v_lineas || (initcap(btrim(r.nombre)) || ' completó sus ' || r.clases_totales
                               || ' clases y ganó ' || v_extra || case when v_extra = 1 then ' clase adicional' else ' clases adicionales' end
                               || case when v_baja
                                 then ' (avísale tú por WhatsApp: código ' || v_cod || ')'
                                 else ' y ya le llegó el aviso' end);
    exception when others then
      raise warning 'pases_por_constancia (tiquetera %): %', r.id, sqlerrm;
    end;
  end loop;

  if n > 0 then
    perform nota_asistente(
      '🎁 Clase adicional por constancia',
      array_to_string(v_lineas, E'\n'),
      'pases:' || hoy);
  end if;
  return n;
exception when others then
  raise warning 'pases_por_constancia: %', sqlerrm;
  return n;
end;
$function$;
