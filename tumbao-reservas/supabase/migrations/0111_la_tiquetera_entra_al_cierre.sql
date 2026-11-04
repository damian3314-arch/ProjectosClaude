-- 0111 · La tiquetera entra al cierre del día, y la puerta dice de
--        cuál tiquetera salió cada cupo.
--
-- LO QUE PIDIÓ DAMIÁN (28 sep)
-- «Organizar el cierre incluyendo el ingreso que tenemos por pago de
--  tiquetera. Cuando un cliente reserva su clase y va, es cuando se usa
--  la tiquetera. Tener visibilidad de que la gente compró una tiquetera,
--  que en el cierre del día sea visible que compró y pagó su tiquetera,
--  y en el listado de validar cada ingreso, que se liste que el cupo se
--  descontó de la tiquetera que tiene.»
--
-- EL PROBLEMA
-- La tiquetera no existía para la caja. Vendida en recepción, creaba el
-- código pero la plata no quedaba en ningún lado: el efectivo sobraba al
-- contar, o la transferencia quedaba "sin cruzar". Comprada en línea, el
-- depósito se consumía y la venta no aparecía en el cierre.
--
-- LA DECISIÓN: la tiquetera es un ingreso de caja más, concepto
-- 'tiquetera'. Así entra sola —sin fórmulas nuevas— a todo lo que ya
-- lee caja_movimientos: la tirilla (hoja 1, por concepto y medio), el
-- punteo del banco (hoja 2), el arqueo del efectivo, el cruce con el
-- banco del informe y ventas_entre. La plata cuenta el día que se PAGA;
-- cuando la persona usa sus clases no se cobra nada (ya estaba pagada).
--
--   · Recepción: admin_tiquetera_vender() crea la tiquetera Y registra el
--     cobro (efectivo o transferencia, con su depósito si lo escogen) en
--     una sola transacción: o quedan las dos cosas o ninguna.
--   · Página: cuando el banco confirma el pago (estado → 'confirmada'),
--     un disparador registra el ingreso con su depósito. Si el día ya se
--     cerró, entra al día siguiente, igual que cualquier movimiento.
--   · caja_movimientos.tiquetera_id amarra cada cobro con su tiquetera
--     (y un índice único impide cobrarla dos veces).
--   · La puerta (admin_lista_clase) y el cierre (caja_del_dia) dicen de
--     qué tiquetera salió cada cupo: «clase 2 de 4».
--   · tablero_tumbao: las tiqueteras vendidas salen de la caja, no de
--     pagado_en (que se llena cuando el cliente REPORTA el pago, aunque
--     el banco no lo haya confirmado).

-- ── 1. el amarre ─────────────────────────────────────────────────────
alter table public.caja_movimientos
  add column if not exists tiquetera_id bigint references public.tiqueteras(id);

create unique index if not exists caja_mov_una_por_tiquetera
  on public.caja_movimientos (tiquetera_id)
  where tiquetera_id is not null and not anulado;

