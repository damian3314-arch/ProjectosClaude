-- El tablero mostraba "1 reservada" en una clase donde no habia nadie que ver.
--
-- Causa: 'reservadas' salia de c.cupo_tomado, el contador de la clase, que
-- incluye los cupos de reservas en pendiente_pago YA VENCIDAS. Pero
-- admin_lista_clase (el "ver quien entra") las excluye a proposito. O sea:
-- el numero las contaba y la lista no las mostraba. Numero sin persona.
--
-- Paso de verdad el 8 de agosto de 2026 con la reserva YH978Z: alguien
-- aparto un cupo de la clase de 6pm, nunca pago, y el panel mostro una
-- reserva que no aparecia por ningun lado.
--
-- Arreglo: 'reservadas' ahora cuenta exactamente lo mismo que muestra la
-- lista, y los cupos atascados salen aparte en 'por_soltar'. Asi
-- reservadas + por_soltar + libres = a_la_venta, y ningun numero del panel
-- vuelve a hablar de gente que no se puede ver.
--
-- 'libres' NO cambia: sigue saliendo de cupo_tomado, que es lo que de
-- verdad limita la venta. Preferible mostrar un cupo de menos que vender
-- uno que no existe.
--
-- Nota: el arreglo de fondo del cupo atascado es el workflow
-- "Tumbao - Liberar cupos vencidos", que estaba creado pero apagado. Se
-- activo el mismo dia. Esto de aca es para que, aunque se vuelva a apagar,
-- el panel nunca mienta.

create or replace function public.admin_tablero(p_token text, p_dia date default null::date)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_admin  uuid;
  v_dia    date;
  v_clases jsonb;
  v_hoy    date;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  v_hoy := (now() at time zone 'America/Bogota')::date;
  v_dia := coalesce(p_dia, v_hoy);

  select coalesce(jsonb_agg(x order by x->>'hora'), '[]'::jsonb) into v_clases
  from (
    select jsonb_build_object(
      'clase_id',    c.id,
      'nombre',      c.nombre,
      'hora',        to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'),
      'activa',      c.activa,
      'ya_paso',     c.fecha_hora <= now(),
      'aforo',       c.aforo,
      'con_plan',    c.activos_plan,
      'a_la_venta',  c.cupo_total,
      'cupo_manual', c.cupo_manual,
      'vencen',      v.vencen,
      -- Cuenta lo MISMO que muestra admin_lista_clase. Si aparece un 1 aca,
      -- hay una persona con nombre y telefono que se puede abrir.
      'reservadas',  n.reservadas,
      -- Cupos que quedaron atascados: alguien los aparto, nunca pago y ya
      -- se le vencio el tiempo. Los suelta el workflow "Liberar cupos
      -- vencidos" a la siguiente corrida. Si esto se queda en mas de cero
      -- por horas, ese workflow esta apagado.
      'por_soltar',  n.por_soltar,
      'libres',      greatest(c.cupo_total - c.cupo_tomado, 0),
      'confirmadas', n.confirmadas,
      'por_validar', n.por_validar,
      'esperando',   n.esperando,
      'en_sala',     c.activos_plan + c.cupo_tomado,
      'ingreso_cop', n.confirmadas * c.precio_cop,
      -- El reparto, solo si esta clase lo tiene
      'reparto', case when c.cupo_miembros is null then null else
        jsonb_build_object(
          'miembros_tope',    c.cupo_miembros,
          'miembros_tomados', n.de_miembros,
          'miembros_libres',  greatest(c.cupo_miembros - n.de_miembros, 0),
          'sueltas_tope',     c.cupo_sueltas,
          'sueltas_tomadas',  n.de_sueltas,
          'sueltas_libres',   greatest(c.cupo_sueltas - n.de_sueltas, 0))
      end
    ) as x
    from clases c
    cross join lateral (
      select
        count(*) filter (where r.estado = 'confirmada')::int            as confirmadas,
        count(*) filter (where r.estado = 'pendiente_validacion')::int  as por_validar,
        count(*) filter (where (r.estado = 'verificando'
         or (r.estado = 'pendiente_pago' and r.expira_en >= now())))::int as esperando,
        -- Mismo filtro, palabra por palabra, que admin_lista_clase.
        count(*) filter (where r.estado not in ('expirada','rechazada')
         and not (r.estado = 'pendiente_pago' and r.expira_en < now()))::int as reservadas,
        count(*) filter (where r.estado = 'pendiente_pago'
         and r.expira_en < now())::int                                  as por_soltar,
        count(*) filter (where r.tipo = 'miembro'
                           and r.estado not in ('rechazada','expirada'))::int as de_miembros,
        count(*) filter (where r.tipo = 'suelta'
                           and r.estado not in ('rechazada','expirada'))::int as de_sueltas
      from reservas r where r.clase_id = c.id
    ) n
    cross join lateral (
      select count(*)::int as vencen
        from membresias m
       where m.hora = (c.fecha_hora at time zone 'America/Bogota')::time
         and (c.fecha_hora at time zone 'America/Bogota')::date
             between m.inicio and m.fin
         and m.fin = (c.fecha_hora at time zone 'America/Bogota')::date
    ) v
   where (c.fecha_hora at time zone 'America/Bogota')::date = v_dia
  ) s;

  return jsonb_build_object(
    'ok', true,
    'dia', v_dia,
    'es_hoy', v_dia = v_hoy,
    'clases', v_clases,
    'resumen', jsonb_build_object(
      'clases',      jsonb_array_length(v_clases),
      'aforo',       coalesce((select sum((c->>'aforo')::int)       from jsonb_array_elements(v_clases) c), 0),
      'con_plan',    coalesce((select sum((c->>'con_plan')::int)    from jsonb_array_elements(v_clases) c), 0),
      'vencen',      coalesce((select sum((c->>'vencen')::int)      from jsonb_array_elements(v_clases) c), 0),
      'a_la_venta',  coalesce((select sum((c->>'a_la_venta')::int)  from jsonb_array_elements(v_clases) c), 0),
      'reservadas',  coalesce((select sum((c->>'reservadas')::int)  from jsonb_array_elements(v_clases) c), 0),
      'por_soltar',  coalesce((select sum((c->>'por_soltar')::int)  from jsonb_array_elements(v_clases) c), 0),
      'libres',      coalesce((select sum((c->>'libres')::int)      from jsonb_array_elements(v_clases) c), 0),
      'confirmadas', coalesce((select sum((c->>'confirmadas')::int) from jsonb_array_elements(v_clases) c), 0),
      'por_validar', coalesce((select sum((c->>'por_validar')::int) from jsonb_array_elements(v_clases) c), 0),
      'esperando',   coalesce((select sum((c->>'esperando')::int)   from jsonb_array_elements(v_clases) c), 0),
      'en_sala',     coalesce((select sum((c->>'en_sala')::int)     from jsonb_array_elements(v_clases) c), 0),
      'ingreso_cop', coalesce((select sum((c->>'ingreso_cop')::int) from jsonb_array_elements(v_clases) c), 0)
    ));
end;
$function$;
