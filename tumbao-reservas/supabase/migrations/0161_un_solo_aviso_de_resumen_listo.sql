-- 0161 · Un solo «Tu reporte del asistente está listo» a la vez, y un toque entrega todo
--
-- Damián (9 oct): «al WhatsApp de recepción ha llegado un montón de veces el mensaje de que el reporte del
-- asistente está listo. Eso no debería pasar».
--
-- QUÉ PASABA
--   · Cada nota para un número que no ha hablado con el de avisos en 23 h (recepción casi nunca escribe) manda
--     SU PROPIA plantilla resumen_listo. El 9 oct llegaron 6 a recepción: 3 de las notas «Venta en curso» que
--     yo había agregado ese mismo día (una por conversación) y 3 «Pendientes por revisar» de alertas_recepcion().
--   · «Ver resumen» entregaba UNA cosa por toque: 6 avisos eran 6 toques, y mientras no se tocaban, más avisos.
--
-- CÓMO QUEDA
--   · wa_avisar_nota(): si ese número ya tiene un resumen_listo sin abrir de las últimas 12 horas, la nota queda
--     esperando (aviso_enviado) y NO manda otra plantilla. Con la ventana cerrada, a lo sumo dos avisos al día.
--   · wa_notas_pendientes(): un toque en «Ver resumen» entrega, además de lo que ya entregaba, las notas que
--     estén esperando (hasta 5), una por mensaje, dentro de la ventana que ese toque acaba de abrir.
-- Aditivo: wa_informe_pendiente() no cambia.

create or replace function public.wa_avisar_nota(p_id bigint)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v wa_notas;
begin
  update wa_notas set estado = 'aviso_enviado' where id = p_id returning * into v;
  if v.id is null then return; end if;
  -- Ya hay un aviso sin abrir para este número: el próximo toque en «Ver resumen» entrega todo lo que espera.
  if exists (select 1 from wa_avisos a
              where a.plantilla = 'resumen_listo'
                and right(a.telefono, 10) = right(v.telefono, 10)
                and a.creado_at > now() - interval '12 hours'
                and a.estado in ('pendiente', 'enviando', 'enviado')
                and coalesce(a.entrega, '') <> 'failed'
                and a.clave <> 'nota:' || v.id) then
    return;
  end if;
  insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
  values ('nota:' || v.id, 'informe', v.telefono, 'resumen_listo',
          jsonb_build_array('reporte del asistente'), now() + interval '24 hours')
  on conflict (clave) do nothing;
end;
$$;
revoke all on function public.wa_avisar_nota(bigint) from public, anon, authenticated;

create or replace function public.wa_notas_pendientes(p_tel text, p_max int default 5)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tel text := right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 10);
  v_out jsonb;
begin
  with t as (
    update wa_notas set estado = 'entregado', entregado_at = now()
     where id in (select id from wa_notas
                   where telefono = v_tel and estado = 'aviso_enviado'
                   order by creado_at limit greatest(p_max, 0) for update skip locked)
    returning titulo, texto, creado_at)
  select coalesce(jsonb_agg('*' || t.titulo || '*' || E'\n\n' || t.texto order by t.creado_at), '[]'::jsonb)
    into v_out from t;
  return v_out;
end;
$$;
revoke all on function public.wa_notas_pendientes(text, int) from public, anon, authenticated;
grant execute on function public.wa_notas_pendientes(text, int) to service_role;
