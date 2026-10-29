# La campaña de aniversario

Las piezas se **dibujan**, no se generan con un modelo. El motivo es
práctico y ya costó dos rondas: un generador de imágenes no respeta una
retícula ni escribe bien las tildes, así que dos piezas de la misma
campaña salían con el precio en sitios distintos y con la «é» a medias.
Aquí el texto lo escribe el navegador y sale exacto siempre.

## La frase

    CRECER TAMBIÉN SE BAILA

Vive en `pieza.html`, en la constante `FRASE`, y de ahí sale a las tres
piezas. Cambiarla es cambiar esa línea y volver a sacarlas: no hay que
retocar ninguna imagen a mano.

Es hermana de «Baila pa' sanar» a propósito —misma voz, misma forma— y
dice las tres cosas que pidió Damián: que aquí se crece, que eso
transforma, y que se hace disfrutando.

## La marca, no una paleta parecida

    lila     #EADCFA   el fondo de la foto de perfil
    naranja  #EE6B31   el logotipo
    magenta  #E8226A   «Baila pa' sanar»
    morado   #3B2258   para leer, cuando el naranja no contrasta
    amarillo #F7DE4A   el subrayado a mano

Tipografías: **Fredoka** para el logotipo y los titulares (es lo más
cercano a las letras redondas del logo real) y **Caveat** para lo escrito
a mano. Las dos van dentro de `fuentes/`, no por CDN: una pieza que
depende de internet para dibujarse bien no es una pieza.

El subrayado amarillo es el único adorno que se deja. Es la firma de
Tumbao —está en todas sus piezas— y sin él esto podría ser de cualquiera.
Un trazo, no un montón de garabatos.

## Sacarlas

    cd campana && node sacar.mjs          # las tres
    cd campana && node sacar.mjs p2       # solo una

Salen a 1080×1920, que es el estado de WhatsApp y la historia de
Instagram. Las franjas de arriba y de abajo se dejan libres a propósito:
ahí WhatsApp pone el nombre con la hora y la barra de responder.
