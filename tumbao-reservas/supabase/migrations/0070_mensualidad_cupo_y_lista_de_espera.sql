-- ---------------------------------------------------------------------
-- 0070 — La mensualidad tiene cupo, y quien no alcanza queda en lista
--
-- EL AGUJERO QUE TAPA
-- Hoy el embudo es: Instagram/Facebook/TikTok → WhatsApp → y ahí se
-- parte en dos. Quien quiere CLASE SUELTA se va a la página y el sistema
-- lo lleva de la mano. Quien quiere MENSUALIDAD no se va a ninguna
-- parte: se le contesta a mano, y a veces se le manda el número de
-- cuenta «por error» y paga. Esa plata entra al banco sin que nadie
-- sepa de quién es ni a qué hora quiere venir — es una de las fuentes de
-- los depósitos sin dueño que aparecen en el cierre.
--
-- Y ahora además hay un tope: la mensualidad no puede crecer sin
-- límite porque el salón se queda sin nada que vender en la puerta. Con
-- 25 mensualidades por hora y aforo 35 quedan 10 sillas para clase
-- suelta. Cuando el cupo se acaba, la respuesta no puede seguir siendo
-- «te aviso»: tiene que quedar registrada.
--
-- LO QUE ESTO CREA
--   · una tabla donde cae toda solicitud de mensualidad, con o sin cupo
--   · `mensualidad_cupos()` — cuántos cupos quedan por hora, en vivo
--   · `mensualidad_solicitar()` — decide si hay cupo y en qué estado cae
--   · `mensualidad_reportar_pago()` — la persona dice «ya pagué»
--   · `mensualidad_lista()` — lo que ve el panel
--
-- EL CUPO SE APARTA MIENTRAS SE PAGA, Y CADUCA
-- Si cinco personas llenan el formulario de las 6pm a la vez y solo
-- quedan dos cupos, no se les puede decir a las cinco que hay sitio. Una
-- solicitud en `esperando_pago` OCUPA cupo mientras está fresca. Pero no
-- para siempre: a las 24 horas sin pagar el cupo se suelta solo, igual
-- que un cupo de clase suelta abandonado. Sin esa caducidad, tres
-- curiosos bloquearían la hora entera para siempre.
--
-- EL TOPE VIVE EN `ajustes`, NO AQUÍ
-- Va a cambiar —es una decisión de negocio, no de código— y cambiarlo no
-- puede exigir una migración. Lo mismo las horas que se ofrecen: hoy son
-- las tres entre semana que tienen mensualidad, y el sábado no tiene
-- porque es solo clase suelta.
--
-- LAS MEDIAS MENSUALIDADES CUENTAN. Una media ocupa una silla igual que
-- un plan: viene menos días, pero cuando viene ocupa. Es como ya lo
-- cuenta `recalcular_cupos` para el aforo, y que las dos mitades del
-- sistema contaran distinto sería peor que no contar.
-- ---------------------------------------------------------------------

-- ── la configuración ──────────────────────────────────────────────────
insert into ajustes (clave, valor, nota) values
  ('mensualidad_tope_por_hora', '25',
   'Cuántas mensualidades (plan + media) caben por hora. Con aforo 35 '
   'deja 10 sillas para clase suelta. Subirlo o bajarlo es una decisión '
   'de negocio: se cambia aquí, sin tocar código.'),
  ('mensualidad_horas', '07:00,18:00,19:00',
   'Las horas que la página ofrece para mensualidad, separadas por coma. '
   'El sábado no está: es solo clase suelta.'),
  ('mensualidad_valor_cop', '125000',
   'Lo que cuesta el plan mensual. La media mensualidad no se vende por '
   'la página todavía.')
on conflict (clave) do nothing;

-- ── la tabla ──────────────────────────────────────────────────────────
create table if not exists mensualidad_solicitudes (
  id           uuid primary key default extensions.gen_random_uuid(),
  creado_at    timestamptz not null default now(),

  nombre       text not null,
  celular      text not null,
  documento    text,
  correo       text,

  hora         time not null,
  tipo         text not null default 'plan',
  valor_cop    int  not null,

  -- lista_espera   → no había cupo; queda anotada y se le avisa
  -- esperando_pago → hay cupo, se le dieron los datos para transferir
  -- pagada         → dijo que pagó (o se le cruzó el depósito)
  -- atendida       → ya se convirtió en membresía de verdad
  -- anulada        → se descartó a mano
  estado       text not null default 'lista_espera',

  -- Lo que dice la persona al reportar el pago. La referencia es lo que
  -- después amarra este cobro con el renglón del extracto.
  pagado_en    timestamptz,
  referencia   text,
  -- El depósito del banco, cuando alguien lo cruce desde el panel.
  pago_id      uuid references pagos(id),

  nota         text,
  atendida_at  timestamptz,
  atendida_por uuid,

  constraint mensualidad_solicitudes_tipo_ck
    check (tipo in ('plan', 'media')),
  constraint mensualidad_solicitudes_estado_ck
    check (estado in ('lista_espera', 'esperando_pago', 'pagada',
                      'atendida', 'anulada')),
  constraint mensualidad_solicitudes_valor_ck
    check (valor_cop > 0)
);

