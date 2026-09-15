# Notificaciones en primer plano — estado y plan

**Fecha:** 2026-09-15
**Rama:** `fix/ios-notificaciones-primer-plano`
**Origen:** hallazgo 1 del E2E manual alumno ↔ PF (`spec-hallazgos-e2e-alumno-pf.md`)

Todo lo de acá está **medido en dos teléfonos reales** —un iPhone 16 y un
Android 16 (CPH2749)— salvo donde diga explícitamente lo contrario.

---

## Resumen en una línea

Android y iOS están **completos**: un banner por mensaje, con supresión, medido
en los dos teléfonos.

---

## 1. Lo que ya funciona

| | Android | iOS |
|---|---|---|
| Notificación del SO con la app abierta | ✅ | ✅ |
| Supresión adentro del chat | ✅ | ✅ (ver §3) |
| Supresión en el centro de notificaciones | ✅ | ✅ (ver §3) |
| Un solo banner por mensaje | ✅ | ✅ (ver §3) |
| Notificación con la app en background | ✅ | ✅ |
| Tap que abre el deep link | ✅ | ✅ |

La verificación de Android tiene **su control al lado**, con 14 segundos de
diferencia en el mismo log:

```
10:38:19  [fcm] se muestra — location=/home deepLink=/coach/chat/...
10:38:33  [fcm] suprimido: ya lo estás mirando (/coach/chat/...)
```

El segundo sin el primero no probaría nada: un arreglo que suprime TODO se ve
idéntico a uno que funciona si sólo se mira el caso que debía suprimir.

---

## 2. Los tres bugs arreglados, y por qué estaban tapados entre sí

Es la parte que más importa para no volver a caer.

### 2.1 `onMessage` no disparaba nunca en iOS

`FLTFirebaseMessagingPlugin` hace **todo** su armado adentro de
`application_onDidFinishLaunchingNotification:` (líneas 214-310 de
`FLTFirebaseMessagingPlugin.m`): ahí están `notificationCenter.delegate`,
`addApplicationDelegate` y `registerForRemoteNotifications`. Y se suscribe a esa
notificación en su `init`, o sea **al registrarse**.

Esta app usa `FlutterImplicitEngineDelegate`, que registra los plugins
**después** de `didFinishLaunching`. El observer llega tarde → el método nunca
corre → el delegate nunca se instala → `onMessage` nunca dispara.

> El `registerForRemoteNotifications()` explícito que ya estaba en
> `AppDelegate.swift` era un parche para **otro** síntoma del mismo método
> muerto. Alguien tapó uno de los dos y el otro quedó vivo dos años.

**Arreglo:** reemitir la notificación con el `launchOptions` original después de
registrar los plugins.

### 2.2 iOS suprimía toda presentación en primer plano

Este bug **era invisible hasta arreglar el 2.1**, porque sin delegate no había
nadie suprimiendo — tampoco mostrando.

Con el delegate instalado, FCM decide qué se presenta, y su rama por defecto es:

```objc
UNNotificationPresentationOptions presentationOptions = UNNotificationPresentationOptionNone;
NSDictionary *persistedOptions = [NSUserDefaults ... presentationOptions];
if (persistedOptions != nil) { ... }
```

Sin `setForegroundNotificationPresentationOptions`, `persistedOptions` es `nil` y
devuelve **None para toda notificación**, incluida la local que dibuja la app.

**Síntoma engañoso:** el plugin de locales loguea `mostrada` y la pantalla queda
vacía. El log reporta que `UNUserNotificationCenter` **aceptó** la notificación;
que se pinte lo decide otra capa, después.

**Arreglo:** llamar a `setForegroundNotificationPresentationOptions(alert, badge, sound)`.

> **Superado por §3.** Con `PresentacionEnPrimerPlano` instalado, FCM ya no
> llega a esa rama: estos flags quedan como red por si el shim se cae. El
> diagnóstico de acá sigue siendo el correcto; lo que cambió es quién decide.

### 2.3 La supresión por pantalla nunca funcionó, en ninguna plataforma

El más caro, y el que la suite no podía ver.

La regla pura (`shouldSuppressForegroundNotification`) tenía **11 tests en verde
y era correcta**. Lo roto era la línea que le pasaba la location:

```dart
_router.routerDelegate.currentConfiguration.uri  // ← ignora los `push`
```

Su propio dartdoc dice que la URL *"ignora cualquier `RouteBase` que sea
resultado de una llamada imperativa"*. Y **el chat se abre siempre con
`context.push(...)`** — los seis call sites. Estando adentro del chat la location
decía `/home`, y la comparación no podía matchear jamás.

Las tres APIs y cuál sirve:

| API | Qué devuelve | ¿Sirve? |
|---|---|---|
| `currentConfiguration.uri` | la location ignorando los `push` | ❌ |
| `state.fullPath` | el PATRÓN (`/coach/chat/:chatId`) | ❌ |
| `state.uri` | la uri concreta del último `go` **o `push`** | ✅ |

