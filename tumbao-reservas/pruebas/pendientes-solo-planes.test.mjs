/** Ingresos por validar: de un día para otro solo pasan mensualidad y tiquetera (25 nov, Damián). node pendientes-solo-planes.test.mjs */
import { readFileSync } from 'node:fs';
const sql = readFileSync(new URL('../supabase/migrations/0218_pendientes_de_dias_anteriores_solo_planes.sql', import.meta.url), 'utf8').replace(/--.*$/gm, '');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
ok('los valores de plan salen de los ajustes (mensualidad y precios de tiquetera), no de números escritos a mano',
   /mensualidad_valor_cop/.test(sql) && /tiquetera_paquetes\(\)/.test(sql) && !/125000|52000|96000/.test(sql));
ok('Pendientes: los de hoy siempre; los de días anteriores solo si valen un plan',
   /admin_pendientes\(text\)/.test(sql) && /::date >= \(now\(\) at time zone ''America\/Bogota''\)::date\s+or p\.valor_cop = any \(valores_de_plan\(\)\)/.test(sql));
ok('la lista de Caja hace lo mismo respecto al día que se está mirando',
   /caja_del_dia\(text,date\)/.test(sql) && /::date >= v_dia\s+or p\.valor_cop = any \(valores_de_plan\(\)\)/.test(sql));
ok('no borra nada', !/\bdrop\s+(table|function|index|column|constraint)|\bdelete\s+from/i.test(sql));
console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