comment on table mensualidad_solicitudes is
  'Quien quiere mensualidad. Cae aquí con cupo (esperando_pago) o sin él '
  '(lista_espera). Antes de esto no caía en ninguna parte: se contestaba '
  'por WhatsApp y a veces se mandaba la cuenta sin registrar nada.';

-- Se consulta por hora y estado en cada visita a la página: sin índice
-- eso es un recorrido completo por cada persona que abre el formulario.
create index if not exists mensualidad_solicitudes_hora_estado_ix
  on mensualidad_solicitudes (hora, estado, creado_at desc);

-- Para encontrar a alguien por su celular desde el panel.
create index if not exists mensualidad_solicitudes_celular_ix
  on mensualidad_solicitudes (celular);

-- La tabla lleva nombres, cédulas y teléfonos de clientas. Nadie llega a
-- ella con la llave pública: todo pasa por las funciones de abajo, que
-- son SECURITY DEFINER y las llama el Worker con la llave de servicio.
alter table mensualidad_solicitudes enable row level security;

-- ── cuántos cupos quedan ──────────────────────────────────────────────
create or replace function public.mensualidad_cupos()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_tope  int;
  v_horas text;
  v_valor int;
  v_out   jsonb;
begin
  select coalesce((select valor::int from ajustes where clave = 'mensualidad_tope_por_hora'), 25)
    into v_tope;
  select coalesce((select valor from ajustes where clave = 'mensualidad_horas'), '07:00,18:00,19:00')
    into v_horas;
  select coalesce((select valor::int from ajustes where clave = 'mensualidad_valor_cop'), 125000)
    into v_valor;

  with horas as (
    select btrim(x)::time as hora, ordinality as orden
      from unnest(string_to_array(v_horas, ',')) with ordinality as t(x, ordinality)
  ),
  cuenta as (
    select h.hora, h.orden,
           -- Las mensualidades vigentes hoy. Plan y media cuentan igual:
           -- una media viene menos días pero cuando viene ocupa silla.
           (select count(*) from membresias m
             where m.hora = h.hora
               and current_date between m.inicio and m.fin)::int as activas,
           -- Y las solicitudes que ya tienen cupo apartado mientras
           -- pagan. Caducan a las 24 horas: sin eso, tres curiosos
           -- bloquearían la hora entera para siempre.
           (select count(*) from mensualidad_solicitudes s
             where s.hora = h.hora
               and s.estado = 'esperando_pago'
               and s.creado_at > now() - interval '24 hours')::int as apartadas,
           -- Las que ya pagaron y esperan que alguien las convierta en
           -- membresía: esas no caducan, su plata ya entró.
           (select count(*) from mensualidad_solicitudes s
             where s.hora = h.hora and s.estado = 'pagada')::int as pagadas
      from horas h
  )
  select jsonb_build_object(
    'ok', true,
    'tope', v_tope,
    'valor_cop', v_valor,
    'horas', coalesce(jsonb_agg(jsonb_build_object(
        'hora',   to_char(c.hora, 'HH24:MI'),
        'etiqueta', ltrim(to_char(c.hora, 'HH12:MI am'), '0'),
        'ocupadas', c.activas + c.apartadas + c.pagadas,
        'tope',     v_tope,
        'libres',   greatest(v_tope - (c.activas + c.apartadas + c.pagadas), 0)
      ) order by c.orden), '[]'::jsonb))
    into v_out
    from cuenta c;

  return v_out;
end;
$$;

