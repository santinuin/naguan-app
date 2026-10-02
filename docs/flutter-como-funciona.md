# Cómo funciona Flutter (y Dart) por debajo

Notas de aprendizaje del proyecto, con analogías a Java/Spring cuando ayudan. Se completa a
medida que aparecen temas nuevos.

## Todo es un widget, y los widgets son baratos

Un widget **no es** un componente visual con estado, como un `JPanel` o una `View` de
Android. Es una **descripción inmutable** de cómo debería verse un pedazo de la UI en un
momento dado: un objeto chico, de campos `final`, que se crea y se descarta sin parar.

`build()` devuelve un árbol nuevo de esas descripciones cada vez que algo cambia. Que
esto sea rápido se explica porque Flutter mantiene **tres árboles**:

| Árbol | Qué es | Vida |
|---|---|---|
| **Widgets** | La configuración: inmutable, se recrea en cada `build()` | Efímera |
| **Elements** | La instancia "montada" de cada widget en la pantalla; mantiene la posición en el árbol y el `State` | Larga: se reutiliza entre builds |
| **RenderObjects** | Hacen el trabajo pesado: layout, pintura, hit testing | Larga: solo se actualizan si cambió algo |

Cuando `build()` devuelve widgets nuevos, Flutter compara cada uno con el anterior en la
misma posición (mismo tipo y misma `key`): si coinciden, reutiliza el Element y el
RenderObject y solo actualiza lo que cambió. Es la misma idea que el *virtual DOM* de
React. Por eso escribir `const` en los widgets que no cambian ayuda: Flutter ve que es la
misma instancia y ni siquiera compara.

## StatelessWidget vs StatefulWidget

- **StatelessWidget** (`ForjaPill`, `_ProgramCard`): todo sale de sus parámetros y del
  contexto. Mismos datos → misma UI.
- **StatefulWidget** (`ProgramsScreen`): el widget sigue siendo inmutable, pero crea un
  objeto **`State`** que vive en el Element y sobrevive a los rebuilds. Ahí se guarda lo
  que cambia con el tiempo.

El ciclo de vida del `State`:

| Método | Cuándo | Para qué |
|---|---|---|
| `initState()` | Una vez, al montarse | Inicializar: crear el `Future` del request, controllers, suscripciones |
| `build()` | Muchas veces | Describir la UI. **Sin efectos secundarios**: puede llamarse en cualquier momento (rotación, cambio de tema, rebuild del padre) |
| `setState(fn)` | Cuando vos lo llamás | Cambiar el estado y pedir un rebuild |
| `dispose()` | Una vez, al desmontarse | Liberar recursos (cerrar streams, controllers) |

`widget.client` desde el `State` accede a la configuración actual del widget: si el padre
reconstruye con otros parámetros, `widget` apunta a la nueva.

**El error clásico:** crear el `Future` dentro de `build()`. Cada rebuild dispararía un
request nuevo y la pantalla volvería a "cargando". Por eso `ProgramsScreen` lo crea en
`initState` y lo reemplaza solo en `_retry`, dentro de `setState`.

## BuildContext y `Theme.of(context)`

`BuildContext` es, en la práctica, el Element: la posición del widget en el árbol. Sirve
para **buscar hacia arriba**. `Theme.of(context)` sube por el árbol hasta el `Theme` que
puso `MaterialApp` y devuelve sus datos.

Esto funciona con **InheritedWidget**: un widget que pone datos a disposición de todo su
subárbol. Además, quien lo consulta queda suscripto y se reconstruye si esos datos
cambian; por eso cambiar de tema actualiza toda la app. Es lo más parecido a la inyección
de dependencias de Spring que hay en Flutter, pero resuelta por posición en el árbol en
vez de por un contenedor global. `context.forja` (la extensión del tema de Forja) usa el
mismo mecanismo.

## Asincronía: Dart para quien viene de WebFlux

Dart corre la UI en **un solo hilo con un event loop**, como el event loop de Netty: nada
puede bloquearlo, o la app se congela (los frames se dibujan en ese mismo hilo).

| Reactor (WebFlux) | Dart |
|---|---|
| `Mono<T>` | `Future<T>`: un valor (o un error) en el futuro |
| `Flux<T>` | `Stream<T>`: varios valores en el tiempo |
| `flatMap`, `map`, `onErrorResume` | `async`/`await` y `try`/`catch`: se escribe secuencial y el compilador lo transforma en callbacks |
| Hilos de un `Scheduler` para trabajo de CPU | `Isolate`s: hilos con memoria propia, que se comunican por mensajes (para cómputo pesado, no para I/O) |

