-- 0089 — Junio y julio, del mismo chat
--
-- La exportación nueva del chat de GASTOS TUMBAO llega hasta el 21 de
-- junio; la de la vez pasada arrancaba el 1 de agosto. Esto es lo que
-- faltaba por delante: 58 renglones, del 21/6 al 31/7.
--
-- Mismo criterio que la 0087: el `concepto` es lo que escribió Tanya,
-- sin limpiar, y la categoría va aparte. Y mismo criterio que la 0088
-- con los adelantos, que aquí vuelven a aparecer y vuelven a cuadrar:
--
--   21/6  «100000 adelantó fabián»
--   27/6  «300000 adelantó profe fabián»
--   30/6  «550000 SALDO de pago quincena»      100+300+550 = 950  ✓
--
-- Tercera vez que el patrón se cumple clavado (junio, agosto y
-- septiembre). Los dos adelantos entran validados, sin aviso.
--
-- Tres renglones sí quedan con aviso, y ninguno es un adelanto de
-- quincena:
--
--   23/7  241.000  «préstamo certificación fabián» — dice préstamo, no
--         pago: es plata que vuelve, y no se ve descontada después.
--   27/7  180.000  «pintada de pared» — Damián preguntó dos veces en el
--         chat si el valor era ése y no hubo respuesta.
--   31/7   80.000  «pago reserva cumpleaños Mayra» — puede ser un pago
--         por trabajar el evento o una devolución a la clienta.
--
-- La caja menor de junio y julio entra aquí como un gasto más: la Caja
-- del sistema no empezó hasta el 10/8, así que no hay nada con lo que
-- chocar y no se cuenta dos veces.
--
-- El guardia del insert mira si ya hay algún gasto de WhatsApp anterior
-- a agosto; con eso, correrla dos veces no duplica nada.

insert into gastos (dia, valor_cop, concepto, categoria, medio, a_quien,
                    es_adelanto, revisar, nota, fuente)
