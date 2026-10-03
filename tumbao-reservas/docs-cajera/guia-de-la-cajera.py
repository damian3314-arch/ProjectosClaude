#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Genera guia-de-la-cajera.pdf — la hoja que se imprime y se pega en recepción.

Para quién es: la persona que cobra de pie, con gente delante, y que a las
diez de la noche cierra la caja. No es documentación técnica. Si al editar
esto una frase se alarga o aparece una palabra de sistema, se corrige aquí
y se vuelve a generar:

    pip install reportlab
    python3 guia-de-la-cajera.py

Reglas de escritura que este archivo intenta respetar (no las rompas al
editar, son el motivo de que la hoja sirva):
  · Frases cortas, palabras normales. Nada de "sistema", "registro",
    "conciliación", "flujo".
  · Cada regla dice POR QUÉ. Una norma sin motivo se salta el día que hay cola.
  · Tres páginas. Si no cabe, sobra texto — no se achica la letra.
  · Los nombres de botones y de la tirilla son los que la cajera tiene
    delante. Si el panel los cambia, cámbialos aquí el mismo día.
"""

import os
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.colors import HexColor
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

# ── tipografía ──────────────────────────────────────────────────────────
# DejaVu y no Helvetica: Helvetica no trae ✓ ni ✗ y los pinta como cuadros
# negros. Las marcas de sí/no son la mitad de para qué sirve esta hoja.
FDIR = "/usr/share/fonts/truetype/dejavu"
pdfmetrics.registerFont(TTFont("D", os.path.join(FDIR, "DejaVuSans.ttf")))
pdfmetrics.registerFont(TTFont("DB", os.path.join(FDIR, "DejaVuSans-Bold.ttf")))

# ── colores ─────────────────────────────────────────────────────────────
INK    = HexColor("#16130F")
GREY   = HexColor("#5E574D")
GOLD   = HexColor("#8A6212")   # el dorado de Tumbao, oscurecido para papel
GOLDBG = HexColor("#FBF3DF")
GOLDLN = HexColor("#E0CB93")
RED    = HexColor("#A32118")
REDBG  = HexColor("#FBECEA")
GREEN  = HexColor("#1F6B33")
RULE   = HexColor("#D8D2C6")

# ── caja de página ──────────────────────────────────────────────────────
W, H = LETTER
ML, MR, MT, MB = 42, 42, 36, 34
CW = W - ML - MR

c = canvas.Canvas("guia-de-la-cajera.pdf", pagesize=LETTER)
c.setTitle("Guía de la cajera — Tumbao")
c.setAuthor("Tumbao")

y = H - MT
pagina = 1


# ── utilidades de dibujo ────────────────────────────────────────────────
def wrap(txt, font, size, width):
    """Parte un texto en líneas que caben en `width`."""
    palabras, lineas, linea = txt.split(), [], ""
    for p in palabras:
        prueba = (linea + " " + p).strip()
        if pdfmetrics.stringWidth(prueba, font, size) <= width:
            linea = prueba
        else:
            if linea:
                lineas.append(linea)
            linea = p
    if linea:
        lineas.append(linea)
    return lineas


def parrafo(txt, x, ancho, font="D", size=9.6, lead=13.2, color=INK, gap=0):
    """Escribe un párrafo con salto de línea automático. Devuelve el alto."""
    global y
    y -= gap
    c.setFont(font, size)
    c.setFillColor(color)
    for ln in wrap(txt, font, size, ancho):
        y -= lead
        c.drawString(x, y, ln)
    return y


def negrita_inicio(prefijo, resto, x, ancho, size=9.6, lead=13.2,
                   color=INK, cprefijo=None):
    """Una línea que empieza en negrita ("Por qué:") y sigue normal.
    Se hace a mano porque el resto de la hoja no necesita HTML."""
    global y
    c.setFillColor(cprefijo or color)
    wpref = pdfmetrics.stringWidth(prefijo + " ", "DB", size)
    lineas = wrap(resto, "D", size, ancho - wpref)
    for i, ln in enumerate(lineas):
        y -= lead
        if i == 0:
            c.setFont("DB", size)
            c.setFillColor(cprefijo or color)
            c.drawString(x, y, prefijo)
            c.setFont("D", size)
            c.setFillColor(color)
            c.drawString(x + wpref, y, ln)
        else:
            c.setFont("D", size)
            c.setFillColor(color)
            c.drawString(x, y, ln)


def porque(txt, x=ML + 26, ancho=CW - 26):
    """La línea del motivo. Ninguna regla de esta hoja va sin una."""
    global y
    y -= 3
    negrita_inicio("Por qué:", txt, x, ancho, size=9, lead=12,
                   color=GREY, cprefijo=GREY)


def marca(simbolo, txt, x=ML + 26, ancho=CW - 26, size=9.8, lead=13.4):
    """Una línea con ✓ o ✗ delante. Es lo que se lee de un vistazo."""
    global y
    col = GREEN if simbolo == "✓" else RED
    w = pdfmetrics.stringWidth(simbolo + "  ", "DB", size)
    lineas = wrap(txt, "D", size, ancho - w)
    for i, ln in enumerate(lineas):
        y -= lead
        if i == 0:
            c.setFont("DB", size + 1)
            c.setFillColor(col)
            c.drawString(x, y, simbolo)
        c.setFont("D", size)
        c.setFillColor(INK)
        c.drawString(x + w, y, ln)


def seccion(txt, gap=20):
    """Título grande. Tiene que verse desde el otro lado del mostrador."""
    global y
    y -= gap
    c.setFont("DB", 14.5)
    c.setFillColor(GOLD)
    y -= 15
    c.drawString(ML, y, txt.upper())
    y -= 7
    c.setStrokeColor(GOLDLN)
    c.setLineWidth(1.6)
    c.line(ML, y, ML + CW, y)
    y -= 4


def caso(num, titulo, gap=15):
    """Un caso numerado. El número va en un cuadro para poder buscarlo."""
    global y
    y -= gap
    c.setFillColor(GOLD)
    c.roundRect(ML, y - 15.5, 19, 19, 3, stroke=0, fill=1)
    c.setFont("DB", 12)
    c.setFillColor(HexColor("#FFFFFF"))
    c.drawCentredString(ML + 9.5, y - 11, str(num))
    c.setFont("DB", 12.2)
    c.setFillColor(INK)
    for i, ln in enumerate(wrap(titulo, "DB", 12.2, CW - 26)):
        if i:
            y -= 14.5
        c.drawString(ML + 26, y - 11, ln)
    y -= 17


def sub(titulo, gap=15):
    """Título de bloque, sin número."""
    global y
    y -= gap
    c.setFont("DB", 12.2)
    c.setFillColor(INK)
    y -= 12
    c.drawString(ML, y, titulo)
    y -= 3


def recuadro(alto, color_borde, color_fondo):
    """Dibuja el marco de un aviso y deja el cursor dentro."""
    global y
    c.setFillColor(color_fondo)
    c.setStrokeColor(color_borde)
    c.setLineWidth(1.4)
    c.roundRect(ML, y - alto, CW, alto, 5, stroke=1, fill=1)
    y -= 12


def pie():
    """Numeración discreta abajo. Sirve para no pegar las hojas al revés."""
    c.setFont("D", 7.6)
    c.setFillColor(GREY)
    c.drawString(ML, MB - 12, "Tumbao · guía de la cajera")
    c.drawRightString(W - MR, MB - 12, "Hoja %d de 3" % pagina)


def nueva_pagina():
    global y, pagina
    assert y > MB, "se pasó de la página %d (y=%.0f)" % (pagina, y)
    pie()
    c.showPage()
    pagina += 1
    y = H - MT


# ════════════════════════════════════════════════════════════════════════
# HOJA 1 — por dónde entra la plata
# ════════════════════════════════════════════════════════════════════════
c.setFont("DB", 25)
c.setFillColor(INK)
y -= 24
c.drawString(ML, y, "Guía de la cajera")
c.setFont("D", 10.5)
c.setFillColor(GREY)
y -= 15
c.drawString(ML, y, "Tumbao · recepción. Pégala donde la veas desde el mostrador.")
y -= 14

# La regla de oro, en amarillo y arriba del todo: es la única frase que
# hay que recordar si no se lee nada más.
recuadro(64, GOLDLN, GOLDBG)
c.setFont("DB", 15)
c.setFillColor(GOLD)
y -= 6
c.drawString(ML + 14, y, "Cada plata se apunta UNA sola vez.")
y -= 4
negrita_inicio("Por qué:",
               "si la misma plata queda apuntada dos veces, el cierre de la "
               "noche cuenta el doble y no cuadra nunca.",
               ML + 14, CW - 28, size=9.6, lead=12.6, color=GREY, cprefijo=GREY)
y -= 16

seccion("Hay tres formas de que entre plata", gap=8)
parrafo("Antes de tocar nada, mira cuál de las tres es. El lío del cierre "
        "casi siempre viene de mezclarlas.",
        ML, CW, size=9.8, color=GREY, gap=2)

caso(1, "Reservó sola por la página y transfirió", gap=13)
marca("✓", "Tú no haces nada. El panel cruza el depósito con su reserva solo, "
           "en pocos minutos.")
parrafo("Si pasa media hora y sigue sin confirmarse, en la pestaña Por validar "
        "sale un aviso rojo. Ahí sí la confirmas a mano: busca su nombre y toca "
        "«Es este» en el depósito que le corresponda.",
        ML + 26, CW - 26, size=9.6, gap=2)
porque("esa plata ya está contada. Volver a apuntarla la cuenta dos veces.")

caso(2, "Llegó sin reservar y tú la apuntas")
parrafo("Tablero → toca la clase → «+ Apuntar a alguien». Nombre, celular, y "
        "«¿Cómo pagó?»: Ya pagó · Paga al llegar · Transfirió.",
        ML + 26, CW - 26, size=9.6, gap=2)
marca("✓", "Si pagó en efectivo, esa plata entra sola a la Caja. No la vuelvas "
           "a apuntar allá.")
marca("✓", "Si transfirió, queda esperando el depósito y se cruza cuando llegue.")
porque("de cómo pagó depende que el cajón cuadre en la noche. Si te lo saltas, "
       "el efectivo queda en el cajón y nadie sabe que existe.")

caso(3, "Paga en el mostrador y tú lo apuntas en la Caja")
parrafo("Caja → toca el concepto → escribe el valor → Efectivo o Transferencia "
        "→ Guardar. Sirve igual para efectivo y para transferencia.",
        ML + 26, CW - 26, size=9.6, gap=2)
porque("es la única forma de que esa plata exista para el cierre.")

y -= 18
recuadro(76, RED, REDBG)
c.setFont("DB", 13.5)
c.setFillColor(RED)
y -= 5
c.drawString(ML + 14, y, "El error que más cuesta")
y -= 2
marca("✗", "Si ya reservó por la página, NO la vuelvas a apuntar en la Caja.",
      x=ML + 14, ancho=CW - 28, size=10, lead=14)
parrafo("Ante la duda, mira Por validar antes de apuntar. Si su nombre está "
        "ahí, la plata ya está contada.",
        ML + 14, CW - 28, size=9.4, color=GREY, gap=1)
y -= 14

seccion("Lo que apuntas en la Caja", gap=16)

sub("Cada plata tiene su nombre", gap=6)
parrafo("Clase suelta · Media mensualidad · Mensualidad · Cumpleaños · Camiseta",
        ML, CW, font="DB", size=10, gap=1)
marca("✗", "Ya no existe «Otro ingreso». Escoge siempre uno de los cinco.",
      x=ML, ancho=CW)
porque("sin nombre no se sabe de qué fue la plata, y a fin de mes no hay nada "
       "que contar.", x=ML, ancho=CW)

sub("Clase suelta: pon cuántas personas son", gap=13)
marca("✓", "Llegan tres juntas y pagan $45.000 → pon 3 en el contador. "
           "El valor sale solo.", x=ML, ancho=CW)
marca("✗", "No apuntes un solo movimiento de $45.000 sin decir que son tres.",
      x=ML, ancho=CW)
porque("el cierre cuenta gente, no solo plata. Con el 1 puesto, la noche dice "
       "que entró una persona cuando entraron tres.", x=ML, ancho=CW)

nueva_pagina()

# ════════════════════════════════════════════════════════════════════════
# HOJA 2 — el cobro por transferencia, y qué hacer cuando algo no cuadra
# ════════════════════════════════════════════════════════════════════════
seccion("Cuando te pagan por transferencia", gap=0)

sub("Escoge el depósito de la lista", gap=12)
parrafo("Al marcar Transferencia sale la lista de depósitos que el banco ya "
        "avisó. Escoge el suyo. Si todavía no aparece, toca «No está en la "
        "lista»: se guarda igual y queda marcado.",
        ML, CW, size=9.6, gap=2)
porque("la foto del comprobante no comprueba nada: puede ser vieja o retocada. "
       "El depósito de la lista lo confirmó el banco.", x=ML, ancho=CW)

sub("El botón «Ya lo registré»", gap=17)
parrafo("Cobras una transferencia y la apuntas de una. Un rato después llega el "
        "aviso del banco y ese depósito aparece como que no es de nadie.",
        ML, CW, size=9.6, gap=2)
marca("✓", "No es plata nueva: es la misma. Toca «Ya lo registré» y enlázalo "
           "con el movimiento que ya hiciste.", x=ML, ancho=CW)
marca("✗", "No lo cobres otra vez. Quedaría doble.", x=ML, ancho=CW)

seccion("Cuando algo no cuadra", gap=22)

sub("Llegó un depósito y no sé de quién es", gap=12)
parrafo("Déjalo quieto. Sale en Por validar, en «Llegó al banco y nadie lo ha "
        "reclamado». Cuando alguien lo reclame, tócalo y cóbralo desde ahí.",
        ML, CW, size=9.5, lead=12.6, gap=1)

sub("Cobré en efectivo y el banco no reporta nada", gap=17)
parrafo("Está bien así. El efectivo no pasa por el banco: nunca va a salir en "
        "la lista de depósitos.",
        ML, CW, size=9.5, lead=12.6, gap=1)

sub("La clienta dice que pagó y no aparece", gap=17)
parrafo("Mírala en Por validar. Si su nombre está ahí con un depósito al lado, "
        "toca «Es este». Si no hay ninguno parecido, pregúntale a nombre de "
        "quién salió: muchas veces pagó la mamá y el banco trae otro nombre.",
        ML, CW, size=9.5, lead=12.6, gap=1)

sub("Apunté algo mal y todavía no he cerrado", gap=17)
parrafo("Caja → «Ver movimientos de hoy» → Anular. Y lo vuelves a apuntar bien. "
        "Si tenía un depósito enlazado, vuelve solo a la lista.",
        ML, CW, size=9.5, lead=12.6, gap=1)

sub("Apunté algo mal y ya cerré el día", gap=17)
parrafo("Caja → «Corregir el cierre». Te pide el motivo en una frase, corriges "
        "y vuelves a cerrar. El motivo queda escrito, para que mañana nadie "
        "adivine qué pasó.",
        ML, CW, size=9.5, lead=12.6, gap=1)

sub("Pagó hoy una clase de la otra semana", gap=17)
parrafo("Apúntalo hoy, normal: la plata entró hoy y está en el cajón hoy. "
        "El panel la separa solo, como clases de otro día.",
        ML, CW, size=9.5, lead=12.6, gap=1)

sub("Entró alguien que había pagado hace días", gap=17)
parrafo("No le cobres nada: su plata ya entró otro día. Márcale la entrada y "
        "listo. En la tirilla sale en POR REVISAR como «Reprogramada · ya pagó "
        "antes», y eso está bien.",
        ML, CW, size=9.5, lead=12.6, gap=1)

nueva_pagina()

# ════════════════════════════════════════════════════════════════════════
# HOJA 3 — el cierre
# ════════════════════════════════════════════════════════════════════════
seccion("El cierre, paso a paso", gap=0)
parrafo("Cobra todo lo que falte ANTES de empezar. Después de cerrar, arreglar "
        "cuesta el triple.", ML, CW, size=9.8, color=GREY, gap=2)


def paso(n, titulo, detalle=None, motivo=None, gap=11):
    global y
    y -= gap
    c.setFont("DB", 11.5)
    c.setFillColor(GOLD)
    y -= 12
    c.drawString(ML, y, str(n) + ".")
    c.setFillColor(INK)
    for i, ln in enumerate(wrap(titulo, "DB", 11.5, CW - 20)):
        if i:
            y -= 13.5
        c.drawString(ML + 20, y, ln)
    if detalle:
        parrafo(detalle, ML + 20, CW - 20, size=9.4, lead=12.4, gap=1)
    if motivo:
        porque(motivo, x=ML + 20, ancho=CW - 20)


paso(1, "¿Queda alguien en Por validar?",
     "Resuélvelo antes de cerrar. La pestaña lleva el número al lado.",
     "una reserva sin resolver es plata que el cierre no sabe de quién es.",
     gap=8)
paso(2, "¿Hay depósitos sin reclamar?",
     "En «Llegó al banco y nadie lo ha reclamado». Si alguno es de hoy y sabes "
     "de quién es, cóbralo ahora.")
paso(3, "¿Apuntaste los gastos del día?",
     "Celador, aseo, cafetería, profesores. Si de verdad no hubo ninguno, el "
     "panel te va a pedir que lo confirmes con un visto.",
     "un gasto sin apuntar hace que falte plata en el cajón sin explicación.")
paso(4, "Caja → «Cerrar el día».",
     "Ahí aparecen los totales. Antes no se ven a propósito.",
     "contar el cajón sabiendo de antemano la cifra no es contar, es confirmar.")
paso(5, "Cuenta los billetes y escribe lo que hay.",
     "En «¿Cuánto contaste en el cajón?» va lo que de verdad hay. Lo que sea.")
paso(6, "Escribe cuánto dejas de base para mañana.",
     "El resto se retira. No puedes dejar más de lo que contaste.")
paso(7, "Cierra, imprime la tirilla y guárdala con el efectivo.",
     "Si vas a cuadrar contra el extracto del banco, imprime también "
     "«Cuándo pagaron».")

seccion("La tirilla, de arriba a abajo", gap=14)

TIRILLA = [
    ("INGRESOS DEL DÍA",
     "Reservas página, Reservas manuales y Pagos en caja. Debajo, cuánta "
     "gente entró a clase suelta. Y «= Entradas»."),
    ("SALIDAS",
     "Los gastos del día, y «= Salidas»."),
    ("CAJA 1",
     "Base al abrir, Debía haber y Se contó. Y el veredicto: SÍ CUADRA ✓ o "
     "NO CUADRA."),
    ("DEPÓSITOS REGISTRADOS HOY",
     "Lo que el panel alcanzó a registrar hoy. Ojo: no es el extracto del banco."),
    ("POR REVISAR",
     "Lo que no pasó solo por la página. Es lo único que hay que mirar uno "
     "por uno."),
]

# La columna se mide, no se adivina: con un número puesto a ojo el rótulo
# más largo se metía encima del texto.
COL = max(pdfmetrics.stringWidth(t, "DB", 8.7) for t, _ in TIRILLA) + 14

for titulo, texto in TIRILLA:
    # Columna fija para el rótulo: los nombres de la tirilla son de largos
    # muy distintos y, alineados a la izquierda cada uno donde cayera, la
    # lista se lee como un texto corrido en vez de como una tabla.
    y -= 7
    for i, ln in enumerate(wrap(texto, "D", 9.4, CW - COL)):
        y -= 12.4
        if i == 0:
            c.setFont("DB", 8.7)
            c.setFillColor(GOLD)
            c.drawString(ML, y, titulo)
        c.setFont("D", 9.4)
        c.setFillColor(INK)
        c.drawString(ML + COL, y, ln)

y -= 14
recuadro(150, RED, REDBG)
c.setFont("DB", 14.5)
c.setFillColor(RED)
y -= 6
c.drawString(ML + 14, y, "Si la tirilla dice NO CUADRA")
y -= 2
marca("✗", "No lo arregles cambiando la cifra que contaste.",
      x=ML + 14, ancho=CW - 28, size=9.8, lead=13.4)
marca("✓", "Escribe siempre lo que de verdad hay en el cajón. Después busca, "
           "en este orden:", x=ML + 14, ancho=CW - 28, size=9.8, lead=13.4)
for i, t in enumerate([
    "¿Falta un gasto por apuntar? Es lo más común de lejos.",
    "¿Alguna clase suelta quedó sin el número de personas?",
    "¿Algo se apuntó dos veces? Mira «Ver movimientos de hoy»: dos iguales seguidos.",
    "¿Alguien pagó en efectivo en la puerta y no quedó en la Caja?",
], 1):
    y -= 12.6
    c.setFont("DB", 9.3)
    c.setFillColor(RED)
    c.drawString(ML + 30, y, str(i) + ".")
    c.setFont("D", 9.3)
    c.setFillColor(INK)
    c.drawString(ML + 45, y, t)
y -= 4
negrita_inicio("Y si aun así no cuadra:",
               "cierra igual, con la cifra real, y escribe en la nota qué pasó. "
               "Un cierre con nota se puede investigar mañana; uno cuadrado a la "
               "fuerza, no.",
               ML + 14, CW - 28, size=9.3, lead=12.4, color=GREY, cprefijo=RED)

assert y > MB, "se pasó de la página 3 (y=%.0f)" % y
pie()
c.showPage()
c.save()
print("Listo: guia-de-la-cajera.pdf — 3 hojas")
