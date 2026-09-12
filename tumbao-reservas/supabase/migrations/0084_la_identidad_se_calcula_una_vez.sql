-- 0084 · La identidad del cliente se calcula una vez, no tres.
--
-- EL NÚMERO QUE LO DESTAPÓ
-- Medido el mismo día que se aplicó la 0083, sobre las 364 reservas que
-- hay hoy:
--
--   el CTE `visitas` del ranking: 131 ms
--   de los cuales 129 en el join, o sea en el cálculo por fila
--
-- 131 ms es el trozo más caro de todo el panel, en una pantalla que se
-- refresca sola. Y crece con los datos: con diez veces más reservas,
-- más de un segundo.
--
-- POR QUÉ TARDABA
-- `nombre_normalizado` hace unaccent + partir con regex + reordenar, y
-- se estaba llamando TRES veces por fila:
--
--   1. dentro de `cliente_clave`, para preguntar si el nombre tiene
--      espacio (o sea, si trae dos palabras);
--   2. otra vez dentro de la rama del case que corresponda;
--   3. y una tercera en el propio `visitas`, que necesita el nombre
--      normalizado para la fusión del subconjunto.
--
-- Postgres no memoriza una función IMMUTABLE entre filas: la ejecuta
-- cada vez que aparece escrita.
--
-- LO QUE SE HACE
-- Se parte la regla en dos funciones. `clave_de` decide sobre un nombre
-- YA normalizado; `cliente_clave` sigue existiendo igual que antes para
-- quien llega con el nombre crudo, y se limita a normalizar y llamar a
-- la otra.
--
-- Con eso el ranking puede normalizar UNA vez por fila en un LATERAL y
-- usar ese valor para las dos cosas que necesita —la clave y los tokens
-- del subconjunto—, sin que la regla de identidad se duplique en la
-- consulta. Eso último es lo que importa: la decisión de qué filas son
-- la misma persona sigue viviendo en un solo sitio. Copiarla dentro del
-- SELECT habría sido más rápido de escribir y habría dejado dos
-- definiciones que se despegan sin avisar, que es el fallo que esta casa
-- ya ha pagado varias veces.

