-- 0083 · Quién es quién, y quién viene más.
--
-- Damián: «el ranking fijo sería útil y la identificación es el número de
-- celular + el nombre del cliente».
--
-- ── POR QUÉ HACÍA FALTA QUE ÉL DIJERA LA REGLA ──────────────────────
--
-- Esta base no tiene clientes. Tiene RESERVAS, cada una con un nombre y
-- un teléfono escritos a mano en el momento. Para rankear hay que decidir
-- qué filas son la misma persona, y las dos llaves obvias fallan cada una
-- por su lado. Medido sobre los datos del 12 de septiembre de 2026:
--
--   · 173 teléfonos distintos y 268 escrituras de nombre
--   · 69 de esos 173 teléfonos tienen MÁS DE UN NOMBRE
--
-- Solo el teléfono junta a gente distinta: quien reserva para el grupo
-- pone su número para las tres. Coronaría a «la que organiza al grupo».
-- Solo el nombre parte a una misma persona: Ludys aparece como «Ludys
-- Herazo», «Ludys herazo», «ludis herazo», «LUDIS HERAZO» y «Ludys
-- haerazo».
--
-- Celular + nombre es la regla correcta: el teléfono acota, el nombre
-- separa a las amigas que comparten ese teléfono.
--
-- ── CÓMO SE REPARTEN EL TRABAJO LOS DOS CAMPOS ──────────────────────
--
-- «Celular + nombre» no puede ser un pegado literal de los dos textos,
-- porque entonces la misma persona que reserva un día desde el teléfono
-- de una amiga y otro día desde el suyo sale como dos clientas. Medido
-- sobre los datos:
--
--   15 nombres aparecen en DOS teléfonos distintos
--   los 15 son de dos palabras o más
--   ninguno de una sola palabra aparece en más de un teléfono
--
-- Y los 15 se leen como una sola persona: Karen Yepes, Saray Lozada,
-- Jacky Benavides, Carolina Carreño, Jessica Paba, Julieth Herrera… Son
-- quien reservó una semana desde el número de la amiga y la siguiente
-- desde el propio. Con el pegado literal, Karen Yepes sale partida en 3
-- y 2 días y se cae del ranking; y las tres del trío de los jueves con
-- ella.
--
-- Así que cada campo hace lo que sabe hacer:
--
--   · el NOMBRE identifica, cuando tiene dos palabras o más: un nombre
--     y un apellido ya distinguen a una persona dentro de esta academia;
--   · el CELULAR entra donde el nombre no alcanza — los nombres de una
--     sola palabra («Paloma», «Yira», «Laura», «doris»), que sí podrían
--     ser dos personas distintas y se separan por número.
--
-- Es la regla que pidió Damián, con los dos campos puestos donde cada
-- uno aporta. Si en el futuro aparecieran dos clientas que se llaman
-- exactamente igual, habría que apoyarse en el teléfono también para
-- los nombres largos; hoy no hay ni un caso.
--
-- ── LO QUE LA REGLA NECESITA PARA FUNCIONAR ─────────────────────────
--
-- Tomada al pie de la letra —el texto tal cual— «Ludys Herazo» y «ludys
-- herazo» serían dos clientas. Así que el nombre se normaliza antes de
-- comparar: sin tildes, en mayúscula, partido en palabras de 3 letras o
-- más y ordenado. Eso se lleva de una:
--
--   mayúsculas        Andrea Ospino = ANDREA OSPINO
--   tildes            Mónica Niño   = Monica Nino
--   orden             Silvia Ayala  = Ayala Silvia
--   partículas        Ana de la Cruz = Ana Cruz   (de, la, y se caen)
--
-- Y UNA FUSIÓN MÁS, la del subconjunto: cuando dos fichas comparten un
-- teléfono y un nombre está entero dentro del otro, es la misma persona
-- escribiendo más o menos de su nombre.
--
--   «Yira»        ⊂ «Yira Zahira»
--   «Jessica Paba» ⊂ «Jessica Paba Campos»
--   «Karen Yepes»  ⊂ «Karen Vivian Yepes»
--
-- Sin esta fusión Yira sale partida en 4 y 3 días y se cae del ranking
-- entero, que es peor que no tener ranking: un ranking equivocado se
-- cree igual.
--
-- La fusión exige que haya UN SOLO candidato que la contenga. Si en un
-- teléfono hay «Karen», «Karen Yepes» y «Karen Herrera», «Karen» podría
-- ser cualquiera de las dos y no se adivina: se deja aparte y se avisa.
--
-- ── LO QUE LA REGLA NO PUEDE ARREGLAR, Y POR ESO SE ENSEÑA ──────────
--
-- Una errata de tecleo parte a la persona y ninguna regla honesta lo
-- impide: «LUDIS» y «LUDYS» no se parecen más que «KAREN YEPES» y «KAREN
-- HERRERA», que SÍ son dos personas. Poner un umbral de parecido aquí
-- sería jugar a los dados con la ficha de una clienta.
--
-- Así que en vez de adivinar, el ranking devuelve `fichas_del_telefono`:
-- cuántas fichas distintas cuelgan de ese mismo número. Cuando son
-- varias, el panel lo dice y una persona mira y decide. Ludys sale con 8
-- días y un aviso de que hay 4 fichas más en su teléfono, en vez de
-- salir con 11 porque yo decidí por mi cuenta que eran la misma.
--
-- ── LA VENTANA DE «ENTRÓ» ES LA DE LA TIRILLA ───────────────────────
--
-- Se cuenta a quien ENTRÓ, con la misma regla de la 0071 que usan el
-- cierre y las tarjetas: confirmada, suelta, sin marca de no_vino y sin
-- reprogramar, fechada por el día de la CLASE. Si este ranking contara
-- con otra regla, diría que alguien vino 9 veces mientras el cierre de
-- esos días contó 8, y no habría forma de saber cuál miente.
--
-- ── LO QUE ESTE RANKING NO MIDE, DICHO AQUÍ PARA QUE NO SE OLVIDE ───
--
-- Solo la CLASE SUELTA. `asistencias` tiene 378 marcas y las 378 son de
-- una reserva: ninguna de una mensualidad. Las afiliadas no generan
-- reserva ni marca, así que las personas que de verdad más vienen —las
-- que pagan por venir tres y cuatro veces por semana— no están en este
-- ranking ni pueden estar. Por eso la función devuelve `afiliada`: para
-- que al menos se vea quién de la lista ya tiene plan, y quién no.

