-- 0158 · Saber quién abrió el enlace de la conversación de ventas
--
-- Damián (7 oct): lo que importa es que compren. Hoy el bot manda el enlace y no se sabe si se abrió. Desde ahora el
-- enlace que sale de una conversación lleva ?r=<número de la conversación>; las páginas (index y mensualidad) avisan
-- a /tumbao/visita cuando se abre y la base lo anota en la conversación (oferta.visita_at y oferta.visitas). No se
-- guarda nada de quien abre la página: solo el número de la conversación.
--
--   · ventas_marcar_visita(chat): primera visita y conteo.
--   · ventas_seguimientos_tomar: devuelve 'visito' para que el seguimiento de las 24 h cambie de pregunta
--     («¿lo viste?» → «¿qué te frenó para terminar?»).
--   · ventas_resultados: suma 'abrieron_enlace' (conversaciones cuyo enlace se abrió).

create or replace function public.ventas_marcar_visita(p_chat bigint)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update ventas_chats
     set oferta = coalesce(oferta, '{}'::jsonb)
                  || jsonb_build_object('visita_at', coalesce(oferta ->> 'visita_at', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SSOF')),
                                        'visitas', coalesce((oferta ->> 'visitas')::int, 0) + 1)
   where id = p_chat and abierta_at > now() - interval '60 days';
$$;
revoke all on function public.ventas_marcar_visita(bigint) from public, anon, authenticated;

do $mig$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.ventas_seguimientos_tomar(int)'::regprocedure);
  if position('''visito''' in v_def) = 0 then
    if position('''hora'', oferta ->> ''hora'')' in v_def) = 0 then raise exception 'ventas_seguimientos_tomar: no encuentro el texto a cambiar'; end if;
    v_def := replace(v_def, '''hora'', oferta ->> ''hora'')', '''hora'', oferta ->> ''hora'', ''visito'', (oferta ? ''visita_at''))');
    execute v_def;
  end if;

  v_def := pg_get_functiondef('public.ventas_resultados(int)'::regprocedure);
  if position('abrieron_enlace' in v_def) = 0 then
    if position('''respondieron'', (select count(*) from c where turnos > 0),' in v_def) = 0 then raise exception 'ventas_resultados: no encuentro el texto a cambiar'; end if;
    v_def := replace(v_def, '''respondieron'', (select count(*) from c where turnos > 0),',
      '''respondieron'', (select count(*) from c where turnos > 0),
    ''abrieron_enlace'', (select count(*) from c where oferta ? ''visita_at''),');
    execute v_def;
  end if;
end
$mig$;
