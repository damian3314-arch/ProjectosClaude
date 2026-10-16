-- 0180 · Se pausa la fidelidad en los cupos de mensualidad de 6 y 7 pm
--
-- 14 oct, Damián: «las mensualidades están caídas, necesitamos nuevos clientes: esa de dar los puestos por fidelidad
-- se puede pausar. Lo único que se necesita es guardar 5 días el cupo a la gente que se vence y luego ya se vende al
-- que compre. Y que la página de mensualidad dé el QR y que la gente pague».
--
-- LO QUE YA ERA ASÍ (y se queda): la gracia. mensualidad_cupos() cuenta como ocupado el plan hasta fin + 5 días
-- (ajustes.mensualidad_gracia_dias = 5): ese cupo está guardado para quien se vence. Al sexto día queda libre y lo compra
-- quien llegue primero. La página, apenas hay un cupo libre, abre el pago con el QR (0074/0133).
--
-- LO QUE SE PAUSA, con un solo interruptor:  ajustes.premium_fidelidad = 'pausada'  (cualquier otro valor = activa)
--   · premium_puede_pagar(): ya no deja pagar por encima del cupo a quien cumple la fidelidad.
--   · mensualidad_fila(): nadie «aplica» y la fila de espera pasa a orden de llegada (no por antigüedad). Con eso
--     mensualidad_cupos() ya no aparta cupos para la fila (reservadas_lista = 0): todo cupo libre se vende.
--   · mensualidad_avisar_lista_espera(): avisa por orden de llegada, mide el cupo con lo que muestra la página y ya
--     no exige cumplir la fidelidad. El cupo no queda apartado: lo gana quien pague primero.
--   · Timba (el bot de ventas): ventas_cupos(), ventas_candidatos() y ventas_perfil() ofrecen la mensualidad de 6 pm y
--     de 7 pm a cualquiera que baile a esa hora y haya cupo, sin mirar la fidelidad; aparece el objetivo
--     «mensualidad_7pm». Con la fidelidad activa, todo se comporta como antes.
-- Para volver atrás:  update ajustes set valor = 'activa' where clave = 'premium_fidelidad';

insert into public.ajustes (clave, valor, nota)
values ('premium_fidelidad', 'pausada',
        'Fidelidad de los cupos de 6 y 7 pm: «pausada» = todo cupo libre se vende a quien pague primero (0180, pedido de Damián el 14-oct). Cualquier otro valor la reactiva.')
on conflict (clave) do update set valor = excluded.valor, nota = excluded.nota, updated_at = now();

create or replace function public.premium_pausado()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((select valor from ajustes where clave = 'premium_fidelidad'), 'activa') = 'pausada'
$$;

do $mig$
declare
  d text;
  nuevo text;
