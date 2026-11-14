-- 0087 · Tesorería: lo que entra, lo que sale y qué hay que mirar.
--
-- LO QUE PIDIÓ DAMIÁN (19 de septiembre)
-- «Un apartado de tesorería que me muestre cómo está el negocio,
--  entradas vs salidas, y qué cosas se deben revisar para tener más
--  utilidad. Te comparto un archivo con el gasto del negocio; vamos a
--  trabajar sobre agosto y septiembre, pero la idea es que esto se pueda
--  hacer para todo el año.»
--
-- ── EL AGUJERO QUE TAPA ─────────────────────────────────────────────
--
-- El panel ya sabía todo lo que ENTRA —`ventas_entre` es la misma regla
-- de la tirilla de cierre— y de lo que SALE solo conocía la caja menor.
-- En septiembre eso eran $120.000. El gasto de verdad del mes va por
-- $7.282.990. O sea que la tarjeta «Queda» del resumen venía diciendo
-- que quedaban nueve millones cuando quedaban dos.
--
-- No era un error de cálculo: era que el gasto real vivía en un grupo de
-- WhatsApp y no entraba a ninguna parte. Esta tabla es ese grupo,
-- pasado a filas.
--
-- ── LO QUE SALE, MEDIDO ─────────────────────────────────────────────
--
--   agosto completo      $11.986.900   contra $9.815.000 que entraron
--   septiembre 1 al 19   $ 7.282.990   contra $9.335.000 que entraron
--
-- Agosto cerró en pérdida y septiembre va en positivo. Los dos números
-- llevan avisos —abajo— y por eso la función no solo devuelve totales:
-- devuelve una lista de lo que hay que revisar antes de creérselos.
--
-- ── POR QUÉ UNA TABLA Y NO MÁS `caja_movimientos` ───────────────────
--
-- `caja_movimientos` es el cajón del mostrador: lo que entra y sale
-- durante el turno, y cuadra contra la tirilla de cierre. Meter ahí el
-- arriendo o la nómina descuadraría ese cierre todas las quincenas.
-- Son dos libros distintos y tienen que seguir siéndolo. La tesorería
-- los SUMA para enseñar el total, y cada renglón dice de cuál viene.
--
-- ── EL TEXTO SE GUARDA PALABRA POR PALABRA ──────────────────────────
--
-- `concepto` es lo que escribió Tanya, sin limpiar. Si mañana un número
-- no cuadra hay que poder volver al mensaje original; un concepto
-- «normalizado» pierde justo el dato que hace falta para entenderlo.
-- La categoría va aparte, en su columna, y es la que suma.
--
-- ── LOS ADELANTOS, QUE ES LO QUE MÁS ENGAÑA ─────────────────────────
--
-- Cuatro renglones son adelantos de quincena: $350.000 y $250.000 en
-- agosto, $350.000 del «ajuste de quincena» y $300.000 en septiembre.
-- Si la quincena se pagó después completa, ese dinero está contado DOS
-- veces y el gasto del mes sale inflado. No se puede decidir desde
-- aquí —hay que mirar el desprendible— así que se marcan con
-- `es_adelanto` y la tesorería los reporta aparte en vez de restarlos
-- por su cuenta. Restarlos sin saber sería inventarse una utilidad.

create table if not exists gastos (
  id          uuid primary key default extensions.gen_random_uuid(),
  dia         date not null,
  -- Lo que escribió Tanya, tal cual. No se limpia.
  concepto    text not null,
  categoria   text not null,
  valor_cop   int  not null,
  medio       text,           -- 'banco' | 'efectivo' | null si no se dijo
  a_quien     text,           -- el profe o la persona, cuando se sabe
  -- Un adelanto que se descuenta de una quincena posterior. Si no se
  -- marca, se cuenta dos veces: al adelantarlo y al pagar la quincena.
  es_adelanto boolean not null default false,
  -- Por qué este renglón hay que mirarlo a mano. Sale en la tesorería.
  revisar     text,
  fuente      text not null default 'whatsapp',
  nota        text,
  creado_at   timestamptz not null default now(),
  creado_por  uuid,
  anulado     boolean not null default false,
  constraint gastos_valor_ck     check (valor_cop > 0),
  constraint gastos_categoria_ck check (categoria in (
    'nomina', 'profesores', 'arriendo', 'sistema', 'mercadeo',
    'talleres', 'viaticos', 'mantenimiento', 'impuestos', 'otros')),
  constraint gastos_medio_ck     check (medio is null or medio in ('banco','efectivo')),
  constraint gastos_fuente_ck    check (fuente in ('whatsapp','mano','caja'))
);