Un `await` **no bloquea el hilo**: suspende la función y devuelve el control al event
loop, que mientras tanto dibuja frames y atiende toques. Cuando llega la respuesta HTTP,
la función sigue desde ahí. Es la misma idea que las goroutines de Go, pero con un solo
hilo y explícita (`async`/`await`) en vez de transparente.

### FutureBuilder

`FutureBuilder` conecta un `Future` con la UI: se reconstruye cada vez que el `Future`
cambia de estado, y el `snapshot` dice en cuál está (`connectionState`, `hasError`,
`data`). Así, "cargando / error / datos" queda en un solo lugar del `build()`. Para un
`Stream` existe `StreamBuilder`, el análogo para varios valores.

## Navegación: el Navigator es una pila

El `Navigator` (que crea `MaterialApp`) mantiene una **pila de rutas**; cada ruta es una
pantalla completa. Es la misma idea que el back stack de Android:

```dart
Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (_) => ProgramScreen(client: client, slug: p.slug, name: p.name)),
);
```

- `push` apila una ruta nueva con su animación de entrada; la anterior queda debajo, viva
  (su `State` se conserva: al volver, la lista sigue donde estaba, sin recargar).
- `pop` (el botón "atrás" del `AppBar`, el gesto de Android o `Navigator.of(context).pop()`)
  la desapila. El `AppBar` muestra el botón "atrás" solo si hay una ruta debajo.
- **Los datos se pasan por constructor**: la pantalla nueva recibe lo que necesita
  (`client`, `slug`, y además el `name`, que ya conocemos, para mostrar el título al
  instante mientras carga el resto).

Esta es la API imperativa ("Navigator 1.0"), la más simple de entender. Para deep links
(abrir la app directo en una Fragua desde una notificación) o navegación declarativa
basada en URLs existe `Router` ("Navigator 2.0"), que casi siempre se usa a través del
paquete `go_router`. Lo vamos a necesitar cuando haya notificaciones; por ahora, la pila
alcanza.

## Componentes reutilizables: `LoadView<T>`

Cuando el mismo patrón aparece por tercera vez, se extrae. "Cargando / error con
reintento / datos" estaba en `ProgramsScreen` y lo iban a necesitar dos pantallas más, así
que vive en `lib/common/load_view.dart`:

```dart
LoadView<Program>(
  load: () => client.fetchProgram(slug),       // cómo cargar
  builder: (context, program) => _SessionList(…),  // qué mostrar con el dato
)
```

- Es **genérico** (`<T>`), como una clase genérica de Java.
- Recibe una **función** (`Future<T> Function()`) y no un `Future`: así decide cuándo
  llamarla (al montarse y en cada reintento). Si no hay argumentos alcanza con un
  *tear-off* (`load: client.fetchPrograms`, sin paréntesis: una method reference); si los
  hay, una closure.
- Las pantallas que lo usan quedan como `StatelessWidget`: el estado vive en `LoadView`.

## Dart que apareció en el camino

| Concepto | Ejemplo en el código | Equivalente en Java |
|---|---|---|
| Enum mejorado (con campos y constructor `const`) | `enum BlockType { tabata('TÁBATA'), …; final String label; }` | `enum` con campos |
| `Enum.values.byName` | `Side.values.byName('left')` | `Side.valueOf("LEFT")` |
| Getter calculado | `List<List<Item>> get rounds` | Un método `getRounds()` sin estado |
| `putIfAbsent` | `byRound.putIfAbsent(round, () => []).add(item)` | `computeIfAbsent` |
| Map literal ordenado | `<int, List<Item>>{}` es un `LinkedHashMap` | `new LinkedHashMap<>()` |
| Collection `if` / `for` | `if (x case final d?) ...[…]`, `for (final b in blocks) …` dentro de `children` | (no hay: se arma la lista a mano) |
| Records y `indexed` | `for (final (index, items) in rounds.indexed)` | (no hay; un `for` con índice) |
| Patrones de objeto | `switch (item) { Item(:final reps?) => …, }` | `switch` con record patterns (Java 21) |
| División entera | `seconds ~/ 60` (`/` siempre da `double`) | `seconds / 60` entre `int` |

Los **campos opcionales** del JSON (`time_cap_s`, `side`, `reps`…) se leen fuera del
patrón con un cast nullable (`json['reps'] as int?`): un map pattern exige que la clave
exista, y la API omite las que no aplican.

## Manejo de estado: `setState`, `ChangeNotifier` y `ListenableBuilder`

