-- 0177 · Pausa de los avisos de renovación (semana del 13 al 18 de octubre)
--
-- 13 oct: Damián pidió que esta semana no se envíen mensajes invitando a renovar, porque recepción ya los mandó a
-- mano. Se pausa por una fecha en lugar de apagar el interruptor, para que se levante sola el lunes 19 y nadie tenga
-- que acordarse de encenderla:
--   ajustes.renovacion_pausa_hasta = '2026-10-18'   (inclusive; vacío o fecha pasada = sin pausa)
-- Qué se pausa mientras la fecha no haya pasado:
--   1. renovacion_automatica(): no encola el aviso diario de renovación (3 días antes / el día / 2 días después).
--   2. ventas_candidatos(): el bot de ventas no abre chats nuevos de mensualidad de 7 am ni de 6 pm (los cupos de
--      mensualidad quedan en 0 para la selección); sigue con «reactivar» y «tiquetera».
--   3. ventas_seguimientos_tomar(): no le escribe el seguimiento a quien tiene un chat abierto de mensualidad.
-- Qué NO se toca: el aviso de lista de espera (alguien que pidió cupo y se le abrió uno), las confirmaciones de
-- reserva, el rescate de tiqueteras, las respuestas a quien escribe, ni lo que ya se haya enviado.
-- Para levantarla antes: update ajustes set valor = '' where clave = 'renovacion_pausa_hasta';

insert into ajustes (clave, valor, nota)
values ('renovacion_pausa_hasta', '2026-10-18',
        'Pausa de los avisos automáticos de renovación y de las ofertas de mensualidad del bot de ventas, hasta esta fecha inclusive (0177). Pedido de Damián el 13-oct: esa semana ya se avisó desde recepción. Se levanta sola.')
on conflict (clave) do update set valor = excluded.valor, nota = excluded.nota, updated_at = now();

do $$
declare
  v_def text;
  v_nuevo text;
begin
  -- 1 · aviso diario de renovación
  v_def := pg_get_functiondef('public.renovacion_automatica()'::regprocedure);
  if position('renovacion_pausa_hasta' in v_def) > 0 then
    raise notice '0177: renovacion_automatica ya tenía la pausa';
  else
    v_nuevo := replace(v_def,
$a$  if extract(isodow from hoy) = 7 or exists (select 1 from festivos where fecha = hoy) then
$a$,
$b$  if hoy <= coalesce(nullif((select valor from ajustes where clave = 'renovacion_pausa_hasta'), '')::date, date '2000-01-01') then
    return jsonb_build_object('ok', true, 'activo', true, 'motivo', 'pausa_hasta');
  end if;
  if extract(isodow from hoy) = 7 or exists (select 1 from festivos where fecha = hoy) then
$b$);
    if v_nuevo = v_def then raise exception '0177: no encontré el ancla en renovacion_automatica'; end if;
    execute v_nuevo;
  end if;

  -- 2 · el bot de ventas no abre chats nuevos de mensualidad
  v_def := pg_get_functiondef('public.ventas_candidatos(integer)'::regprocedure);
  if position('renovacion_pausa_hasta' in v_def) > 0 then
    raise notice '0177: ventas_candidatos ya tenía la pausa';
  else
    v_nuevo := replace(v_def,
$a$  return query
  with vig as ($a$,
$b$  if hoy <= coalesce(nullif((select valor from ajustes where clave = 'renovacion_pausa_hasta'), '')::date, date '2000-01-01') then
    v_l7 := 0; v_l6 := 0;
  end if;

  return query
  with vig as ($b$);
    if v_nuevo = v_def then raise exception '0177: no encontré el ancla en ventas_candidatos'; end if;
    execute v_nuevo;
  end if;

  -- 3 · el seguimiento no toca los chats abiertos de mensualidad
  v_def := pg_get_functiondef('public.ventas_seguimientos_tomar(integer)'::regprocedure);
  if position('renovacion_pausa_hasta' in v_def) > 0 then
    raise notice '0177: ventas_seguimientos_tomar ya tenía la pausa';
  else
    v_nuevo := replace(v_def,
$a$       and c.interes in ('alto', 'medio')
$a$,
$b$       and c.interes in ('alto', 'medio')
       and not (c.objetivo like 'mensualidad%'
                and hoy <= coalesce(nullif((select valor from ajustes where clave = 'renovacion_pausa_hasta'), '')::date, date '2000-01-01'))
$b$);
    if v_nuevo = v_def then raise exception '0177: no encontré el ancla en ventas_seguimientos_tomar'; end if;
    execute v_nuevo;
  end if;
end $$;
