-- ---------------------------------------------------------------------
-- 0037 — Quince minutos de gracia
--
-- EL PROBLEMA
-- Alguien mira la página a las 7:00 en punto para la clase de las 7:00 y
-- la clase ya no está. No dice "ya empezó": sencillamente no aparece, y
-- lo que la persona entiende es que no hay cupo. Se va.
--
-- En la vida real esa persona llega a las 7:10 y entra sin problema. La
-- página estaba siendo más estricta que la puerta.
--
-- LO QUE HACE
-- Una clase se puede reservar hasta 15 minutos después de su hora. Ni el
-- aforo ni el cobro ni nada más cambia: lo único que se mueve es cuándo
-- deja de ofrecerse.
--
-- POR QUÉ EL NÚMERO VIVE EN `ajustes`
-- Porque el día que quieran 20 minutos, o 10, o cero para el sábado, no
-- deberían necesitar una migración. Es lo mismo que se hizo con
-- `inicio_produccion`.
--
--   update ajustes set valor = '20' where clave = 'minutos_de_gracia';
--
-- POR QUÉ SE PARCHEA EL TEXTO Y NO SE REESCRIBEN LAS FUNCIONES
-- `tomar_cupo` son 6 KB y es lo más delicado que hay: aforo, sábado
-- partido, membresías, códigos. Copiarla entera para cambiar UNA línea
-- es la mejor forma de meter una errata en algo que hoy funciona.
--
-- Así que se toma el texto que de verdad está en la base
-- (`pg_get_functiondef`), se cambia solo esa condición, y se vuelve a
-- crear. Si la condición no aparece EXACTAMENTE una vez en cada
-- función, la migración revienta en vez de aplicar algo a medias.
-- ---------------------------------------------------------------------

insert into ajustes (clave, valor, nota)
values ('minutos_de_gracia', '15',
        'Cuántos minutos después de empezar se sigue pudiendo reservar una clase. La página estaba siendo más estricta que la puerta.')
on conflict (clave) do nothing;

create or replace function minutos_de_gracia()
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Si alguien borra la fila o escribe algo que no es un número, se cae
  -- a cero: el comportamiento de siempre. Fallar siendo estricto es
  -- recuperable —la persona escribe por WhatsApp— y fallar siendo
  -- permisivo mete gente a una clase que ya va por la mitad.
  select coalesce(
    (select nullif(regexp_replace(valor, '\D', '', 'g'), '')::int
       from ajustes where clave = 'minutos_de_gracia'), 0)
$$;

revoke execute on function minutos_de_gracia() from public, anon, authenticated;
grant  execute on function minutos_de_gracia() to service_role;


-- TRES SITIOS, NO DOS
--
--   tomar_cupo    y  tomar_cupos   deciden si se puede tomar el cupo
--   clases_para                    decide si la clase se OFRECE
--
-- El tercero es el que la persona ve. Sin él, la clase de las 7:00
-- desaparece del listado a las 7:00:01 aunque tomar_cupo la aceptara:
-- no hay nada donde hacer clic.
do $$
declare
  v_arreglos constant text[][] := array[
    -- función,      lo que dice ahora,                    lo que va a decir
    ['tomar_cupo',   'if v_clase.fecha_hora < now() then',
                     'if v_clase.fecha_hora < now() - make_interval(mins => minutos_de_gracia()) then'],
    ['tomar_cupos',  'if v_clase.fecha_hora < now() then',
                     'if v_clase.fecha_hora < now() - make_interval(mins => minutos_de_gracia()) then'],
    ['clases_para',  'and c.fecha_hora > now()',
                     'and c.fecha_hora > now() - make_interval(mins => minutos_de_gracia())']
  ];
  v_fn    text;
  v_viejo text;
  v_nuevo text;
  v_def   text;
  v_veces int;
  i       int;
begin
  for i in 1 .. array_length(v_arreglos, 1) loop
    v_fn    := v_arreglos[i][1];
    v_viejo := v_arreglos[i][2];
    v_nuevo := v_arreglos[i][3];

    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;

    if v_def is null then
      raise exception '0037: no existe la función %', v_fn;
    end if;

    -- Si ya se aplicó, no hay nada que hacer. Esto es lo que la vuelve
    -- idempotente: pegarla dos veces no la aplica dos veces.
    if position('minutos_de_gracia()' in v_def) > 0 then
      raise notice '0037: % ya tenía la gracia puesta, se deja como está', v_fn;
      continue;
    end if;

    v_veces := (length(v_def) - length(replace(v_def, v_viejo, ''))) / length(v_viejo);
    if v_veces <> 1 then
      raise exception '0037: en % la condición aparece % veces, esperaba 1. '
                      'Alguien la cambió; hay que mirarla a mano antes de parchear.',
                      v_fn, v_veces;
    end if;

    execute replace(v_def, v_viejo, v_nuevo);
    raise notice '0037: % parcheada', v_fn;
  end loop;
end $$;


-- ---------------------------------------------------------------------
-- El mensaje, cuando de verdad ya pasó
--
-- Con la gracia puesta, "Esa clase ya empezó" solo sale pasados los 15
-- minutos, que es cuando de verdad no tiene sentido entrar. Se deja tal
-- cual: es cierto y es corto.
-- ---------------------------------------------------------------------
