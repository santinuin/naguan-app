# Limitaciones del modelo

El modelo de datos (ver `modelo-de-datos.md`) nació de los programas de Mammoth Hunters:
cada ítem tiene un número fijo de reps o de segundos, y cada Fragua es igual para todos.
Los planes de Fitness Revolucionario piden más que eso. Este documento junta lo que no
entra, cómo se carga mientras tanto y qué haría falta para resolverlo. Se completa a
medida que se cargan planes nuevos. Cuando una limitación se resuelve, se borra de acá y
se documenta en `modelo-de-datos.md`.

Cada entrada dice en qué plan apareció. El "hoy" es lo que hace el importador, así que
cambiarlo es corregir la transcripción y volver a generar el seed, no tocar el modelo.

## Cómo se mide un ejercicio

### Progresión de carga y porcentajes

*Barra Libre* receta la carga, no solo las reps:

- **Progresión lineal** (Fase I): el peso sube en cada sesión (5 kg en sentadilla y
  peso muerto, 2,5 kg en los press, la mitad el segundo mes); si no completás las
  series, se repite; tres sesiones sin subir, se baja un 10 %.
- **Porcentajes** de una marca: método Texas al 90 % del 5RM, recuperación al 80 %
  del peso del lunes, complejos al 65-70 % del 1RM, densidad al 70-75 %.
- **Series de aproximación**: barra vacía, 40-50 %, 60 % y 80-85 % del peso de
  trabajo de ese día.
- **Marcas que rotan**: los viernes del método Texas buscan 1RM, 2RM y 3RM por turno.

- **Hoy:** el plan de reps y descansos se carga entero (incluidas las series de
  aproximación como pasos); los porcentajes y la regla de progreso van en la
  descripción. El peso se registra por serie (`workout_item.load_kg`, desde el
  2026-10-30) y la app propone el último usado, pero calcular el de hoy (subir 2,5 kg,
  el 90 % del 5RM) queda del lado del usuario.
- **Haría falta:** una regla de progresión por ejercicio (incremento por sesión o por
  semana, cuándo repetir o bajar) y cargas relativas en el plan (`% de` una marca o del
  peso de otra serie) que la app resuelva con el historial. El 1RM del usuario ya se
  puede estimar de lo registrado (es el Mojón `e1rm_kg`).

## Cómo se arma un bloque

### Escaleras hasta el fallo, de un ejercicio por vez

*Efecto Kettlebell*, semana 10: una escalera de clean, press y sentadilla de 10 minutos
que sube un ejercicio por vez hasta agotarte, cambiando de lado. (Las pirámides con tope
de Desencadenado y la de swings y thrusters ya son bloques `pyramid`, desde el
2026-10-30.)

- **Hoy:** un AMRAP con el tope y una vuelta de referencia; cómo subir va en la
  descripción.
- **Haría falta:** una pirámide cuyos peldaños suban solo uno de los ejercicios.

### Cada minuto (EMOM)

*Sinergia*, semana 3: «cada minuto, por 10 minutos», 15 swings y 10 flexiones hindúes
al empezar cada minuto, y lo que sobra del minuto es el descanso. Si no llegás, una rep
menos de cada uno en las vueltas que siguen.

- **Hoy:** un bloque de 10 vueltas sin Enfriá fijo, con una nota; el minuto lo lleva el
  usuario con su reloj.
- **Haría falta:** un tipo de bloque `emom` (vueltas por intervalo fijo): la app
  arranca cada vuelta al empezar el minuto y cuenta hacia atrás lo que queda como
  Enfriá; si el minuto se termina antes, avisa.

### Alternativas que no son progresiones

*Desencadenado*: «si no tenés cuerda, levantamientos de rodilla», «si no podés hacer
Dips, extensiones de tríceps contra la pared», y la semana 10 da otra versión del día 4
«si estás en casa».

- **Hoy:** se carga una sola opción (la principal del libro). El editor de la Fragua solo
  ofrece progresiones (más fácil / más difícil), no alternativas del mismo nivel.
  *Barra Libre*: «sin kettlebells, rotá solo los HIIT de calistenia» (los HIIT 3 y 4
  se cargan igual, con la indicación en la descripción), «roll-out con barra o con
  rueda», «swing o levantamiento de piernas», y el orden de los press, que se puede
  alternar entre sesiones.
