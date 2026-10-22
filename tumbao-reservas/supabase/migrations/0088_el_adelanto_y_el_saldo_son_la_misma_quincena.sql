-- 0088 — El adelanto y el saldo son la misma quincena
--
-- POR QUÉ
--
-- Al montar la tesorería marqué cuatro adelantos de quincena con un aviso
-- que decía «esto puede estar contado dos veces» y no los resté, porque
-- restarlos sin mirar el desprendible habría sido inventarme una utilidad.
--
-- Damián leyó el chat y me corrigió los de septiembre:
--
--   «esos 300.000 ya se habían dado y se pagó 650.000 para completar la
--    quincena que es 950.000»
--
-- Al volver al chat con eso en la cabeza aparece la regla que me faltaba, y
-- es de Tanya, no mía: ella escribe «adelanto» cuando entrega una parte y
-- «saldo» cuando entrega lo que falta. Dos mensajes, dos transferencias
-- distintas, una sola quincena.
--
--   6/8   «350000 adelanto quincena»
--   15/8  «600000 pago SALDO quincena Fabián»        350 + 600 = 950  ✓
--
--   12/9  «300000 adelantó fabi»
--   15/9  «650000 SALDO nómina quincena»             300 + 650 = 950  ✓
--
-- Donde dice «saldo» no hay doble conteo: el segundo pago ya viene rebajado.
-- Si el del 15 de agosto hubiera sido la quincena completa habría dicho
-- 950.000, como sí dicen los de Luisa. Dice 600.000. Eso lo cierra.
--
-- Así que el aviso estaba mal planteado. No sobraba plata: cada renglón es
-- una transferencia real y el gasto del mes siempre estuvo bien. Lo único
-- que hacía falta era saber a qué quincena pertenecía cada mitad.
--
-- ── LO QUE SÍ QUEDA POR MIRAR ───────────────────────────────────────────
--
-- Reconstruida la nómina persona por persona, quedan dos diferencias, y son
-- mucho más chicas y más concretas que el susto original:
--
--   Luisa (quincena 950.000)
--     10/8  adelantó            250.000
--     15/8  «quincena Luisa»    950.000   ← completa, NO dice saldo
--     31/8  «nómina Luisa»      950.000
--     16/9  «nómina quincena»   950.000
--   Sus tres quincenas se pagaron enteras. Los 250.000 del 10 no se le
--   descontaron de ninguna. O es un préstamo pendiente de recuperar, o se
--   descontó en un sitio que el chat no muestra.
--
--   Fabián, segunda quincena de agosto (16–31)
--     15/8  «ajuste de quincena, descuento en siguiente quincena»  350.000
--     29/8  «pago quincena fabián»                                 650.000
--                                                         suma  1.000.000
--   Contra una quincena de 950.000 sobran 50.000. El descuento sí se hizo
--   —si no, el pago del 29 habría sido de 950.000— pero por 300.000 y no
--   por 350.000. Es una diferencia de 50.000, no de 350.000.
--
-- Esos dos siguen con aviso. Los otros dos quedan validados.
--
-- ── EL AVISO CAMBIA DE PREGUNTA ─────────────────────────────────────────
--
-- Antes el panel avisaba por `es_adelanto`: todo adelanto era sospechoso
-- para siempre, y revisarlo no servía de nada porque el aviso volvía al mes
-- siguiente igual de rojo. Ahora avisa por `revisar`, que es justamente la
-- columna que dice «esto todavía no lo ha mirado nadie». Cuando se mira, se
-- apunta el veredicto en `nota`, se borra el `revisar` y el aviso se calla.
--
-- `es_adelanto` no se toca: era un adelanto y lo sigue siendo. Es un dato
-- del pago, no un juicio sobre él.
--
-- Efecto en la cifra: `adelantos_cop` deja de sumar los validados, y con
-- ellos `utilidad_sin_adelantos_cop` deja de inflarse. En septiembre esa
-- segunda utilidad estaba 300.000 por encima de la de verdad. Ya no.

-- ── los dos que quedan validados ────────────────────────────────────────

