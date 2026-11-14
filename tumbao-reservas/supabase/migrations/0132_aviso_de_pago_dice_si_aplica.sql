-- 0132 · Cuando llega una mensualidad, el aviso a recepción dice si quien pagó APLICA
--
-- Damián (1 oct): «si llegan pagos de mensualidad y es de gente que aplica,
-- decirlo». La mensualidad es solo para quien cumple los requisitos (0129): un
-- pago de $60.000 o más que llega sin dueño, o una mensualidad pagada por la
-- página, ahora sale con su veredicto al lado:
--   ✅ Aplica: la razón, los cupos libres de su horario y que se puede registrar.
--   ⛔ NO aplica: la razón, y que no se registre (se decide si se devuelve o se
--      le ofrece tiquetera).
--   ❓ No la encuentro / hay varias con ese nombre: pedir celular o cédula.
-- Un pago trae el nombre del banco (a veces cortado o con otro orden); si no
-- aparece con todas las palabras se prueba con la primera y la última, y se
-- avisa que la identificó por el nombre y hay que confirmar con el celular.

create or replace function public.premium_frase(p_buscar text, p_valor int default null)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  ev jsonb; p jsonb; n int; hora text; libres text; v_q text; v_toks text[];
begin
  if coalesce(btrim(p_buscar), '') = '' then return null; end if;
  -- solo pagos del tamaño de una mensualidad
  if p_valor is not null and p_valor < 60000 then return null; end if;

  v_q := p_buscar;
  if regexp_replace(p_buscar, '\D', '', 'g') = '' then
    -- nombre del banco: se quitan las letras sueltas («V», «C»)
    v_toks := array(select t from unnest(string_to_array(norm_nombre(btrim(p_buscar)), ' ')) t where length(t) >= 3);
    v_q := array_to_string(v_toks, ' ');
  end if;

  ev := premium_evaluar(v_q);
  n := (ev ->> 'encontradas')::int;
  if n = 0 and v_toks is not null and cardinality(v_toks) >= 3 then
    ev := premium_evaluar(v_toks[1] || ' ' || v_toks[cardinality(v_toks)]);
    n := (ev ->> 'encontradas')::int;
  end if;

  if n = 0 then
    return '❓ No la encuentro en el historial con ese dato: pide el celular o la cédula para saber si aplica a mensualidad.';
  elsif n > 1 then
    return '❓ Hay ' || n || ' personas con ese nombre: pide el celular o la cédula para saber si aplica a mensualidad.';
  end if;

  p := ev -> 'personas' -> 0;
  hora := p ->> 'horario_habitual';
  libres := case when hora is null then null else ev -> 'cupos_por_horario' -> hora ->> 'libres' end;

  if p ->> 'veredicto' = 'aplica' then
    return '✅ Aplica a mensualidad (' || (p ->> 'nombre') || '): ' || (p ->> 'razon')
      || coalesce(' Su horario de ' || hora || ' tiene ' || libres || ' cupo(s) libre(s).', '')
      || ' Se puede registrar.'
      || case when p ->> 'encontrada_por' = 'nombre'
              then ' La identifiqué por el nombre del banco: confirma con su celular o cédula antes de registrar.' else '' end;
  end if;
  return '⛔ NO aplica a mensualidad (' || (p ->> 'nombre') || '): ' || (p ->> 'razon')
    || ' No la registres; consulta qué hacer (devolver o ofrecerle tiquetera).'
    || case when p ->> 'encontrada_por' = 'nombre'
            then ' La identifiqué por el nombre del banco (o un nombre ligado a ese celular): confirma con su celular o cédula antes de decidir.' else '' end;
end;
$$;
revoke all on function public.premium_frase(text, int) from public, anon, authenticated;

-- El aviso: los pagos sin dueño y las mensualidades pagadas por la página.
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.alertas_recepcion()'::regprocedure) into v_src;
  if position('premium_frase' in v_src) > 0 then return; end if;

  v_new := replace(v_src,
    '      || case when r.espera is not null',
    '      || case when r.espera is null then coalesce(E''\n   '' || public.premium_frase(r.remitente, r.saldo), '''') else '''' end
      || case when r.espera is not null');
  if v_new = v_src then raise exception '0132: no encontré la línea de la lista de espera'; end if;

  v_src := v_new;
  v_new := replace(v_src,
    'Si es una mensualidad de alguien que YA tiene plan, regístrala en Caja y pásala a AdminGym. Si dice lista de espera, no la registres.',
    'Si dice «aplica», regístrala en Caja y pásala a AdminGym. Si dice «NO aplica» o «lista de espera», no la registres.');
  if v_new = v_src then raise exception '0132: no encontré el cierre del bloque de pagos'; end if;

  v_src := v_new;
  v_new := replace(v_src,
    '|| lower(to_char(r.hora::time, ''FMHH12:MI am'')));',
    '|| lower(to_char(r.hora::time, ''FMHH12:MI am''))
      || coalesce(E''\n   '' || public.premium_frase(r.celular, 125000), ''''));');
  if v_new = v_src then raise exception '0132: no encontré la línea de la mensualidad pagada'; end if;

  execute v_new;
end
$mig$;