- **Haría falta:** una relación de alternativas entre ejercicios (por equipamiento), o
  sesiones con variantes.

### Variantes por nivel o por equipamiento

*Efecto Kettlebell*: cada semana está escrita para un nivel intermedio, con
indicaciones para hacerla más fácil (básico) o más difícil (avanzado), y muchos
ejercicios cambian si tenés una o dos kettlebells.

- **Hoy:** se carga el intermedio con una kettlebell; lo básico y lo avanzado va en
  la descripción de cada sesión.

  *Barra Libre*: la Fase I tiene una versión entera para intermedios (método Texas).
  Hoy es otra Senda («Barra Libre I: Fuerza (intermedio)»).
- **Haría falta:** variantes de una sesión (o de un bloque) por nivel, elegibles antes
  de empezar.

## El usuario

### Nivel del usuario por ejercicio

*Desencadenado* gira alrededor de esto. Los 5 ejercicios básicos (flexión, flexión
vertical, dominada, sentadilla, abdominales) tienen 5 niveles cada uno. Un test, en las
semanas 1, 4 y 8, fija tu «nivel máximo». Cada bloque pide «nivel máximo», «máximo − 1»
o «máximo + 1». *Muscle Hunters* también tiene niveles según un test.

- **Hoy:** cada sesión trae un nivel de referencia (el clásico, nivel 3) y los 5 niveles
  están encadenados como progresiones en `exercise_progression`. Antes de cada Fragua
  cambiás el ejercicio por el de tu nivel en el editor, y eso hay que repetirlo cada vez.
  Los tests no se cargan como Fraguas (tampoco los de Efecto Kettlebell: 100
  swings en 5 minutos, etc.).

  Dos asperezas del cambio de nivel en el editor: el lado del ítem no cambia, así
  que pasar de la sentadilla (nivel 3) a la pistolero asistida (nivel 4, unilateral)
  deja un solo paso en vez de uno por pierna; y la medida tampoco cambia, así que
  bajar de la flexión vertical (por reps) al pino de cabeza (que se aguanta por
  tiempo) deja reps donde harían falta segundos.
- **Haría falta:** el nivel del usuario por cadena de progresión (persistente, con
  historia), ítems que digan "nivel máximo ± n" en vez de un ejercicio fijo, y sesiones de
  test que lo actualicen.

## Programas

### Semanas que se repiten

*Desencadenado*: las semanas 1 y 2 son iguales, y también la 3 y la 4, y la 5 y la 6.

- **Hoy:** cada semana tiene sus propias sesiones (copias). Una sesión que aparece dos
  veces en el mismo programa tendría un solo check, porque los checks se derivan por
  sesión.
- **Haría falta:** nada, por ahora. Solo molestaría si se edita una copia y no la otra,
  y como el importador las genera desde la misma transcripción, no pasa.

### Fases de duración variable

*Barra Libre* tiene 4 fases que duran lo que necesites: las dos primeras, de 2 a 4
meses (hasta que te estancás); la tercera, alrededor de un mes. Se encadenan: se pasa a
la siguiente al estancarse.

- **Hoy:** una Senda por fase (y otra para la Fase I de intermedios), con un ciclo base
  (8, 6, 4 y 4 semanas). Para alargar una fase, se resetea la Senda. Nada une las
  cinco Sendas como un solo programa.
- **Haría falta:** un programa con fases (cada una con su ciclo y un "repetir hasta"),
  o al menos agrupar Sendas.

### Sesiones que arma el usuario

*Barra Libre*, Fase IV: después de la parte común, 2 o 3 ejercicios para una de tus
dos «zonas retrasadas», que elegís según tus medidas (el libro calcula las
proporciones). *Barra Libre* también tiene semanas de descarga (el mismo programa al
60 % del peso).

- **Hoy:** solo la parte común; las zonas retrasadas van como indicación en la
  descripción, y se hacen por fuera de la Fragua. Las descargas no se cargan.
- **Haría falta:** que el usuario pueda sumar bloques propios a una Fragua (y que
  queden para las siguientes), o armar sesiones desde cero.