Hasta ahora el estado vivía en un `State` y se cambiaba con `setState`. Alcanza para
estado chico y local (un formulario, un spinner). La ejecución de una Fragua necesita algo
más: mucha lógica (pasos, tiempos, pausas, resultados) que conviene testear sin widgets.

| Herramienta | Cuándo | En Java/Spring |
|---|---|---|
| `setState` | Estado chico, de una sola pantalla | Un campo de un componente |
| `ChangeNotifier` + `ListenableBuilder` | Lógica con estado, separada de la UI (`WorkoutRunner`) | Un servicio con estado que publica eventos (el patrón Observer) |
| Paquetes (Provider, Riverpod, Bloc) | Estado compartido entre muchas pantallas | Un contenedor de beans con scopes |

`WorkoutRunner extends ChangeNotifier`: tiene la lógica y llama a `notifyListeners()`
cuando algo cambia. La pantalla lo escucha con:

```dart
ListenableBuilder(
  listenable: _runner,
  builder: (context, _) => _StepView(runner: _runner),
)
```

Solo se reconstruye lo que está dentro del builder, no la pantalla entera. La lógica se
testea sola (`test/training/workout_runner_test.dart`), sin pantalla ni emulador.

No sumamos un paquete de manejo de estado: con `ChangeNotifier` (que viene con Flutter)
alcanza, y entenderlo primero hace que después Provider o Riverpod se lean fácil (están
construidos sobre las mismas ideas).

## Timers y el reloj

La cuenta regresiva **no cuenta ticks**: calcula el tiempo desde la hora real.

```dart
Duration get remaining => duration - (now() - stepStartedAt - paused);
```

El `Timer.periodic` de la pantalla (cada 250 ms) solo "le da cuerda" al runner
(`tick()`): recalcula y avanza si un paso llegó a cero. Si el Timer se atrasa, o si la
app pasa a segundo plano durante un descanso, el próximo tick corrige solo. Contar ticks
("le resto 1 segundo cada vez") acumula error y se rompe en segundo plano.

- **El reloj se inyecta** (`clock: DateTime Function()`), igual que en el backend Go. Los
  tests usan un `FakeClock` que se adelanta a mano: un descanso de 20 s se testea en
  milisegundos.
- **`dispose()` cancela el Timer**: un `Timer.periodic` sigue vivo aunque la pantalla se
  cierre, y seguiría llamando a un objeto descartado.
- **En un widget test hay dos relojes**: el del runner (el `FakeClock`) y el del test
  (`tester.pump(duration)` avanza el tiempo simulado que dispara los Timers). Hay que
  adelantar los dos.

## Recargar un widget: cambiar su `key`

Después de templar una Fragua, la Senda y el inicio tienen que recargar sus datos. La
forma idiomática de "reiniciar" un widget con estado desde afuera es **cambiarle la
key**:

```dart
LoadView(key: ValueKey(_version), load: _load, builder: ...)
// al volver de otra pantalla:
setState(() => _version++);
```

Con otra key, Flutter considera que es otro widget: desmonta el anterior (y su `State`)
y monta uno nuevo, que vuelve a correr `initState` y la carga. Es la otra cara de lo que
vimos en los tests de `AuthGate`: con la misma key y el mismo tipo, Flutter *reutiliza* el
`State`.

`Navigator.push` devuelve un `Future` que se completa cuando esa pantalla hace `pop`: así
se sabe que el usuario volvió.

## Otras piezas que aparecieron

- **Records de Futures**: `(a(), b()).wait` lanza los dos requests a la vez y espera
  ambos (como `Mono.zip`). El resultado es un record que se desarma con un patrón:
  `final (programs, stats) = data;`.
- **`PopScope`**: intercepta el "atrás" (botón o gesto). La ejecución lo usa para pedir
  confirmación antes de abandonar una Fragua a la mitad.
- **`pushReplacement`**: reemplaza la pantalla actual en la pila. TEMPLADO reemplaza a la
  ejecución, así "atrás" desde el resumen vuelve a la sesión y no a una ejecución
  terminada.
- **`HapticFeedback.heavyImpact()`**: una vibración al terminar un tiempo, para avisar sin
  tener que mirar la pantalla.
- **`FittedBox(fit: BoxFit.scaleDown)`**: achica un texto si no entra en el ancho, y lo
  deja igual si entra. "TEMPLADO." a 64 px se cortaba a la mitad de la palabra, algo que
  el sistema de diseño prohíbe.
- **`showDialog` / `AlertDialog` y `SnackBar`**: la confirmación de resetear una Senda y
  el aviso si falla.

## La ejecución en el mundo real: pantalla, interrupciones y señal

