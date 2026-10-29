-- El sábado: 15 para afiliados, 20 para clase suelta, y sin que se note.
--
-- Tres cosas que no pueden fallar:
--
--   1. Los dos cupos son independientes. Llenar el de afiliados NO
--      puede cerrarle la puerta a las sueltas, ni al revés. Si se
--      cerraran entre sí, se dejaría de vender la mitad del sábado.
--   2. El techo de la sala sigue mandando. 15 + 20 caben en 35; si
--      alguien baja el aforo a mano, ninguno de los dos lados puede
--      pasarse de lo que queda de verdad.
--   3. El cliente no se entera. La respuesta del horario no puede traer
--      los números del otro lado, y el mensaje al llenarse tiene que
--      ser el mismo de siempre.
--
-- Y entre semana nada cambia: ahí el afiliado ni siquiera reserva.
--
--   psql -d tumbao -f pruebas/humo-sabado-partido.sql

\set ON_ERROR_STOP on
set timezone = 'America/Bogota';

do $$
declare
  v_sab date; v_lun date;
  v_c uuid; v_c18 uuid;
  v_r jsonb; v_fila record;
  v_n int; v_libres int;
begin
  delete from asistencias where true;
  delete from reservas where true;
  delete from pagos where true;
  delete from membresias where true;
  delete from clases where true;
  delete from admin_tokens where true;
  perform generar_horario(current_date, current_date + 13);

  select (fecha_hora at time zone 'America/Bogota')::date into v_sab
    from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') = 6
     and (fecha_hora at time zone 'America/Bogota')::date
         > (now() at time zone 'America/Bogota')::date
   order by fecha_hora limit 1;
  select id into v_c from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_sab
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 8;

  -- ── 1. el sábado nace partido, entre semana no ─────────────
  select cupo_miembros, cupo_sueltas into v_fila from clases where id = v_c;
  -- 0058: pasa de 15/15 a 15/20. La 0020 ya avisaba que este numero
  -- iba a cambiar sin avisar; lo que cambio ademas es que ahora es un
  -- literal y no `aforo / 2`, para que se pueda cambiar sin reescribir
  -- una formula.
  if v_fila.cupo_miembros <> 15 or v_fila.cupo_sueltas <> 20 then
    raise exception 'el sabado deberia nacer 15/20, nacio %/%',
      v_fila.cupo_miembros, v_fila.cupo_sueltas;
  end if;
  select (fecha_hora at time zone 'America/Bogota')::date into v_lun
    from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') between 1 and 5
     and (fecha_hora at time zone 'America/Bogota')::date
         > (now() at time zone 'America/Bogota')::date order by fecha_hora limit 1;
  select id into v_c18 from clases
   where (fecha_hora at time zone 'America/Bogota')::date = v_lun
     and extract(hour from fecha_hora at time zone 'America/Bogota') = 18;
  select cupo_miembros into v_n from clases where id = v_c18;
  if v_n is not null then
    raise exception 'entre semana no debe haber reparto, hay %', v_n;
  end if;
  raise notice '1. sabado 15/20; entre semana sin reparto';

  -- 20 afiliadas con plan de 6pm — el sábado su plan no las cubre, así
  -- que reservan como todo el mundo.
  perform importar_membresias((
    select jsonb_agg(f) from (
      select jsonb_build_object(
        'afiliado', 'Socia ' || g, 'membresia', 'PLAN MENSUALIDAD 6:00PM',
        'hora', '18:00:00', 'tipo', 'plan',
        'documento', (700000 + g)::text, 'celular', '300' || lpad(g::text, 7, '0'),
        'correo', null,
        'inicio', (current_date - 3)::text, 'fin', (current_date + 25)::text) as f
      from generate_series(1, 20) g
    ) s));

  -- ── 2. se llenan los 15 de afiliados ───────────────────────
  for v_n in 1..15 loop
    select tomar_cupo(v_c, 'Socia ' || v_n, '300' || lpad(v_n::text, 7, '0'),
                      null, 'web', 'miembro') into v_r;
    if (v_r->>'ok')::boolean is not true then
      raise exception 'la afiliada % no pudo entrar: %', v_n, v_r;
    end if;
  end loop;
  raise notice '2. entraron las 15 afiliadas';

  -- ── 3. la 16 afiliada NO entra ─────────────────────────────
  select tomar_cupo(v_c, 'Socia 16', '3000000016', null, 'web', 'miembro') into v_r;
  if (v_r->>'error') <> 'SIN_CUPO' then
    raise exception 'entro una afiliada de mas: %', v_r;
  end if;
  -- Y el mensaje no puede delatar el reparto.
  if v_r->>'mensaje' ~* 'afiliad|miembro|plan|reparto|mitad' then
    raise exception 'el mensaje delata el reparto: %', v_r->>'mensaje';
  end if;
  raise notice '3. la 16 rebota, y el mensaje no menciona el reparto';

  -- ── 4. pero las sueltas SIGUEN entrando ────────────────────
  -- Esta es la que de verdad importa: si los dos cupos se cerraran
  -- entre si, se dejaria de vender media clase.
  for v_n in 1..20 loop
    select tomar_cupo(v_c, 'Suelta ' || v_n, '311' || lpad(v_n::text, 7, '0'),
                      null, 'web', 'suelta') into v_r;
    if (v_r->>'ok')::boolean is not true then
      raise exception 'la suelta % no pudo entrar con los afiliados llenos: %', v_n, v_r;
    end if;
  end loop;
  raise notice '4. con afiliados lleno, las 20 sueltas entran igual';

  -- ── 5. y la 16 suelta tampoco ──────────────────────────────
  select tomar_cupo(v_c, 'Suelta 21', '3110000021', null, 'web', 'suelta') into v_r;
  if (v_r->>'error') <> 'SIN_CUPO' then
    raise exception 'entro una suelta de mas: %', v_r;
  end if;
  select cupo_tomado, cupo_total into v_fila from clases where id = v_c;
  if v_fila.cupo_tomado <> 35 then
    raise exception 'deberian haber entrado 35, entraron %', v_fila.cupo_tomado;
  end if;
  -- Que la suma de los dos lados sea EXACTAMENTE el techo es lo que se
  -- rompio antes de la 0058: los lados sumaban 30 contra un techo de 35
  -- y cinco puestos no se podian vender por ningun lado.
  if v_fila.cupo_total <> 35 then
    raise exception 'el techo del sabado deberia ser 35, es %', v_fila.cupo_total;
  end if;
  raise notice '5. la clase queda en 35 exactos: 15 y 20, y el techo es la suma';

  -- ── 6. rechazar una libera SU lado, no el otro ─────────────
  declare v_tok text; v_cod text;
  begin
    v_tok := (crear_token_admin('humo del sabado'))->>'token';
    select codigo into v_cod from reservas
     where clase_id = v_c and tipo = 'suelta' limit 1;
    update reservas set estado = 'pendiente_validacion' where codigo = v_cod;
    perform admin_rechazar(v_tok, v_cod);

    -- Ahora cabe una suelta...
    select tomar_cupo(v_c, 'Suelta Nueva', '3119999999', null, 'web', 'suelta') into v_r;
    if (v_r->>'ok')::boolean is not true then
      raise exception 'al rechazar una suelta deberia caber otra suelta: %', v_r;
    end if;
    -- ...pero NO una afiliada de mas.
    select tomar_cupo(v_c, 'Socia 17', '3000000017', null, 'web', 'miembro') into v_r;
    if (v_r->>'error') <> 'SIN_CUPO' then
      raise exception 'el hueco de una suelta se lo llevo una afiliada: %', v_r;
    end if;
    delete from admin_tokens where nombre = 'humo del sabado';
  end;
  raise notice '6. el hueco que deja una suelta es para las sueltas';

  -- ── 7. el aforo compartido sigue mandando ──────────────────
  -- Si alguien baja el cupo a mano, ninguno de los dos lados puede
  -- pasarse de lo que queda de verdad.
  delete from reservas where clase_id = v_c;
  update clases set cupo_tomado = 0, cupo_total = 4 where id = v_c;
  -- Dos sueltas y dos afiliadas: las afiliadas con un celular que SI
  -- esta en membresias, si no rebotan por otro motivo y la prueba
  -- estaria midiendo otra cosa.
  for v_n in 1..4 loop
    select tomar_cupo(
      v_c,
      'Mezcla ' || v_n,
      case when v_n <= 2 then '312' || lpad(v_n::text, 7, '0')
           else '300' || lpad(v_n::text, 7, '0') end,
      null, 'web',
      case when v_n <= 2 then 'suelta' else 'miembro' end) into v_r;
    if (v_r->>'ok')::boolean is not true then
      raise exception 'no entro la % con cupo 4: %', v_n, v_r;
    end if;
  end loop;
  select tomar_cupo(v_c, 'Sobra', '3129999999', null, 'web', 'suelta') into v_r;
  if (v_r->>'error') <> 'SIN_CUPO' then
    raise exception 'el reparto dejo pasar de un aforo de 4: %', v_r;
  end if;
  raise notice '7. con el aforo bajado a 4, el reparto no lo desborda';

  -- ── 8. el horario no delata el reparto ─────────────────────
  -- Ni un numero del otro lado puede salir del servidor.
  delete from reservas where clase_id = v_c;
  update clases set cupo_tomado = 0, cupo_total = 35 where id = v_c;
  select tomar_cupo(v_c, 'Una Socia', '3000000001', null, 'web', 'miembro') into v_r;

  select cupo_total, cupo_tomado into v_fila
    from clases_para('suelta') where id = v_c;
  if v_fila.cupo_total <> 20 then
    raise exception 'a una suelta deberian ofrecersele 20, se le ofrecen %',
      v_fila.cupo_total;
  end if;
  if v_fila.cupo_total - v_fila.cupo_tomado <> 20 then
    raise exception 'la reserva de una afiliada le quito cupo a las sueltas: quedan %',
      v_fila.cupo_total - v_fila.cupo_tomado;
  end if;

  select cupo_total, cupo_tomado into v_fila
    from clases_para('miembro') where id = v_c;
  if v_fila.cupo_total - v_fila.cupo_tomado <> 14 then
    raise exception 'a un miembro deberian quedarle 14, le quedan %',
      v_fila.cupo_total - v_fila.cupo_tomado;
  end if;
  raise notice '8. cada quien ve solo su lado: suelta 20, miembro 14';

  -- ── 9. entre semana clases_para no cambia nada ─────────────
  select cupo_total, cupo_tomado into v_fila
    from clases_para('suelta') where id = v_c18;
  select cupo_total, cupo_tomado into v_r
    from clases where id = v_c18;
  if v_fila.cupo_total <> (select cupo_total from clases where id = v_c18) then
    raise exception 'entre semana el cupo no debe cambiar: % vs %',
      v_fila.cupo_total, (select cupo_total from clases where id = v_c18);
  end if;
  raise notice '9. entre semana todo sigue exactamente igual';
end $$;

-- ── 10. y con gente dandole al boton a la vez ────────────────
-- La proteccion de verdad. Va en pruebas/carrera-sabado.mjs, que abre
-- conexiones reales; aqui solo se deja la clase lista y se comprueba
-- que el tope quedo puesto.
do $$
declare v_c uuid; v_m int; v_s int;
begin
  select id, cupo_miembros, cupo_sueltas into v_c, v_m, v_s
    from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') = 6
     and (fecha_hora at time zone 'America/Bogota')::date
         > (now() at time zone 'America/Bogota')::date
   order by fecha_hora limit 1;
  if v_m is null or v_s is null then
    raise exception 'el sabado se quedo sin reparto';
  end if;
  if v_m + v_s > (select aforo from clases where id = v_c) then
    raise exception 'el reparto (%+%) no cabe en el aforo', v_m, v_s;
  end if;
  raise notice '10. el reparto cabe en el aforo (% + % de %)',
    v_m, v_s, (select aforo from clases where id = v_c);
end $$;

select 'TODO EN VERDE' as resultado;
