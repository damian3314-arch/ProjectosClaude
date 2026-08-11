# Antes de pegar cualquier cosa de esta carpeta

**Los `PEGAR_*.sql` de aquí ya están aplicados.** Son el historial de cómo
se llegó al estado actual, no una lista de tareas.

## Por qué esto tiene su propio aviso

`PEGAR_LISTO_PRODUCCION.sql` se borró el 11 de agosto porque se había
vuelto peligroso. Contenía un `create or replace` de `caja_del_dia`
completo. Después de aplicarlo, **otra sesión arregló en producción un
doble conteo de plata dentro de esa misma función** — y ese arreglo no
quedó en el repositorio.

A partir de ese momento, volver a pegar el archivo habría deshecho el
arreglo en silencio y el cierre habría vuelto a inflarse. Nadie se
habría enterado hasta que un cuadre no diera.

La lección no es "borra el archivo". Es que **un `create or replace` de
una función entera es destructivo si la función pudo cambiar por otra
vía.** Antes de reemplazar una función que ya vive en producción:

```sql
select pg_get_functiondef(oid)
  from pg_proc where proname = 'la_funcion';
```

Y comparar con lo que se va a pegar. Si hay algo que no reconoces, alguien
más lo puso ahí por un motivo.

## Dónde está la verdad

`supabase/migrations/` en orden. `0030` es la última y refleja lo que hay
en producción hoy, incluido el arreglo del doble conteo.
