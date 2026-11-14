-- 0179 · La tiquetera de la página cuenta el día que se PAGÓ, aunque se valide después del cierre
--
-- 13 oct, Damián: «el cierre no está incluyendo las tiqueteras; necesito que esos valores se incluyan y sumen a lo
-- vendido del día, porque se queda por fuera y me afecta el valor».
--
-- QUÉ PASABA
-- La tiquetera comprada en la página entra a la caja cuando recepción (o el banco) la confirma (0111/0112). Si en ese
-- momento el día ya estaba cerrado, el ingreso se mandaba a MAÑANA («igual que cualquier movimiento»). Hoy Yenifer
-- (dijo «ya pagué» a las 3:38 pm) y Tania (6:54 pm) se validaron a las 8:19 y 8:45 pm, con la caja del 13 cerrada
-- desde las 7:29 pm: sus $192.000 quedaron en el 14 y la venta del 13 salió corta ($620.000 en vez de $812.000).
--
-- LA REGLA NUEVA
--   · El ingreso cuenta el día en que el cliente pagó (pagado_en = cuando dijo «ya pagué», o cuando recepción la validó
--     si nunca lo dijo; si no hay, cuando se creó), aunque ese día ya esté cerrado.
--   · Eso es seguro porque la tiquetera de la página siempre entra como TRANSFERENCIA: no toca el efectivo, así que
--     el arqueo ya cerrado (contado / esperado / diferencia) queda igual. Lo que cambia es lo vendido del día.
--   · Solo dentro del mes en curso. Un pago de un mes anterior (cuyo informe ya salió) cuenta hoy, y si hoy está
--     cerrado, mañana, como antes.
--   · Una transferencia sin depósito del banco queda «sin cruzar» en ese día hasta que se enlace el depósito
--     (caja_enlazar_deposito), igual que cualquier otra.
-- Y se corrigen las dos de hoy: del 14 al 13.

create or replace function public.tiquetera_ingreso_en_linea()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hoy  date := (now() at time zone 'America/Bogota')::date;
  v_pago date := (coalesce(new.pagado_en, new.creada_en, now()) at time zone 'America/Bogota')::date;
  v_dia  date;
begin
  if new.estado = 'confirmada' and coalesce(old.estado, '') <> 'confirmada'
     and new.creada_por is null
     and coalesce(new.precio_cop, 0) > 0
     and not exists (select 1 from caja_movimientos m
                      where m.tiquetera_id = new.id and not m.anulado) then
    if v_pago between date_trunc('month', v_hoy)::date and v_hoy then
      v_dia := v_pago;
    else
      v_dia := v_hoy;
      if exists (select 1 from caja_cierres where dia = v_dia) then
        v_dia := v_dia + 1;
      end if;
    end if;
    insert into caja_movimientos (dia, sentido, concepto, valor_cop, medio, nota,
                                  registrado_por, pago_id, cantidad, origen, tiquetera_id)
    values (v_dia, 'ingreso', 'tiquetera', new.precio_cop, 'transferencia',
            'Tiquetera ' || new.codigo || ' · ' || new.nombre || ' · comprada en la página'
              || coalesce(' · ref ' || nullif(btrim(new.referencia), ''), ''),
            null, new.pago_id, 1, 'caja_menor', new.id);
  end if;
  return new;
end;
$$;
revoke all on function public.tiquetera_ingreso_en_linea() from public, anon, authenticated;

-- Las dos de hoy (Yenifer #43 y Tania #44) habían quedado en el 14: vuelven al 13, el día en que pagaron.
update public.caja_movimientos m
   set dia = date '2026-10-13'
 where m.tiquetera_id in (43, 44)
   and m.dia = date '2026-10-14'
   and m.concepto = 'tiquetera'
   and m.medio = 'transferencia'
   and not m.anulado;