-- El nombre comparable: sin tildes, en mayúscula, sin partículas y
-- ordenado, para que «Mónica Niño» y «NINO MONICA» sean lo mismo.
--
-- Va ANTES de cliente_clave a propósito: una función SQL se valida al
-- crearla, así que si la llamada apareciera primero, la migración
-- fallaría con «no existe nombre_normalizado».
create or replace function public.nombre_normalizado(p_nombre text)
returns text
language sql
immutable
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
  select coalesce((select string_agg(t, ' ' order by t)
            from (select distinct t
                    from regexp_split_to_table(
                           upper(extensions.unaccent(coalesce(p_nombre, ''))),
                           '[^A-Z]+') t
                   -- 3 letras: se caen «de», «la», «y» y las iniciales
                   -- sueltas, que es lo que hace que el mismo nombre
                   -- escrito con y sin segundo apellido no cuadre.
                   where length(t) >= 3) x), '');
$function$;

-- ── la identidad de un cliente: celular + nombre ────────────────────
--
-- El nombre manda cuando trae dos palabras o más. El celular se le pega
-- delante cuando es de una sola, que es donde el nombre no alcanza para
-- distinguir a dos personas.
create or replace function public.cliente_clave(p_nombre text, p_telefono text)
returns text
language sql
immutable
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
  select case
    when position(' ' in nombre_normalizado(p_nombre)) > 0
      then nombre_normalizado(p_nombre)
    else right(regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g'), 10)
         || '|' || nombre_normalizado(p_nombre)
  end;
$function$;

-- ── el ranking ──────────────────────────────────────────────────────
create or replace function public.admin_clientes_ranking(
  p_token  text,
  p_dias   int default null,     -- null = desde que hay datos
  p_limite int default 10)
returns jsonb
language plpgsql
-- VOLATILE obligatorio: verificar_token_admin_rol actualiza ultimo_uso y
-- una STABLE corre en transacción de solo lectura (lo que rompió
-- /api/mensualidad en la 0073).
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
  -- Nombres, teléfonos y cuánto paga cada quien: lo ve quien manda. Un
  -- token de antes de los roles (rol nulo) sigue viendo todo.
  if v_admin.rol = 'cajero' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO',
      'mensaje', 'Esta vista es del propietario y el administrador.');
  end if;

  v_hoy   := (now() at time zone 'America/Bogota')::date;
  -- Un p_dias absurdo no debe poder pedir un barrido infinito ni cero.
  v_desde := case when p_dias is null or p_dias < 1 then '-infinity'::date
                  else v_hoy - (least(p_dias, 3650) - 1) end;
  v_lim   := least(greatest(coalesce(p_limite, 10), 1), 50);

  with visitas as (
    -- 0071: quien ENTRÓ. Palabra por palabra la regla del cierre.
    select cliente_clave(r.nombre, r.telefono) as clave,
           right(regexp_replace(coalesce(r.telefono,''), '\D', '', 'g'), 10) as tel,
           nombre_normalizado(r.nombre) as norma,
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
     where r.estado = 'confirmada' and r.tipo = 'suelta'
       and r.no_vino_at is null and r.reprogramada_a is null
       and (c.fecha_hora at time zone 'America/Bogota')::date
             between v_desde and v_hoy
  ),
  fichas as (
    select clave,
           -- Una ficha puede colgar de dos teléfonos: quien reservó una
           -- semana desde el número de la amiga y otra desde el suyo.
           array_agg(distinct tel) as tels,
           -- La escritura que se enseña: la más larga —la que más se
           -- parece a cómo se llama de verdad— y, entre dos del mismo
           -- largo, la bien escrita. Sin el desempate salía «yira
           -- zahira» y «Ludys herazo»: el orden por defecto del idioma
           -- no distingue mayúsculas, así que elegía al azar entre
           -- «Ludys Herazo» y «Ludys herazo». `collate "C"` sí ordena
           -- por código de letra y lo vuelve estable.
           (array_agg(nombre order by length(nombre) desc, bien_escrito desc,
                                      nombre collate "C"))[1] as nombre,
           string_to_array(nullif(max(norma), ''), ' ') as tokens
      from visitas
     group by clave
  ),
  -- La fusión del subconjunto: solo entre fichas que COMPARTEN un
  -- teléfono, y solo cuando hay UN candidato que la contenga. Con dos es
  -- ambiguo y no se toca.
  --
  -- Una cadena («Yira» ⊂ «Yira Zahira» ⊂ «Yira Zahira Díaz») deja a la
  -- primera con dos candidatos, así que no se fusiona. Es conservador a
  -- propósito: preferible dos fichas y un aviso que una fusión a dedo.
  cont as (
    select f.clave,
           count(*) as cuantos,
           (array_agg(g.clave order by cardinality(g.tokens) desc, g.clave))[1] as jefe
      from fichas f
      join fichas g
        on g.tels && f.tels               -- comparten algún teléfono
       and g.clave <> f.clave
       and f.tokens <@ g.tokens           -- f está entero dentro de g
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
           -- El teléfono que se enseña es el de la visita más reciente:
           -- es el número por el que hay que llamarla hoy.
           (array_agg(v.tel order by v.dia desc))[1]    as tel,
           -- Cuando se fusionaron varias escrituras, se enseña la del
           -- jefe, que es la más completa.
           (array_agg(cn.nombre order by (cn.clave = cn.jefe) desc,
                                         length(cn.nombre) desc,
                                         cn.nombre collate "C"))[1] as nombre,
           count(distinct cn.clave)                     as escrituras
      from visitas v
      join canon cn on cn.clave = v.clave
     group by cn.jefe
  ),
  -- Cuántas fichas distintas cuelgan del mismo teléfono DESPUÉS de
  -- fusionar. Más de una puede ser un grupo de amigas (correcto) o una
  -- errata que partió a alguien (hay que mirarlo). Se cuenta sobre TODOS
  -- los teléfonos de cada ficha, no solo el último que usó.
  porcel as (
    select u.tel, count(distinct cn.jefe) as fichas
      from canon cn, unnest(cn.tels) as u(tel)
     group by u.tel
  ),
  -- El ranking y el aviso salen de la MISMA cuenta, en una sola
  -- consulta. Calcularlos aparte ya había salido mal antes en esta casa:
  -- el aviso contaría fichas sin fusionar y diría que Yira está repetida
  -- justo cuando el ranking acaba de juntarla.
  tabla as (
    select j.*, p.fichas,
           row_number() over (order by j.dias desc, j.plata desc,
                                       j.ultima desc, j.nombre) as puesto,
           -- ¿Ya tiene plan? Se exige que TODAS las palabras del nombre
           -- estén en el del afiliado, no un parecido a medias: con un
           -- umbral flojo, «Carolina» casaría con cualquier Carolina.
           exists (select 1 from membresias m
                    where similitud_nombre(j.nombre, m.afiliado) >= 0.999
                      and m.fin >= v_hoy) as afiliada
      from juntas j join porcel p on p.tel = j.tel
  ),
  -- Los teléfonos con más de una ficha, para que una persona los mire.
  -- Es el límite de la regla puesto a la vista en vez de tapado.
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
    -- Dicho en la respuesta y no solo en un comentario: quien lea esto
    -- por la API tiene que enterarse igual que quien mira el panel.
    'solo_clase_suelta', true);
end;
$function$;

revoke execute on function public.cliente_clave(text, text)       from public, anon, authenticated;
revoke execute on function public.nombre_normalizado(text)        from public, anon, authenticated;
revoke execute on function public.admin_clientes_ranking(text, int, int)
  from public, anon, authenticated;
grant execute on function public.admin_clientes_ranking(text, int, int) to service_role;

comment on function public.cliente_clave(text, text) is
  '0083: la identidad de un cliente que fijó Damián — celular + nombre, '
  'con el nombre normalizado para que la misma persona no se parta por una tilde.';
