-- 0182 · Campaña del 14 de octubre, 9:00 am: retoma, frecuentes y seguimiento más largo
--
-- 13 oct, Damián: «envíalo mañana a las 9 am, con el copy nuevo que armamos, y a las que apliquen a mensualidad,
-- invitarlas a mensualidad. Y a la gente que le viste alguna intención o reacción, escríbele si se puede».
-- 14 oct: «las mensualidades están caídas, necesitamos nuevos clientes; la fidelidad se puede pausar» (0180).
--
-- A QUIÉN Y QUÉ RECIBE (nadie recibe dos mensajes):
--
-- 1 · RETOMA. Quienes ya pidieron la mensualidad de 6 pm o de 7 pm en una conversación con Timba de los últimos 9 días,
--   interés alto o medio, y siguen sin comprar. A ellos Timba les dijo «lista de espera» y ahora hay cupo (13 oct: a
--   Mónica, que quería la mensualidad de 6 pm para ir con su hija, el bot le contestó «lista de espera» con 4 cupos
--   libres en la página). Se les reabre la conversación con la mensualidad de ese horario y se les manda la apertura
--   «ventas_apertura» con «me contaste que querías la mensualidad en el horario de las X y ya hay cupo disponible».
--   Hasta el número de cupos libres de cada horario, los de interés alto primero.
-- 2 · FRECUENTES · MENSUALIDAD. Clientes con 2 o más clases sueltas en 30 días, sin plan vigente (gracia incluida) ni
--   tiquetera, sin SALIR, que no son del equipo, sin oferta de tiquetera en los últimos 14 días, máximo 2 campañas en 14
--   días y ninguna en los últimos 3. Si su horario habitual (7 am, 6 pm o 7 pm; quien baila antes del mediodía entra al
--   de 7 am, donde hay más cupo) tiene cupo libre en la página, Timba le abre una conversación con la mensualidad de ese
--   horario. Hasta los cupos que quedan después del grupo 1, los que más vienen primero. El cupo es de quien pague
--   primero: no se promete ninguno. Si dice «cuéntame más», Timba sigue y le da el enlace y el QR.
-- 3 · FRECUENTES · TIQUETERA. Los frecuentes que no caben en los cupos libres de su horario reciben la plantilla
--   «tiquetera_constancia» (el copy nuevo, aprobado por Meta).
-- Todo sale como campaña: el despachador la retiene fuera del horario de mercadeo (Ley 2300), así que no sale antes de las
-- 8 am ni en domingo o festivo. El saludo usa el nombre que más se repite en las reservas de ese celular.
--
-- p_ejecutar = false solo cuenta y devuelve una muestra; true encola.
-- La corrida es de una sola vez: hoy 14 de octubre a las 9:00 am de Bogotá (14:00 UTC); el mismo cron se desprograma.

