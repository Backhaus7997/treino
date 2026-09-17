import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cota para las lecturas de Firestore del camino crítico de la sesión.
///
/// Existe porque abrir o retomar un entreno NO tenía ninguna: `getActive`,
/// `listSetLogs` y la carga de la rutina son tres `await` sin límite, y un
/// `get()` que no resuelve —ni devuelve ni tira— deja el `AsyncNotifier` en
/// `AsyncLoading` para siempre. No hay excepción, no hay log, no hay reintento y
/// no hay salida: el atleta se queda mirando un spinner sobre un entreno que ya
/// empezó.
///
/// Medido en el simulador el 2026-08-12: el player quedó girando más de 2
/// minutos al retomar una sesión que el reloj había creado, sin una sola
/// excepción en el log. No se pudo reproducir a pedido en tres intentos
/// dirigidos (arranque limpio, ciclo segundo plano→primer plano, y seis toques
/// seguidos), lo cual encaja con la causa: depende de que la conexión a
/// Firestore quede a medias, no de una secuencia de UI.
///
/// El arreglo NO es adivinar cuándo se cuelga: es que **colgarse deje de ser un
/// estado posible**. Con la cota, un stall se convierte en `TimeoutException` →
/// `AsyncError`, y la pantalla ya sabe mostrar eso con su botón de reintento.
///
/// Es además lo que destraba `_cacheOnlyOnSuccess` en `routine_providers.dart`:
/// toma `ref.keepAlive()` ANTES del await y solo lo suelta en el `catch`, así
/// que un fetch que nunca termina clava el elemento en `AsyncLoading` por el
/// resto de la vida del proceso —y cada lector posterior de `.future` espera
/// para siempre—. Al hacer que el fetch TIRE, el `catch` corre, el link se
/// cierra y la próxima lectura arranca un fetch nuevo.
///
/// 15 segundos es holgado para leer un documento: la idea no es cortar una red
/// lenta de gimnasio, es que un stall tenga fondo. Si en la cancha resulta corto,
/// subirlo es barato; lo que no puede volver es el spinner infinito.
const Duration kFirestoreReadTimeout = Duration(seconds: 15);

/// Cota para la lectura de ADOPCIÓN del documento del reloj en `addSetLog`.
///
/// Es mucho más corta que [kFirestoreReadTimeout] a propósito, y el motivo es
/// que las dos lecturas no valen lo mismo. Abrir un entreno NECESITA su lectura:
/// sin ella no hay pantalla, y 15 segundos es "no te cuelgues para siempre".
/// La adopción del doc del reloj es un EXTRA —evita un duplicado cuando el
/// reloj escribió primero— y está en el camino de marcar una serie, que es el
/// gesto más repetido de la app. Esperar 15 segundos ahí es tan inservible
/// como colgarse: el atleta marca y la fila no reacciona.
///
/// Así que acá el fondo no es "que termine alguna vez", es "que no se note".
/// Si la lectura no contesta en este tiempo, la serie se escribe sin adoptar:
/// el mismo camino que cuando el reloj no escribió nada.
///
/// Hace falta porque un `get()` de Firestore puede quedar a medias sin
/// devolver NI tirar —está medido y documentado arriba—, y un `try/catch` solo
/// no cubre ese caso: sin cota, `logSet` se queda esperando, su guard queda
/// trabado y vuelve el bug de no poder marcar nada sin conexión.
const Duration kWatchAdoptionReadTimeout = Duration(seconds: 2);

/// La cota, inyectable.
///
/// Va por provider y no como constante suelta para que los tests puedan bajarla
/// a milisegundos: un test que espera 15 segundos reales no se corre, y uno que
/// no se corre no protege nada.
final firestoreReadTimeoutProvider =
    Provider<Duration>((ref) => kFirestoreReadTimeout);
