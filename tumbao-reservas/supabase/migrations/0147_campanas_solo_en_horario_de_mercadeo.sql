-- 0147 · Ninguna campaña sale fuera del horario de mercadeo (Ley 2300), pase lo que pase
--
-- El 5 oct a las 10:26 pm salieron 3 aperturas de ventas: una llamada de prueba a ventas_ronda con una
-- hora futura SÍ ejecuta (p_ejecutar = true) y el despachador envió los avisos al instante. Para que
-- esto no dependa de quién encola, el despachador (wa_tomar_avisos) ahora no toma ningún aviso de tipo
-- 'campana' fuera de lunes a viernes 9:00-19:00 o sábado 9:00-13:00 (nunca domingo ni festivo): se queda
-- pendiente hasta que abra la ventana (o vence, según su vence_at). Lo transaccional (reservas, informes,
-- renovaciones, tiquetera comprada) no cambia.

create or replace function public.wa_horario_mercadeo(p_ahora timestamptz default now())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select extract(isodow from (p_ahora at time zone 'America/Bogota')) < 7
     and not exists (select 1 from festivos where fecha = (p_ahora at time zone 'America/Bogota')::date)
     and (p_ahora at time zone 'America/Bogota')::time >= time '09:00'
     and (p_ahora at time zone 'America/Bogota')::time < case when extract(isodow from (p_ahora at time zone 'America/Bogota')) = 6 then time '13:00' else time '19:00' end
$$;
revoke all on function public.wa_horario_mercadeo(timestamptz) from public, anon, authenticated;

-- wa_tomar_avisos: solo cambia la subconsulta de los pendientes:
--   select id from wa_avisos where estado = 'pendiente' and (tipo <> 'campana' or wa_horario_mercadeo())