Tres problemas que no aparecen en el emulador pero sí en un gimnasio:

### Pantalla encendida (`wakelock_plus`)

Sin intervención, el teléfono apaga la pantalla en un descanso largo y la cuenta
regresiva no se ve. `WakelockPlus.enable()` en `initState` y `disable()` en `dispose`:
mientras la pantalla de ejecución exista, la ventana lleva el flag `KEEP_SCREEN_ON` de
Android. Los tests lo apagan (`keepScreenOn: false`): en un widget test no hay plugin
nativo.

### Retomar una Fragua interrumpida (snapshot del runner)

El sistema puede cerrar la app en cualquier momento (falta de memoria, una llamada, la
batería). Para no perder lo hecho:

- `WorkoutRunner.toSnapshot()` saca una "foto" serializable del estado (paso actual,
  tiempos, reps, resultados, client_id), y `WorkoutRunner.restore(...)` hace el camino
  inverso.
- La pantalla guarda el snapshot en el teléfono **cuando cambia algo** (el runner tiene
  un contador `revision` que sube con cada cambio real, no con cada tick) y, además,
  **cada 5 segundos** (*heartbeat*). Escribir al disco 4 veces por segundo sería gasto
  inútil; con el heartbeat, al retomar se pierden como mucho 5 segundos.
- Se guarda **la sesión completa**, no solo su id: retomar no depende de la red.
- Al retomar, la Fragua queda **pausada en el momento del último guardado**: el tiempo
  que la app estuvo cerrada no cuenta (un descanso no "se termina solo" con el teléfono
  en el bolsillo).
- El inicio muestra **FRAGUA EN CURSO · RETOMAR / DESCARTAR**. Una Fragua de más de 12
  horas, o con datos corruptos, se descarta en vez de romper la app.

### Sin señal al terminar (cola offline + idempotencia)

- Si el registro falla **sin conexión** (o con el servidor caído, un 5xx), la Fragua va a
  una **cola** en el teléfono y TEMPLADO avisa que se registra después. Un 4xx (un dato
  que la API rechaza) no se encola: reintentar daría el mismo error.
- El inicio, al cargar, intenta registrar la cola **antes** de pedir el progreso: así la
  Brasa y los checks ya incluyen lo entrenado sin señal.
- **Idempotencia:** cada Fragua lleva un `client_id` (un UUID que genera el teléfono). Si
  el `POST` llegó al servidor pero se perdió la respuesta, el reintento manda el mismo id
  y la API devuelve la Fragua existente (200) en vez de crear otra (201). Es la misma
  técnica que usan las APIs de pagos para no cobrar dos veces.

### Almacenamiento local

`LocalStore` es una interfaz propia (leer / escribir / borrar texto por clave), con una
implementación sobre `shared_preferences` (`SharedPreferencesAsync`), otra cifrada
(`SecureLocalStore`, sobre `flutter_secure_storage`, para la sesión) y otra en memoria
para los tests. Sirve para datos chicos; para muchos datos o consultas haría falta una
base local (sqflite, drift). Encima van `ActiveWorkoutStore` (la Fragua en curso) y
`PendingWorkouts` (la cola). Las tres dependencias de entrenamiento viajan juntas en
`TrainingServices`.

## El ciclo de vida de la app y los mixins (`LockGate`)

Para saber cuándo la app pasa a segundo plano, un `State` se registra como
**observador** del binding: `WidgetsBinding.instance.addObserver(this)` en `initState`, y
`removeObserver` en `dispose` (lo que se registra se libera, como los controllers).
Flutter llama a `didChangeAppLifecycleState` con `resumed` (al frente), `inactive`
(tapada por algo del sistema, como el diálogo de huella), `hidden` y `paused` (en segundo
plano).

`class _LockGateState extends State<LockGate> with WidgetsBindingObserver`: el `with`
mezcla un **mixin**, un bloque de código reutilizable que se incorpora a la clase. Java no
tiene equivalente exacto: se parece a los métodos `default` de una interfaz, pero un mixin
también puede tener campos. `WidgetsBindingObserver` trae todos los callbacks vacíos y se
sobrescribe solo el que interesa.

Dos detalles más:

- **`MaterialApp.builder`** envuelve al `Navigator`. Lo que se ponga ahí queda por encima
  de todas las rutas: sirve para cosas globales, como el candado.
- **`addPostFrameCallback`** corre algo después del primer frame. Hace falta para mostrar
  un diálogo del sistema al arrancar, porque la Activity tiene que estar dibujada, y para
  llamar a `setState`, que no se puede usar dentro de `initState`.

## Arquitectura de la app