create or replace function public.campana_frecuentes_14oct(p_ejecutar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  hoy date := (now() at time zone 'America/Bogota')::date;
  cupos jsonb := ventas_cupos();
  v_r int; v_m int; v_t int; v_enc_r int; v_enc_m int; v_enc_t int; v_muestra jsonb;
begin
  with vig as (
    select distinct right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) tel
      from membresias
     where fin + coalesce(nullif((select valor from ajustes where clave = 'mensualidad_gracia_dias'), '')::int, 3) >= hoy),
  -- 1 · retoma: pidieron la mensualidad de 6 o de 7 pm (su conversación más reciente de los últimos 9 días)
  ult as (
    select distinct on (c.telefono) c.id chat_id, c.telefono tel, c.nombre n, c.interes,
           case when c.resumen ~* '7(:00)?\s*(pm|p\.\s*m\.)' then '19:00'
                when c.resumen ~* '6(:00)?\s*(pm|p\.\s*m\.)' then '18:00' end hora_r
      from ventas_chats c
     where c.abierta_at > now() - interval '9 days' and c.interes in ('alto', 'medio') and coalesce(c.resultado, '') <> 'no_interesado'
     order by c.telefono, c.abierta_at desc),
  rq as (
    select u.*, row_number() over (partition by u.hora_r order by (u.interes = 'alto') desc, u.chat_id desc) rn
      from ult u
     where u.hora_r is not null and u.tel ~ '^3[0-9]{9}$'
       and coalesce((cupos ->> u.hora_r)::int, 0) > 0
       and u.tel not in (select tel from vig)
       and not wa_es_dueno(u.tel)
       and not exists (select 1 from wa_bajas b where b.telefono = u.tel)
       and not exists (select 1 from tiqueteras t
                        where right(regexp_replace(t.telefono, '\D', '', 'g'), 10) = u.tel
                          and (t.estado in ('confirmada', 'pendiente_validacion') or t.pagado_en is not null) and t.vence_el >= hoy)
       and not exists (select 1 from mensualidad_solicitudes m
                        where right(regexp_replace(coalesce(m.celular, ''), '\D', '', 'g'), 10) = u.tel
                          and m.estado in ('esperando_pago', 'pagada') and m.creado_at > now() - interval '3 days')
       and not exists (select 1 from wa_avisos a where a.clave = 'ventas:' || u.tel || ':retoma:' || to_char(hoy, 'YYYYMMDD'))),
  ret as (select rq.* from rq where rq.rn <= coalesce((cupos ->> rq.hora_r)::int, 0)),
  upd as (
    update ventas_chats c
       set objetivo = case r.hora_r when '18:00' then 'mensualidad_6pm' else 'mensualidad_7pm' end,
           estado = 'abierta', abierta_at = now(),
           oferta = coalesce(c.oferta, '{}'::jsonb) || jsonb_build_object('campana', '14oct_retoma', 'hora', r.hora_r)
      from ret r
     where p_ejecutar and c.id = r.chat_id
    returning c.telefono, c.nombre, r.hora_r),
  enc_r as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'ventas:' || u.telefono || ':retoma:' || to_char(hoy, 'YYYYMMDD'), 'campana', u.telefono, 'ventas_apertura',
           jsonb_build_array(coalesce(nullif(initcap(split_part(btrim(u.nombre), ' ', 1)), ''), 'amigo(a)'),
             'Me contaste que querías la mensualidad en el horario de las ' || case u.hora_r when '18:00' then '6 pm' else '7 pm' end
             || ' y ya hay cupo disponible 🧡'),
           now() + interval '5 hours'
      from upd u
    on conflict (clave) do nothing
    returning 1),
  -- cupos que quedan para los frecuentes, por horario
  resto as (
    select h, greatest(coalesce((cupos ->> h)::int, 0) - (select count(*) from ret where ret.hora_r = h), 0) libres
      from (values ('07:00'), ('18:00'), ('19:00')) v(h)),
  r as (
    select right(regexp_replace(x.telefono, '\D', '', 'g'), 10) tel,
           mode() within group (order by initcap(split_part(btrim(x.nombre), ' ', 1))) n,
           count(*) filter (where x.tipo = 'suelta' and c.fecha_hora >= now() - interval '30 days' and c.fecha_hora < now()) v30,
           max(c.fecha_hora) filter (where c.fecha_hora < now()) ultima,
           mode() within group (order by to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'))
             filter (where c.fecha_hora >= now() - interval '60 days') hh
      from reservas x join clases c on c.id = x.clase_id
     where x.estado = 'confirmada' group by 1),
  base as (
    select r.* from r
     where r.v30 >= 2 and r.tel ~ '^3[0-9]{9}$'
       and r.tel not in (select tel from vig)
       and r.tel not in (select tel from ret)
       and not wa_es_dueno(r.tel)
       and not exists (select 1 from wa_bajas b where b.telefono = r.tel)
       and not exists (select 1 from tiqueteras t
                        where right(regexp_replace(t.telefono, '\D', '', 'g'), 10) = r.tel
                          and (t.estado in ('confirmada', 'pendiente_validacion') or t.pagado_en is not null) and t.vence_el >= hoy)
       and not exists (select 1 from wa_avisos a where a.clave = 'tiqconst:' || r.tel)
       and not exists (select 1 from wa_avisos a where a.telefono = r.tel
                         and a.plantilla in ('tiquetera_semana', 'tiquetera_frecuentes', 'tiquetera_constancia')
                         and a.estado in ('enviando', 'enviado', 'pendiente')
                         and coalesce(a.enviado_at, a.creado_at) > now() - interval '14 days')
       and (select count(*) from wa_avisos a where a.telefono = r.tel and a.tipo = 'campana'
              and a.estado in ('enviando', 'enviado', 'pendiente') and a.creado_at > now() - interval '14 days') < 2
       and not exists (select 1 from wa_avisos a where a.telefono = r.tel and a.tipo = 'campana'
                         and a.estado in ('enviando', 'enviado', 'pendiente') and a.creado_at > now() - interval '3 days')
       and not exists (select 1 from ventas_chats c where c.telefono = r.tel and c.abierta_at > now() - interval '3 days')
       and not exists (select 1 from ventas_chats c where c.telefono = r.tel and c.resultado = 'no_interesado'
                         and c.cerrada_at > now() - interval '45 days')),
  clas as (
    select b.*,
           -- quien baila de mañana (antes del mediodía) puede tomar la mensualidad de 7 am, que es donde más cupo hay
           case when b.hh < '12:00' then '07:00' else b.hh end hp,
           row_number() over (partition by case when b.hh < '12:00' then '07:00' else b.hh end order by b.v30 desc, b.ultima desc) rn
      from base b),
  asig as (
    select c.*,
           case when c.hp in ('07:00', '18:00', '19:00')
                     and c.rn <= coalesce((select libres from resto where h = c.hp), 0)
                then 'mensualidad' else 'tiquetera' end as camino,
           case c.hp when '07:00' then 'mensualidad_7am' when '18:00' then 'mensualidad_6pm' when '19:00' then 'mensualidad_7pm' end as obj
      from clas c),
  chat as (
    insert into ventas_chats (telefono, nombre, objetivo, oferta, abierta_at)
    select a.tel, coalesce(nullif(a.n, ''), 'amigo(a)'), a.obj,
           jsonb_build_object('visitas_30d', a.v30, 'hora_habitual', a.hh, 'origen', 'reservas', 'campana', '14oct'), now()
      from asig a where p_ejecutar and a.camino = 'mensualidad'
    returning telefono, nombre, objetivo, oferta),
  enc_m as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'ventas:' || c.telefono || ':' || to_char(hoy, 'YYYYMMDD'), 'campana', c.telefono, 'ventas_apertura',
           jsonb_build_array(c.nombre, ventas_gancho2(c.objetivo, (c.oferta ->> 'visitas_30d')::int, 'reservas', null)),
           now() + interval '5 hours'
      from chat c
    on conflict (clave) do nothing
    returning 1),
  enc_t as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'tiqconst:' || a.tel, 'campana', a.tel, 'tiquetera_constancia',
           jsonb_build_array(coalesce(nullif(a.n, ''), 'amigo(a)'), a.v30::text), now() + interval '5 days'
      from asig a where p_ejecutar and a.camino = 'tiquetera'
    on conflict (clave) do nothing
    returning 1)
  select (select count(*) from ret), (select count(*) from asig where camino = 'mensualidad'), (select count(*) from asig where camino = 'tiquetera'),
         (select count(*) from enc_r), (select count(*) from enc_m), (select count(*) from enc_t),
         (select coalesce(jsonb_agg(z.x order by z.x ->> 'camino', z.x ->> 'hora'), '[]'::jsonb)
            from (select jsonb_build_object('cel', right(tel, 4), 'nombre', n, 'hora', hora_r, 'camino', 'retoma') x from ret
                  union all
                  select jsonb_build_object('cel', right(tel, 4), 'nombre', n, 'hora', hh, 'camino', camino, 'v30', v30) from asig) z)
    into v_r, v_m, v_t, v_enc_r, v_enc_m, v_enc_t, v_muestra;

  return jsonb_build_object('ejecutado', p_ejecutar, 'retoma', v_r, 'mensualidad', v_m, 'tiquetera', v_t,
                            'encolados_retoma', v_enc_r, 'encolados_mensualidad', v_enc_m, 'encolados_tiquetera', v_enc_t,
                            'cupos', cupos, 'muestra', v_muestra);
