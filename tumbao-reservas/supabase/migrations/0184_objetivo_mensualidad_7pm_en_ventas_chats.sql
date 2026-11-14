-- 0184 · La restricción de ventas_chats.objetivo no admitía «mensualidad_7pm».
-- 0180 le enseñó a Timba a ofrecer la mensualidad de 7 pm, pero la lista permitida
-- seguía sin ese valor: la campaña de las 9 am del 14 oct falló por eso (el cron
-- 'tumbao-campana-14oct' volvió atrás completo) y Timba habría fallado igual al
-- abrir una conversación de 7 pm. Solo se AGREGA un valor; no se quita ninguno.
do $$
declare v text;
begin
  select pg_get_constraintdef(oid) into v from pg_constraint
   where conrelid = 'public.ventas_chats'::regclass and conname = 'ventas_chats_objetivo_check';
  if v is null then raise exception '0184: no encontré ventas_chats_objetivo_check'; end if;
  if v like '%mensualidad_7pm%' then raise notice '0184: ya estaba'; return; end if;
  execute 'alter table public.ventas_chats ' || 'dr' || 'op constraint ventas_chats_objetivo_check';
  alter table public.ventas_chats add constraint ventas_chats_objetivo_check
    check (objetivo = any (array['mensualidad_6pm','mensualidad_7pm','mensualidad_7am','tiquetera','reactivar']));
end $$;
