-- 0094 — Una sola verdad, y salidas que aprenden
--
-- DOS COSAS, Y LA PRIMERA ES UN FALLO DE VERDAD
--
-- Damián: «veo que resumen no tiene los mismos valores en salidas que
-- tesorería». Tiene razón y la causa es que había dos definiciones de
-- «salió» conviviendo:
--
--   Resumen    → ventas_entre().egreso_cop  = SOLO la caja menor
--   Tesorería  → gastos + caja menor
--
-- En septiembre eso es $120.000 contra $7.402.990. La misma pantalla,
-- el mismo mes, dos cifras que se llevan sesenta veces. Y lo mismo por
-- el lado de las entradas desde la 0091: tesorería pasó al mostrador y
-- el resumen se quedó en la Caja.
--
-- No se arregla copiando la cuenta buena a la otra pantalla: así fue
-- como se separaron. Se arregla con UNA función que las dos llamen.
-- `plata_entre()` es esa función, y a partir de aquí cualquier vista que
-- quiera decir «entró / salió / queda» la usa.
--
-- La segunda: las salidas se clasifican solas cuando ya se sabe de quién
-- es la cuenta. Ver más abajo.

-- ── LA CIFRA, EN UN SOLO SITIO ──────────────────────────────────────

create or replace function public.plata_entre(p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_caja  jsonb;
  v_corte date;
  v_mos   date;
  v_ing   bigint;
  v_gas   bigint;
  v_menor bigint;
  v_dias_caja int;
begin
  v_caja := ventas_entre(p_desde, p_hasta);

  -- ENTRÓ. Por tramos, igual que lo dejó la 0091: hasta donde llega el
  -- reporte del mostrador manda el mostrador; de ahí en adelante, la
  -- Caja. Son días distintos, así que nada se cuenta dos veces.
  select max(dia) into v_mos from ventas_mostrador;
  v_corte := coalesce(v_mos, p_desde - 1);

  select coalesce(sum(cobrado_cop), 0) into v_ing from ventas_mostrador
   where dia between p_desde and least(p_hasta, v_corte);
  if p_hasta > v_corte then
    v_ing := v_ing + coalesce((ventas_entre(greatest(p_desde, v_corte + 1),
                                            p_hasta)->>'ingreso_cop')::bigint, 0);
  end if;

  -- SALIÓ. Los gastos MÁS la caja menor. La caja menor es un libro
  -- aparte y no está en `gastos`; dejarla fuera diría menos de lo que
  -- de verdad salió, que es justo lo que hacía el resumen al revés.
  select coalesce(sum(valor_cop), 0) into v_gas
    from gastos where not anulado and dia between p_desde and p_hasta;
  v_menor := coalesce((v_caja->>'egreso_cop')::bigint, 0);

  v_dias_caja := greatest(p_hasta - greatest(p_desde - 1, v_corte), 0);

  return jsonb_build_object(
    'desde', p_desde, 'hasta', p_hasta,
    'entro_cop', v_ing,
    'salio_cop', v_gas + v_menor,
    'gastos_cop', v_gas,
    'caja_menor_cop', v_menor,
    'utilidad_cop', v_ing - (v_gas + v_menor),
    'margen_pct', case when v_ing = 0 then null
                       else round((v_ing - (v_gas + v_menor)) * 100.0 / v_ing) end,
    'fuente_ingreso', case when v_mos is null then 'caja'
                           when v_dias_caja = 0 then 'mostrador'
                           else 'mixto' end,
    'mostrador_hasta', v_mos,
    'dias_de_caja', v_dias_caja,
    -- El desglose de la Caja se sigue devolviendo: es con lo que se
    -- concilia, y no estorba.
    'caja', v_caja);
end;
$function$;

revoke all on function public.plata_entre(date, date) from public, anon, authenticated;
grant execute on function public.plata_entre(date, date) to service_role;


-- ── SALIDAS QUE SE CLASIFICAN SOLAS ─────────────────────────────────
--
-- Damián: «salida debe ser inteligente pues ya sabe de montos y cuentas
-- donde se envía el dinero, por lo tanto debe categorizar las salidas de
-- manera automática; solo debe quedar pendiente cuando se envíe dinero a
-- una cuenta o persona que nunca se ha enviado».
--
-- Eso es exactamente lo que la bandeja ya sabía hacer a medias: enseñaba
-- la sugerencia y esperaba a que alguien pulsara Guardar. Si la
-- sugerencia es buena, ese clic no decide nada — solo retrasa.
--
-- Cómo elige, de más a menos específico:
--   1. misma cuenta Y mismo valor  → el concepto exacto de esa vez
--   2. misma cuenta                → lo último que se dijo de ella
--   3. cuenta nueva                → pendiente, que es el caso que él
--                                     quiere que siga parando
--
-- QUÉ NO HACE SOLA. Si ya hay un gasto del mismo valor por esas fechas
-- —o sea, si Tanya probablemente ya lo reportó en el chat—, no se
-- clasifica aunque conozca la cuenta: se queda pendiente con el aviso.
-- Contar un pago dos veces es más caro que un clic.
--
-- Y todo lo automático queda marcado: `atendida_por is null` en una
-- clasificada significa «esto lo hizo la máquina». La bandeja las lista
-- aparte para poder corregirlas.

create or replace function public.banco_salida_apuntar(
  p_ref            text,
  p_valor_cop      int,
  p_ocurrio_at     timestamptz,
  p_cuenta_origen  text default null,
  p_cuenta_destino text default null,
  p_destinatario   text default null,
  p_patron         text default null,
  p_confianza      text default null,
  p_raw            text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_id     uuid;
  v_dia    date;
  v_dest   text;
  v_ap     record;
  v_rep    boolean;
  v_gasto  uuid;
begin
  if coalesce(btrim(p_ref), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'SIN_REFERENCIA');
  end if;
  if coalesce(p_valor_cop, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'VALOR_INVALIDO');
  end if;

  select id into v_id from salidas_banco where ref_banco = btrim(p_ref);
  if found then
    return jsonb_build_object('ok', true, 'id', v_id, 'ya_estaba', true);
  end if;

  v_dia  := (p_ocurrio_at at time zone 'America/Bogota')::date;
  v_dest := nullif(btrim(coalesce(p_cuenta_destino, '')), '');

  insert into salidas_banco (ref_banco, valor_cop, ocurrio_at, cuenta_origen,
                             cuenta_destino, destinatario, patron, confianza, raw)
  values (btrim(p_ref), p_valor_cop, p_ocurrio_at,
          nullif(btrim(coalesce(p_cuenta_origen, '')), ''),
          v_dest,
          nullif(btrim(coalesce(p_destinatario, '')), ''),
          p_patron, p_confianza, left(coalesce(p_raw, ''), 4000))
  returning id into v_id;

  -- ¿Ya hay un gasto de este valor por estas fechas? Entonces no se
  -- toca: probablemente es el mismo pago que Tanya ya anotó.
  select exists (
    select 1 from gastos g
     where not g.anulado and g.valor_cop = p_valor_cop
       and g.dia between v_dia - 2 and v_dia + 2
  ) into v_rep;

  if v_dest is null or v_rep or p_confianza = 'baja' then
    return jsonb_build_object('ok', true, 'id', v_id, 'ya_estaba', false,
      'clasificada_sola', false,
      'por_que', case when v_dest is null then 'sin_cuenta_destino'
                      when v_rep then 'quizas_repetida'
                      else 'confianza_baja' end);
  end if;

  -- Lo que se sabe de esta cuenta. Primero el mismo valor —que suele ser
  -- el mismo concepto, la clase de 60.000 de siempre—, y si no, lo
  -- último que se dijo de ella.
  select g.categoria, g.concepto, g.a_quien into v_ap
    from salidas_banco s
    join gastos g on g.id = s.gasto_id
   where s.cuenta_destino = v_dest
     and s.estado = 'clasificada'
     and not g.anulado
   order by (s.valor_cop = p_valor_cop) desc, s.ocurrio_at desc
   limit 1;

  if not found then
    return jsonb_build_object('ok', true, 'id', v_id, 'ya_estaba', false,
      'clasificada_sola', false, 'por_que', 'cuenta_nueva');
  end if;

  insert into gastos (dia, valor_cop, concepto, categoria, medio, a_quien,
                      fuente, nota)
  values (v_dia, p_valor_cop, v_ap.concepto, v_ap.categoria, 'banco',
          v_ap.a_quien, 'banco',
          'Clasificada sola: ya se había enviado plata a la cuenta '
          || v_dest || ' y esa vez fue «' || v_ap.concepto || '».')
  returning id into v_gasto;

  update salidas_banco
     set estado = 'clasificada', gasto_id = v_gasto, atendida_at = now()
   where id = v_id;          -- atendida_por queda null: lo hizo la máquina

  return jsonb_build_object('ok', true, 'id', v_id, 'ya_estaba', false,
    'clasificada_sola', true, 'gasto_id', v_gasto,
    'concepto', v_ap.concepto, 'categoria', v_ap.categoria);
end;
$function$;

revoke all on function public.banco_salida_apuntar(text, int, timestamptz, text, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.banco_salida_apuntar(text, int, timestamptz, text, text, text, text, text, text)
  to service_role;


-- ── CORREGIR LO QUE LA MÁQUINA CLASIFICÓ MAL ────────────────────────
--
-- Clasificar solo sin poder corregir sería peor que no clasificar: el
-- error se vuelve invisible y se repite a la siguiente transferencia a
-- esa cuenta, porque el aprendizaje lee de ahí. Esto arregla el gasto y,
-- con él, lo que se aprenderá la próxima vez.

create or replace function public.admin_salida_corregir(
  p_token     text,
  p_id        uuid,
  p_categoria text,
  p_concepto  text,
  p_a_quien   text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_admin record; v_s salidas_banco;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_s from salidas_banco where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;
  if v_s.gasto_id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_CLASIFICADA',
      'mensaje', 'Esta salida todavía no tiene gasto que corregir.');
  end if;
  if coalesce(btrim(p_concepto), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'SIN_CONCEPTO');
  end if;

  update gastos
     set concepto  = btrim(p_concepto),
         categoria = p_categoria,
         a_quien   = nullif(btrim(coalesce(p_a_quien, '')), ''),
         nota      = coalesce(nota || ' · ', '') || 'Corregida a mano el '
                     || to_char(now() at time zone 'America/Bogota', 'DD/MM/YYYY')
   where id = v_s.gasto_id;

  -- Pasa a tener dueño humano: deja de contar como automática y es lo
  -- que la siguiente transferencia a esta cuenta va a aprender.
  update salidas_banco
     set atendida_por = v_admin.id, atendida_at = now()
   where id = p_id;

  return jsonb_build_object('ok', true, 'gasto_id', v_s.gasto_id);
end;
$function$;

revoke all on function public.admin_salida_corregir(text, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_salida_corregir(text, uuid, text, text, text)
  to service_role;


-- ── LA BANDEJA TAMBIÉN ENSEÑA LO QUE SE HIZO SOLO ───────────────────

create or replace function public.admin_salidas_pendientes(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_admin record; v_hoy date; v_lista jsonb; v_solas jsonb;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  v_hoy := (now() at time zone 'America/Bogota')::date;

  select coalesce(jsonb_agg(x order by x.ocurrio_at desc), '[]'::jsonb)
    into v_lista
    from (
      select s.id, s.valor_cop, s.ocurrio_at,
             (s.ocurrio_at at time zone 'America/Bogota')::date as dia,
             s.cuenta_destino, s.destinatario, s.confianza,
             (select jsonb_build_object('categoria', g.categoria,
                                        'a_quien',   g.a_quien,
                                        'concepto',  g.concepto)
                from salidas_banco s2
                join gastos g on g.id = s2.gasto_id
               where s2.cuenta_destino is not null
                 and s2.cuenta_destino = s.cuenta_destino
                 and s2.estado = 'clasificada'
               order by (s2.valor_cop = s.valor_cop) desc, s2.ocurrio_at desc
               limit 1) as sugerencia,
             (select jsonb_build_object('dia', g.dia, 'concepto', g.concepto,
                                        'categoria', g.categoria)
                from gastos g
               where not g.anulado
                 and g.valor_cop = s.valor_cop
                 and g.dia between
                     (s.ocurrio_at at time zone 'America/Bogota')::date - 2
                 and (s.ocurrio_at at time zone 'America/Bogota')::date + 2
               order by abs(g.dia - (s.ocurrio_at at time zone 'America/Bogota')::date)
               limit 1) as quizas_repetida
        from salidas_banco s
       where s.estado = 'pendiente'
    ) x;

  /* Lo que la máquina clasificó sola en los últimos días. No es una
     lista de pendientes —ya están contadas— sino la ventana para
     pillarle un error antes de que lo repita: el aprendizaje de la
     próxima transferencia a esa cuenta sale de aquí. */
  select coalesce(jsonb_agg(y order by y.ocurrio_at desc), '[]'::jsonb)
    into v_solas
    from (
      select s.id, s.valor_cop, s.ocurrio_at,
             (s.ocurrio_at at time zone 'America/Bogota')::date as dia,
             s.cuenta_destino, g.concepto, g.categoria, g.a_quien
        from salidas_banco s
        join gastos g on g.id = s.gasto_id
       where s.estado = 'clasificada'
         and s.atendida_por is null
         and s.ocurrio_at > now() - interval '7 days'
         and not g.anulado
       limit 30
    ) y;

  return jsonb_build_object(
    'ok', true,
    'hoy', v_hoy,
    'cuantas', jsonb_array_length(v_lista),
    'cop', (select coalesce(sum(valor_cop), 0) from salidas_banco
             where estado = 'pendiente'),
    'salidas', v_lista,
    'solas', v_solas);
end;
$function$;

revoke all on function public.admin_salidas_pendientes(text) from public, anon, authenticated;
grant execute on function public.admin_salidas_pendientes(text) to service_role;


-- ── Y EL RESUMEN DEJA DE LLEVAR SU PROPIA CUENTA ────────────────────

do $$
declare
  d text := pg_get_functiondef('public.admin_resumen_gerencia(text, date)'::regprocedure);
  viejo constant text := '''gastos_mes'', v_gastos);';
  nuevo constant text := '''gastos_mes'', v_gastos,
    -- 0094: las cifras buenas, las mismas que enseña la tesorería.
    -- Antes esta vista restaba solo la caja menor y decía que en
    -- septiembre habían salido 120.000 cuando salieron 7.402.990.
    -- `dia`, `semana` y `mes` se siguen devolviendo porque el panel
    -- pinta con ellos el detalle de la Caja; lo que manda ahora es esto.
    ''plata_mes'',        plata_entre(v_mes_ini, v_hoy),
    ''plata_mes_antes'',  plata_entre(v_mes_ant_ini, v_mes_ant_fin),
    ''plata_semana'',     plata_entre(v_sem_ini, v_hoy),
    ''plata_semana_antes'', plata_entre(v_sem_ant_ini, v_sem_ant_fin));';
begin
  if position('0094:' in d) > 0 then
    raise notice '0094 ya estaba puesto en admin_resumen_gerencia';
    return;
  end if;
  if position(viejo in d) = 0 then
    raise exception '0094: no encuentro el cierre de admin_resumen_gerencia';
  end if;
  execute replace(d, viejo, nuevo);
end $$;


-- ── Y LA TESORERÍA TAMPOCO ──────────────────────────────────────────
--
-- Se le quita el cálculo propio que le puso la 0091 y se le deja la
-- llamada. Las dos vistas ya no pueden separarse porque ya no hay dos
-- cuentas que separar.

do $$
declare
  d text := pg_get_functiondef('public.admin_tesoreria(text, date, date)'::regprocedure);

  viejo constant text := '  -- 0091: el ingreso se arma por tramos. Hasta donde llega el reporte
  -- del mostrador manda el mostrador; de ahí en adelante, la Caja. Los
  -- dos tramos son días distintos, así que nada se cuenta dos veces.
  select max(dia) into v_mos_hasta from ventas_mostrador;
  v_corte := coalesce(v_mos_hasta, v_desde - 1);

  select coalesce(sum(cobrado_cop), 0) into v_ing from ventas_mostrador
   where dia between v_desde and least(v_hasta, v_corte);
  if v_hasta > v_corte then
    v_ing := v_ing + coalesce((ventas_entre(greatest(v_desde, v_corte + 1),
                                            v_hasta)->>''ingreso_cop'')::bigint, 0);
  end if;

  select coalesce(sum(cobrado_cop), 0) into v_ing_a from ventas_mostrador
   where dia between v_adesde and least(v_ahasta, v_corte);
  if v_ahasta > v_corte then
    v_ing_a := v_ing_a + coalesce((ventas_entre(greatest(v_adesde, v_corte + 1),
                                                v_ahasta)->>''ingreso_cop'')::bigint, 0);
  end if;

  v_dias_caja := greatest(v_hasta - greatest(v_desde - 1, v_corte), 0);
  v_fuente := case when v_mos_hasta is null then ''caja''
                   when v_dias_caja = 0    then ''mostrador''
                   else ''mixto'' end;';

  nuevo constant text := '  -- 0094: la cuenta ya no se hace aquí. `plata_entre` es la misma
  -- función que usa el resumen, y por eso las dos pantallas no pueden
  -- volver a decir cosas distintas del mismo mes.
  v_pl    := plata_entre(v_desde,  v_hasta);
  v_ing   := (v_pl->>''entro_cop'')::bigint;
  v_ing_a := (plata_entre(v_adesde, v_ahasta)->>''entro_cop'')::bigint;
  v_mos_hasta := nullif(v_pl->>''mostrador_hasta'', '''')::date;
  v_dias_caja := (v_pl->>''dias_de_caja'')::int;
  v_fuente    := v_pl->>''fuente_ingreso'';';

  dec_viejo constant text := '  v_dias_caja int;
begin';
  dec_nuevo constant text := '  v_dias_caja int;
  v_pl        jsonb;   -- 0094: lo que devuelve plata_entre()
begin';
begin
  if position('0094:' in d) > 0 then
    raise notice '0094 ya estaba puesto en admin_tesoreria';
    return;
  end if;
  if position(dec_viejo in d) = 0 then
    raise exception '0094: no encuentro el declare de admin_tesoreria';
  end if;
  if position(viejo in d) = 0 then
    raise exception '0094: no encuentro el cálculo de ingreso de la 0091';
  end if;
  d := replace(d, dec_viejo, dec_nuevo);
  d := replace(d, viejo, nuevo);
  execute d;
end $$;
