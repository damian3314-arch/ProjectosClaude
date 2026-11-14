-- 0121 · Pase de regalo por constancia
--
-- Damián (29 sep): «si la persona compra una tiquetera y va a las 4
-- clases, le puede llegar un mensaje diciendo que se ganó un pase por su
-- constancia. Lo podemos hacer sin decir; cuando veamos reacciones lo
-- anunciamos en la página como gancho».
--
-- Cómo queda:
--   · El pase es una tiquetera de 1 clase, sin precio, con su propio código.
--     Así se reserva por el mismo camino de siempre («Tengo tiquetera»): no
--     hay nada nuevo que aprender ni que cambiar en la página.
--   · Se gana al ASISTIR a todas las clases de la tiquetera (lo marca
--     recepción en la puerta), no al reservarlas: la constancia es ir.
--   · Lo otorga `pases_por_constancia()` una vez al día (10:30 am, lunes a
--     sábado, sin festivos), no un disparador sobre asistencias: la lista
--     de la puerta es lo más delicado del panel y no se toca. Además el
--     mensaje sale en horario de campaña (Ley 2300) y a la mañana
--     siguiente, con el pase ya creado.
--   · Uno por tiquetera (índice único) y el pase no gana otro pase.
--   · Nace APAGADO (ajustes.wa_pase_constancia): se enciende cuando Meta
--     apruebe la plantilla 'pase_constancia', igual que las demás.
--   · A Damián le llega una nota por WhatsApp cada vez que alguien lo gana.
--   · Quien pidió no recibir mensajes (SALIR) recibe el pase igual, sin
--     mensaje; la nota a Damián lo dice para que se lo cuenten en persona.

-- ── 1. el pase sabe de cuál tiquetera salió ─────────────────────────
alter table public.tiqueteras
  add column if not exists premio_de bigint references public.tiqueteras(id);

create unique index if not exists tiqueteras_un_pase_por_tiquetera
  on public.tiqueteras (premio_de) where premio_de is not null;

insert into ajustes (clave, valor, nota)
values ('wa_pase_constancia', 'apagado',
        'Pase de regalo al completar una tiquetera. Se enciende cuando Meta apruebe la plantilla pase_constancia (0121).')
on conflict (clave) do nothing;

-- ── 2. el pase NO manda el mensaje de «tu tiquetera quedó activa» ───
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.wa_encolar_tiquetera()'::regprocedure) into v_src;
  if position('premio_de' in v_src) > 0 then return; end if;
  v_new := replace(v_src,
    'if new.estado <> ''confirmada'' then return new; end if;',
    'if new.estado <> ''confirmada'' or new.premio_de is not null then return new; end if;');
  if v_new = v_src then raise exception '0121: wa_encolar_tiquetera no cambió'; end if;
  execute v_new;
end
$mig$;

