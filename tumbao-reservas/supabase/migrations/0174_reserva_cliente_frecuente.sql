-- 0174 · ¿La reserva es de un cliente frecuente?
--
-- Damián (13 oct): cuando la reserva se valida sola, la pantalla final de la página solo da el código y «nos vemos en la
-- pista» (sin WhatsApp); y si es un cliente frecuente, un botón que lo invita a la página de mensualidad y tiquetera.
--
-- Frecuente = la persona (por su celular) tiene 2 o más clases SUELTAS confirmadas distintas con fecha en los últimos 30
-- días o por venir, contando la de esta reserva. Es el mismo umbral de la campaña de la tiquetera (0171: 2 o más en 30
-- días). Se cuentan clases distintas: un grupo que reserva varios cupos en la misma clase no cuenta como frecuente.
-- La llama el Worker en /tumbao/estado solo cuando la reserva ya está confirmada. Solo lectura.

create or replace function public.reserva_es_de_cliente_frecuente(p_codigo text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with r as (
    select right(regexp_replace(coalesce(telefono, ''), '\D', '', 'g'), 10) tel
      from reservas
     where codigo = upper(trim(p_codigo))
     limit 1)
  select coalesce((
    select count(distinct x.clase_id) >= 2
      from reservas x
      join clases c on c.id = x.clase_id
      join r on right(regexp_replace(coalesce(x.telefono, ''), '\D', '', 'g'), 10) = r.tel
     where r.tel ~ '^3[0-9]{9}$'
       and x.estado = 'confirmada'
       and x.tipo = 'suelta'
       and c.fecha_hora >= now() - interval '30 days'), false);
$$;
revoke all on function public.reserva_es_de_cliente_frecuente(text) from public, anon, authenticated;
grant execute on function public.reserva_es_de_cliente_frecuente(text) to service_role;
