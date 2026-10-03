-- =====================================================================
-- El panel de admin no abría: "Invalid time value"
--
-- EL BUG
-- `admin_semana` armaba los siete días así:
--
--     from generate_series(p_desde, p_desde + 6, interval '1 day') g(dia)
--
-- `generate_series` con paso de intervalo NO devuelve date: promueve los
-- extremos a `timestamptz`. Así que `jsonb_build_object('fecha', dia)`
-- no serializaba "2026-07-28" sino:
--
--     "2026-07-28T00:00:00+00:00"
--
-- La página hace `fecha.split('-')` para partir el ISO en año/mes/día.
-- Con esa forma, el tercer trozo es "28T00:00:00+00:00" → Number(...) es
-- NaN → Date.UTC(2026, 6, NaN) es Invalid Date → Intl lanza
-- `RangeError: Invalid time value`. La excepción subía hasta el catch
-- del login, que pintaba el mensaje del error en rojo bajo el token.
-- Desde fuera parecía que el token estaba mal. El token estaba bien: la
-- semana llegaba y la página moría al pintarla.
--
-- Y había un segundo problema escondido en el mismo sitio: al ser
-- `timestamptz`, tanto el texto del JSON como `extract(dow ...)`
-- dependían de la zona horaria de la conexión. Hoy PostgREST se conecta
-- en UTC y cuadra; el día que no, los días de la cuadrícula se corrían
-- uno.
--
-- LA CORRECCIÓN
-- Recorrer con enteros y sumarlos a la fecha: `p_desde + n` entre un
-- `date` y un `int` da `date`, sin pasar nunca por un timestamp. El JSON
-- sale "2026-07-28" y `dow` ya no depende de la zona de la sesión.
--
-- Por qué no lo vio ninguna prueba: el espejo local (pruebas/espejo-api.mjs)
-- devolvía la fecha ya limpia, porque la arma en Node. Probaba la página
-- contra un contrato inventado, no contra el de verdad. Es el mismo hueco
-- que escondió el bug de `.first()` en los nodos Code de n8n. El espejo
-- ahora imita la forma fea a propósito.
-- =====================================================================

create or replace function admin_semana(p_token text, p_desde date)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_dias  jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select coalesce(jsonb_agg(d order by d->>'fecha'), '[]'::jsonb) into v_dias
  from (
    select jsonb_build_object(
      'fecha', dia,
      'dow',   extract(dow from dia)::int,
      'clases', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'clase_id',    c.id,
                 'nombre',      c.nombre,
                 'hora',        to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI'),
                 'profesor',    c.profesor,
                 'activa',      c.activa,
                 'aforo',       c.aforo,
                 'activos_plan', c.activos_plan,
                 'cupo_total',  c.cupo_total,
                 'cupo_tomado', c.cupo_tomado,
                 'cupo_manual', c.cupo_manual,
                 'ya_paso',     c.fecha_hora <= now()
               ) order by c.fecha_hora)
          from clases c
         where (c.fecha_hora at time zone 'America/Bogota')::date = dia
      ), '[]'::jsonb)
    ) as d
    -- date + int = date. Con `interval '1 day'` esto era timestamptz y
    -- el JSON salía con hora y desfase pegados a la fecha.
    from generate_series(0, 6) g(n)
    cross join lateral (select (p_desde + g.n)::date as dia) f
  ) s;

  return jsonb_build_object('ok', true, 'desde', p_desde,
    'hasta', p_desde + 6, 'dias', v_dias);
end;
$$;

comment on function admin_semana(text, date) is
  'Los 7 dias de la semana para el panel. fecha sale como AAAA-MM-DD: no usar generate_series con intervalo, que la convierte en timestamptz.';
