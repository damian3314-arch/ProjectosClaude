-- =====================================================================
-- El tablero del día
--
-- Lo que hay que poder responder de un vistazo, sin abrir nada más:
--
--   ¿Cuántos cupos quedan para vender de la clase de las 7?
--   ¿Cuánta gente con plan tiene esa hora?
--   ¿Cuántas reservas llevamos?
--   ¿Cuánta gente va a entrar en total a esa sala?
--
-- Esa última no estaba en ningún sitio y es la que de verdad importa
-- cuando se abre la puerta: entre semana entran los que tienen plan
-- (que no reservan, solo llegan) MÁS los que compraron clase suelta.
-- El sábado nadie tiene plan, así que ahí "en sala" son las reservas.
--
--     en sala = gente con plan + reservas vivas
--
-- Todo sale de columnas que ya se mantienen solas (`clases.aforo`,
-- `activos_plan`, `cupo_total`, `cupo_tomado`). Esta función no calcula
-- nada nuevo ni escribe: solo junta y cuenta. Si algún número se ve
-- raro, el problema está en la importación de la noche, no aquí.
--
-- Lectura pura: no hay un solo insert/update/delete.
-- =====================================================================

create or replace function admin_tablero(p_token text, p_dia date default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
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
      -- de dónde sale el cupo
      'aforo',       c.aforo,
      'con_plan',    c.activos_plan,
      'a_la_venta',  c.cupo_total,
      'cupo_manual', c.cupo_manual,
      -- qué se ha vendido
      'reservadas',  c.cupo_tomado,
      'libres',      greatest(c.cupo_total - c.cupo_tomado, 0),
      'confirmadas', n.confirmadas,
      'por_validar', n.por_validar,
      'esperando',   n.esperando,
      -- cuánta gente entra
      'en_sala',     c.activos_plan + c.cupo_tomado,
      'ingreso_cop', n.confirmadas * c.precio_cop
    ) as x
    from clases c
    cross join lateral (
      select
        count(*) filter (where r.estado = 'confirmada')::int            as confirmadas,
        count(*) filter (where r.estado = 'pendiente_validacion')::int  as por_validar,
        count(*) filter (where r.estado in ('pendiente_pago','verificando'))::int as esperando
      from reservas r where r.clase_id = c.id
    ) n
   where (c.fecha_hora at time zone 'America/Bogota')::date = v_dia
  ) s;

  return jsonb_build_object(
    'ok', true,
    'dia', v_dia,
    'es_hoy', v_dia = v_hoy,
    'clases', v_clases,
    -- El resumen se saca de las mismas tarjetas para que no puedan
    -- contradecirse: si sumas las tarjetas a mano, da esto.
    'resumen', jsonb_build_object(
      'clases',      jsonb_array_length(v_clases),
      'aforo',       coalesce((select sum((c->>'aforo')::int)       from jsonb_array_elements(v_clases) c), 0),
      'con_plan',    coalesce((select sum((c->>'con_plan')::int)    from jsonb_array_elements(v_clases) c), 0),
      'a_la_venta',  coalesce((select sum((c->>'a_la_venta')::int)  from jsonb_array_elements(v_clases) c), 0),
      'reservadas',  coalesce((select sum((c->>'reservadas')::int)  from jsonb_array_elements(v_clases) c), 0),
      'libres',      coalesce((select sum((c->>'libres')::int)      from jsonb_array_elements(v_clases) c), 0),
      'confirmadas', coalesce((select sum((c->>'confirmadas')::int) from jsonb_array_elements(v_clases) c), 0),
      'por_validar', coalesce((select sum((c->>'por_validar')::int) from jsonb_array_elements(v_clases) c), 0),
      'esperando',   coalesce((select sum((c->>'esperando')::int)   from jsonb_array_elements(v_clases) c), 0),
      'en_sala',     coalesce((select sum((c->>'en_sala')::int)     from jsonb_array_elements(v_clases) c), 0),
      'ingreso_cop', coalesce((select sum((c->>'ingreso_cop')::int) from jsonb_array_elements(v_clases) c), 0)
    ));