**Arreglo:** `state.uri`, extraído a `locationActualDe(GoRouter)` para poder
testearlo con un router de verdad. 8 tests nuevos que navegan como navega la
app; control negativo corrido (con la API vieja caen 3).

> Este hueco **estaba anunciado**. El PR #1128 decía textual que el cableado de
> `_onForeground` no tenía test porque el harness existente replica la lógica en
> widgets de prueba en vez de manejar `TreinoApp`. El bug entró justo por ahí.

---

## 3. Los dos banners en iOS: resuelto

**Estado:** resuelto el 2026-09-15 y medido en el iPhone 16. Un banner por
mensaje, con la supresión por pantalla funcionando.

### Por qué aparecían dos, de verdad

El diagnóstico original —"el interruptor es uno solo, global y binario"— era
correcto pero incompleto. Faltaba la causa de fondo: **el puesto de delegate de
`UNUserNotificationCenter` estaba vacante**, y con la app en primer plano ese
delegate es quien decide qué se dibuja.

- `flutter_local_notifications` **nunca** se asigna como delegate en iOS; sólo
  hace `addApplicationDelegate` (`FlutterLocalNotificationsPlugin.m:145-159`).
  Por eso su `willPresentNotification` —que presenta las suyas y se retira con
  las ajenas— era **código muerto**: nadie lo llamaba.
- `FlutterAppDelegate` tampoco se asigna. Implementa los métodos y los reenvía a
  todos los plugins, pero nadie cableaba la entrada de esa cadena.

Con el puesto libre, FCM se lo quedaba entero (`shouldReplaceDelegate = YES` con
`_original = nil`) y caía siempre a su rama por defecto, que aplica un único
interruptor global a **toda** notificación — incluida la local de la app. De ahí
los dos banners, y de ahí también el bug 2.2.

### La opción C estaba mal planteada

Decía forzar el orden de registro para que el plugin de locales ganara el
delegate. **No podía funcionar bajo ningún orden**, porque ese plugin no compite
por el puesto. El orden de `GeneratedPluginRegistrant` es irrelevante acá.

Se falsificó leyendo las fuentes, sin gastar ninguno de los ciclos de build en
device que la estimación preveía.

### Opción D — la que se implementó

Un delegate propio, `PresentacionEnPrimerPlano` (en `AppDelegate.swift`), que
ocupa el puesto **antes** de la reemisión de `didFinishLaunching`. FCM lo captura
como `_originalNotificationCenterDelegate` y le cede la decisión **por
notificación** (`FLTFirebaseMessagingPlugin.m:336-344`):

- **remota** (trae `gcm.message_id`) → `[]`, no se dibuja. No se pierde nada: su
  llegada ya disparó `Messaging#onMessage` en Dart, que aplica `isOwnChatMessage`
  y la supresión por pantalla, y publica la local si corresponde.
- **local** → pasa, con las opciones que eligió Dart (se leen del `userInfo`, así
  `DarwinNotificationDetails` sigue siendo la única fuente de verdad).

Resultado: un banner, supresión completa, las dos guardas vivas, y sin
Notification Service Extension.

### Tres trampas que tiene adentro

1. **`_originalNotificationCenterDelegate` es `__weak`**
   (`FLTFirebaseMessagingPlugin.m:45`). Si no lo retenemos, se libera, FCM deja
   de reenviarle y vuelve a decidir él — **en silencio**. Por eso el
   `AppDelegate` lo guarda en una propiedad `let`.
2. **No puede conformar `FlutterAppLifeCycleProvider`.** Si lo hiciera, FCM lo
   detectaría y NO se quedaría con el delegate
   (`FLTFirebaseMessagingPlugin.m:271-274`), dejándonos como delegate único y sin
   nadie que dispare `onMessage`. Es un `NSObject` pelado a propósito.
3. **No implementa `didReceiveNotificationResponse`.** A propósito: si lo
   hiciera, FCM le reenviaría también los taps y habría que reimplementar su
   ruteo entero. Sin implementarlo, `respondsTo` da 0 y el tap se resuelve
   exactamente como antes.

Los `setForegroundNotificationPresentationOptions` del lado Dart quedan **sin
efecto** mientras el shim esté vivo, y se dejan en `true` a propósito: son la
rama que corre si el shim se cae, y así esa caída se degrada a dos banners —que
se ven y se reportan— en vez de a silencio total, que no se nota hasta que
alguien se pierde un mensaje.

### La medición

Log nativo del iPhone 16, con el control al lado:

```
10:56:48.173  [fcm] delegate armado: FCM se quedó con el centro y nos cede la decisión
10:57:09.388  [fcm] remota callada          ← mensaje 1, fuera del chat
10:57:09.408  [fcm] local presentada        ← 20 ms después → UN banner
10:57:24.781  [fcm] remota callada          ← mensaje 2, adentro del chat
              (sin local atrás)             → SUPRIMIDA
```