begin
  -- 1 · la página: nadie paga por encima del cupo por fidelidad
  d := pg_get_functiondef('public.premium_puede_pagar(text,text,time without time zone)'::regprocedure);
  if position('premium_pausado' in d) > 0 then
    raise notice '0180: premium_puede_pagar ya estaba pausable';
  else
    nuevo := replace(d,
$a$begin
  if v_hasta is not null and v_hasta < (now() at time zone 'America/Bogota')::date then return false; end if;
$a$,
$b$begin
  if premium_pausado() then return false; end if;
  if v_hasta is not null and v_hasta < (now() at time zone 'America/Bogota')::date then return false; end if;
$b$);
    if nuevo = d then raise exception '0180: no encontré el ancla en premium_puede_pagar'; end if;
    execute nuevo;
  end if;

  -- 2 · la fila de espera: nadie aplica y va por orden de llegada
  d := pg_get_functiondef('public.mensualidad_fila(time without time zone)'::regprocedure);
  if position('premium_pausado' in d) > 0 then
    raise notice '0180: mensualidad_fila ya estaba pausable';
  else
    nuevo := d;
    nuevo := replace(nuevo,
      $a$coalesce((p ->> 'veredicto') = 'aplica', false) as ap,$a$,
      $b$(coalesce((p ->> 'veredicto') = 'aplica', false) and not premium_pausado()) as ap,$b$);
    nuevo := replace(nuevo,
      $a$coalesce((p ->> 'meses_seguidos_pagando_plan')::int, 0) as r,$a$,
      $b$case when premium_pausado() then 0 else coalesce((p ->> 'meses_seguidos_pagando_plan')::int, 0) end as r,$b$);
    nuevo := replace(nuevo,
      $a$coalesce((p ->> 'meses_con_plan_en_total')::int, 0) as m,$a$,
      $b$case when premium_pausado() then 0 else coalesce((p ->> 'meses_con_plan_en_total')::int, 0) end as m,$b$);
    nuevo := replace(nuevo,
      $a$coalesce((p -> 'clases_sueltas' ->> 'visitas')::int, 0) as v$a$,
      $b$case when premium_pausado() then 0 else coalesce((p -> 'clases_sueltas' ->> 'visitas')::int, 0) end as v$b$);
    if (length(nuevo) - length(replace(nuevo, 'premium_pausado', ''))) / length('premium_pausado') <> 4 then
      raise exception '0180: no encontré los cuatro puntos de mensualidad_fila';
    end if;
    execute nuevo;
  end if;

  -- 3 · el aviso a la lista de espera: por orden de llegada, con el cupo que muestra la página
  d := pg_get_functiondef('public.mensualidad_avisar_lista_espera()'::regprocedure);
  if position('premium_pausado' in d) > 0 then
    raise notice '0180: mensualidad_avisar_lista_espera ya estaba pausable';
  else
    nuevo := d;
    nuevo := replace(nuevo,
      $a$v_libres := coalesce(v_tope, 0) - coalesce(v_ocup, 0);$a$,
      $b$v_libres := case when premium_pausado()
                       then coalesce((select (h ->> 'libres')::int from jsonb_array_elements(mensualidad_cupos() -> 'horas') h where h ->> 'hora' = v_hora), 0)
                       else coalesce(v_tope, 0) - coalesce(v_ocup, 0) end;$b$);
    nuevo := replace(nuevo,
      $a$from mensualidad_fila(v_hora::time) f where f.aplica order by f.orden loop$a$,
      $b$from mensualidad_fila(v_hora::time) f where (f.aplica or premium_pausado()) order by f.orden loop$b$);
    nuevo := replace(nuevo,
      $a$continue when not coalesce(premium_puede_pagar(r.celular, null, v_hora::time), false);$a$,
      $b$continue when not premium_pausado() and not coalesce(premium_puede_pagar(r.celular, null, v_hora::time), false);$b$);
    nuevo := replace(nuevo,
      $a$values (v_tel, v_nombre, 'mensualidad_6pm', jsonb_build_object('origen', 'lista_espera', 'hora', v_hora));$a$,
      $b$values (v_tel, v_nombre, case when v_hora = '19:00' and premium_pausado() then 'mensualidad_7pm' else 'mensualidad_6pm' end,
                 jsonb_build_object('origen', 'lista_espera', 'hora', v_hora));$b$);
    nuevo := replace(nuevo,
      $a$update ventas_chats set objetivo = 'mensualidad_6pm', estado = 'abierta',$a$,
      $b$update ventas_chats set objetivo = case when v_hora = '19:00' and premium_pausado() then 'mensualidad_7pm' else 'mensualidad_6pm' end, estado = 'abierta',$b$);
    nuevo := replace(nuevo,
      $a$' y, como estabas en la lista de espera, eres la primera persona a quien se lo ofrecemos 🧡'$a$,
      $b$case when premium_pausado() then ' y, como estabas en la lista de espera, te avisamos primero 🧡'
                     else ' y, como estabas en la lista de espera, eres la primera persona a quien se lo ofrecemos 🧡' end$b$);
    if (length(nuevo) - length(replace(nuevo, 'premium_pausado', ''))) / length('premium_pausado') <> 6 then
      raise exception '0180: no encontré los seis puntos de mensualidad_avisar_lista_espera';
    end if;
    execute nuevo;
  end if;

  -- 4 · Timba: el perfil dice que aplica a quien tenga cupo en su horario y arma la lista de espera con los cupos de la página
  d := pg_get_functiondef('public.ventas_perfil(text)'::regprocedure);
  if position('premium_pausado' in d) > 0 then
    raise notice '0180: ventas_perfil ya estaba pausable';
  else
    nuevo := d;
    nuevo := replace(nuevo,
      $a$'aplica_mensualidad', coalesce(per ->> 'veredicto', 'sin_historial') = 'aplica',$a$,
      $b$'aplica_mensualidad', coalesce(per ->> 'veredicto', 'sin_historial') = 'aplica' or premium_pausado(),$b$);
    nuevo := replace(nuevo,
      $a$'libres', coalesce((premium_cupos_horario() -> (c.oferta ->> 'hora') ->> 'libres')::int, 0),$a$,
      $b$'libres', case when premium_pausado() then coalesce((ventas_cupos() ->> (c.oferta ->> 'hora'))::int, 0)
                        else coalesce((premium_cupos_horario() -> (c.oferta ->> 'hora') ->> 'libres')::int, 0) end,$b$);
    nuevo := replace(nuevo,
      $a$'puede_pagar', coalesce(premium_puede_pagar(t, null, (c.oferta ->> 'hora')::time), false))$a$,
      $b$'puede_pagar', case when premium_pausado() then coalesce((ventas_cupos() ->> (c.oferta ->> 'hora'))::int, 0) > 0
                             else coalesce(premium_puede_pagar(t, null, (c.oferta ->> 'hora')::time), false) end)$b$);
    if (length(nuevo) - length(replace(nuevo, 'premium_pausado', ''))) / length('premium_pausado') <> 3 then
      raise exception '0180: no encontré los tres puntos de ventas_perfil';
    end if;
    execute nuevo;
  end if;

  -- 5 · Timba: el gancho de la mensualidad de 7 pm
  d := pg_get_functiondef('public.ventas_gancho(text,integer)'::regprocedure);
  if position('mensualidad_7pm' in d) > 0 then
    raise notice '0180: ventas_gancho ya tenía mensualidad_7pm';
  else
    nuevo := replace(d,
      $a$when 'mensualidad_7am' then$a$,
      $b$when 'mensualidad_7pm' then 'Hay cupo de mensualidad en el horario de 7 pm y pensé en ti por lo constante que has sido 🧡'
    when 'mensualidad_7am' then$b$);
    if nuevo = d then raise exception '0180: no encontré el ancla en ventas_gancho'; end if;
    execute nuevo;
  end if;