end;
$$;

comment on function admin_tablero(text, date) is
  'Tarjetas del dia para el panel: cupos, gente con plan, reservas y cuanta gente entra a cada clase. Solo lectura.';


-- ---------------------------------------------------------------------
-- La cola de validacion, ahora agrupable por clase
--
-- El caso real es el mostrador: llega alguien, el cajero tiene que
-- encontrarlo en la lista. Con diez tarjetas seguidas y todas iguales
-- no se distingue quien viene a la clase de las 7 de quien viene a la
-- de las 6. Se agrega `clase_id` para poder agrupar sin adivinar por
-- la fecha, y `tipo` para ver de un golpe si es miembro o clase suelta.
--
-- Lo demas queda igual: mismos campos, mismo orden.
-- ---------------------------------------------------------------------

create or replace function admin_pendientes(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_out   jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select coalesce(jsonb_agg(x order by x->>'creada_at'), '[]'::jsonb) into v_out
  from (
    select jsonb_build_object(
      'codigo',      r.codigo,
      'nombre',      r.nombre,
      'telefono',    r.telefono,
      'estado',      r.estado,
      'tipo',        r.tipo,
      'creada_at',   r.created_at,
      'pagado_en',   r.pagado_en,
      'pagador',     r.pagador_nombre,
      'referencia',  r.referencia_pago,
      'clase_id',    c.id,
      'clase',       c.nombre,
      'fecha_hora',  c.fecha_hora,
      'precio_cop',  c.precio_cop,
      'pagos_sueltos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'pago_id',   p.id,
                 'valor_cop', p.valor_cop,
                 'fecha',     p.fecha_pago,
                 'remitente', p.remitente,
                 -- El parecido se mide contra quien paga de verdad.
                 'parecido',  round(similitud_nombre(
                                coalesce(r.pagador_nombre, r.nombre), p.remitente), 2),
                 -- Minutos de diferencia con la hora que declaro. Es el
                 -- dato que mas rapido resuelve el caso a ojo.
                 'minutos',   case when r.pagado_en is null then null
                              else round(extract(epoch from
                                     (p.fecha_pago - r.pagado_en)) / 60) end)
               order by case when r.pagado_en is null then 0
                        else abs(extract(epoch from (p.fecha_pago - r.pagado_en))) end)
          from pagos p
         where p.valor_cop = c.precio_cop
           and p.fecha_pago between coalesce(r.pagado_en, r.created_at) - interval '1 hour'
                               and coalesce(r.pagado_en, r.created_at) + interval '3 hours'
           and not exists (select 1 from reservas r2 where r2.pago_id = p.id)
      ), '[]'::jsonb)
    ) as x
    from reservas r
    join clases c on c.id = r.clase_id
   where r.estado in ('pendiente_validacion', 'verificando')
  ) s;

  return jsonb_build_object('ok', true, 'reservas', v_out);
end;
$$;


-- ---------------------------------------------------------------------
-- Nada de esto se toca con la llave publica
--
-- Postgres le da EXECUTE a PUBLIC a toda funcion nueva. Sin esta linea,
-- `admin_tablero` quedaba abierta a la llave anon: cualquiera con la
-- URL del proyecto veria el aforo, los afiliados y la caja del dia. Lo
-- caza pruebas/humo-tablero.sql, que fue exactamente como aparecio.
--
-- `create or replace` conserva los permisos, asi que el revoke de
-- admin_pendientes es redundante — pero cuesta una linea y quita la
-- duda de si se conservan o no.
-- ---------------------------------------------------------------------
revoke execute on function admin_tablero(text, date)  from public, anon, authenticated;
revoke execute on function admin_pendientes(text)     from public, anon, authenticated;