comment on table gastos is
  '0087: el gasto real del negocio (nómina, arriendo, profes, sistema). '
  'Vivía en un grupo de WhatsApp y no entraba al sistema: el panel creía '
  'que en septiembre se habían gastado $120.000 cuando iban $7.282.990.';

-- Se consulta siempre por rango de fechas y casi siempre agrupando por
-- categoría: sin índice, cada visita a la pestaña recorre la tabla entera.
create index if not exists gastos_dia_ix on gastos (dia desc) where not anulado;
create index if not exists gastos_categoria_ix on gastos (categoria, dia desc) where not anulado;

-- Lleva a quién se le pagó y cuánto gana cada quien. Nadie llega con la
-- llave pública: todo pasa por funciones SECURITY DEFINER.
alter table gastos enable row level security;

-- ── los datos de agosto y septiembre ───────────────────────────────
-- Cargados una sola vez. El `where not exists` deja volver a correr la
-- migración sin duplicar: sin él, aplicarla dos veces duplica el gasto
-- del negocio entero.
insert into gastos (dia, valor_cop, concepto, categoria, medio, a_quien, es_adelanto, revisar)
select * from (values
  ('2026-08-01'::date,196900::int,'desayuno tumbao','otros','banco',null,false,null),
  ('2026-08-04',500000,'aporte viaje profe Fabián','viaticos','banco','Fabián',false,null),
  ('2026-08-04',330000,'avisos publicidad','mercadeo','banco',null,false,null),
  ('2026-08-06',50000,'postura ventilador','mantenimiento',null,null,false,null),
  ('2026-08-06',150000,'saldo aporte para competencia','viaticos',null,null,false,null),
  ('2026-08-06',350000,'adelanto quincena','nomina',null,null,true,'Adelanto de quincena. Si la quincena del 15 se pagó completa, este valor está contado dos veces.'),
  ('2026-08-06',1250000,'Bot tumbao','sistema',null,null,false,null),
  ('2026-08-08',60000,'clase Nagle','profesores','banco','Nagle',false,null),
  ('2026-08-08',60000,'Yeli','mercadeo',null,'Yeli',false,null),
  ('2026-08-10',250000,'adelanto Luisa','nomina','banco','Luisa',true,'Adelanto. La quincena de Luisa del 15 son $950.000: revisar si ya venía descontado.'),
  ('2026-08-10',80000,'pago Luz Alejandra','nomina','banco','Luz Alejandra',false,null),
  ('2026-08-11',180000,'clases lunes 3, martes 4, lunes 10','profesores','banco',null,false,null),
  ('2026-08-12',1800000,'retiro de bancos para pago de arriendo','arriendo','banco',null,false,'Es el RETIRO para pagar el arriendo, no el recibo. Confirmar que el arriendo de agosto se pagó con esta plata y no se registró aparte.'),
  ('2026-08-13',60000,'clase profe Nagle','profesores','banco','Nagle',false,null),
  ('2026-08-13',60000,'clase Milena','profesores','banco','Milena',false,null),
  ('2026-08-14',120000,'dos clases profe Milena, 6pm y 7pm viernes','profesores',null,'Milena',false,null),
  ('2026-08-15',600000,'saldo quincena Fabián','nomina','banco','Fabián',false,null),
  ('2026-08-15',60000,'clase Milena 8am sábado','profesores','banco','Milena',false,null),
  ('2026-08-15',60000,'clase profe Nagle 9am','profesores','banco','Nagle',false,null),
  ('2026-08-15',200000,'quincena redes Yeli','mercadeo','banco','Yeli',false,null),
  ('2026-08-15',950000,'quincena Luisa','nomina','banco','Luisa',false,null),
  ('2026-08-15',375000,'quincena Damián','nomina','banco','Damián',false,null),
  ('2026-08-15',350000,'ajuste de quincena','nomina','banco',null,true,'El mensaje dice «descuento en siguiente quincena»: es un adelanto, no un gasto nuevo. Contarlo aquí y pagar la quincena completa es contarlo dos veces.'),
  ('2026-08-15',240000,'camisetas tumbao','mercadeo',null,null,false,null),
  ('2026-08-17',60000,'clase momba','profesores','banco',null,false,null),
  ('2026-08-17',80000,'viáticos','viaticos','banco',null,false,null),
  ('2026-08-18',60000,'clase profe Vivi 7am martes','profesores','banco','Vivi',false,null),
  ('2026-08-18',105000,'AdminGym','sistema','banco',null,false,null),
  ('2026-08-18',60000,'clase profe Vivi martes 7pm','profesores','banco','Vivi',false,null),
  ('2026-08-19',60000,'profe Nagle','profesores','banco','Nagle',false,null),
  ('2026-08-20',25000,'celador','otros','banco',null,false,null),
  ('2026-08-21',60000,'clase Milena','profesores','banco','Milena',false,null),
  ('2026-08-22',60000,'Andrea profe zumba','profesores','banco','Andrea',false,null),
  ('2026-08-22',60000,'profe Nagle','profesores','banco','Nagle',false,null),
  ('2026-08-26',60000,'profe Vivi','profesores','banco','Vivi',false,null),
  ('2026-08-26',60000,'Nagle','profesores','banco','Nagle',false,null),
  ('2026-08-26',60000,'clase Fabián lunes','profesores','banco','Fabián',false,null),
  ('2026-08-27',200000,'salón taller','talleres','banco',null,false,null),
  ('2026-08-27',200000,'taller Silvia','talleres','banco','Silvia',false,null),
  ('2026-08-27',60000,'clase profe Milena','profesores',null,'Milena',false,null),
  ('2026-08-29',60000,'Nagle','profesores','banco','Nagle',false,null),
  ('2026-08-29',150000,'saldo taller Silvia','talleres','banco','Silvia',false,null),
  ('2026-08-29',650000,'quincena Fabián','nomina','banco','Fabián',false,null),
  ('2026-08-31',950000,'nómina Luisa','nomina','banco','Luisa',false,null),
  ('2026-08-31',375000,'nómina Damián','nomina','banco','Damián',false,null),
  ('2026-08-31',200000,'Yeli redes','mercadeo','banco','Yeli',false,null),
  ('2026-09-01',120000,'clases lunes y martes','profesores','banco',null,false,null),
  ('2026-09-02',517400,'PILA Fabián agosto','nomina','banco','Fabián',false,null),
  ('2026-09-02',60000,'clase profe Nagle','profesores','banco','Nagle',false,null),
  ('2026-09-04',60000,'Milena profe','profesores','banco','Milena',false,null),
  ('2026-09-05',60000,'clase profe Nagle','profesores','banco','Nagle',false,null),
  ('2026-09-08',200000,'Fabián: 60 lunes, 60 martes, 80 cumpleaños','profesores',null,'Fabián',false,null),
  ('2026-09-09',80000,'pago Luz Alejandra','nomina','banco','Luz Alejandra',false,null),
  ('2026-09-11',50000,'decoración y mantenimiento','mantenimiento','efectivo',null,false,null),
  ('2026-09-11',60000,'clase Milena','profesores','banco','Milena',false,null),
  ('2026-09-12',300000,'adelanto Fabián','nomina','banco','Fabián',true,'Adelanto. El 15 se pagó «saldo nómina quincena» de $650.000: revisar si ya venía descontado.'),
  ('2026-09-15',105000,'AdminGym','sistema','banco',null,false,null),
  ('2026-09-15',650000,'saldo nómina quincena','nomina','banco',null,false,null),
  ('2026-09-15',120000,'clases lunes y martes','profesores','banco',null,false,null),
  ('2026-09-15',1800000,'arriendo','arriendo','efectivo',null,false,null),
  ('2026-09-16',950000,'nómina Luisa quincena','nomina','banco','Luisa',false,null),
  ('2026-09-16',375000,'quincena Damián','nomina','banco','Damián',false,null),
  ('2026-09-16',15590,'aseo','mantenimiento',null,null,false,null),
  ('2026-09-16',1250000,'sistema tumbao','sistema','banco',null,false,null),
  ('2026-09-16',60000,'Nagle','profesores','banco','Nagle',false,null),
  ('2026-09-17',30000,'arreglo de luz del espejo','mantenimiento','banco',null,false,null),
  ('2026-09-17',60000,'Michael clase','profesores','banco','Michael',false,null),
  ('2026-09-17',60000,'clase profe Milena','profesores','banco','Milena',false,null),
  ('2026-09-18',180000,'clases Vivi','profesores','banco','Vivi',false,null),
  ('2026-09-19',60000,'clase sábado 8am','profesores','banco',null,false,null),
  ('2026-09-19',60000,'profe Nagle','profesores','banco','Nagle',false,null)
) as v(dia, valor_cop, concepto, categoria, medio, a_quien, es_adelanto, revisar)
where not exists (select 1 from gastos g where g.fuente = 'whatsapp');