El código se organiza **por funcionalidad** (feature-first), no por tipo de archivo:

```
lib/
  main.dart                     arma las dependencias (CatalogClient) y la app
  catalog/                      todo lo del catálogo junto
    program_summary.dart        modelos (fromJson)
    program.dart, session.dart
    catalog_client.dart         acceso a la API
    programs_screen.dart        pantallas: Sendas → Senda → Fragua
    program_screen.dart
    session_screen.dart
    format.dart                 formato de duraciones y reps
  training/                     progreso, Brasa, Mojones y la ejecución de una Fragua
    training_models.dart, training_client.dart
    execution/
      workout_runner.dart       el motor (lógica pura, ChangeNotifier)
      execution_screen.dart     la pantalla que lo muestra
      templado_screen.dart      el resumen al terminar
    offline/                    la Fragua en curso y la cola sin señal
  common/                       piezas compartidas: ApiClient (HTTP), LoadView, LocalStore
  theme/                        sistema de diseño: tokens, ThemeData, widgets propios
```

La alternativa (`models/`, `services/`, `screens/`) obliga a saltar entre tres carpetas
para tocar una sola funcionalidad. Las dependencias se pasan por constructor desde `main`
(como en el backend Go), y eso es lo que permite testear la pantalla con un cliente falso.

### Modelos y JSON

`ProgramSummary.fromJson` usa **pattern matching** de Dart 3: un `switch` sobre el mapa
que verifica a la vez que existan las claves y que tengan el tipo correcto. Si el JSON no
tiene la forma esperada, falla con un `FormatException` claro.

No usamos generación de código (`json_serializable`, `freezed`) a propósito: escribir el
`fromJson` a mano enseña qué pasa. Cuando haya muchos modelos, conviene evaluarla.

**Trampa de encoding:** `response.body` del paquete `http` decodifica con el charset del
header `Content-Type`, y si no viene asume latin1. Nuestra API manda `application/json`
sin charset, así que "Sesión" llegaría como "SesiÃ³n". JSON siempre es UTF-8: por eso el
cliente hace `utf8.decode(response.bodyBytes)`.

## Tests

| Tipo | Qué prueba | Herramientas |
|---|---|---|
| Unit | Modelos y clientes, sin UI | `test`, `expect`; `MockClient` de `package:http/testing.dart` reemplaza la red |
| Widget | Una pantalla, sin emulador | `testWidgets`, `tester.pumpWidget`, `find.text`, `tester.tap` |

En un widget test, Flutter no dibuja solo: `tester.pump()` procesa lo pendiente y dibuja
un frame; `tester.pumpAndSettle()` bombea frames hasta que no queden animaciones. El patrón es acción (`tap`, completar un `Completer`) → `pump()` → `expect`. Los
fakes se escriben a mano con `implements` (toda clase de Dart es también una interfaz), y
un `Completer` permite decidir *cuándo* responde el falso, para ver el estado "cargando".

### Trampas al testear

- **El árbol de semántica está apagado por defecto en los tests**: para buscar por
  etiqueta de accesibilidad (`find.bySemanticsLabel`) hay que encenderlo con
  `tester.ensureSemantics()` (y liberarlo con `dispose()`). Además, un `InkWell` fusiona
  la semántica de sus hijos en un solo nodo ("Templada, FRAGUA 01, Fundamentos"): se
  busca con una expresión regular.

- **Un `setState` que llega después de un `await` puede necesitar un frame más**: si la
  microtarea corre después del frame del `pump`, el cambio recién se ve en el siguiente.
  Pasó en los tests de `LockGate` al resolver el fake del candado. `pumpAndSettle()` bombea
  hasta que no quede nada pendiente.

### Trampas al testear navegación

- **`pumpAndSettle` se cuelga con un `CircularProgressIndicator` en pantalla**: gira para
  siempre, así que nunca "se asienta" (`pumpAndSettle timed out`). Primero hay que
  completar la carga (el `Completer` del fake) y recién después llamar a `pumpAndSettle`
  para que termine la transición.
- **En el primer frame después de un `push`, la pantalla nueva está offstage**: Flutter la
  construye fuera de escena para preparar la transición. El `fetch` ya se disparó, pero
  `find.byType(...)` todavía no la ve (los finders ignoran lo offstage). Un segundo
  `pump` con algo de tiempo la pone en escena.
- **El fake compartido** (`test/catalog/fake_catalog_client.dart`) usa `implements
  CatalogClient`: si el cliente real suma un método, el fake deja de compilar y el
  analizador avisa. Es una ventaja: nunca queda desactualizado en silencio.