update gastos set
  a_quien = 'Fabián',
  revisar = null,
  nota    = 'Validado 19/9. Primera quincena de agosto de Fabián: 350.000 el 6 '
         || 'más el «saldo quincena Fabián» de 600.000 el 15 = 950.000. El del '
         || '15 dice saldo, no quincena, así que ya venía descontado. El chat '
         || 'no pone el nombre el día 6; se lo pone el saldo del 15.'
where fuente = 'whatsapp' and dia = date '2026-08-06'
  and valor_cop = 350000 and concepto = 'adelanto quincena';

update gastos set
  revisar = null,
  nota    = 'Validado 19/9 por Damián: «ya se habían dado esos 300.000 y se '
         || 'pagó 650.000 para completar la quincena que es 950.000». El pago '
         || 'del 15 dice «saldo nómina quincena»: ya venía descontado.'
where fuente = 'whatsapp' and dia = date '2026-09-12'
  and valor_cop = 300000 and concepto = 'adelanto Fabián';

-- El otro lado del par, para que el libro se lea solo.
update gastos set
  a_quien = 'Fabián',
  nota    = 'Es el saldo de la primera quincena de septiembre de Fabián: '
         || '300.000 adelantados el 12 más estos 650.000 = 950.000.'
where fuente = 'whatsapp' and dia = date '2026-09-15'
  and valor_cop = 650000 and concepto = 'saldo nómina quincena';

-- ── los dos que siguen abiertos, con la pregunta bien hecha ─────────────

update gastos set
  revisar = 'Sus tres quincenas de agosto y septiembre se pagaron enteras '
         || '(950.000 el 15/8, el 31/8 y el 16/9) y ninguna dice «saldo». '
         || 'Estos 250.000 no se le descontaron de ninguna: o es un préstamo '
         || 'por recuperar, o el descuento está en un sitio que el chat no '
         || 'muestra. Son 250.000 por aclarar, no un gasto de más.'
where fuente = 'whatsapp' and dia = date '2026-08-10'
  and valor_cop = 250000 and concepto = 'adelanto Luisa';

update gastos set
  revisar = 'El mensaje dice «descuento en siguiente quincena». La siguiente '
         || 'se pagó el 29/8 por 650.000: si no se hubiera descontado nada '
         || 'habría sido de 950.000, así que el descuento sí se hizo, pero '
         || 'por 300.000. Sobran 50.000 contra la quincena. Es lo único que '
         || 'hay que mirar en el desprendible.'
where fuente = 'whatsapp' and dia = date '2026-08-15'
  and valor_cop = 350000 and concepto = 'ajuste de quincena';

-- ── el aviso ahora pregunta por lo que falta mirar, no por lo que fue ───