end
$mig$;

-- 6 · Timba: los cupos de 6 y 7 pm salen de lo que muestra la página cuando la fidelidad está pausada
create or replace function public.ventas_cupos()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  with c as (
    select h ->> 'hora' as hora, (h ->> 'libres')::int as libres
      from jsonb_array_elements(mensualidad_cupos() -> 'horas') h)
  select jsonb_build_object(
    '07:00', coalesce((select libres from c where hora = '07:00'), 0),
    -- 6 pm: con la fidelidad activa, lo que se vende por la página (el resto lo maneja el equipo por dentro)
    '18:00', case when premium_pausado() then coalesce((select libres from c where hora = '18:00'), 0)
                  else least(coalesce((premium_cupos_horario() -> '18:00' ->> 'libres')::int, 0),
                             coalesce((select libres from c where hora = '18:00'), 0)) end,
    '19:00', case when premium_pausado() then coalesce((select libres from c where hora = '19:00'), 0)
                  else coalesce((premium_cupos_horario() -> '19:00' ->> 'libres')::int, 0) end)
$function$;

-- 7 · Timba: quién recibe la invitación a la mensualidad de 6 y de 7 pm
create or replace function public.ventas_candidatos(p_limite integer default 50)
returns table(tel text, nombre text, objetivo text, visitas_30d integer, hora_habitual text, prioridad integer)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  hoy date := (now() at time zone 'America/Bogota')::date;
  cupos jsonb := ventas_cupos();
  pausada boolean := premium_pausado();
  v_l7 int; v_l6 int; v_l19 int;
