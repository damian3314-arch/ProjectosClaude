-- 0164 · La gracia de 5 días se cumple completa y 6 pm / 7 pm se venden hasta 23
--
-- Damián (9 oct): «hay una regla: máximo 23 cupos de mensualidad; y si a una persona se le vence, se le espera 5
-- días y se cuenta ese cupo para no liberarlo. Revisa que se cumpla y que la página muestre los cupos
-- disponibles en todos los horarios: ya es tiempo de comenzar a vender esos cupos».
--
-- QUÉ ENCONTRÉ (9 oct, contra la base)
--   · Los cupos de la página ya cuentan la gracia que dice ajustes.mensualidad_gracia_dias (5): vigentes + hasta
--     5 días vencidas + lo apartado o pagado por la página. Ninguna función quedó con un «3 días» fijo.
--   · PERO la tabla membresias es un espejo del «Reporte de afiliados con membresía activa» de AdminGym y se
--     reemplaza entera cada mañana (importar_membresias). Ese reporte solo trae a quien venció hace 3 días o menos
--     (la foto de las 8:00 del 9 oct empieza en el 6 oct). Es decir: aunque la regla es de 5 días, a quien venció
--     hace 4 o 5 días lo borraba el siguiente reporte y su cupo se soltaba un día o dos ANTES.
--   · Hoy nadie ha cumplido los 5 días: las primeras mensualidades vencieron el 6 oct (gracia hasta el 11 oct),
--     así que los primeros cupos por gracia terminada se sueltan el lunes 12 oct. No hay cupos retenidos de más.
--   · La página vendía solo hasta el tope público: 6 pm 20 (3 libres, ocupadas 20), 7 pm 0 (cerrado). El tope
--     máximo real es 23 en 6 pm y 7 pm (premium_topes).
--
-- QUÉ CAMBIA
--   1. importar_membresias(): antes de reemplazar la tabla guarda a quien venció hace 5 días o menos (según
--      mensualidad_gracia_dias) y lo vuelve a poner si el reporte nuevo ya no lo trae y no renovó. Así cada cupo
--      se sostiene los 5 días completos, aunque AdminGym lo saque a los 3. Si renovó (el reporte trae una
--      membresía suya que termina después), no se conserva la vencida.
--   2. mensualidad_topes: 6 pm y 7 pm sube a 23 (el máximo) y 7 am queda en 35. Desde ahora la página vende todo
--      cupo libre bajo ese tope: se libera solo cuando termina la gracia de alguien y se aparta al comprar.
-- Aditivo: una función nueva, una reemplazada (mismo contrato) y un ajuste.

create or replace function public.membresia_persona(p_celular text, p_documento text, p_afiliado text)
returns text
language sql
immutable
as $$
  select coalesce(nullif(right(regexp_replace(coalesce(p_celular, ''), '\D', '', 'g'), 10), ''),
                  nullif(btrim(coalesce(p_documento, '')), ''),
                  lower(btrim(coalesce(p_afiliado, ''))))
$$;

create or replace function public.importar_membresias(p_filas jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_n        int;
  v_g        int := 0;
  v_recalc   jsonb;
  v_hoy      date := (now() at time zone 'America/Bogota')::date;
  v_gracia   int  := coalesce(nullif((select valor from ajustes where clave = 'mensualidad_gracia_dias'), '')::int, 3);
  v_vencidas jsonb;
begin
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'formato_invalido');
  end if;

  select count(*) into v_n from jsonb_array_elements(p_filas);

  -- Un archivo vacío casi siempre es un error de exportación, no que Tumbao se quedó sin afiliados. Borrar todo
  -- dejaría cupos inflados.
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'error', 'archivo_vacio',
      'mensaje', 'El archivo no trajo filas. No se toca nada.');
  end if;

  -- 0164: quien venció hace v_gracia días o menos sigue ocupando su cupo aunque el reporte ya no lo traiga.
  select coalesce(jsonb_agg(to_jsonb(m)), '[]'::jsonb) into v_vencidas
    from membresias m
   where m.fin < v_hoy and m.fin + v_gracia >= v_hoy;

  -- "where true" por la extension safeupdate de Supabase, que rechaza
  -- cualquier DELETE sin WHERE en las conexiones de PostgREST.
  delete from membresias where true;

  insert into membresias (afiliado, membresia, hora, tipo, documento,
                          celular, correo, inicio, fin)
  select f->>'afiliado',
         f->>'membresia',
         (f->>'hora')::time,
         coalesce(f->>'tipo', 'otro'),
         f->>'documento',
         f->>'celular',
         f->>'correo',
         (f->>'inicio')::date,
         (f->>'fin')::date
    from jsonb_array_elements(p_filas) f
   where f->>'hora' is not null
     and f->>'inicio' is not null
     and f->>'fin' is not null;

  get diagnostics v_n = row_count;

  -- 0164: se vuelven a poner los que siguen en gracia y no están en el reporte nuevo (ni renovaron).
  insert into membresias (afiliado, membresia, hora, tipo, documento, celular, correo, inicio, fin, importado_at)
  select r->>'afiliado', r->>'membresia', (r->>'hora')::time, r->>'tipo', r->>'documento', r->>'celular',
         r->>'correo', (r->>'inicio')::date, (r->>'fin')::date, coalesce((r->>'importado_at')::timestamptz, now())
    from jsonb_array_elements(v_vencidas) r
   where not exists (
     select 1 from membresias n
      where membresia_persona(n.celular, n.documento, n.afiliado) = membresia_persona(r->>'celular', r->>'documento', r->>'afiliado')
        and (n.fin > (r->>'fin')::date or (n.fin = (r->>'fin')::date and n.hora = (r->>'hora')::time)));

  get diagnostics v_g = row_count;

  v_recalc := recalcular_cupos();

  return jsonb_build_object('ok', true, 'membresias', v_n, 'en_gracia_conservadas', v_g, 'cupos', v_recalc);
end;
$$;
revoke execute on function public.importar_membresias(jsonb) from public, anon, authenticated;
grant  execute on function public.importar_membresias(jsonb) to service_role;

-- Tope de la página: 6 pm y 7 pm hasta 23 (el máximo), 7 am sin cambio.
update public.ajustes set valor = '07:00=35,18:00=23,19:00=23', updated_at = now() where clave = 'mensualidad_topes';