-- ── 2. vender en recepción: tiquetera + cobro, juntos ────────────────
create or replace function public.admin_tiquetera_vender(
  p_token text, p_nombre text, p_telefono text, p_clases integer,
  p_vigencia_dias integer, p_precio_cop integer, p_medio text,
  p_pago_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_t   jsonb;
  v_c   jsonb;
  v_dia date := (now() at time zone 'America/Bogota')::date;
begin
  if verificar_token_admin(p_token) is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if p_precio_cop is null or p_precio_cop <= 0 then
    return jsonb_build_object('ok', false, 'error', 'PRECIO_REQUERIDO',
      'mensaje', 'Escribe cuánto pagó: la tiquetera entra al cierre del día como ingreso.');
  end if;
  if p_medio is null or p_medio not in ('efectivo', 'transferencia') then
    return jsonb_build_object('ok', false, 'error', 'MEDIO_INVALIDO',
      'mensaje', 'Escoge si pagó en efectivo o por transferencia.');
  end if;
  if exists (select 1 from caja_cierres where dia = v_dia) then
    return jsonb_build_object('ok', false, 'error', 'DIA_CERRADO',
      'mensaje', 'El día ya está cerrado. Véndela mañana, para que entre al cierre de ese día.');
  end if;

  begin
    v_t := admin_tiquetera_crear(p_token, p_nombre, p_telefono, p_clases,
                                 p_vigencia_dias, p_precio_cop);
    if not coalesce((v_t->>'ok')::boolean, false) then
      return v_t;
    end if;

    v_c := caja_registrar(p_token, 'ingreso', 'tiquetera', p_precio_cop, p_medio,
             'Tiquetera ' || (v_t->>'codigo') || ' · ' || (v_t->>'nombre'),
             p_pago_id, 1, 'caja_menor');
    if not coalesce((v_c->>'ok')::boolean, false) then
      -- Sin cobro no hay tiquetera: se deshace la creación.
      raise exception using errcode = 'P0111', message = v_c::text;
    end if;

    update caja_movimientos set tiquetera_id = (v_t->>'id')::bigint
     where id = (v_c->>'id')::uuid;
    update tiqueteras
       set pagado_en = now(), pago_id = p_pago_id, estado = 'confirmada'
     where id = (v_t->>'id')::bigint;
  exception when sqlstate 'P0111' then
    return sqlerrm::jsonb;
  end;

  return v_t || jsonb_build_object('movimiento_id', v_c->>'id',
                                   'medio', p_medio, 'precio_cop', p_precio_cop);
end;
$$;
revoke all on function public.admin_tiquetera_vender(text, text, text, integer, integer, integer, text, uuid)
  from public, anon, authenticated;

-- ── 3. comprada en la página: el ingreso nace cuando el banco confirma ─
create or replace function public.tiquetera_ingreso_en_linea()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_dia date := (now() at time zone 'America/Bogota')::date;
begin
  if new.estado = 'confirmada' and coalesce(old.estado, '') <> 'confirmada'
     and new.creada_por is null
     and coalesce(new.precio_cop, 0) > 0
     and not exists (select 1 from caja_movimientos m
                      where m.tiquetera_id = new.id and not m.anulado) then
    if exists (select 1 from caja_cierres where dia = v_dia) then
      v_dia := v_dia + 1;
    end if;
    insert into caja_movimientos (dia, sentido, concepto, valor_cop, medio, nota,
                                  registrado_por, pago_id, cantidad, origen, tiquetera_id)
    values (v_dia, 'ingreso', 'tiquetera', new.precio_cop, 'transferencia',
            'Tiquetera ' || new.codigo || ' · ' || new.nombre || ' · comprada en la página',
            null, new.pago_id, 1, 'caja_menor', new.id);
  end if;
  return new;
end;
$$;
revoke all on function public.tiquetera_ingreso_en_linea() from public, anon, authenticated;

drop trigger if exists tiquetera_ingreso_en_linea on public.tiqueteras;
create trigger tiquetera_ingreso_en_linea
  after update of estado on public.tiqueteras
  for each row execute function public.tiquetera_ingreso_en_linea();

-- ── 4. la puerta dice de cuál tiquetera salió el cupo ─────────────────
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.admin_lista_clase(text,uuid)'::regprocedure) into v_src;
  if position('''tiquetera'', case' in v_src) > 0 then return; end if;
  v_new := replace(v_src, '''tipo'',       r.tipo,',
    '''tipo'',       r.tipo,' || E'\n' ||
    '      ''tiquetera'', case when r.tiquetera_id is null then null else (' ||
    'select jsonb_build_object(''codigo'', t.codigo, ' ||
    '''clase_n'', (select count(*) from reservas x where x.tiquetera_id = t.id ' ||
    'and x.estado = ''confirmada'' and x.created_at <= r.created_at), ' ||
    '''total'', t.clases_totales, ''quedan'', t.clases_totales - t.clases_usadas, ' ||
    '''vence_el'', t.vence_el) from tiqueteras t where t.id = r.tiquetera_id) end,');
  if v_new = v_src then raise exception '0111: no encontré dónde poner la tiquetera en la puerta'; end if;
  execute v_new;
end
$mig$;

-- ── 5. el cierre: tiqueteras vendidas y clases tomadas con tiquetera ──
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.caja_del_dia(text,date)'::regprocedure) into v_src;
  if position('''tiqueteras_usadas''' in v_src) > 0 then return; end if;
  v_new := replace(v_src, '''cuadre'', v_cuadre,',
    '-- 0111: lo que se vendió de tiquetera hoy (ya está en los conceptos)' || E'\n' ||
    '    -- y las clases que se tomaron con tiquetera (no mueven plata hoy).' || E'\n' ||
    '    ''tiqueteras_vendidas'', coalesce((select jsonb_agg(jsonb_build_object(' ||
    '''nombre'', t.nombre, ''codigo'', t.codigo, ''clases'', t.clases_totales, ' ||
    '''valor_cop'', m.valor_cop, ''medio'', m.medio, ''en_linea'', t.creada_por is null, ' ||
    '''hora'', to_char(m.created_at at time zone ''America/Bogota'', ''HH24:MI'')) order by m.created_at) ' ||
    'from caja_movimientos m join tiqueteras t on t.id = m.tiquetera_id ' ||
    'where m.dia = v_dia and not m.anulado), ''[]''::jsonb),' || E'\n' ||
    '    ''tiqueteras_usadas'', coalesce((select jsonb_agg(jsonb_build_object(' ||
    '''nombre'', r.nombre, ''codigo'', t.codigo, ' ||
    '''hora'', to_char(c.fecha_hora at time zone ''America/Bogota'', ''HH24:MI''), ' ||
    '''clase_n'', (select count(*) from reservas x where x.tiquetera_id = t.id ' ||
    'and x.estado = ''confirmada'' and x.created_at <= r.created_at), ' ||
    '''total'', t.clases_totales, ' ||
    '''asistio'', exists (select 1 from asistencias a where a.reserva_id = r.id)) ' ||
    'order by c.fecha_hora, r.nombre) ' ||
    'from reservas r join clases c on c.id = r.clase_id join tiqueteras t on t.id = r.tiquetera_id ' ||
    'where r.estado = ''confirmada'' ' ||
    'and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia), ''[]''::jsonb),' || E'\n' ||
    '    ''cuadre'', v_cuadre,');
  if v_new = v_src then raise exception '0111: no encontré dónde poner la tiquetera en el cierre'; end if;
  execute v_new;
end
$mig$;

-- ── 6. ventas_entre dice cuánto fue de tiquetera ──────────────────────
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.ventas_entre(date,date)'::regprocedure) into v_src;
  if position('tiqueteras_cop' in v_src) > 0 then return; end if;
  v_new := replace(v_src, '        as mensualidades_n' || E'\n' || '      from caja_movimientos',
    '        as mensualidades_n,' || E'\n' ||
    '      -- 0111: la tiquetera es un ingreso de caja más; aquí se nombra aparte.' || E'\n' ||
    '      coalesce(sum(valor_cop) filter (where sentido = ''ingreso'' and concepto = ''tiquetera''), 0)' || E'\n' ||
    '        as tiqueteras_cop,' || E'\n' ||
    '      coalesce(count(*) filter (where sentido = ''ingreso'' and concepto = ''tiquetera''), 0)' || E'\n' ||
    '        as tiqueteras_n' || E'\n' ||
    '      from caja_movimientos');
  v_new := replace(v_new, '''mensualidades_n'',   caja.mensualidades_n,',
    '''mensualidades_n'',   caja.mensualidades_n,' || E'\n' ||
    '    ''tiqueteras_cop'', caja.tiqueteras_cop,' || E'\n' ||
    '    ''tiqueteras_n'',   caja.tiqueteras_n,');
  if position('caja.tiqueteras_n' in v_new) = 0 or position('as tiqueteras_n' in v_new) = 0 then
    raise exception '0111: no se aplicó ventas_entre';
  end if;
  execute v_new;
end
$mig$;

-- ── 7. el tablero del informe: tiqueteras desde la caja ───────────────
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.tablero_tumbao(text)'::regprocedure) into v_src;
  if position('0111' in v_src) > 0 then return; end if;
  v_new := v_src;
  v_new := replace(v_new,
    'and concepto not in (''clase_suelta'', ''mensualidad'', ''media_mensualidad'');',
    'and concepto not in (''clase_suelta'', ''mensualidad'', ''media_mensualidad'', ''tiquetera'');  -- 0111');
  v_new := replace(v_new,
    '''sueltas_cop'', (v_hoy->>''ingreso_cop'')::bigint - (v_hoy->>''mensualidades_cop'')::bigint - v_otros,',
    '''sueltas_cop'', (v_hoy->>''ingreso_cop'')::bigint - (v_hoy->>''mensualidades_cop'')::bigint - v_otros'
    || ' - coalesce((v_hoy->>''tiqueteras_cop'')::bigint, 0),');
  v_new := replace(v_new,
    '''tiqueteras_en_linea_n'', (select count(*) from tiqueteras' || E'\n' ||
    '                        where pagado_en is not null and (pagado_en at time zone ''America/Bogota'')::date = d),' || E'\n' ||
    '      ''tiqueteras_en_linea_cop'', (select coalesce(sum(precio_cop), 0) from tiqueteras' || E'\n' ||
    '                        where pagado_en is not null and (pagado_en at time zone ''America/Bogota'')::date = d),',
    '''tiqueteras_n'', coalesce((v_hoy->>''tiqueteras_n'')::int, 0),' || E'\n' ||
    '      ''tiqueteras_cop'', coalesce((v_hoy->>''tiqueteras_cop'')::bigint, 0),');
  v_new := replace(v_new,
    '''tiqueteras_en_linea_n'', (select count(*) from tiqueteras' || E'\n' ||
    '                        where pagado_en is not null and (pagado_en at time zone ''America/Bogota'')::date between ini_mes and d),',
    '''tiqueteras_n'', coalesce((v_mes->>''tiqueteras_n'')::int, 0),' || E'\n' ||
    '      ''tiqueteras_cop'', coalesce((v_mes->>''tiqueteras_cop'')::bigint, 0),');
  v_new := replace(v_new,
    '''vendidas_mes'', (select count(*) from tiqueteras where pagado_en is not null' || E'\n' ||
    '                      and (pagado_en at time zone ''America/Bogota'')::date between ini_mes and d),',
    '''vendidas_mes'', coalesce((v_mes->>''tiqueteras_n'')::int, 0),');
  v_new := replace(v_new, 'from tiqueteras where pagado_en is not null', 'from tiqueteras where estado = ''confirmada''');
  v_new := replace(v_new, 'tq.pagado_en is not null', 'tq.estado = ''confirmada''');
  v_new := replace(v_new, 'and tq.pagado_en > a.enviado_at',
    'and tq.estado = ''confirmada'' and coalesce(tq.pagado_en, tq.creada_en) > a.enviado_at');
  if position('tiqueteras_en_linea' in v_new) > 0 or position('pagado_en is not null' in v_new) > 0
     or position('''tiquetera'');  -- 0111' in v_new) = 0 then
    raise exception '0111: no se aplicó el tablero';
  end if;
  execute v_new;
end
$mig$;