select v.dia::date, v.valor_cop, v.concepto, v.categoria, v.medio, v.a_quien,
       v.es_adelanto, v.revisar, v.nota, 'whatsapp'
  from (values
  ('2026-06-21',100000,'adelantó fabián','nomina','banco','Fabián',true,null,'Validado: primera parte de la quincena del 30/6 de Fabián. 100.000 el 21 + 300.000 el 27 + el «saldo de pago quincena» de 550.000 el 30 = 950.000.'),
  ('2026-06-22',517400,'Seguridad social Mayo Fabián','nomina','banco','Fabián',false,null,null),
  ('2026-06-22',400000,'bono fabián','nomina','banco','Fabián',false,null,null),
  ('2026-06-23',60000,'pago clase fabi lunes','profesores','banco','Fabián',false,null,null),
  ('2026-06-24',60000,'clase profe fabián','profesores','banco','Fabián',false,null,null),
  ('2026-06-24',20000,'aseo tumbao (egresos de caja)','mantenimiento','efectivo',null,false,null,'Caja menor. En junio la Caja todavía no existía —empezó el 10/8— así que este renglón sólo está aquí y no se cuenta dos veces.'),
  ('2026-06-25',258800,'pago pila fabián, 15 días de junio','nomina','banco','Fabián',false,null,null),
  ('2026-06-27',60000,'clase profe Nagle','profesores',null,'Nagle',false,null,null),
  ('2026-06-27',300000,'adelantó profe fabián','nomina','banco','Fabián',true,null,'Validado: segunda parte de la quincena del 30/6 de Fabián. Ver el renglón del 21.'),
  ('2026-06-28',80000,'clase club infantas','profesores','banco',null,false,null,null),
  ('2026-06-28',120000,'Redes y transporte, club infantas','mercadeo','banco',null,false,null,null),
  ('2026-06-28',40000,'apoyo club infantas','viaticos','banco',null,false,null,null),
  ('2026-06-30',40000,'elementos de aseo solar city','mantenimiento','banco',null,false,null,null),
  ('2026-06-30',550000,'saldo de pago quincena','nomina','banco','Fabián',false,null,'Es el saldo: 100.000 del 21 + 300.000 del 27 + estos 550.000 = 950.000, la quincena.'),
  ('2026-06-30',225000,'pago quincena damian','nomina','banco','Damián',false,null,null),
  ('2026-06-30',950000,'quincena yeli','nomina','banco','Yeli',false,null,null),
  ('2026-07-01',5000,'bolsas grandes','mantenimiento','efectivo',null,false,null,null),
  ('2026-07-02',20000,'Julián, mantenimiento','mantenimiento','efectivo','Julián',false,null,null),
  ('2026-07-03',60000,'milena clase','profesores','banco','Milena',false,null,'En el chat se anota debajo «recibió Tanya 60.000 en efectivo»: es cómo se entregó este mismo pago, no un segundo pago.'),
  ('2026-07-03',60000,'clase profe fabián','profesores','banco','Fabián',false,null,null),
  ('2026-07-04',60000,'profe nagle','profesores','banco','Nagle',false,null,null),
  ('2026-07-08',60000,'clase lunes','profesores','banco',null,false,null,null),
  ('2026-07-08',70000,'reserva cumple','profesores','banco',null,false,null,null),
  ('2026-07-09',18000,'aseo','mantenimiento','efectivo',null,false,null,null),
  ('2026-07-10',50000,'tumbao mantenimiento','mantenimiento',null,null,false,null,null),
  ('2026-07-13',70000,'pago clase Festivo profesor fabián','profesores','banco','Fabián',false,null,null),
  ('2026-07-13',40000,'aseo tumbao','mantenimiento',null,null,false,null,null),
  ('2026-07-15',80000,'nómina Luz alejandra','nomina','banco','Luz Alejandra',false,null,null),
  ('2026-07-15',950000,'pago quincena fabián','nomina','banco','Fabián',false,null,null),
  ('2026-07-15',1050000,'pago quincena yeli + redes','nomina','banco','Yeli',false,null,null),
  ('2026-07-15',225000,'quincena damian','nomina','banco','Damián',false,null,null),
  ('2026-07-15',60000,'clase martes profe fabián','profesores','banco','Fabián',false,null,null),
  ('2026-07-16',1800000,'pago arriendo tumbao efectivo','arriendo','efectivo',null,false,null,null),
  ('2026-07-18',60000,'clase profe nagle','profesores','banco','Nagle',false,null,null),
  ('2026-07-19',70000,'reserva domingo Fabian','profesores','banco','Fabián',false,null,null),
  ('2026-07-21',105000,'pago sistema','sistema','banco',null,false,null,null),
  ('2026-07-21',17000,'Aseo TUMBAO','mantenimiento','efectivo',null,false,null,null),
  ('2026-07-22',258600,'Pago PILA 15na Junio Fabian','nomina','banco','Fabián',false,null,null),
  ('2026-07-22',542500,'Pago Planilla Julio Yeli','nomina','banco','Yeli',false,null,null),
  ('2026-07-22',60000,'pago clase martes fabián','profesores','banco','Fabián',false,null,null),
  ('2026-07-23',241000,'préstamo certificación fabián','nomina','banco','Fabián',true,'Dice «préstamo», no pago: es plata que vuelve. No se ve descontada de ninguna quincena posterior. Confirmar si ya se recuperó o sigue pendiente.',null),
  ('2026-07-23',140000,'mantenientos tumbao julian','mantenimiento','banco','Julián',false,null,null),
  ('2026-07-23',60000,'milena profe','profesores','banco','Milena',false,null,null),
  ('2026-07-24',53000,'pintura tumbao','mantenimiento',null,null,false,null,null),
  ('2026-07-24',3500,'Marcador azul','otros','efectivo',null,false,null,null),
  ('2026-07-25',130000,'soldador','mantenimiento','banco',null,false,null,null),
  ('2026-07-26',60000,'pago profe Nagle','profesores','banco','Nagle',false,null,null),
  ('2026-07-27',180000,'pintada de pared, mantenimiento','mantenimiento',null,null,false,'Damián preguntó dos veces en el chat si el valor era 180.000 y no hubo respuesta. El 24 ya se habían pagado 53.000 de pintura. Confirmar el valor antes de darlo por bueno.',null),
  ('2026-07-28',950000,'quincena','nomina','banco',null,false,null,'El mensaje del 28 junta tres pagos: 950 de quincena y dos clases de 60. Salió de la cuenta de Juliana.'),
  ('2026-07-28',60000,'clase lunes','profesores','banco',null,false,null,null),
  ('2026-07-28',60000,'clase martes','profesores','banco',null,false,null,null),
  ('2026-07-28',30000,'Gastos papelería','otros','efectivo',null,false,null,null),
  ('2026-07-29',400000,'abono camisetas tumbao','mercadeo','banco',null,false,null,null),
  ('2026-07-29',25000,'Aseo TUMBAO','mantenimiento','efectivo',null,false,null,null),
  ('2026-07-30',1050000,'quincena yeli','nomina','banco','Yeli',false,null,null),
  ('2026-07-30',375000,'quincena damian','nomina','banco','Damián',false,null,null),
  ('2026-07-30',150000,'remplazos luisa','nomina','banco','Luisa',false,null,null),
  ('2026-07-31',80000,'pago reserva cumpleaños Mayra','profesores','banco','Mayra',false,'Salió de la cuenta de Tumbao y está en el chat de gastos, así que se carga como salida. Pero «pago reserva cumpleaños» también puede ser una devolución a la clienta: confirmar cuál de las dos es.',null)
) as v(dia, valor_cop, concepto, categoria, medio, a_quien, es_adelanto, revisar, nota)
 where not exists (select 1 from gastos g
                    where g.fuente = 'whatsapp' and g.dia < date '2026-08-01');
