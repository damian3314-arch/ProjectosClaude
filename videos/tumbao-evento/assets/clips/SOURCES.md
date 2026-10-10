# Fuentes de los clips

Los .mp4 de esta carpeta no van al repo (pesan ~60 MB). Se regeneran desde el material
bruto de Drive (carpeta compartida «2026», Septiembre/Octubre › Material bruto) con:

`ffmpeg -ss <inicio> -t <dur> -i <original> -vf "[setpts=2.0*PTS,]fps=30,scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920" -an -c:v libx264 -crf 17 -pix_fmt yuv420p <nombre>.mp4`

| Clip | Original | Inicio (s) | Duración (s) | Cámara lenta |
|---|---|---|---|---|
| s1-clase-llena | Sep › Contenido 1 › IMG_7673.MOV | 5.0 | 4.8 | no |
| s1-sonrisa | Sep › Contenido 2 › IMG_7773.mov | 0.8 | 4.8 | no |
| s1-multitud | Sep › Contenido 2 › IMG_7766.MOV | 8.0 | 4.8 | no |
| s2-entrada | Oct › Contenido 2 › IMG_9350.MOV | 6.8 | 2.6 | no |
| s2-suelta | Sep › Contenido 2 › IMG_7764.MOV | 2.0 | 2.8 | no |
| s3-terapia | Sep › Contenido 1 › IMG_8727.MOV | 9.8 | 2.6 | 2x (60 fps) |
| s4-fachada | Oct › Contenido 2 › IMG_9352.MOV | 2.4 | 3.0 | no |
| s4-neon | Sep › Contenido 2 › IMG_9177.MOV | 0.0 | 1.5 | 2x (60 fps) |
| s4-salon | Oct › Contenido 2 › IMG_9359.MOV | 1.5 | 3.0 | no |

Foto del cierre: Sep › Contenido 2 › foto 6967aa31.jpg, recorte 16:9 desde 33 % de la altura.
