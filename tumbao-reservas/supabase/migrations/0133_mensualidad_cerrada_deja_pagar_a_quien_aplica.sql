-- 0133 · En un horario de mensualidad cerrado (6 pm / 7 pm), quien CUMPLE los requisitos puede pagar
--
-- Damián (2 oct): «la idea es que en el futuro la gente se apunta, el sistema de una
-- revisa si aplica y, si aplica, le dice que ya puede pagar».
--
-- Hasta hoy, en un horario sin cupo (tope 0) todo el que se apuntaba caía en
-- lista_espera, aunque cumpliera los requisitos del grupo premium (0129). Ahora,
-- al apuntarse (o al volver a apuntarse), mensualidad_solicitar() pregunta a
-- premium_puede_pagar():
--   · la persona se identifica por CELULAR o CÉDULA (nunca solo por nombre),
--   · hay una sola con ese dato y su veredicto es «aplica»,
--   · el premium sigue vigente (premium_vigente_hasta),
--   · y el horario no pasa de premium_cupo_max (25) contando activas, apartadas y pagadas.
-- Si todo se cumple, queda en 'esperando_pago' y la página le muestra el pago de una
-- vez ('por_requisitos': true). Si no, sigue en lista_espera, como siempre. El cupo
-- público (tope) no cambia: quien no cumple no puede comprar en un horario cerrado.

create or replace function public.premium_puede_pagar(p_celular text, p_documento text, p_hora time)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_max int := coalesce((select valor from ajustes where clave = 'premium_cupo_max'), '25')::int;
  v_hasta date := nullif((select valor from ajustes where clave = 'premium_vigente_hasta'), '')::date;
  v_ocup int; v_dato text; ev jsonb;
begin
  if v_hasta is not null and v_hasta < (now() at time zone 'America/Bogota')::date then return false; end if;

  select (h ->> 'ocupadas')::int into v_ocup
    from jsonb_array_elements(mensualidad_cupos() -> 'horas') h
   where h ->> 'hora' = to_char(p_hora, 'HH24:MI');
  if v_ocup is null or v_ocup >= v_max then return false; end if;

  foreach v_dato in array array[nullif(btrim(coalesce(p_celular, '')), ''), nullif(btrim(coalesce(p_documento, '')), '')] loop
    continue when v_dato is null;
    ev := premium_evaluar(v_dato);
    if (ev ->> 'encontradas')::int = 1
       and ev -> 'personas' -> 0 ->> 'veredicto' = 'aplica'
       and ev -> 'personas' -> 0 ->> 'encontrada_por' in ('celular', 'documento') then
      return true;
    end if;
  end loop;
  return false;
end;
$$;
revoke all on function public.premium_puede_pagar(text, text, time) from public, anon, authenticated;

do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.mensualidad_solicitar(text,text,text,text,text)'::regprocedure) into v_src;
  if position('premium_puede_pagar' in v_src) > 0 then return; end if;

  v_new := replace(v_src,
    'v_id uuid; v_estado text; v_previa mensualidad_solicitudes;',
    'v_id uuid; v_estado text; v_previa mensualidad_solicitudes; v_req boolean := false;');
  if v_new = v_src then raise exception '0133: no encontré las variables'; end if;

  v_src := v_new;
  v_new := replace(v_src,
    '  if found then
    return jsonb_build_object(''ok'', true, ''id'', v_previa.id, ''estado'', v_previa.estado,
                              ''valor_cop'', v_previa.valor_cop, ''ya_estaba'', true);',
    '  if found then
    -- ya estaba en la lista y ahora cumple (o hay cupo premium): se le abre el pago
    if v_previa.estado = ''lista_espera'' and premium_puede_pagar(p_celular, p_documento, v_hora) then
      update mensualidad_solicitudes set estado = ''esperando_pago'' where id = v_previa.id;
      v_previa.estado := ''esperando_pago'';
      v_req := true;
    end if;
    return jsonb_build_object(''ok'', true, ''id'', v_previa.id, ''estado'', v_previa.estado,
                              ''valor_cop'', v_previa.valor_cop, ''ya_estaba'', true,
                              ''por_requisitos'', v_req);');
  if v_new = v_src then raise exception '0133: no encontré el bloque de la solicitud previa'; end if;

  v_src := v_new;
  v_new := replace(v_src,
    'v_estado := case when coalesce(v_libres,0) > 0 then ''esperando_pago'' else ''lista_espera'' end;',
    'v_estado := case when coalesce(v_libres,0) > 0 then ''esperando_pago'' else ''lista_espera'' end;
  if v_estado = ''lista_espera'' and premium_puede_pagar(p_celular, p_documento, v_hora) then
    v_estado := ''esperando_pago'';
    v_req := true;
  end if;');
  if v_new = v_src then raise exception '0133: no encontré el cálculo del estado'; end if;

  v_src := v_new;
  v_new := replace(v_src,
    '''valor_cop'', v_valor, ''ya_estaba'', false);',
    '''valor_cop'', v_valor, ''ya_estaba'', false,
                            ''por_requisitos'', v_req);');
  if v_new = v_src then raise exception '0133: no encontré la respuesta final'; end if;

  execute v_new;
end
$mig$;