-- ── la tesorería ───────────────────────────────────────────────────
--
-- Entradas contra salidas de un rango, con el mismo rango del mes
-- anterior al lado, y una lista de lo que hay que revisar.
--
-- LAS ENTRADAS SALEN DE `ventas_entre`, que es la regla de la tirilla de
-- cierre. No se recalculan aquí: dos pantallas que suman distinto el
-- mismo día es el problema del 5 de septiembre, cuando una hoja decía
-- 300.000 y la otra 315.000.
--
-- LO QUE REVISAR NO ES UN ADORNO. Damián pidió «qué cosas se deben
-- revisar para tener más utilidad», y eso no es una lista de consejos:
-- son los renglones concretos donde el número puede estar mal o donde
-- se está yendo la plata. Una pantalla que solo diga «utilidad:
-- −2.171.900» no sirve para hacer nada.
create or replace function public.admin_tesoreria(
  p_token text,
  p_desde date default null,
  p_hasta date default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_admin   record;
  v_hoy     date;
  v_desde   date;
  v_hasta   date;
  v_dias    int;
  v_adesde  date;
  v_ahasta  date;
  v_ent     jsonb;
  v_ent_a   jsonb;
  v_sal     bigint;
  v_sal_a   bigint;
  v_menor   bigint;
  v_menor_a bigint;
  v_ade     bigint;
  v_cat     jsonb;
  v_rev     jsonb := '[]'::jsonb;
  v_primer  date;
  v_util    bigint;
  v_util_a  bigint;
  v_n       int;
  v_cop     bigint;
  v_txt     text;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  -- La plata del negocio es del dueño y del administrador. La cajera ve
  -- su turno, no la nómina de sus compañeros.
  if v_admin.rol = 'cajero' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO',
      'mensaje', 'La tesorería es del propietario y el administrador.');
  end if;

  v_hoy   := (now() at time zone 'America/Bogota')::date;
  -- Sin rango, el mes en curso hasta hoy. Es lo que se mira al abrir.
  v_desde := coalesce(p_desde, date_trunc('month', v_hoy)::date);
  v_hasta := least(coalesce(p_hasta, v_hoy), v_hoy);
  if v_hasta < v_desde then v_hasta := v_desde; end if;
  v_dias  := (v_hasta - v_desde) + 1;

  -- El MISMO rango del mes anterior, no el mes anterior entero: comparar
  -- 19 días contra 31 da un porcentaje que no significa nada. Ya pasó
  -- con la tarjeta del resumen y el +180% de septiembre.
  v_adesde := (v_desde - interval '1 month')::date;
  v_ahasta := (v_hasta - interval '1 month')::date;

  v_ent   := ventas_entre(v_desde,  v_hasta);
  v_ent_a := ventas_entre(v_adesde, v_ahasta);

  select coalesce(sum(valor_cop), 0) into v_sal
    from gastos where not anulado and dia between v_desde and v_hasta;
  select coalesce(sum(valor_cop), 0) into v_sal_a
    from gastos where not anulado and dia between v_adesde and v_ahasta;
  select coalesce(sum(valor_cop), 0) into v_ade
    from gastos where not anulado and es_adelanto
      and dia between v_desde and v_hasta;

  -- La caja menor sigue siendo un libro aparte y se suma al total: si no,
  -- la tesorería diría menos de lo que de verdad salió.
  v_menor   := coalesce((v_ent->>'egreso_cop')::bigint, 0);
  v_menor_a := coalesce((v_ent_a->>'egreso_cop')::bigint, 0);
  v_sal     := v_sal + v_menor;
  v_sal_a   := v_sal_a + v_menor_a;

  v_util   := coalesce((v_ent->>'ingreso_cop')::bigint, 0)   - v_sal;
  v_util_a := coalesce((v_ent_a->>'ingreso_cop')::bigint, 0) - v_sal_a;

  -- ── por categoría, con lo del mes anterior al lado ────────────────
  -- La comparación por categoría es la que enseña dónde se está yendo
  -- la plata de más. Un total que sube no dice en qué.
  select coalesce(jsonb_agg(x order by x.cop desc), '[]'::jsonb) into v_cat
    from (
      select c.categoria,
             coalesce(a.cop, 0)::bigint as cop,
             coalesce(a.n, 0)           as n,
             coalesce(b.cop, 0)::bigint as cop_antes
        from (select distinct categoria from gastos
               where not anulado
                 and (dia between v_desde and v_hasta
                      or dia between v_adesde and v_ahasta)) c
        left join (select categoria, sum(valor_cop) as cop, count(*)::int as n
                     from gastos where not anulado and dia between v_desde and v_hasta
                    group by categoria) a on a.categoria = c.categoria
        left join (select categoria, sum(valor_cop) as cop
                     from gastos where not anulado and dia between v_adesde and v_ahasta
                    group by categoria) b on b.categoria = c.categoria
    ) x
   where x.cop > 0 or x.cop_antes > 0;

  -- ── qué revisar ───────────────────────────────────────────────────

  -- 1. Los adelantos. Es lo que más infla un mes.
  if v_ade > 0 then
    select count(*)::int into v_n from gastos
     where not anulado and es_adelanto and dia between v_desde and v_hasta;
    v_rev := v_rev || jsonb_build_object(
      'clave', 'adelantos', 'peso', 1, 'cop', v_ade,
      'titulo', 'Adelantos de quincena que pueden estar contados dos veces',
      'detalle', v_n || ' pago' || case when v_n = 1 then '' else 's' end ||
        ' de adelanto. Si la quincena se pagó después completa, este dinero ' ||
        'salió una vez pero está sumado dos, y la utilidad sale peor de lo que es.');
  end if;

  -- 2. Renglones que vienen con una nota de «mírame».
  select count(*)::int, coalesce(sum(valor_cop), 0)
    into v_n, v_cop
    from gastos where not anulado and revisar is not null
      and dia between v_desde and v_hasta;
  if v_n > 0 then
    v_rev := v_rev || jsonb_build_object(
      'clave', 'con_nota', 'peso', 2, 'cop', v_cop,
      'titulo', v_n || ' gasto' || case when v_n = 1 then '' else 's' end ||
                ' con algo por confirmar',
      'detalle', 'Ábrelos abajo: cada uno dice qué hay que mirar.');
  end if;

  -- 3. Mismo día y mismo valor: o se pagó dos veces, o se anotó dos
  --    veces. Las dos cosas hay que saberlas.
  select count(*)::int, coalesce(sum(cop), 0) into v_n, v_cop
    from (select dia, valor_cop as cop from gastos
           where not anulado and dia between v_desde and v_hasta
           group by dia, valor_cop having count(*) > 1) d;
  if v_n > 0 then
    v_rev := v_rev || jsonb_build_object(
      'clave', 'repetidos', 'peso', 3, 'cop', v_cop,
      'titulo', v_n || ' pago' || case when v_n = 1 then '' else 's' end ||
                ' repetido' || case when v_n = 1 then '' else 's' end ||
                ' el mismo día por el mismo valor',
      'detalle', 'Puede ser correcto —dos clases del mismo profe el mismo ' ||
                 'día valen igual— o puede ser el mismo pago anotado dos veces.');
  end if;

  -- 4. La categoría que más creció. Es la respuesta corta a «dónde se
  --    me fue la plata».
  select x.categoria, x.cop - x.antes into v_txt, v_cop
    from (select categoria,
                 coalesce(sum(valor_cop) filter (where dia between v_desde and v_hasta), 0) as cop,
                 coalesce(sum(valor_cop) filter (where dia between v_adesde and v_ahasta), 0) as antes
            from gastos where not anulado
             and (dia between v_desde and v_hasta or dia between v_adesde and v_ahasta)
           group by categoria) x
   where x.antes > 0 and x.cop > x.antes
   order by x.cop - x.antes desc limit 1;
  if v_txt is not null then
    v_rev := v_rev || jsonb_build_object(
      'clave', 'subio', 'peso', 4, 'cop', v_cop, 'categoria', v_txt,
      'titulo', 'Lo que más subió contra el mismo tramo del mes pasado: ' || v_txt,
      -- El número ya viaja en `cop` y lo formatea el panel. to_char con
      -- 'G' usa la coma del locale y sale «320,000», que en Colombia se
      -- lee como trescientos veinte.
      'detalle', 'Es lo que más creció contra el mes pasado en las mismas fechas.');
  end if;

  -- 5. La Caja no existía al principio: comparar contra un mes en el que
  --    no se registraba todo da un porcentaje que miente.
  select min(dia) into v_primer from caja_movimientos where not anulado;
  if v_primer is not null and v_adesde < v_primer then
    v_rev := v_rev || jsonb_build_object(
      'clave', 'antes_incompleto', 'peso', 5, 'cop', 0,
      'titulo', 'El periodo con el que se compara está incompleto',
      'detalle', 'La Caja empezó a registrar el ' ||
                 to_char(v_primer, 'DD/MM') || ', así que lo de antes de esa ' ||
                 'fecha tiene menos ingresos de los que hubo. La comparación ' ||
                 'se ve mejor de lo que fue.');
  end if;

  -- 6. Un mes sin gastos cargados no es un mes sin gastos.
  select count(*)::int into v_n from gastos
   where not anulado and dia between v_desde and v_hasta;
  if v_n = 0 then
    v_rev := jsonb_build_object(
      'clave', 'sin_gastos', 'peso', 0, 'cop', 0,
      'titulo', 'Este periodo no tiene gastos cargados',
      'detalle', 'Solo se ve la caja menor. La utilidad de arriba no es real ' ||
                 'hasta que se carguen la nómina, el arriendo y los profes.')
      || v_rev;
  end if;

  return jsonb_build_object(
    'ok', true,
    'hoy', v_hoy,
    'desde', v_desde, 'hasta', v_hasta, 'dias', v_dias,
    'antes_desde', v_adesde, 'antes_hasta', v_ahasta,
    'entradas', v_ent,
    'entradas_antes', v_ent_a,
    'salidas_cop', v_sal,
    'salidas_antes_cop', v_sal_a,
    'caja_menor_cop', v_menor,
    'adelantos_cop', v_ade,
    -- La utilidad SIN los adelantos, para poder ver las dos. No se
    -- elige por él cuál es la buena: eso depende del desprendible.
    'utilidad_cop', v_util,
    'utilidad_sin_adelantos_cop', v_util + v_ade,
    'utilidad_antes_cop', v_util_a,
    'margen_pct', case when coalesce((v_ent->>'ingreso_cop')::bigint, 0) = 0 then null
                       else round(v_util * 100.0 /
                                  (v_ent->>'ingreso_cop')::bigint) end,
    'categorias', v_cat,
    'revisar', (select coalesce(jsonb_agg(r order by (r->>'peso')::int), '[]'::jsonb)
                  from jsonb_array_elements(v_rev) r));