El segundo caso sin el primero no probaría nada, y el primero sin el segundo
tampoco: juntos separan "se suprimió" de "el push nunca llegó", que desde la
pantalla se ven idénticos.

⚠️ Los `debugPrint` de Dart **no salen** por el console de `devicectl`, e
`idevicesyslog` devuelve vacío en este iOS. Por eso el shim loguea las dos ramas
—la callada y la presentada—: para que el log nativo alcance solo.

## 4. Pendientes, por orden sugerido

1. **La carrera del permiso.** Un push que llega antes de que `PermissionGate`
   pida autorización se degrada al cartel in-app. En una instalación nueva está
   **garantizado**: el gate necesita el perfil cargado. Visto en iOS hoy
   (`Error 2003 — Source is not authorized` con la app en `/splash`) y es
   probablemente el "cartel blanco" que se veía en Android ayer.
   **Arreglo propuesto:** encolar el aviso hasta que el permiso resuelva, en vez
   de degradarlo.
2. **Cold-start tap** de la notificación local: pierde el deep link
   (`getNotificationAppLaunchDetails` sin implementar). Sólo afecta Android hoy.
   Hallazgo de Codex en el PR #1128.
3. **Los eventos nuevos del lado del PF** (hallazgo original del E2E, punto 1):
   sesión terminada, medidas cargadas, molestia reportada; y del lado del alumno,
   rutina asignada. Ninguno existe. El doc del E2E advierte —y coincido— que
   conviene elegir pocos: una app que notifica todo se silencia entera.
4. **Los accesos en el header del Home** (punto 1.5 del doc del E2E), con badge
   de no leídos. Independiente de todo lo anterior.

---

## 5. Qué NO está cubierto por tests, y por qué

Dicho explícito para que nadie lea el verde como garantía:

| Cambio | Test | Motivo |
|---|---|---|
| `locationActualDe` | ✅ 8, con control negativo | — |
| Regla de supresión | ✅ 11 | ya existían |
| Reemitir `didFinishLaunching` | ❌ | Swift nativo; la suite de Dart no lo alcanza |
| `setForegroundNotificationPresentationOptions` | ❌ | su efecto vive en `UNUserNotificationCenter` |
| `PresentacionEnPrimerPlano` | ❌ | Swift nativo, y su efecto vive en `UNUserNotificationCenter` |

Los dos últimos **sólo se pueden verificar en un device**, y así se verificaron.

---

## 6. Cómo reproducir las pruebas

**Android** (el device queda listo con `flutter run --debug --flavor phone`):

```bash
# los diagnósticos NO salen por el log de `flutter run` en Android — van a logcat
adb logcat -T 1 | grep -aE "se muestra|suprimido|mostrada|show\(\) FALLÓ"
```

**iOS**: `flutter run` falla al iniciar la sesión de depuración
(`Timed out waiting for CONFIGURATION_BUILD_DIR`) por falta del permiso de
**Automatización** de macOS sobre Xcode. Rodeo:

```bash
flutter build ios --release
xcrun devicectl device install app --device <UDID> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --console --terminate-existing \
  --device <UDID> com.backhaus.treino > console.log 2>&1 &
```

En **debug** no sirve `devicectl`: un build JIT sin depurador muestra la
pantalla de "iOS 14+ debug mode".

**Para ver los diagnósticos** va `--console`, y hay que saber qué NO se ve por
ahí: sólo salen los `NSLog` nativos. Los `debugPrint` de Dart **no aparecen**, e
`idevicesyslog` devuelve cero bytes en este iOS. Por eso `PresentacionEnPrimer
Plano` loguea sus dos ramas —`remota callada` y `local presentada`—: para que el
log nativo se baste solo. Ojo también con el retraso de APNS: se midieron hasta
**55 segundos** entre mandar el mensaje y la línea en el log, así que un log que
parece vacío puede estar sólo atrasado.

**Mandar un push de prueba** sin depender del Coach Hub: hacía falta un script
de sólo lectura + envío (`diag_push.js`) que leyera los `fcmTokens` del alumno.
Vivía en el scratchpad de aquella sesión, **y ya no existe** — el scratchpad se
vacía. Si hace falta de nuevo, hay que rehacerlo, y necesita credenciales de
Admin SDK que hoy no están en la máquina (sin ADC y sin service account). La
alternativa que se usó el 2026-09-15 fue mandar el mensaje real desde el PF, que
además prueba el camino de producción entero.

---

## 7. Una trampa de método que costó tres intentos

Para ver un heads-up de Android hay que capturar **dentro de sus ~5 segundos**.
Fallaron: capturar a los 2s de lanzar el script (el push todavía no había
llegado) y capturar a los 60s (ya se había ido). Lo que funcionó: una ráfaga de
8 capturas y comparar **tamaños de archivo** — seis idénticas byte a byte y la
séptima distinta.

Y la regla general que lo engloba, que se repitió todo el día: **el log diciendo
"mostrada" no prueba que se vea.** Son dos capas distintas y sólo la pantalla
contesta la segunda.