-- La regla, sobre un nombre que ya viene normalizado.
create or replace function public.clave_de(p_norma text, p_telefono text)
returns text
language sql
immutable
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
  -- Un espacio quiere decir dos palabras o más: el nombre ya identifica
  -- y aguanta el cambio de teléfono. Una sola palabra no distingue a
  -- nadie —puede haber dos Palomas— y ahí manda el número.
  select case
    when position(' ' in coalesce(p_norma, '')) > 0 then p_norma
    else right(regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g'), 10)
         || '|' || coalesce(p_norma, '')
  end;
$function$;

-- La puerta de entrada de siempre, para quien tiene el nombre como lo
-- teclearon. Se queda porque es la que se lee y la que documenta la
-- regla; ahora solo normaliza una vez y delega.
create or replace function public.cliente_clave(p_nombre text, p_telefono text)
returns text
language sql
immutable
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
  select clave_de(nombre_normalizado(p_nombre), p_telefono);
$function$;

-- El ranking, con la normalización sacada a un LATERAL. Cambia SOLO el
-- CTE `visitas`; el resto del cuerpo es el de la 0083 palabra por
-- palabra, porque aquí no se está arreglando ninguna cuenta.
create or replace function public.admin_clientes_ranking(
  p_token  text,
  p_dias   int default null,
  p_limite int default 10)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_admin record;
  v_hoy   date;
  v_desde date;
  v_lim   int;
  v_lista jsonb;
  v_repetidas jsonb;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if v_admin.rol = 'cajero' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO',
      'mensaje', 'Esta vista es del propietario y el administrador.');
  end if;

  v_hoy   := (now() at time zone 'America/Bogota')::date;
  v_desde := case when p_dias is null or p_dias < 1 then '-infinity'::date
                  else v_hoy - (least(p_dias, 3650) - 1) end;
  v_lim   := least(greatest(coalesce(p_limite, 10), 1), 50);

  with visitas as (
    -- 0071: quien ENTRÓ. Palabra por palabra la regla del cierre, para
    -- que este ranking no pueda contradecir a la tirilla.
    --
    -- 0084: el LATERAL normaliza el nombre UNA vez por fila y de ahí
    -- salen las dos cosas que hacen falta, la clave y los tokens. La
    -- regla sigue en `clave_de`, no copiada aquí.
    select clave_de(n.norma, n.tel) as clave,
           n.tel, n.norma,
           btrim(r.nombre) as nombre,
           (c.fecha_hora at time zone 'America/Bogota')::date as dia,
           to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI') as hora,
           c.precio_cop,
           -- Empieza en mayúscula y sigue en minúscula: escrito como un
           -- nombre y no a gritos ni todo en bajo.
           (btrim(r.nombre) ~ '^[[:upper:]]' and btrim(r.nombre) ~ '[[:lower:]]')
             as bien_escrito
      from reservas r
      join clases c on c.id = r.clase_id
      cross join lateral (
        select nombre_normalizado(r.nombre) as norma,
               right(regexp_replace(coalesce(r.telefono, ''), '\D', '', 'g'), 10) as tel
      ) n
     where r.estado = 'confirmada' and r.tipo = 'suelta'
       and r.no_vino_at is null and r.reprogramada_a is null
       and (c.fecha_hora at time zone 'America/Bogota')::date
             between v_desde and v_hoy
  ),
  fichas as (
    select clave,
           array_agg(distinct tel) as tels,
           (array_agg(nombre order by length(nombre) desc, bien_escrito desc,
                                      nombre collate "C"))[1] as nombre,
           string_to_array(nullif(max(norma), ''), ' ') as tokens
      from visitas
     group by clave
  ),
  cont as (
    select f.clave,
           count(*) as cuantos,
           (array_agg(g.clave order by cardinality(g.tokens) desc, g.clave))[1] as jefe
      from fichas f
      join fichas g
        on g.tels && f.tels
       and g.clave <> f.clave
       and f.tokens <@ g.tokens
     group by f.clave
  ),
  canon as (
    select f.*,
           case when c.cuantos = 1 then c.jefe else f.clave end as jefe
      from fichas f
      left join cont c on c.clave = f.clave
  ),
  juntas as (
    select cn.jefe,
           count(distinct v.dia)                        as dias,
           sum(v.precio_cop)                            as plata,
           min(v.dia)                                   as primera,
           max(v.dia)                                   as ultima,
           mode() within group (order by v.hora)        as hora,
           (array_agg(v.tel order by v.dia desc))[1]    as tel,
           (array_agg(cn.nombre order by (cn.clave = cn.jefe) desc,
                                         length(cn.nombre) desc,
                                         cn.nombre collate "C"))[1] as nombre,
           count(distinct cn.clave)                     as escrituras
      from visitas v
      join canon cn on cn.clave = v.clave
     group by cn.jefe
  ),
  porcel as (
    select u.tel, count(distinct cn.jefe) as fichas
      from canon cn, unnest(cn.tels) as u(tel)
     group by u.tel
  ),
  tabla as (
    select j.*, p.fichas,
           row_number() over (order by j.dias desc, j.plata desc,
                                       j.ultima desc, j.nombre) as puesto,
           exists (select 1 from membresias m
                    where similitud_nombre(j.nombre, m.afiliado) >= 0.999
                      and m.fin >= v_hoy) as afiliada
      from juntas j join porcel p on p.tel = j.tel
  ),
  repes as (
    select u.tel,
           count(distinct cn.jefe) as cuantas,
           array_agg(distinct cn.nombre order by cn.nombre) as nombres
      from canon cn, unnest(cn.tels) as u(tel)
     group by u.tel
    having count(distinct cn.jefe) > 1
  )
  select
    coalesce((select jsonb_agg(jsonb_build_object(
           'puesto', t.puesto,
           'nombre', t.nombre,
           'telefono', t.tel,
           'dias', t.dias,
           'plata_cop', t.plata,
           'primera', t.primera,
           'ultima', t.ultima,
           'hace_dias', v_hoy - t.ultima,
           'hora', t.hora,
           'escrituras', t.escrituras,
           'fichas_del_telefono', t.fichas,
           'afiliada', t.afiliada)
           order by t.puesto)
        from tabla t where t.puesto <= v_lim), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
           'telefono', r.tel, 'nombres', r.nombres, 'cuantas', r.cuantas)
           order by r.cuantas desc, r.tel)
        from repes r), '[]'::jsonb)
    into v_lista, v_repetidas;

  return jsonb_build_object(
    'ok', true,
    'hoy', v_hoy,
    'desde', case when v_desde = '-infinity'::date then null else v_desde end,
    'dias_pedidos', p_dias,
    'clientes', v_lista,
    'telefonos_compartidos', v_repetidas,
    'solo_clase_suelta', true);
end;
$function$;

revoke execute on function public.clave_de(text, text) from public, anon, authenticated;

comment on function public.clave_de(text, text) is
  '0084: la regla de identidad (celular + nombre) sobre un nombre ya normalizado. '
  'cliente_clave() es la misma regla para quien llega con el nombre crudo.';
