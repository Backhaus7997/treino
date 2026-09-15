# Notificaciones en primer plano — estado y plan

**Fecha:** 2026-09-15
**Rama:** `fix/ios-notificaciones-primer-plano`
**Origen:** hallazgo 1 del E2E manual alumno ↔ PF (`spec-hallazgos-e2e-alumno-pf.md`)

Todo lo de acá está **medido en dos teléfonos reales** —un iPhone 16 y un
Android 16 (CPH2749)— salvo donde diga explícitamente lo contrario.

---

## Resumen en una línea

Android está **completo**. iOS notifica pero muestra **dos banners**, y ésa es
la única decisión abierta.

---

## 1. Lo que ya funciona

| | Android | iOS |
|---|---|---|
| Notificación del SO con la app abierta | ✅ | ✅ |
| Supresión adentro del chat | ✅ | ❌ (ver §3) |
| Supresión en el centro de notificaciones | ✅ | ❌ (ver §3) |
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

## 3. La decisión abierta: los dos banners en iOS

**Estado:** en iOS aparecen **dos** banners por mensaje — el remoto que dibuja
el sistema y el local que dibuja la app.

**Por qué no se puede elegir:** son dos notificaciones distintas y el
interruptor que las habilita es **uno solo, global y binario**. No hay forma de
decirle a iOS "presentá ésta sí y ésta no" por mensaje.

Las opciones, con su costo:

| | Banners | Supresión en iOS | Riesgo |
|---|---|---|---|
| **A** — no postear la local en iOS | 1 | se pierde | ninguno |
| **B** — togglear el interruptor global al entrar/salir de pantallas | 1 | se recupera, pero **de más** (adentro de un chat suprime los de otros chats) | si el toggle queda apagado, **te quedás mudo sin enterarte** |
| **C** — hipótesis de orden de delegates | 1 | completa | sin medir |

### Sobre la opción A

Perder la supresión en iOS apaga **dos** guardas, no una:

1. La supresión por pantalla.
2. **`isOwnChatMessage`**, que evita que veas tu propio mensaje cuando tu token
   quedó registrado en la cuenta del otro. Pasa al probar dos cuentas en un
   mismo teléfono. Corre en Dart; con la remota nunca llega a correr.

### Sobre la opción C — la pista concreta, sin medir

`FLTFirebaseMessagingPlugin.willPresentNotification` tiene esta rama:

```objc
// Forward on to any other delegates and allow them to control presentation behavior.
if (_originalNotificationCenterDelegate != nil && respondsTo.willPresentNotification) {
    [_originalNotificationCenterDelegate ... withCompletionHandler:completionHandler];
}
```

Si **otro** delegate llegó primero, FCM le cede la decisión. Y
`flutter_local_notifications` tiene exactamente el comportamiento que queremos:
presenta **las suyas** y se retira sin tocar el handler para las ajenas — lo que
en la práctica suprime la remota.

El orden lo fija `GeneratedPluginRegistrant`, que es alfabético:
`firebase_messaging` va **antes** que `flutter_local_notifications`. Se podría
forzar registrando el de locales a mano primero en el `AppDelegate`.

⚠️ **Es una hipótesis leída, no medida.** El orden real depende de cómo Flutter
encadena los application delegates. Estimación: 1 a 3 iteraciones de
build+prueba en device (10-15 min cada una), con chance real de que no dé y haya
que ir a una **Notification Service Extension** — un target nativo nuevo,
bastante más obra.

---

## 4. Pendientes, por orden sugerido

1. **Decidir iOS** (§3). Bloquea el merge de esta rama.
2. **La carrera del permiso.** Un push que llega antes de que `PermissionGate`
   pida autorización se degrada al cartel in-app. En una instalación nueva está
   **garantizado**: el gate necesita el perfil cargado. Visto en iOS hoy
   (`Error 2003 — Source is not authorized` con la app en `/splash`) y es
   probablemente el "cartel blanco" que se veía en Android ayer.
   **Arreglo propuesto:** encolar el aviso hasta que el permiso resuelva, en vez
   de degradarlo.
3. **Cold-start tap** de la notificación local: pierde el deep link
   (`getNotificationAppLaunchDetails` sin implementar). Sólo afecta Android hoy.
   Hallazgo de Codex en el PR #1128.
4. **Los eventos nuevos del lado del PF** (hallazgo original del E2E, punto 1):
   sesión terminada, medidas cargadas, molestia reportada; y del lado del alumno,
   rutina asignada. Ninguno existe. El doc del E2E advierte —y coincido— que
   conviene elegir pocos: una app que notifica todo se silencia entera.
5. **Los accesos en el header del Home** (punto 1.5 del doc del E2E), con badge
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
xcrun devicectl device process launch --device <UDID> com.backhaus.treino
```

En **debug** no sirve `devicectl`: un build JIT sin depurador muestra la
pantalla de "iOS 14+ debug mode".

**Mandar un push de prueba** sin depender del Coach Hub: hay un script de sólo
lectura + envío en el scratchpad de la sesión (`diag_push.js`), que lee los
`fcmTokens` del alumno y manda uno a cada uno reportando el error por token.

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
