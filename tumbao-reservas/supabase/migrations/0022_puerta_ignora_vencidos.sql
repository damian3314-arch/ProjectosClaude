-- ---------------------------------------------------------------------
-- 0022 — La lista de puerta y el tablero ignoran lo vencido
--
-- EL CASO REAL (2 de agosto de 2026)
-- Una clienta intentó reservar a las 9:22, no le salió, reintentó a las
-- 9:24 y ahí sí. El intento fallido —Z8NHNX— quedó en pendiente_pago,
-- venció a las 9:52 sin pago, y siguió apareciendo en la lista de la
-- puerta como si fuera a venir. Recepción veía dos veces a la misma
-- persona para la misma clase y no tenía forma de sacar la falsa.
--
-- POR QUÉ NO BASTABA CON 0021
-- 0021 puso el barrido dentro de tomar_cupo, que solo corre cuando
-- alguien reserva ESA clase. Si nadie vuelve a reservarla, la vencida se
-- queda ahí. clases_para ya la descontaba al leer; la lista de la puerta
-- y el tablero no. O sea: la página pública mostraba bien el cupo, y el
-- panel mostraba un fantasma. Peor que fallar en los dos.
--
-- CÓMO SE PARCHEA
-- Se lee la definición viva de cada función y se le añade la condición
-- al filtro que ya tiene. Así no se reescribe lógica que funciona —el
-- reparto del sábado, los vencimientos, el resumen— solo se acota qué
-- entra. Es más seguro que copiar 100 líneas y editarlas a mano.
--
-- Idempotente: si la condición ya está, no hace nada. Y comprueba que
-- encuentra exactamente los dos filtros que espera antes de tocar.
-- ---------------------------------------------------------------------
do $outer$
declare
  d text;
  v_falta int;
begin
  select pg_get_functiondef(p.oid) into d
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_lista_clase';

  if d is null then
    raise exception 'no existe admin_lista_clase';
  end if;

  if position('expira_en < now()' in d) = 0 then
    v_falta := (length(d) - length(replace(d,
                 'r.estado not in (''expirada'', ''rechazada'')', '')))
               / length('r.estado not in (''expirada'', ''rechazada'')');
    if v_falta <> 2 then
      raise exception 'se esperaban 2 filtros en admin_lista_clase, hay %', v_falta;
    end if;

    d := replace(d,
      'r.estado not in (''expirada'', ''rechazada'')',
      'r.estado not in (''expirada'', ''rechazada'')
       and not (r.estado = ''pendiente_pago'' and r.expira_en < now())');
    execute d;
    raise notice 'admin_lista_clase parcheada';
  else
    raise notice 'admin_lista_clase ya estaba';
  end if;

  select pg_get_functiondef(p.oid) into d
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_tablero';

  if d is null then
    raise exception 'no existe admin_tablero';
  end if;

  if position('expira_en < now()' in d) = 0 then
    if position('r.estado in (''pendiente_pago'',''verificando'')' in d) = 0 then
      raise exception 'no se hallo el contador esperando en admin_tablero';
    end if;
    d := replace(d,
      'r.estado in (''pendiente_pago'',''verificando'')',
      '(r.estado = ''verificando''
         or (r.estado = ''pendiente_pago'' and r.expira_en >= now()))');
    execute d;
    raise notice 'admin_tablero parcheada';
  else
    raise notice 'admin_tablero ya estaba';
  end if;
end $outer$;

-- create or replace conserva permisos, pero depender de eso ya mordió
-- una vez. Se repiten explícitos.
revoke execute on function admin_lista_clase(text, uuid) from public, anon, authenticated;
revoke execute on function admin_tablero(text, date)     from public, anon, authenticated;
grant  execute on function admin_lista_clase(text, uuid) to service_role;
grant  execute on function admin_tablero(text, date)     to service_role;
