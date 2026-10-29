-- 0189 · Campaña «rescatar el mes» (29 oct): un mensaje lindo a la base que no tiene plan ni tiquetera vigente
--
-- Damián (29 oct): «el número ya puede enviar hasta 2000 mensajes; lancemos algo en comunicación super lindo que empuje a
-- la conversión; objetivo, rescatar el mes». Sin descuentos, regalos ni promociones (la dueña no los autoriza): solo la
-- mensualidad y las tiqueteras con sus precios de siempre y el enlace a la página.
--
-- Esta función NO envía nada por sí sola: con p_ejecutar = false (por defecto) solo cuenta a quién le llegaría. Con
-- p_ejecutar = true deja los avisos en la cola (tipo «campana»): el despachador los retiene fuera del horario de mercadeo
-- (lunes a viernes 9 am a 7 pm, sábado hasta la 1 pm, nunca domingos ni festivos) y respeta el tope diario wa_tope_diario.
-- Correrla con true es una decisión de Damián: cuesta (plantilla de marketing, ≈ $46 por mensaje) y escribe a clientes reales.
--
-- Quién entra (los mismos filtros de siempre):
--   · celular válido de reservas de clase o de quien escribió por WhatsApp;
--   · sin SALIR, sin dueñas, sin plan vigente (con su gracia) ni tiquetera vigente;
--   · sin campaña en los últimos 3 días y máximo 1 antes de esta en 14 días (máx. 2 en 14);
--   · sin un «no me interesa» de ventas en 45 días, sin conversación de ventas abierta y sin una solicitud de mensualidad
--     por pagar o pagada.
-- Quién recibe qué: quien bailó 2 o más veces en 30 días recibe «rescate_mes_frecuentes» (con cuántas veces); los demás,
-- «rescate_mes_general».

create or replace function public.campana_rescate_mes(p_ejecutar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_gracia int; v_f int; v_g int; v_enc_f int := 0; v_enc_g int := 0;
begin
  v_gracia := coalesce(nullif((select valor from ajustes where clave = 'mensualidad_gracia_dias'), '')::int, 3);

  create temporary table if not exists _rescate (t text primary key, n text, v30 int, seg text) on commit drop;
  truncate _rescate;

  insert into _rescate (t, n, v30, seg)
  with base as (
    select right(regexp_replace(r.telefono, '\D', '', 'g'), 10) t,
           count(*) filter (where r.created_at > now() - interval '30 days' and r.estado = 'confirmada') v30,
           mode() within group (order by initcap(split_part(btrim(r.nombre), ' ', 1))) n
      from reservas r where r.telefono is not null group by 1
  ), wa as (
    select distinct right(regexp_replace(m.telefono, '\D', '', 'g'), 10) t from wa_mensajes m
     where m.telefono is not null and m.direccion = 'entrante'
  ), todos as (
    select t from base union select t from wa
  )
  select td.t, coalesce(nullif(b.n, ''), nullif(initcap(split_part(btrim(vc.nombre), ' ', 1)), ''), 'amigo(a)'),
         coalesce(b.v30, 0),
         case when coalesce(b.v30, 0) >= 2 then 'frecuentes' else 'general' end
    from todos td
    left join base b on b.t = td.t
    left join lateral (select nombre from ventas_chats c where right(c.telefono, 10) = td.t order by c.ultima_at desc nulls last limit 1) vc on true
   where td.t ~ '^3[0-9]{9}$'
     and not exists (select 1 from wa_bajas x where right(x.telefono, 10) = td.t)
     and not wa_es_dueno(td.t)
     and not exists (select 1 from membresias m where m.celular is not null
                       and right(regexp_replace(m.celular, '\D', '', 'g'), 10) = td.t
                       and current_date between m.inicio and m.fin + v_gracia)
     and not exists (select 1 from tiqueteras q where q.telefono is not null
                       and right(regexp_replace(q.telefono, '\D', '', 'g'), 10) = td.t and q.vence_el >= current_date)
     and not exists (select 1 from wa_avisos a where right(a.telefono, 10) = td.t and a.tipo = 'campana'
                       and a.creado_at > now() - interval '3 days')
     and (select count(*) from wa_avisos a where right(a.telefono, 10) = td.t and a.tipo = 'campana'
                       and a.creado_at > now() - interval '14 days') < 2
     and not exists (select 1 from ventas_chats c where right(c.telefono, 10) = td.t
                       and (c.estado = 'abierta' or c.cerrada_at > now() - interval '45 days'))
     and not exists (select 1 from mensualidad_solicitudes s where s.celular = td.t and s.estado in ('esperando_pago', 'pagada'));

  select count(*) filter (where seg = 'frecuentes'), count(*) filter (where seg = 'general') into v_f, v_g from _rescate;

  if p_ejecutar then
    with a as (
      insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
      select 'rescate-mes:' || t, 'campana', t,
             case seg when 'frecuentes' then 'rescate_mes_frecuentes' else 'rescate_mes_general' end,
             case seg when 'frecuentes' then jsonb_build_array(n, v30::text) else jsonb_build_array(n) end,
             now() + interval '4 days'
        from _rescate
      on conflict (clave) do nothing
      returning plantilla)
    select count(*) filter (where plantilla = 'rescate_mes_frecuentes'), count(*) filter (where plantilla = 'rescate_mes_general')
      into v_enc_f, v_enc_g from a;
  end if;

  return jsonb_build_object('ejecutado', p_ejecutar, 'frecuentes', v_f, 'general', v_g, 'total', v_f + v_g,
                            'encolados_frecuentes', v_enc_f, 'encolados_general', v_enc_g,
                            'costo_aprox_cop', (v_f + v_g) * 46);
end; $function$;

revoke all on function public.campana_rescate_mes(boolean) from public, anon, authenticated;