do $$
declare
  d text := pg_get_functiondef('public.admin_tesoreria(text, date, date)'::regprocedure);

  -- 1. la cifra: solo los adelantos que nadie ha cuadrado todavía
  a_viejo constant text :=
    'select coalesce(sum(valor_cop), 0) into v_ade
    from gastos where not anulado and es_adelanto
      and dia between v_desde and v_hasta;';
  a_nuevo constant text :=
    '-- 0088: solo los que siguen sin cuadrar. Un adelanto emparejado con su
  -- saldo es plata que salió una sola vez y ya está bien contada; seguir
  -- sumándolo aquí inflaba `utilidad_sin_adelantos_cop` en 300.000.
  select coalesce(sum(valor_cop), 0) into v_ade
    from gastos where not anulado and es_adelanto and revisar is not null
      and dia between v_desde and v_hasta;';

  -- 2. el texto: ya sabemos que el doble conteo no era el problema
  b_viejo constant text :=
    '-- 1. Los adelantos. Es lo que más infla un mes.
  if v_ade > 0 then
    select count(*)::int into v_n from gastos
     where not anulado and es_adelanto and dia between v_desde and v_hasta;
    v_rev := v_rev || jsonb_build_object(
      ''clave'', ''adelantos'', ''peso'', 1, ''cop'', v_ade,
      ''titulo'', ''Adelantos de quincena que pueden estar contados dos veces'',
      ''detalle'', v_n || '' pago'' || case when v_n = 1 then '''' else ''s'' end ||
        '' de adelanto. Si la quincena se pagó después completa, este dinero '' ||
        ''salió una vez pero está sumado dos, y la utilidad sale peor de lo que es.'');
  end if;';
  b_nuevo constant text :=
    '-- 1. Los adelantos que todavía no se emparejan con su quincena.
  -- 0088: el aviso ya no es «están contados dos veces». Tanya escribe
  -- «adelanto» a la parte y «saldo» a lo que falta, y donde dice saldo el
  -- segundo pago ya viene rebajado: la suma del mes siempre estuvo bien.
  -- Lo que queda es saber a qué quincena pertenece cada mitad, y eso se
  -- apunta en `revisar`. Cuadrado el par, se borra y el aviso se calla.
  if v_ade > 0 then
    select count(*)::int into v_n from gastos
     where not anulado and es_adelanto and revisar is not null
       and dia between v_desde and v_hasta;
    v_rev := v_rev || jsonb_build_object(
      ''clave'', ''adelantos'', ''peso'', 1, ''cop'', v_ade,
      ''titulo'', ''Adelantos sin cuadrar con su quincena'',
      ''detalle'', v_n || '' adelanto'' || case when v_n = 1 then '''' else ''s'' end ||
        '' sin descontar de ninguna quincena. La plata salió, eso no se discute; '' ||
        ''falta saber si se recupera o ya se descontó. Ábrelos abajo: cada uno '' ||
        ''dice qué mirar.'');
  end if;';

  -- Este es el mismo bloque con una concordancia mal hecha: pluralizaba
  -- «descontado» pero dejaba «se ve» en singular, y el panel llegó a decir
  -- «2 adelantos que no se ve descontados». Estuvo un rato en producción, así
  -- que hay que saber reconocerlo; no vale gastar una migración en una ese.
  b_torcido constant text :=
    '-- 1. Los adelantos que todavía no se emparejan con su quincena.
  -- 0088: el aviso ya no es «están contados dos veces». Tanya escribe
  -- «adelanto» a la parte y «saldo» a lo que falta, y donde dice saldo el
  -- segundo pago ya viene rebajado: la suma del mes siempre estuvo bien.
  -- Lo que queda es saber a qué quincena pertenece cada mitad, y eso se
  -- apunta en `revisar`. Cuadrado el par, se borra y el aviso se calla.
  if v_ade > 0 then
    select count(*)::int into v_n from gastos
     where not anulado and es_adelanto and revisar is not null
       and dia between v_desde and v_hasta;
    v_rev := v_rev || jsonb_build_object(
      ''clave'', ''adelantos'', ''peso'', 1, ''cop'', v_ade,
      ''titulo'', ''Adelantos sin cuadrar con su quincena'',
      ''detalle'', v_n || '' adelanto'' || case when v_n = 1 then '''' else ''s'' end ||
        '' que no se ve descontado'' || case when v_n = 1 then '''' else ''s'' end ||
        '' de ninguna quincena. La plata salió, eso no se discute; falta saber '' ||
        ''si se recupera o ya se descontó. Ábrelos abajo: cada uno dice qué mirar.'');
  end if;';
begin
  -- Reejecutable a propósito: normaliza venga de donde venga (0087, o del
  -- 0088 con la ese de más). Lo que no puede es quedarse a medias.
  if position(a_viejo in d) > 0 then
    d := replace(d, a_viejo, a_nuevo);
  elsif position(a_nuevo in d) = 0 then
    raise exception '0088: no encuentro el cálculo de v_ade en admin_tesoreria';
  end if;

  if position(b_viejo in d) > 0 then
    d := replace(d, b_viejo, b_nuevo);
  elsif position(b_torcido in d) > 0 then
    d := replace(d, b_torcido, b_nuevo);
  elsif position(b_nuevo in d) = 0 then
    raise exception '0088: no encuentro el aviso de adelantos en admin_tesoreria';
  end if;

  execute d;
end $$;
