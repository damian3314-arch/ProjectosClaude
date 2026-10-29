-- 0178 · La pausa de renovaciones se acota a «ya se les venció la mensualidad»
--
-- 13 oct, más tarde: Damián aclaró que lo único que pidió pausar son los avisos a los clientes a quienes ya se les
-- venció la mensualidad para invitarlos a renovar. 0177 había pausado de más (también el aviso de «te vence en 3 días»,
-- las ofertas de mensualidad del bot de ventas y su seguimiento). Esta migración lo deja así, hasta
-- ajustes.renovacion_pausa_hasta (18 de octubre, inclusive; se levanta sola el lunes 19):
--   · renovacion_automatica(): ya no corta todo. Solo se salta la parte de «ya venció» (fin entre hoy-2 y hoy). La parte
--     de «te vence en 1 a 3 días» (fin entre hoy+1 y hoy+3) sigue saliendo.
--   · ventas_candidatos() y ventas_seguimientos_tomar(): vuelven a como estaban antes de 0177 (el bot propone
--     mensualidades de 7 am y de 6 pm y el seguimiento les escribe a esos chats).
-- Para levantarla antes: update ajustes set valor = '' where clave = 'renovacion_pausa_hasta';

update ajustes
   set nota = 'Pausa SOLO de los avisos de renovación a quien ya se le venció la mensualidad (el aviso de «ya venció», de 2 días antes a 2 después del fin), hasta esta fecha inclusive (0178). Pedido de Damián el 13-oct: esa semana ya se avisó desde recepción. El aviso de «te vence en 3 días», el bot de ventas y la lista de espera siguen normales. Se levanta sola.',
       updated_at = now()
 where clave = 'renovacion_pausa_hasta';

do $$
declare
  d text;
  nuevo text;
begin
  -- 1 · aviso diario: ya no sale del todo; solo se salta la parte de «ya venció»
  d := pg_get_functiondef('public.renovacion_automatica()'::regprocedure);
  if position('en_pausa' in d) > 0 then
    raise notice '0178: renovacion_automatica ya estaba acotada';
  else
    nuevo := replace(d,
$a$  if hoy <= coalesce(nullif((select valor from ajustes where clave = 'renovacion_pausa_hasta'), '')::date, date '2000-01-01') then
    return jsonb_build_object('ok', true, 'activo', true, 'motivo', 'pausa_hasta');
  end if;
$a$, '');
    if nuevo = d then raise exception '0178: no encontré el bloque de pausa en renovacion_automatica'; end if;
    d := nuevo;
    nuevo := replace(d,
$a$  n_rec  int := 0;
begin
$a$,
$b$  n_rec  int := 0;
  en_pausa boolean := hoy <= coalesce(nullif((select valor from ajustes where clave = 'renovacion_pausa_hasta'), '')::date, date '2000-01-01');
begin
$b$);
    if nuevo = d then raise exception '0178: no encontré la declaración en renovacion_automatica'; end if;
    d := nuevo;
    nuevo := replace(d,
$a$     where e.fin between hoy - 2 and hoy
$a$,
$b$     where e.fin between hoy - 2 and hoy and not en_pausa
$b$);
    if nuevo = d then raise exception '0178: no encontré el filtro de «ya venció» en renovacion_automatica'; end if;
    execute nuevo;
  end if;

  -- 2 · el bot de ventas vuelve a proponer mensualidades
  d := pg_get_functiondef('public.ventas_candidatos(integer)'::regprocedure);
  if position('renovacion_pausa_hasta' in d) = 0 then
    raise notice '0178: ventas_candidatos ya estaba normal';
  else
    nuevo := replace(d,
$a$  if hoy <= coalesce(nullif((select valor from ajustes where clave = 'renovacion_pausa_hasta'), '')::date, date '2000-01-01') then
    v_l7 := 0; v_l6 := 0;
  end if;

$a$, '');
    if nuevo = d then raise exception '0178: no encontré el bloque de pausa en ventas_candidatos'; end if;
    execute nuevo;
  end if;

  -- 3 · el seguimiento vuelve a escribirle a los chats de mensualidad
  d := pg_get_functiondef('public.ventas_seguimientos_tomar(integer)'::regprocedure);
  if position('renovacion_pausa_hasta' in d) = 0 then
    raise notice '0178: ventas_seguimientos_tomar ya estaba normal';
  else
    nuevo := replace(d,
$a$       and not (c.objetivo like 'mensualidad%'
                and hoy <= coalesce(nullif((select valor from ajustes where clave = 'renovacion_pausa_hasta'), '')::date, date '2000-01-01'))
$a$, '');
    if nuevo = d then raise exception '0178: no encontré el bloque de pausa en ventas_seguimientos_tomar'; end if;
    execute nuevo;
  end if;
end $$;
