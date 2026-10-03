-- 0125 · La pista «parece la renovación de…» solo cuando de verdad lo parece
--
-- El primer aviso a recepción (29 sep) le dijo «parece la renovación de María
-- Fernanda (vence 20/10)» a un pago de $15.000: era una clase suelta de
-- alguien que ya tiene plan hasta el 20 de octubre. Una renovación es de
-- mensualidad (>= $60.000) y de un plan que está por vencer (de 5 días atrás
-- a 10 días adelante). Fuera de eso el aviso queda sin pista.
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.alertas_recepcion()'::regprocedure) into v_src;
  if position('hoy + 10' in v_src) > 0 then return; end if;
  v_new := replace(v_src,
    'where m.fin >= hoy - 5',
    'where m.fin between hoy - 5 and hoy + 10 and p.valor_cop - coalesce(p.usado_cop, 0) >= 60000');
  if v_new = v_src then raise exception '0125: no encontré la condición de la pista'; end if;
  execute v_new;
end
$mig$;
