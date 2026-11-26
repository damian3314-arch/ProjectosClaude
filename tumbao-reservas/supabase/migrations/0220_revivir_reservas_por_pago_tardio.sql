-- 0220 · Reservas que se liberaron y cuyo pago llega después se REVIVEN solas (26 nov, Damián)
--
-- Pasa que el cliente reserva, paga, y el correo del banco no llega (o llega tarde). La reserva se libera —por vencer, por no
-- compartir el soporte en 30 min (0210) o porque recepción la rechaza con «el pago no aparece en el banco»— y luego el depósito
-- aparece en la base. Antes esa reserva quedaba perdida aunque el cliente sí hubiera pagado.
--
-- revivir_reservas_por_pago_tardio() corre cada 2 minutos y, para las reservas de clase suelta de los últimos 3 días, cuya clase
-- todavía no ha terminado y que se liberaron por falta de pago (vencidas, o rechazadas por «pago/comprobante/banco/soporte»):
--   · busca un depósito SIN reclamar con el valor exacto del grupo, cuyo remitente se parezca al nombre de alguien del grupo (>= 0.5)
--     y que haya caído entre 3 horas antes de la reserva y 3 días después;
--   · si la clase aún no termina y hay cupo para todo el grupo, las vuelve a confirmar, les enlaza el depósito, toma el cupo y lo deja en la
--     auditoría como «Sistema · revivir_por_pago_tardio» (avisa la confirmación igual que cualquier otra).
-- Si la clase ya terminó (hasta 3 días atrás) también las revive —sin tomar cupo—, para que la persona use su pago reprogramando
-- en tumbaobaila.com/reprogramar (3 días después de la clase). No toca reservas liberadas por otra razón (la persona canceló, duplicada, error al apuntar). No borra nada.

create or replace function public.revivir_reservas_por_pago_tardio()
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions', 'pg_temp' as $$
declare
  g record; v_total int; v_pago uuid; v_libres int; v_n int := 0; v_cods text[] := '{}';
begin
  for g in
    select coalesce(r.grupo_id, r.id) as gid,
           min(r.created_at) as creada,
           count(*)::int as n,
           (array_agg(r.clase_id))[1] as clase_id,
           array_agg(coalesce(r.pagador_nombre, r.nombre)) as quienes,
           max(c.fecha_hora) as fecha_hora,
           max(c.fecha_hora + make_interval(mins => coalesce(c.duracion_min, 45))) as termina,
           max(c.precio_cop) as unit,
           min(r.codigo) as cod,
           (array_agg(r.nombre order by r.created_at))[1] as nombre
      from reservas r join clases c on c.id = r.clase_id
     where r.tipo = 'suelta' and r.pago_id is null
       and (r.estado = 'expirada'
            or (r.estado = 'rechazada' and r.motivo_rechazo ~* 'pago|comprobante|banco|soporte'))
       and r.created_at > now() - interval '3 days'
       and c.fecha_hora + make_interval(mins => coalesce(c.duracion_min, 45)) > now() - interval '3 days'   -- a tiempo, o con 3 días para reprogramar
       and not exists (select 1 from reservas v
                        where coalesce(v.grupo_id, v.id) = coalesce(r.grupo_id, r.id)
                          and v.estado in ('confirmada', 'pendiente_pago', 'verificando', 'pendiente_validacion'))
     group by coalesce(r.grupo_id, r.id)
     order by min(r.created_at)
  loop
    begin
      v_total := promo_total_cupos(g.n, g.unit, g.fecha_hora);
      v_pago := null;
      select p.id into v_pago
        from pagos p
       where not p.consumido and p.fusionado_en is null
         and p.valor_cop = v_total
         and p.fecha_pago >= g.creada - interval '3 hours'
         and p.fecha_pago <= g.creada + interval '3 days'
         and (select max(similitud_nombre(q, p.remitente)) from unnest(g.quienes) q) >= 0.5   -- puede pagar cualquiera del grupo
       order by (select max(similitud_nombre(q, p.remitente)) from unnest(g.quienes) q) desc, p.fecha_pago
       limit 1
         for update skip locked;
      if v_pago is null then continue; end if;

      select c.cupo_total - c.cupo_tomado into v_libres from clases c where c.id = g.clase_id for update;
      if g.termina > now() and coalesce(v_libres, 0) < g.n then continue; end if;   -- sin cupo: no se revive a costa de otros

      update reservas
         set estado = 'confirmada', pago_id = v_pago, motivo_rechazo = null, updated_at = now()
       where coalesce(grupo_id, id) = g.gid and estado in ('expirada', 'rechazada');
      if g.termina > now() then update clases set cupo_tomado = cupo_tomado + g.n where id = g.clase_id; end if;
      update pagos set consumido = true where id = v_pago;

      insert into caja_auditoria (admin_id, quien, accion, codigo, clase_id, nombre, motivo, detalle)
      values (null, 'Sistema', 'revivir_por_pago_tardio', g.cod, g.clase_id, g.nombre,
              'Llegó el depósito después de liberar la reserva',
              jsonb_build_object('pago_id', v_pago, 'cupos', g.n, 'valor_cop', v_total));
      v_n := v_n + 1;
      v_cods := v_cods || g.cod;
    exception when others then
      raise warning 'revivir_reservas_por_pago_tardio (grupo %): %', g.gid, sqlerrm;
    end;
  end loop;
  return jsonb_build_object('ok', true, 'revividas', v_n, 'codigos', to_jsonb(v_cods));
end;
$$;

revoke all on function public.revivir_reservas_por_pago_tardio() from public, anon, authenticated;
grant execute on function public.revivir_reservas_por_pago_tardio() to service_role;

-- Cada 2 minutos, igual que el cruce de mensualidades.
select cron.schedule('tumbao-revivir-pago-tardio', '*/2 * * * *', 'select public.revivir_reservas_por_pago_tardio()')
 where not exists (select 1 from cron.job where jobname = 'tumbao-revivir-pago-tardio');
