-- 0145 · Aviso de tiquetera por vencer (hito del 5 oct del Plan Tumbao, autorizado por Damián)
--
-- A quien tiene una tiquetera confirmada que vence en los próximos 2 a 5 días y todavía le quedan
-- clases: un aviso con cuántas le quedan, hasta cuándo, y el enlace para reservar. Una sola vez por
-- tiquetera (clave 'tiquetera_vence:<id>'). Sin bajas, sin dueños, ni domingos ni festivos (Ley 2300:
-- ese día no sale y al siguiente alcanza a salir, por eso la ventana es de 2 a 5 días, no solo 5).
-- Corre todos los días a las 9:30 am de Bogotá (14:30 UTC). Interruptor: ajustes.wa_tiquetera_vence.
-- La plantilla 'tiquetera_por_vencer' (UTILITY) está en el Worker; el dato va DENTRO de las
-- variables (Meta rechaza «código» junto a una variable).

insert into public.ajustes (clave, valor, nota) values
  ('wa_tiquetera_vence', 'encendido',
   'Aviso de tiquetera por vencer (2 a 5 días antes, si le quedan clases). Una vez por tiquetera. 0145.')
on conflict (clave) do nothing;

create or replace function public.tiquetera_por_vencer_avisos()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  hoy date := (now() at time zone 'America/Bogota')::date;
  dias text[] := array['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  meses text[] := array['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
                        'septiembre', 'octubre', 'noviembre', 'diciembre'];
  v_n int := 0;
begin
  if coalesce((select valor from ajustes where clave = 'wa_tiquetera_vence'), 'apagado') <> 'encendido' then
    return jsonb_build_object('ok', true, 'activo', false);
  end if;
  if extract(isodow from hoy) = 7 or exists (select 1 from festivos where fecha = hoy) then
    return jsonb_build_object('ok', true, 'activo', true, 'motivo', 'dia_sin_envio');
  end if;

  with c as (
    select t.id, right(regexp_replace(t.telefono, '\D', '', 'g'), 10) tel,
           initcap(split_part(btrim(t.nombre), ' ', 1)) nom,
           t.clases_totales - t.clases_usadas quedan, t.vence_el
      from tiqueteras t
     where t.estado = 'confirmada' and t.activa and t.clases_usadas < t.clases_totales
       and t.vence_el between hoy + 2 and hoy + 5
  ), enc as (
    insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
    select 'tiquetera_vence:' || c.id, 'tiquetera_vence', c.tel, 'tiquetera_por_vencer',
           jsonb_build_array(
             coalesce(nullif(c.nom, ''), 'amigo(a)'),
             c.quedan || case when c.quedan = 1 then ' clase' else ' clases' end,
             dias[extract(isodow from c.vence_el)::int] || ' ' || extract(day from c.vence_el)::int
               || ' de ' || meses[extract(month from c.vence_el)::int]),
           now() + interval '8 hours'
      from c
     where c.tel ~ '^3[0-9]{9}$'
       and not wa_es_dueno(c.tel)
       and not exists (select 1 from wa_bajas b where b.telefono = c.tel)
    on conflict (clave) do nothing
    returning 1
  )
  select count(*) into v_n from enc;

  return jsonb_build_object('ok', true, 'activo', true, 'encolados', v_n);
exception when others then
  raise warning 'tiquetera_por_vencer_avisos: %', sqlerrm;
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;
revoke all on function public.tiquetera_por_vencer_avisos() from public, anon, authenticated;

select cron.schedule('tumbao-tiquetera-vence', '30 14 * * *', 'select public.tiquetera_por_vencer_avisos()');
