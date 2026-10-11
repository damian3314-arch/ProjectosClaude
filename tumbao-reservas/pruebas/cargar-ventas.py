# -*- coding: utf-8 -*-
"""Convierte el reporte de ventas de AdminGym en el insert de `ventas_mostrador`.

El .xlsx que exporta AdminGym («Reporte Ventas Membresías X días») trae una
venta por fila, con nombre, cédula, correo y celular. Aquí se agrega por
día × tipo × medio y se tiran las columnas de la persona: la tesorería no
las necesita y duplicarlas en la base es cargar un riesgo a cambio de nada.

    python3 cargar-ventas.py reporte.xlsx > nuevas_ventas.sql

Lo que sale es idempotente (`on conflict`), así que recargar el mismo mes
—o uno que se solape— pisa los renglones en vez de duplicarlos.

SOBRE «VALOR» Y «VALOR A PAGAR»: en la mayoría de las ventas son iguales.
Cuando no, hay un descuento o un pago parcial de por medio, y las dos
columnas no se usan igual en los dos casos. Se toma la menor, que es la
única lectura que da un número sensato en todos. `ajustadas_n` cuenta
cuántas ventas así hay en cada renglón, para poder ir a buscarlas.
"""
import re, sys, zipfile
from collections import defaultdict
from xml.etree import ElementTree as ET

NS = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
MES = {'ene':1,'feb':2,'mar':3,'abr':4,'may':5,'jun':6,
       'jul':7,'ago':8,'sep':9,'oct':10,'nov':11,'dic':12}


def filas(ruta):
    z = zipfile.ZipFile(ruta)
    hoja = ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
    for r in hoja.iter(NS + 'row'):
        c = {}
        for celda in r.findall(NS + 'c'):
            ref = re.match(r'([A-Z]+)', celda.get('r')).group(1)
            texto = celda.find(NS + 'is/' + NS + 't')
            valor = celda.find(NS + 'v')
            c[ref] = (texto.text if texto is not None
                      else (valor.text if valor is not None else ''))
        yield c


def fecha(s):
    """'05/ene./2026' → '2026-01-05'."""
    d, m, a = s.replace('.', '').split('/')
    return f'{a}-{MES[m[:3]]:02d}-{int(d):02d}'


def main(ruta):
    agg = defaultdict(lambda: [0, 0, 0])   # cobrado, ventas, ajustadas
    for f in list(filas(ruta))[2:]:        # dos filas de encabezado
        if not f.get('A'):
            continue
        valor  = int(f.get('I') or 0)
        pagar  = int(f.get('J') or 0)
        cobrado = valor if valor == pagar else min(valor, pagar)
        k = (fecha(f['A']), (f.get('G') or 'SIN TIPO').strip(),
             (f.get('H') or 'SIN MEDIO').strip())
        agg[k][0] += cobrado
        agg[k][1] += 1
        if valor != pagar:
            agg[k][2] += 1

    q = lambda s: "'" + str(s).replace("'", "''") + "'"
    print('insert into ventas_mostrador (dia, membresia, medio, cobrado_cop,'
          ' ventas_n, ajustadas_n)')
    print('select v.dia::date, v.membresia, v.medio, v.cobrado_cop,'
          ' v.ventas_n, v.ajustadas_n')
    print('  from (values')
    print(',\n'.join(
        f'  ({q(d)},{q(t)},{q(m)},{v[0]},{v[1]},{v[2]})'
        for (d, t, m), v in sorted(agg.items())))
    print(') as v(dia, membresia, medio, cobrado_cop, ventas_n, ajustadas_n)')
    print('on conflict (dia, membresia, medio) do update')
    print('   set cobrado_cop = excluded.cobrado_cop,')
    print('       ventas_n    = excluded.ventas_n,')
    print('       ajustadas_n = excluded.ajustadas_n,')
    print('       cargado_at  = now();')

    total = sum(v[0] for v in agg.values())
    ventas = sum(v[1] for v in agg.values())
    print(f'\n-- {len(agg)} renglones · {ventas} ventas · {total:,} cobrado'
          .replace(',', '.'), file=sys.stderr)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
