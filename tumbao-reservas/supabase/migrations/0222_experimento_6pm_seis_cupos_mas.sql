-- 0222 · Experimento 6 pm (Damián, 26 nov): como la gente reservada no asiste, el 6 pm admite 3 mensualidades
-- y 3 sueltas más (aforo 34 -> 40) en las clases del 26 nov al 2 dic (5 clases: jue, vie, lun, mar, mié).
-- Fuera de esas fechas o de las 6 pm, el techo sigue en 34. Para terminar el experimento basta vaciar el ajuste.
insert into ajustes (clave, valor, nota) values
 ('experimento_6pm', '{"hora":"18:00","desde":"2026-11-26","hasta":"2026-12-02","extra":6}',
  'Aforo extra en las clases de esa hora entre esas fechas. Vacío = sin experimento.')
on conflict (clave) do update set valor = excluded.valor;

create or replace function public.techo_clase(p_fecha_hora timestamptz) returns int
language plpgsql stable set search_path to 'public','pg_temp' as $f$
declare v jsonb; b timestamp := p_fecha_hora at time zone 'America/Bogota';
begin
  begin v := nullif((select valor from ajustes where clave='experimento_6pm'),'')::jsonb;
  exception when others then v := null; end;
  if v is not null and to_char(b,'HH24:MI') = v->>'hora'
     and b::date between (v->>'desde')::date and (v->>'hasta')::date then
    return 34 + coalesce((v->>'extra')::int, 0);
  end if;
  return 34;
end $f$;

create or replace function public.clases_techo_aforo() returns trigger language plpgsql as $t$
begin
  if new.aforo is null or new.aforo > public.techo_clase(new.fecha_hora) then new.aforo := public.techo_clase(new.fecha_hora); end if;
  return new;
end $t$;

do $$
declare d text := pg_get_functiondef('public.recalcular_cupos'::regproc); n text;
begin
  n := replace(d, 'least(c.aforo, v_techo) as aforo_real', 'least(c.aforo, public.techo_clase(c.fecha_hora)) as aforo_real');
  if n = d then raise exception '0222: parche de recalcular_cupos no aplicó'; end if;
  execute n;
end $$;

-- Las clases ya abiertas dentro de la ventana suben a 40 y sus cupos se recalculan.
update clases set aforo = public.techo_clase(fecha_hora)
 where fecha_hora > now() and aforo < public.techo_clase(fecha_hora);
-- Mensualidad 6 pm: 25 -> 28 mientras dure el experimento.
update ajustes set valor = replace(valor, '18:00=25', '18:00=28'), updated_at = now()
 where clave = 'mensualidad_topes' and valor like '%18:00=25%';
select recalcular_cupos();
