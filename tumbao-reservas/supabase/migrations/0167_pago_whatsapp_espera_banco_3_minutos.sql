-- 0167 · El asistente de pagos espera al banco 3 minutos, no 6.
--
-- Damián (10 oct): al recibir un comprobante válido el bot le pide «uno o dos minutos» mientras verifica con el banco;
-- si el banco no lo muestra, le dice que su reserva ya está realizada y que el pago queda en verificación hasta que
-- una persona lo confirme. Seis minutos era demasiado para una persona esperando en el chat. Tres es lo mismo que la
-- página espera antes de decir «en revisión» (MINUTOS_ESPERA = 3), y el aviso del banco llega de 1 a 2 minutos.
--
-- Solo cambia ese número. La función es la de 0166, el resto igual: se mira a los 75 segundos y cada 2 minutos; confirmada
-- si el banco ya cuadró; rechazada/expirada si la base lo dice; y pendiente_validacion (la cola humana de siempre) si
-- pasaron 3 minutos sin que el banco aparezca.
create or replace function public.pago_seguimientos_tomar(p_limite int default 5)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare c record; v jsonb; v_tipo text; v_out jsonb := '[]'::jsonb;
begin
  for c in
    select * from pago_chats
     where resultado = 'soporte_recibido' and seguimiento_at is null
       and soporte_at <= now() - interval '75 seconds' and soporte_at > now() - interval '20 hours'
     order by soporte_at limit greatest(p_limite, 0) for update skip locked
  loop
    v := conciliar_reserva(c.codigo);
    v_tipo := null;
    if v ->> 'estado' = 'confirmada' then
      v_tipo := 'confirmada';
    elsif v ->> 'estado' in ('rechazada', 'expirada') then
      v_tipo := 'rechazada';
    elsif v ->> 'estado' = 'pendiente_validacion'
          or (v ->> 'estado' = 'verificando' and c.soporte_at <= now() - interval '3 minutes') then
      if v ->> 'estado' = 'verificando' then perform marcar_pendiente_validacion(c.codigo); end if;
      v_tipo := 'en_revision';
    end if;
    if v_tipo is not null then
      update pago_chats
         set seguimiento_at = now(), estado = 'cerrada', cerrada_at = now(),
             resultado = case v_tipo when 'confirmada' then 'pagado' else 'recepcion' end
       where id = c.id;
      v_out := v_out || jsonb_build_object('chat', c.id, 'telefono', c.telefono, 'nombre', c.nombre, 'tipo', v_tipo,
                                           'codigo', c.codigo, 'info', pago_info(c.id));
    end if;
  end loop;
  return v_out;
end;
$$;
revoke all on function public.pago_seguimientos_tomar(int) from public, anon, authenticated;
grant execute on function public.pago_seguimientos_tomar(int) to service_role;
