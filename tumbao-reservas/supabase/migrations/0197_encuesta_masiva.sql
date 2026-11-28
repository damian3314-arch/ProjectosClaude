-- 0197 · Encuesta masiva a toda la base (2 nov, Damián). Aplicada en vivo.
-- Timba le escribe a toda la base (plantilla encuesta_tumbao, marketing ≈ $46) con un botón a «Tumbao opina» (opina.tumbaobaila.com): chat anónimo de
-- 5 preguntas, contacto opcional al final. Con p_ejecutar = false solo cuenta; con true deja los avisos en la cola y el despachador los reparte
-- dentro del horario de mercadeo y del tope diario. Nunca a quien pidió no recibir mensajes, a las dueñas, a quien tuvo una campaña en 2 días ni a
-- quien ya la recibió. Se corre SOLO cuando Meta aprueba la plantilla.
create or replace function public.campana_encuesta(p_ejecutar boolean default false)
returns jsonb language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $f$
declare v_tot int; v_enc int := 0;
begin
  with todos as (
    select right(regexp_replace(coalesce(r.telefono,''),'\D','','g'),10) t, max(r.created_at) ult, mode() within group (order by initcap(split_part(btrim(r.nombre),' ',1))) n
      from reservas r where r.telefono is not null group by 1
    union all select right(regexp_replace(coalesce(m.celular,''),'\D','','g'),10), null::timestamptz, null::text from membresias m where m.celular is not null
    union all select right(regexp_replace(coalesce(q.telefono,''),'\D','','g'),10), null::timestamptz, null::text from tiqueteras q where q.telefono is not null
    union all select distinct right(regexp_replace(coalesce(w.telefono,''),'\D','','g'),10), null::timestamptz, null::text from wa_mensajes w where w.direccion='entrante' and w.telefono is not null),
  uno as (select t, (array_remove(array_agg(n order by ult desc nulls last), null))[1] n from todos group by t),
  cand as (
    select u.t, coalesce(nullif(u.n,''),'amigo(a)') n from uno u
     where u.t ~ '^3[0-9]{9}$'
       and not wa_es_dueno(u.t)
       and not exists (select 1 from wa_bajas x where right(x.telefono,10)=u.t)
       and not exists (select 1 from wa_avisos a where right(a.telefono,10)=u.t and a.tipo='campana' and a.creado_at > now()-interval '2 days')
       and not exists (select 1 from wa_avisos a where right(a.telefono,10)=u.t and a.plantilla='encuesta_tumbao')),
  ins as (
    insert into wa_avisos (clave,tipo,telefono,plantilla,variables,vence_at)
    select 'encuesta-nov:'||t,'campana',t,'encuesta_tumbao',jsonb_build_array(n),now()+interval '7 days' from cand where p_ejecutar
    on conflict (clave) do nothing returning 1)
  select (select count(*) from cand), (select count(*) from ins) into v_tot, v_enc;
  return jsonb_build_object('ejecutado',p_ejecutar,'candidatos',v_tot,'encolados',v_enc,'costo_aprox_cop',v_tot*46);
end $f$;
revoke all on function public.campana_encuesta(boolean) from public, anon, authenticated;