end;
$function$;
revoke all on function public.campana_frecuentes_14oct(boolean) from public, anon, authenticated;

-- La corrida es de una sola vez: hoy 14 de octubre a las 9:00 am de Bogotá (14:00 UTC). Cuando termina, el mismo cron se
-- desprograma; la fecha fija en el cron impide que vuelva a correr el año que viene.
select cron.schedule('tumbao-campana-14oct', '0 14 14 10 *',
  $cmd$select public.campana_frecuentes_14oct(true); select cron.unschedule('tumbao-campana-14oct');$cmd$);

-- 0182 (parte 2) · El seguimiento gratis de 24 h llega hasta 22 horas después del último mensaje de Timba
-- (antes 20). Así, quien le escribió a Timba entre las 11 am y la noche de un día todavía alcanza el seguimiento de las
-- 9 am del día siguiente, que es la primera hora en que se puede (Ley 2300). Sigue siendo una sola vez por conversación,
-- solo dentro de la ventana de 24 h de WhatsApp (gratis) y sin tocar los demás filtros.
do $mig$
declare d text; nuevo text;
begin
  d := pg_get_functiondef('public.ventas_seguimientos_tomar(integer)'::regprocedure);
  if position('between ahora - interval ''22 hours'' and ahora - interval ''3 hours''' in d) > 0 then
    raise notice '0182: el seguimiento ya llegaba a 22 horas';
    return;
  end if;
  nuevo := replace(d, 'between ahora - interval ''20 hours'' and ahora - interval ''3 hours''',
                      'between ahora - interval ''22 hours'' and ahora - interval ''3 hours''');
  if nuevo = d then raise exception '0182: no encontré el rango de 20 horas en ventas_seguimientos_tomar'; end if;
  execute nuevo;
end
$mig$;
