-- 0193 · La dueña aprobó las clases de obsequio por constancia (1 nov, Damián): 1 con la tiquetera de 4, 2 con la de 8.
-- Se encienden las entregas que ya existían (0121/0187). Aplicada en vivo.
update ajustes set valor = 'encendido', updated_at = now() where clave in ('wa_pase_constancia', 'wa_pase_constancia_2');