end;
$function$;

revoke all on function public.admin_tesoreria(text, date, date)
  from public, anon, authenticated;
grant execute on function public.admin_tesoreria(text, date, date) to service_role;

-- ── el detalle, cuando se quiere abrir un renglón ──────────────────
-- Aparte de la tesorería a propósito: son dos preguntas distintas —«¿cómo
-- vamos?» y «¿qué fue ese pago?»— y la primera se hace todos los días y
-- la segunda una vez al mes. Traer 71 renglones para pintar 9 totales
-- sería pagar el detalle siempre.
create or replace function public.admin_gastos_lista(
  p_token     text,
  p_desde     date default null,
  p_hasta     date default null,
  p_categoria text default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_admin record;
  v_hoy   date;
  v_desde date;
  v_hasta date;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if v_admin.rol = 'cajero' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO',
      'mensaje', 'La tesorería es del propietario y el administrador.');
  end if;

  v_hoy   := (now() at time zone 'America/Bogota')::date;
  v_desde := coalesce(p_desde, date_trunc('month', v_hoy)::date);
  v_hasta := least(coalesce(p_hasta, v_hoy), v_hoy);

  return jsonb_build_object(
    'ok', true,
    'gastos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', g.id, 'dia', g.dia,
               'concepto', g.concepto, 'categoria', g.categoria,
               'cop', g.valor_cop, 'medio', g.medio, 'a_quien', g.a_quien,
               'es_adelanto', g.es_adelanto, 'revisar', g.revisar,
               'fuente', g.fuente)
             order by g.dia desc, g.valor_cop desc)
        from gastos g
       where not g.anulado
         and g.dia between v_desde and v_hasta
         and (p_categoria is null or g.categoria = p_categoria)), '[]'::jsonb),
    -- La caja menor va en la misma lista, marcada: si saliera aparte,
    -- el total de arriba no cuadraría con lo que se ve abajo.
    'caja_menor', coalesce((
      select jsonb_agg(jsonb_build_object(
               'dia', m.dia, 'concepto', m.concepto,
               'cop', m.valor_cop, 'medio', m.medio)
             order by m.dia desc)
        from caja_movimientos m
       where m.sentido = 'egreso' and not m.anulado
         and m.dia between v_desde and v_hasta), '[]'::jsonb));
