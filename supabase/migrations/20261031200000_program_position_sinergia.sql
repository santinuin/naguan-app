-- Sinergia (Desencadenado y Efecto Kettlebell juntos) va justo después de
-- Efecto Kettlebell, en la posición 5: todas las Sendas desde ahí bajan un
-- lugar. Mismo orden que programOrder en backend/cmd/seed.
--
-- En dos pasos porque position es única y la restricción se verifica fila
-- por fila: sumar 1 de una vez chocaría con la Senda de al lado (la 5 pasa a
-- 6 mientras la 6 todavía está). Primero se corren lejos y después a su lugar.

update program set position = position + 100 where position >= 5;
update program set position = position - 99 where position >= 105;
