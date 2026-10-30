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

### Rangos de repeticiones

*Desencadenado* («3 tandas de 5-8»), *Barra Libre* («3x3-5», «4x8-10») y *Guerrera
Espartana* (`4x15-20`). En Barra Libre el rango es además la regla de progreso:
mantenés el peso hasta llegar al máximo en todas las series, y entonces lo subís.

- **Hoy:** se carga el máximo del rango (5-8 → 8). Es la meta: si no llegás, bajás las
  reps antes de empezar o durante la Fragua. Los Mojones salen de lo que registrás, así
  que no se inflan.
- **Haría falta:** `reps_min` y `reps_max` en `block_item` (o un `reps` y un
  `reps_max` opcional), y que la app muestre el rango y proponga el máximo.

### Máximo posible (mrp / mtp)

*Desencadenado*, semana 9: «máximas repeticiones posibles» y «máximo tiempo posible».
*Barra Libre*: dominadas y fondos «3xF» (al fallo) en todas las fases.

- **Hoy:** un valor de referencia (por ejemplo 15 reps o 60 s; 8 o 10 en los «al
  fallo» de Barra Libre), y se registra lo que hiciste de verdad.
- **Haría falta:** una medida "abierta": el ítem dice si va por reps o por tiempo, pero
  sin objetivo. La app cuenta hacia arriba (cronómetro, no cuenta regresiva) y pide el
  número al terminar. Hoy el `check` de `block_item` exige que haya exactamente uno de
  los dos valores.

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

### Pirámides y escaleras hasta el fallo, con tope de tiempo

*Desencadenado*, semanas 1 y 2: durante 7 minutos subís 1, 2, 3… hasta tu máximo y
bajás de nuevo. Si terminás antes, volvés a empezar. El descanso entre reps dura lo
mismo que la serie anterior. *Efecto Kettlebell*, semana 10: una escalera de clean,
press y sentadilla de 10 minutos (sube un ejercicio por vez hasta agotarte) y una
pirámide de swings y thrusters de 5 minutos, que sube de a dos.

- **Hoy:** en Desencadenado, una escalera fija (`ladder`) de 1 a 7 y de vuelta a 1
  (49 reps), sin tope de tiempo; se acorta o se alarga ajustando las reps antes de
  empezar. En Efecto Kettlebell, un AMRAP con el tope de tiempo y una vuelta de
  referencia; cómo subir va en la descripción.
- **Haría falta:** un bloque con tope de tiempo cuyas vueltas cambien de reps (hoy el
  `amrap` repite una vuelta idéntica) y con el pico definido por el usuario.

### Ejercicios opcionales

*Desencadenado*: cada sesión termina con un «ejercicio extra», que se hace solo si te
quedan fuerzas. *Barra Libre*: el extra (fase II) u opcional (fase III), «si
terminaste en menos de 45 minutos».

- **Hoy:** es el último bloque de la Fragua. Si no lo hacés, salteás sus pasos uno por
  uno.
- **Haría falta:** un bloque marcado como opcional, con un "terminar acá" antes de
  empezarlo. No debería contar en contra de la Fragua templada.

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

### Indicaciones de ejecución

*Desencadenado*: «2 segundos de subida y 2 de bajada» (fuerza), «fase concéntrica lo más
rápido posible» (potencia), «30 s de descanso entre tandas» (semana 9).

- **Hoy:** van en la descripción de la sesión (`session.description`). Los descansos sí
  se cargan como Enfriá.
- **Haría falta:** una descripción (o cadencia) por bloque, para mostrarla en el
  momento.

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

### Números de un ítem por tiempo

*Efecto Kettlebell*: «todos los swings que puedas en un minuto», «anotá el total de
burpees de los 4 minutos».

- **Hoy:** el ítem es por tiempo (60 s, o intervalos de 30/30) y se registra la
  duración, no las reps. Las vueltas de un AMRAP sí se registran.
- **Haría falta:** que un ítem por tiempo pueda registrar también las reps (y que
  cuenten para los Mojones).

### Mojón de una sesión entera

*Desencadenado*, semana 10 (HIIT): «anotá el tiempo que tardás en completar las 2 rondas,
es tu tiempo a batir». *Barra Libre*: el tiempo de cada HIIT, y el total de reps de
cada bloque de densidad (fase IV), que es la regla para subir el peso.

- **Hoy:** la duración de la Fragua queda en el historial, pero no es un Mojón.
- **Haría falta:** Mojones por sesión (menor tiempo), además de los Mojones por
  ejercicio.

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