begin
  v_l7 := greatest((cupos ->> '07:00')::int
            - (select count(*) from ventas_chats c where c.objetivo = 'mensualidad_7am' and c.abierta_at > now() - interval '7 days' and c.estado <> 'cerrada'), 0);
  v_l6 := greatest((cupos ->> '18:00')::int
            - (select count(*) from ventas_chats c where c.objetivo = 'mensualidad_6pm' and c.abierta_at > now() - interval '7 days' and c.estado <> 'cerrada'), 0);
  v_l19 := greatest((cupos ->> '19:00')::int
            - (select count(*) from ventas_chats c where c.objetivo = 'mensualidad_7pm' and c.abierta_at > now() - interval '7 days' and c.estado <> 'cerrada'), 0);

  return query
  with vig as (
    select distinct right(regexp_replace(coalesce(celular, ''), '\D', '', 'g'), 10) t
      from membresias where fin + coalesce(nullif((select valor from ajustes where clave = 'mensualidad_gracia_dias'), '')::int, 3) >= hoy),
  tq as (
    select distinct right(regexp_replace(telefono, '\D', '', 'g'), 10) t
      from tiqueteras
     where pagado_en is not null and vence_el >= hoy and clases_usadas < clases_totales),
  r as (
    select right(regexp_replace(x.telefono, '\D', '', 'g'), 10) t,
           (array_agg(initcap(split_part(btrim(x.nombre), ' ', 1)) order by x.created_at desc))[1] n,
           count(*) filter (where x.tipo = 'suelta' and c.fecha_hora >= now() - interval '30 days') v30,
           max(c.fecha_hora) ultima,
           mode() within group (order by to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'))
             filter (where c.fecha_hora >= now() - interval '60 days') hh
      from reservas x join clases c on c.id = x.clase_id
     where x.estado = 'confirmada' and c.fecha_hora < now()
     group by 1),
  base as (
    select r.* from r
     where r.t ~ '^3[0-9]{9}$'
       and r.t not in (select t from vig) and r.t not in (select t from tq)
       and not wa_es_dueno(r.t)
       and not exists (select 1 from wa_bajas b where b.telefono = r.t)
       and not exists (select 1 from wa_avisos a where a.telefono = r.t and a.tipo = 'campana'
                         and a.estado in ('enviando', 'enviado', 'pendiente') and a.creado_at > now() - interval '5 days')
       and (select count(*) from wa_avisos a where a.telefono = r.t and a.tipo = 'campana'
              and a.estado in ('enviando', 'enviado', 'pendiente') and a.creado_at > now() - interval '14 days') < 2
       and not exists (select 1 from ventas_chats c where c.telefono = r.t and c.abierta_at > now() - interval '14 days')
       and not exists (select 1 from ventas_chats c where c.telefono = r.t and c.resultado = 'no_interesado'
                         and c.cerrada_at > now() - interval '45 days')
       and not exists (select 1 from wa_opiniones o where o.telefono = r.t and o.estado <> 'cerrada' and o.invitada_at > now() - interval '72 hours')),
  clas as (
    select b.*,
           case
             when b.hh = '18:00' and v_l6 > 0
                  and (pausada or (premium_evaluar(b.t) -> 'personas' -> 0 ->> 'veredicto') = 'aplica') then 'mensualidad_6pm'
             when b.hh = '19:00' and v_l19 > 0 and pausada and b.v30 >= 1 then 'mensualidad_7pm'
             when b.hh = '07:00' and v_l7 > 0 and b.v30 >= 1 then 'mensualidad_7am'
             when b.v30 >= 2 then 'tiquetera'
             when b.ultima < now() - interval '30 days' and b.ultima >= now() - interval '90 days' then 'reactivar'
           end obj
      from base b),
  orden as (
    select c.*,
           row_number() over (partition by c.obj order by c.v30 desc, c.ultima desc) rn
      from clas c where c.obj is not null)
  select o.t, coalesce(nullif(o.n, ''), 'amigo(a)'), o.obj, o.v30::int, o.hh,
         case o.obj when 'mensualidad_6pm' then 1 when 'mensualidad_7pm' then 1 when 'mensualidad_7am' then 2 when 'tiquetera' then 3 else 4 end
    from orden o
   where (o.obj = 'mensualidad_6pm' and o.rn <= v_l6)
      or (o.obj = 'mensualidad_7pm' and o.rn <= v_l19)
      or (o.obj = 'mensualidad_7am' and o.rn <= v_l7)
      or o.obj in ('tiquetera', 'reactivar')
   order by 6, o.v30 desc, o.ultima desc
   limit greatest(p_limite, 0);
end;
$function$;