end;
$function$;

revoke all on function public.admin_gastos_lista(text, date, date, text)
  from public, anon, authenticated;
grant execute on function public.admin_gastos_lista(text, date, date, text)
  to service_role;

-- ── apuntar un gasto desde el panel ────────────────────────────────
-- Para que cargar el resto del año no dependa de que yo esté aquí.
create or replace function public.admin_gasto_apuntar(
  p_token     text,
  p_dia       date,
  p_valor_cop int,
  p_concepto  text,
  p_categoria text,
  p_medio     text default null,
  p_a_quien   text default null,
  p_adelanto  boolean default false
) returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_admin record;
  v_id    uuid;
  v_hoy   date;
begin
  select * into v_admin from verificar_token_admin_rol(p_token);
  if v_admin.id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if v_admin.rol = 'cajero' then
    return jsonb_build_object('ok', false, 'error', 'SIN_PERMISO',
      'mensaje', 'Los gastos del negocio los apunta el propietario o el administrador.');
  end if;

  if coalesce(p_valor_cop, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'VALOR',
      'mensaje', 'El valor tiene que ser mayor que cero.');
  end if;
  if length(btrim(coalesce(p_concepto, ''))) < 2 then
    return jsonb_build_object('ok', false, 'error', 'CONCEPTO',
      'mensaje', 'Escribe qué se pagó.');
  end if;

  v_hoy := (now() at time zone 'America/Bogota')::date;
  -- Una fecha futura es una errata de tecleo, no un gasto. Y más de dos
  -- años atrás, también.
  if p_dia is null or p_dia > v_hoy or p_dia < v_hoy - 730 then
    return jsonb_build_object('ok', false, 'error', 'FECHA',
      'mensaje', 'La fecha tiene que ser de hoy o de antes, y no de hace años.');
  end if;

  begin
    insert into gastos (dia, valor_cop, concepto, categoria, medio, a_quien,
                        es_adelanto, fuente, creado_por)
    values (p_dia, p_valor_cop, btrim(p_concepto), p_categoria,
            nullif(btrim(coalesce(p_medio, '')), ''),
            nullif(btrim(coalesce(p_a_quien, '')), ''),
            coalesce(p_adelanto, false), 'mano', v_admin.id)
    returning id into v_id;
  exception when check_violation then
    return jsonb_build_object('ok', false, 'error', 'CATEGORIA',
      'mensaje', 'Esa categoría o ese medio de pago no existen.');
  end;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$function$;

revoke all on function public.admin_gasto_apuntar(text, date, int, text, text, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.admin_gasto_apuntar(text, date, int, text, text, text, text, boolean)
  to service_role;