-- ── 3. la lista del panel dice cuál es pase ─────────────────────────
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.admin_tiqueteras_listar(text,text)'::regprocedure) into v_src;
  if position('premio_de' in v_src) > 0 then return; end if;
  v_new := replace(v_src,
    '''referencia'', t.referencia',
    '''referencia'', t.referencia, ''premio'', t.premio_de is not null');
  if v_new = v_src then raise exception '0121: admin_tiqueteras_listar no cambió'; end if;
  execute v_new;
end
$mig$;

-- ── 4. la puerta dice que es un pase (no hay que cobrar nada) ───────
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.admin_lista_clase(text,uuid)'::regprocedure) into v_src;
  if position('premio_de' in v_src) > 0 then return; end if;
  v_new := replace(v_src,
    '''vence_el'', t.vence_el) from tiqueteras t where t.id = r.tiquetera_id',
    '''vence_el'', t.vence_el, ''premio'', t.premio_de is not null) from tiqueteras t where t.id = r.tiquetera_id');
  if v_new = v_src then raise exception '0121: admin_lista_clase no cambió'; end if;
  execute v_new;
end
$mig$;

-- ── 5. el tablero no cuenta el pase como una tiquetera vendida ──────
-- 'vigentes_con_clases' y 'vencen_en_5_dias_con_clases' salían de contar
-- todas las tiqueteras confirmadas; con el pase inflarían el dato. Y se
-- suma cuántos pases se han regalado este mes, para el informe.
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.tablero_tumbao(text)'::regprocedure) into v_src;
  if position('premio_de' in v_src) > 0 then return; end if;
  v_new := replace(v_src,
    'from tiqueteras where estado = ''confirmada''',
    'from tiqueteras where premio_de is null and estado = ''confirmada''');
  v_new := replace(v_new,
    '''vigentes_con_clases'', (select count(*)',
    '''pases_regalados_mes'', (select count(*) from tiqueteras where premio_de is not null'
    || ' and (creada_en at time zone ''America/Bogota'')::date >= date_trunc(''month'', (now() at time zone ''America/Bogota'')::date)::date),'
    || E'\n    ''vigentes_con_clases'', (select count(*)');
  if v_new = v_src or position('pases_regalados_mes' in v_new) = 0
     or position('premio_de is null and estado' in v_new) = 0 then
    raise exception '0121: tablero_tumbao no cambió como se esperaba';
  end if;
  execute v_new;
end
$mig$;

-- ── 6. quien otorga los pases ───────────────────────────────────────
create or replace function public.pases_por_constancia()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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
  v_lineas text[] := '{}';
begin
  if coalesce((select valor from ajustes where clave = 'wa_pase_constancia'), 'apagado')
     <> 'encendido' then
    return 0;
  end if;
  -- Ley 2300: nada de mensajes de mercadeo domingos ni festivos.
  if extract(isodow from hoy) = 7 or exists (select 1 from festivos where fecha = hoy) then
    return 0;
  end if;

  for r in
    select t.id, t.nombre, t.telefono, t.clases_totales
      from tiqueteras t
     where t.estado = 'confirmada'
       and t.premio_de is null
       and not exists (select 1 from tiqueteras p where p.premio_de = t.id)
       -- Fue a TODAS sus clases: asistencias marcadas en la puerta, no
       -- reservas.
       and (select count(distinct a.reserva_id)
              from asistencias a join reservas x on x.id = a.reserva_id
             where x.tiquetera_id = t.id) >= t.clases_totales
       -- Y la última fue reciente: si el reloj estuvo apagado semanas, no
       -- se regala un pase a destiempo.
       and (select max((c.fecha_hora at time zone 'America/Bogota')::date)
              from asistencias a join reservas x on x.id = a.reserva_id
              join clases c on c.id = a.clase_id
             where x.tiquetera_id = t.id) >= hoy - 14
     order by t.id
  loop
    begin
      v_tel := right(regexp_replace(coalesce(r.telefono, ''), '\D', '', 'g'), 10);
      v_nom := coalesce(nullif(initcap(split_part(btrim(r.nombre), ' ', 1)), ''), 'amigo(a)');

      -- Un código que no choque con ninguna tiquetera.
      loop
        v_cod := generar_codigo_reserva();
        exit when not exists (select 1 from tiqueteras where codigo = v_cod);
      end loop;

      insert into tiqueteras (codigo, nombre, telefono, clases_totales, clases_usadas,
                              precio_cop, vence_el, activa, estado, nota, premio_de)
      values (v_cod, r.nombre, r.telefono, 1, 0, 0, v_vence, true, 'confirmada',
              'Pase de regalo por constancia (completó la tiquetera ' || r.id || ')', r.id)
      on conflict (premio_de) where premio_de is not null do nothing
      returning id into v_id;
      if v_id is null then continue; end if;
      n := n + 1;

      v_baja := v_tel !~ '^3[0-9]{9}$'
                or exists (select 1 from wa_bajas b where b.telefono = v_tel);

      if not v_baja then
        insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
        values ('pase_constancia:' || v_id, 'pase_constancia', v_tel, 'pase_constancia',
                jsonb_build_array(v_nom, r.clases_totales::text, 'Código: ' || v_cod,
                                  wa_fecha_texto(v_vence)),
                now() + interval '3 days')
        on conflict (clave) do nothing;
      end if;

      v_lineas := v_lineas || (initcap(btrim(r.nombre)) || ' completó sus ' || r.clases_totales
                               || ' clases' || case when v_baja
                                 then ' (pidió no recibir mensajes: cuéntale tú que ganó su pase, código ' || v_cod || ')'
                                 else ' y ya le llegó su pase' end);
    exception when others then
      -- Un pase que falla no frena a los demás.
      raise warning 'pases_por_constancia (tiquetera %): %', r.id, sqlerrm;
    end;
  end loop;

  if n > 0 then
    perform nota_asistente(
      '🎁 Pase por constancia',
      array_to_string(v_lineas, E'\n') || E'\nEs el regalo silencioso: mira cómo reaccionan antes de anunciarlo.',
      'pases:' || hoy);
  end if;
  return n;
exception when others then
  raise warning 'pases_por_constancia: %', sqlerrm;
  return n;
end;
$$;
revoke all on function public.pases_por_constancia() from public, anon, authenticated;

-- 10:30 am de Bogotá (15:30 UTC), lunes a sábado. Media hora después de
-- las invitaciones de opinión, para no juntar los dos avisos.
do $cron$
begin
  perform cron.unschedule('tumbao-pases-constancia');
exception when others then null;
end
$cron$;
select cron.schedule('tumbao-pases-constancia', '30 15 * * 1-6',
                     'select public.pases_por_constancia()');