-- ── pedir la mensualidad ──────────────────────────────────────────────
create or replace function public.mensualidad_solicitar(
  p_nombre    text,
  p_celular   text,
  p_hora      text,
  p_documento text default null,
  p_correo    text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_hora   time;
  v_horas  text;
  v_valor  int;
  v_cupos  jsonb;
  v_libres int;
  v_id     uuid;
  v_estado text;
  v_previa mensualidad_solicitudes;
begin
  if length(btrim(coalesce(p_nombre, ''))) < 2 then
    return jsonb_build_object('ok', false, 'error', 'NOMBRE_CORTO');
  end if;
  if coalesce(p_celular, '') !~ '^\d{10}$' then
    return jsonb_build_object('ok', false, 'error', 'CELULAR_INVALIDO');
  end if;

  begin
    v_hora := btrim(p_hora)::time;
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'HORA_INVALIDA');
  end;

  -- Solo las horas que de verdad se ofrecen. Sin esto alguien podría
  -- apuntarse a una hora que no existe y quedar en una lista que nadie
  -- mira.
  select coalesce((select valor from ajustes where clave = 'mensualidad_horas'), '07:00,18:00,19:00')
    into v_horas;
  if not exists (select 1 from unnest(string_to_array(v_horas, ',')) x
                  where btrim(x)::time = v_hora) then
    return jsonb_build_object('ok', false, 'error', 'HORA_NO_DISPONIBLE');
  end if;

  select coalesce((select valor::int from ajustes where clave = 'mensualidad_valor_cop'), 125000)
    into v_valor;

  -- YA VINO ANTES. El doble toque en un botón, o quien vuelve a abrir el
  -- enlace, no puede crear dos solicitudes ni comerse dos cupos: se le
  -- devuelve la suya. Solo se reusa la que sigue viva.
  select * into v_previa
    from mensualidad_solicitudes
   where celular = p_celular and hora = v_hora
     and estado in ('lista_espera', 'esperando_pago', 'pagada')
     and creado_at > now() - interval '24 hours'
   order by creado_at desc
   limit 1;

  if found then
    return jsonb_build_object(
      'ok', true, 'id', v_previa.id, 'estado', v_previa.estado,
      'valor_cop', v_previa.valor_cop, 'ya_estaba', true);
  end if;

  -- El cupo se mira AQUÍ y no en el navegador: entre que la página pintó
  -- "quedan 2" y la persona terminó de escribir su cédula pueden haberse
  -- ido los dos.
  v_cupos := mensualidad_cupos();
  select (h->>'libres')::int into v_libres
    from jsonb_array_elements(v_cupos->'horas') h
   where h->>'hora' = to_char(v_hora, 'HH24:MI');

  v_estado := case when coalesce(v_libres, 0) > 0
                   then 'esperando_pago' else 'lista_espera' end;

  insert into mensualidad_solicitudes
    (nombre, celular, documento, correo, hora, tipo, valor_cop, estado)
  values (btrim(p_nombre), p_celular,
          nullif(btrim(coalesce(p_documento, '')), ''),
          nullif(lower(btrim(coalesce(p_correo, ''))), ''),
          v_hora, 'plan', v_valor, v_estado)
  returning id into v_id;

  return jsonb_build_object(
    'ok', true, 'id', v_id, 'estado', v_estado,
    'valor_cop', v_valor, 'ya_estaba', false);
end;
$$;

-- ── «ya pagué» ────────────────────────────────────────────────────────
create or replace function public.mensualidad_reportar_pago(
  p_id         uuid,
  p_referencia text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_s mensualidad_solicitudes;
begin
  select * into v_s from mensualidad_solicitudes where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;
  -- Quien está en lista de espera no debería poder decir que pagó: no se
  -- le dieron los datos de la cuenta. Si lo hace, es que pagó por otro
  -- lado y hay que mirarlo a mano.
  if v_s.estado = 'lista_espera' then
    return jsonb_build_object('ok', false, 'error', 'SIN_CUPO',
      'mensaje', 'Estás en lista de espera: todavía no hay cupo en esa hora.');
  end if;
  if v_s.estado in ('pagada', 'atendida') then
    return jsonb_build_object('ok', true, 'estado', v_s.estado, 'ya_estaba', true);
  end if;
  if v_s.estado = 'anulada' then
    return jsonb_build_object('ok', false, 'error', 'ANULADA');
  end if;

  update mensualidad_solicitudes
     set estado     = 'pagada',
         pagado_en  = now(),
         referencia = nullif(btrim(coalesce(p_referencia, '')), '')
   where id = p_id;

  return jsonb_build_object('ok', true, 'estado', 'pagada', 'ya_estaba', false);
end;
$$;

-- ── lo que ve el panel ────────────────────────────────────────────────
create or replace function public.mensualidad_lista(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_admin uuid;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  return jsonb_build_object(
    'ok', true,
    'cupos', mensualidad_cupos(),
    -- Lo pendiente primero y lo más viejo arriba: quien lleva más
    -- esperando es a quien hay que llamar antes.
    'solicitudes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id,
               'cuando', to_char(s.creado_at at time zone 'America/Bogota', 'DD/MM HH24:MI'),
               'dias', (current_date - (s.creado_at at time zone 'America/Bogota')::date),
               'nombre', s.nombre, 'celular', s.celular,
               'documento', s.documento, 'correo', s.correo,
               'hora', to_char(s.hora, 'HH24:MI'),
               'estado', s.estado, 'valor_cop', s.valor_cop,
               'referencia', s.referencia,
               'pagado_en', s.pagado_en,
               'nota', s.nota)
             order by
               case s.estado when 'pagada' then 0 when 'esperando_pago' then 1
                             when 'lista_espera' then 2 else 3 end,
               s.creado_at)
        from mensualidad_solicitudes s
       where s.estado <> 'anulada'
         and s.creado_at > now() - interval '90 days'), '[]'::jsonb));
end;
$$;

-- Las públicas las llama el Worker con la llave de servicio. Nadie llega
-- a ellas con la llave anónima: la tabla lleva cédulas y teléfonos.
revoke all on function public.mensualidad_cupos() from public, anon;
revoke all on function public.mensualidad_solicitar(text, text, text, text, text) from public, anon;
revoke all on function public.mensualidad_reportar_pago(uuid, text) from public, anon;
revoke all on function public.mensualidad_lista(text) from public, anon;
grant execute on function public.mensualidad_cupos() to service_role;
grant execute on function public.mensualidad_solicitar(text, text, text, text, text) to service_role;
grant execute on function public.mensualidad_reportar_pago(uuid, text) to service_role;
grant execute on function public.mensualidad_lista(text) to service_role;
