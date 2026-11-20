-- ---------------------------------------------------------------------
-- 0048 — Lo que entró hoy para una clase de otro día, contado aparte
--
-- EL PROBLEMA
-- El 24 de agosto el banco confirmó $905.000, pero comparado contra el
-- cierre de AdminGym ($845.000) parecía faltar plata real. No faltaba
-- nada: $105.000 de eso eran reservas que alguien pagó el 24 para
-- clases del 25 — Monica Niño y Johel Macías, cada uno pagando por dos
-- cupos de un día que todavía no llegaba. Esa plata SÍ entró al banco
-- el 24 (por eso tiene que seguir contando para el arqueo de ese día:
-- no puede desaparecer de la caja), pero no es plata de un cliente que
-- disfrutó algo ese día — es un anticipo.
--
-- `reservas_dictadas_cop` ya existía para la otra mitad de esta
-- pregunta (clases de hoy, sin importar cuándo se pagaron). Faltaba el
-- reverso: de lo que se pagó hoy, cuánto es para una clase de otro día.
--
-- LO QUE HACE
-- Agrega reservas_futuras_cop / reservas_futuras_n a caja_del_dia():
-- reservas confirmadas y pagadas el día que se pide, cuya clase es de
-- una fecha posterior. No se resta de nada — sigue sumando al total
-- del banco, que es correcto: esa plata entró de verdad. Solo se
-- separa para que la tirilla pueda decir "de esto, tanto es de hoy y
-- tanto es de una clase futura", y esos dos números sumen justo el
-- total recibido.
--
-- Se parchea sobre pg_get_functiondef en vez de reescribir la función:
-- es larga, y reescribir de memoria ya salió mal en este proyecto.
-- ---------------------------------------------------------------------
do $$
declare
  v_def text;
  v_a   text;
  v_b   text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';
  if v_def is null then
    raise exception 'no existe caja_del_dia';
  end if;
  if position('v_res_futuras' in v_def) > 0 then
    raise notice 'ya estaba aplicada';
    return;
  end if;

  -- 1. Declarar las dos variables nuevas.
  v_a := '  v_res_mano int; v_res_mano_n int;';
  v_b := v_a || E'\n' || '  v_res_futuras int; v_res_futuras_n int;';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro la declaracion de v_res_mano exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  -- 2. La consulta: mismo cruce que reservas_cop, pero exigiendo que la
  -- clase sea de DESPUES del dia que se esta pidiendo.
  v_a := '  select coalesce(sum(c.precio_cop), 0), count(*)
    into v_res_mano, v_res_mano_n
    from reservas r join clases c on c.id = r.clase_id
   where r.estado = ''confirmada'' and r.tipo = ''suelta''
     and r.pago_id is null
     and (r.created_at at time zone ''America/Bogota'')::date = v_dia;';
  v_b := v_a || E'\n\n' ||
    '  -- Lo que se pagó hoy pero es para una clase de otro dia: un' || E'\n' ||
    '  -- anticipo. Sigue contando para el arqueo de hoy -la plata SI' || E'\n' ||
    '  -- entro-, pero no es lo que un cliente disfruto hoy.' || E'\n' ||
    '  select coalesce(sum(c.precio_cop), 0), count(*)' || E'\n' ||
    '    into v_res_futuras, v_res_futuras_n' || E'\n' ||
    '    from reservas r' || E'\n' ||
    '    join clases c on c.id = r.clase_id' || E'\n' ||
    '    left join pagos p on p.id = r.pago_id' || E'\n' ||
    '   where r.estado = ''confirmada'' and r.tipo = ''suelta''' || E'\n' ||
    '     and r.pago_id is not null' || E'\n' ||
    '     and (coalesce(p.fecha_pago, r.created_at)' || E'\n' ||
    '            at time zone ''America/Bogota'')::date = v_dia' || E'\n' ||
    '     and (c.fecha_hora at time zone ''America/Bogota'')::date > v_dia;';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro la consulta de v_res_mano exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  -- 3. Sacarlas en la respuesta.
  v_a := '    ''reservas_n'',            v_reservas_n,';
  v_b := v_a || E'\n' ||
    '    ''reservas_futuras_cop'', v_res_futuras,' || E'\n' ||
    '    ''reservas_futuras_n'',   v_res_futuras_n,';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro reservas_n en la respuesta exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  execute v_def;
end $$;
