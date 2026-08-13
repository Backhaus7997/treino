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

/// La cota, inyectable.
///
/// Va por provider y no como constante suelta para que los tests puedan bajarla
/// a milisegundos: un test que espera 15 segundos reales no se corre, y uno que
/// no se corre no protege nada.
final firestoreReadTimeoutProvider =
    Provider<Duration>((ref) => kFirestoreReadTimeout);
