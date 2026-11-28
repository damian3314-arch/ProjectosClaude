-- 0109 · "Mañana" en el informe es el próximo día con clase.
--
-- El informe del sábado miraba el domingo y decía "no aparece la agenda".
-- Ahora clases_manana es el siguiente día que tiene clases activas (el
-- lunes, si hoy es sábado), y el tablero dice cuál es.

do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.tablero_tumbao(text)'::regprocedure) into v_src;
  v_new := replace(v_src,
    'manana   date := d + 1;',
    'manana   date := coalesce((select min((c0.fecha_hora at time zone ''America/Bogota'')::date) from clases c0'
    || ' where c0.activa and (c0.fecha_hora at time zone ''America/Bogota'')::date > d), d + 1);');
  v_new := replace(v_new,
    '''dia_semana'', (array[''lunes'',''martes'',''miércoles'',''jueves'',''viernes'',''sábado'',''domingo''])[extract(isodow from d)::int]);',
    '''dia_semana'', (array[''lunes'',''martes'',''miércoles'',''jueves'',''viernes'',''sábado'',''domingo''])[extract(isodow from d)::int],'
    || ' ''proximo_dia_con_clase'', manana,'
    || ' ''proximo_dia_con_clase_semana'', (array[''lunes'',''martes'',''miércoles'',''jueves'',''viernes'',''sábado'',''domingo''])[extract(isodow from manana)::int]);');
  if v_new = v_src or position('proximo_dia_con_clase_semana' in v_new) = 0
     or position('c0.activa' in v_new) = 0 then
    raise exception '0109: no se aplicaron los cambios';
  end if;
  execute v_new;
end
$mig$;
