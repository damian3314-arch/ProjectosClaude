-- 0191 · Techo duro de 34 personas por clase (Damián, 29 oct): mensualidades vigentes o en gracia + sueltas/tiqueteras + cambios.
-- El cupo puesto a mano solo puede bajar el cupo, nunca subirlo por encima de lo que deja el aforo.
-- (Ya aplicada en vivo; ver recalcular_cupos() para el cuerpo vigente.)
update clases set aforo = 34 where aforo > 34;
alter table clases alter column aforo set default 34;
create or replace function public.clases_techo_aforo() returns trigger language plpgsql as $t$
begin if new.aforo is null or new.aforo > 34 then new.aforo := 34; end if; return new; end $t$;
create trigger clases_techo_aforo before insert or update of aforo on public.clases
  for each row execute function public.clases_techo_aforo();
update ajustes set valor = '07:00=34,18:00=25,19:00=25', updated_at = now() where clave = 'mensualidad_topes';
