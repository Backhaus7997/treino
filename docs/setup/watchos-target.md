# Setup: target watchOS

> ## ✅ RESUELTO (2026-08-04) — `pod install` estuvo roto en esta rama
>
> Se resolvió con `brew upgrade cocoapods` (1.16.2 → 1.17.0). Verificado
> después: `pod install` completa, la reescritura del `.pbxproj` **no** se comió
> el enganche del reloj (`fileSystemSynchronizedGroups`, la fase *Embed Watch
> Content* y la `PBXTargetDependency` siguen ahí), y `xcodebuild` del scheme
> Runner da `BUILD SUCCEEDED`.
>
> Se conserva el detalle abajo porque el mismo problema vuelve en cualquier
> máquina con CocoaPods viejo, y porque la trampa del `objectVersion` sigue
> siendo una trampa.
>
> <details><summary>Detalle del problema original</summary>
>
> Crear el target watchOS en Xcode 26.3 **subió el `objectVersion` del
> `project.pbxproj` de 54 a 70**. CocoaPods 1.16.2 no entiende ese formato:
>
> ```
> [Xcodeproj] Unable to find compatibility version string for object version `70`.
> ```
>
> Mientras los Pods estuvieran sincronizados no molestaba. Al agregar
> `watch_connectivity` (que trae un pod nuevo), `pod install` pasó a ser
> obligatorio — y falla. **Eso rompe `flutter run` y cualquier build de iOS en
> esta rama.**
>
> **El CI no está afectado**: solo corre analyze/test/functions, nunca
> `pod install`.
>
> ### Arreglo propuesto (necesita decisión: toca tu máquina, no el repo)
>
> ```bash
> brew upgrade cocoapods
> ```
>
> Hay 1.17.0 estable contra la 1.16.2 instalada. No se aplicó porque CocoaPods
> es **global** (no hay Gemfile en el repo), así que la actualización afecta
> todos tus proyectos, no solo TREINO.
>
> ### Por qué NO se bajó el `objectVersion` a 54 en su lugar
>
> Parece el arreglo obvio y es una trampa. El target del reloj usa
> `fileSystemSynchronizedGroups`, una clave del formato nuevo. CocoaPods
> **reescribe el `.pbxproj`** durante el install, y una versión de Xcodeproj que
> no conoce esa clave puede descartarla al escribir — dejando el target sin sus
> archivos, en silencio y sin error. El riesgo no compensa.
>
> ### Cómo verificar que quedó arreglado
>
> ```bash
> cd ios && LANG=en_US.UTF-8 pod install
> ```
>
> (El `LANG` no es opcional: sin UTF-8, CocoaPods aborta con
> `Unicode Normalization not appropriate for ASCII-8BIT`.)
>
> </details>

---

## ℹ️ Flutter baja el `objectVersion` del `.pbxproj` en cada build

Xcode 26 escribe `objectVersion = 70` al crear el target del reloj. El paso de
configuración de iOS de Flutter lo **reescribe a 54** en cada `flutter run` /
`flutter build` (reproducido con `flutter build ios --config-only`).

**Consecuencia práctica:** ese archivo va a aparecer modificado seguido, con un
diff de una línea. Es ruido de la herramienta, no un cambio tuyo.

**No es un problema funcional**, verificado con el archivo en 54:
`fileSystemSynchronizedGroups` sobrevive, las 5 referencias a *Embed Watch
Content* siguen, y `xcodebuild` del target da `BUILD SUCCEEDED`. El archivo
queda técnicamente inconsistente (declara el formato viejo usando una clave del
nuevo), pero ni Xcode ni CocoaPods se quejan.

Ni `pod install` ni `xcodebuild` lo tocan — se comprobó cada uno por separado.
Es Flutter.

---

## 🔑 Destrabar el provisioning del reloj para HealthKit

**Prerequisito manual: hay que tocar el portal de Apple Developer — no es
automatizable desde un agente ni desde CI.** Bloquea probar en un Apple Watch
real, pero **no** bloquea escribir, verificar ni mergear el código: las tres
fases del change `watch-workout-session` se verificaron en simulador, incluido
el ritmo cardíaco.

La cuenta es **Individual** (visto en Xcode → Signing & Capabilities, Team
"Martin Backhaus (Individual)"), así que el titular puede hacerlo solo: no hay
que pedirle permiso a ningún Admin.

### El estado de partida, medido

Decodificando los 5 perfiles de
`~/Library/Developer/Xcode/UserData/Provisioning Profiles`:

| application-identifier | claves healthkit |
|---|---|
| `J66AQRRM96.com.treino.app` | 0 |
| `J66AQRRM96.com.backhaus.treino` | 0 |
| `J66AQRRM96.com.backhaus.treino` (Store) | 0 |
| `J66AQRRM96.com.treino.ar` | 0 |
| `J66AQRRM96.com.backhaus.treino-` | 0 |

Dos cosas: ninguno tiene HealthKit, y **ninguno cubre
`com.backhaus.treino.watchkitapp`**. El companion nunca se firmó para un
dispositivo real — todo se hizo en simulador.

Confirmado por el lado del build: el `.xcent` de **dispositivo** del reloj sale
vacío (`{}`), mientras que el `-Simulated.xcent` sí trae
`com.apple.developer.healthkit = true`. En simulador el entitlement está; para
dispositivo todavía no hay de dónde sacarlo.

### Paso a paso

**1. Habilitar HealthKit en el App ID del reloj** (developer.apple.com →
Certificates, Identifiers & Profiles → Identifiers)

- Buscar `com.backhaus.treino.watchkitapp`. **Si no existe, crearlo** — es lo
  más probable, porque el companion nunca se firmó.
  - Tipo: App IDs → App
  - Bundle ID: Explicit, `com.backhaus.treino.watchkitapp`
- En la lista de capabilities, tildar **HealthKit**. Guardar.
- Dejar **sin** tildar "Clinical Health Records": TREINO no lee registros
  clínicos, y pedirlo agranda la superficie que Apple revisa.

**2. Dejar que Xcode regenere el perfil**

La firma del target ya está en automático (`CODE_SIGN_STYLE = Automatic`,
`DEVELOPMENT_TEAM = J66AQRRM96`), así que no hay que crear el perfil a mano:

```bash
open ios/Runner.xcworkspace
```

Target **TreinoWatch Watch App** → pestaña **Signing & Capabilities** → que el
Team sea el correcto. Xcode regenera el perfil solo. Si muestra un error de
firma, el botón *Try Again* fuerza el reintento después del paso 1.

Desde la terminal, el equivalente es agregarle `-allowProvisioningUpdates` a un
build con destino dispositivo.

**3. Verificar que quedó bien — sin necesidad de tener el reloj**

```bash
bash scripts/verify_watch_provisioning.sh
```

Chequea las dos cosas que importan: que exista un perfil que cubra el bundle id
del reloj, y que ese perfil declare `com.apple.developer.healthkit`.

### Por qué esto no se puede saltear

Sin el entitlement en el perfil de **dispositivo**, la app compila e instala
igual y HealthKit **niega todo en silencio** en la muñeca. No hay crash ni
error: simplemente no hay pulsaciones y el entreno no llega a Salud. Es el mismo
modo de falla que cubre `scripts/test_watch_capabilities.sh` del lado del
proyecto, pero éste vive en la cuenta de Apple y ningún test del repo lo alcanza.

---

## ⚠️ El typecheck rápido necesita los flags del target

Para no esperar los +20 minutos de `xcodebuild` veníamos usando un `swiftc
-typecheck` suelto contra el SDK de watchOS. **Ese comando deja pasar errores
que después aparecen recién en el build largo**, porque no reproduce los flags
del target.

Medido en el change `watch-workout-session` (F0): un archivo usaba `@Published`
sin `import Combine`. El typecheck corto lo daba limpio; el build falló con

```
error: initializer 'init(wrappedValue:)' is not available due to missing
import of defining module 'Combine' [#MemberImportVisibility]
```

La causa es `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` en el
target: exige que **cada archivo importe lo que usa**. Sin ese flag, el `import
Combine` de *otro* archivo del mismo lote alcanzaba para que resolviera. Costó
un build entero.

Usar el script, que fija los flags del target:

```bash
bash scripts/typecheck_watch.sh
```

No reemplaza al build —no linkea, no firma, no arma el bundle— pero es el
filtro rápido de antes, ahora sin ese agujero.

---

## ⚠️ Nunca pasar `-sdk` al buildear un workspace con target watchOS

`-sdk iphonesimulator` (o `-sdk iphoneos`) **pisa el `SDKROOT` de TODOS los
targets**, incluido el del reloj. La app watchOS pasa a compilarse contra el SDK
de iOS y aparecen errores que no tienen nada que ver con el código:

```
error: type 'CredentialCoordinator' does not conform to protocol 'WCSessionDelegate'
error: 'foregroundStyle' is only available in iOS 15.0 or newer
```

El primero engaña especialmente: en iOS `WCSessionDelegate` exige
`sessionDidBecomeInactive` y `sessionDidDeactivate`, que en watchOS **no
existen**. El código está bien; el comando está mal.

Usar `-destination` y dejar que cada target resuelva su SDK:

```bash
# MAL
xcodebuild -workspace Runner.xcworkspace -scheme Runner -sdk iphonesimulator build

# BIEN
xcodebuild -workspace Runner.xcworkspace -scheme Runner \
  -destination "platform=iOS Simulator,id=<UDID>" build
```

---

## Probar el reloj de punta a punta

El código Dart y Swift compila y está testeado, pero **el runtime del
emparejamiento no se puede verificar sin hardware**: el simulador no es
confiable para pairing ni reachability, mismo patrón "no emulable" que FCM.

### Qué hace falta

1. iPhone y Apple Watch **físicos**, emparejados entre sí.
2. Los dos con sesión iniciada en la misma cuenta de Apple ID.

### Cómo correrlo

```bash
flutter run -d <UDID-del-iPhone>
```

Al instalarse la app de iPhone, la del reloj viaja adentro y se instala sola
(eso es lo que hace la fase *Embed Watch Content*). Puede tardar unos minutos
en aparecer en la muñeca; si no aparece, en el iPhone: **app Watch → TREINO →
Mostrar app en Apple Watch**.

### Qué deberías ver

| Momento | Reloj |
|---|---|
| Antes de abrir TREINO en el teléfono | "Abrí TREINO en el teléfono para vincular el reloj" |
| Al abrir TREINO estando logueado | "Vinculando…" y enseguida "Listo para entrenar" |
| Reabriendo la app del reloj después | "Listo para entrenar" directo, sin el teléfono cerca |

Ese último punto es **la prueba de que funciona**: el reloj ya tiene credencial
propia y no depende más del teléfono.

### Si se queda en "Abrí TREINO en el teléfono"

Quiere decir que el contexto no llegó. En orden:

1. ¿La app del teléfono estaba abierta y con sesión iniciada? La entrega se
   dispara con el cambio de estado de auth.
2. ¿El reloj figura como emparejado? El servicio corta sin hacer nada si
   `isPaired` es false, a propósito.
3. Mirá el log del teléfono: `deliverCredential` devuelve un enum que dice
   exactamente cuál de las cuatro cosas falló (`notSupported`,
   `noWatchPaired`, `mintFailed`, `deliveryFailed`).

### Prerequisito que sigue sin verificarse

**Si Xcode pide algún *capability* nuevo para `WCSession`.** El ciclo viejo
afirmaba que no hace falta ninguno y nadie lo comprobó. Si al firmar para
dispositivo aparece uno, anotalo acá — es señal de volver al design, no de
aprobarlo y seguir.


Prerequisito manual del change `watch-standalone-client` (fase F0). Requiere
Xcode y una Mac — **no es automatizable desde un agente ni desde CI**, mismo
patrón que la APNs key de `push-notifications-fcm`.

No bloquea el merge del código que no sea Swift. Sí bloquea el smoke
end-to-end.

---

## Contexto: por qué el reloj no usa el SDK de Firestore

Firebase en watchOS es **community-supported**, y **Firestore no figura entre
sus productos soportados** (Auth, Storage, Crashlytics y Analytics sí). Por eso
la app del reloj:

- usa **Firebase Auth** para tener un ID token válido, y
- habla la **REST API de Firestore** con ese token como
  `Authorization: Bearer <idToken>`.

Que las Security Rules se apliquen a ese camino REST **está verificado** contra
el emulador — ver `functions/src/__tests__/watch-rest-session-writes-rules.test.ts`,
que corre en CI. Los resultados: el dueño escribe su sesión y sus `setLogs`
(200); un tercero con token válido es rechazado (403); sin token, rechazado
(403).

---

## Datos del proyecto

| Dato | Valor |
|---|---|
| Apple Team ID | `J66AQRRM96` |
| Bundle id iOS | `com.backhaus.treino` |
| Bundle id watchOS sugerido | `com.backhaus.treino.watchkitapp` |
| Proyecto Firebase | `treino-dev` (ver `.firebaserc`) |

El firmado automático viene funcionando para iOS (salió un IPA de release sin
intervención manual), así que el target nuevo debería heredar la misma cuenta
sin configuración extra.

---

## Paso 0 (bloqueante): instalar la plataforma watchOS

**Xcode NO trae watchOS instalado por defecto.** Descubierto en la práctica el
2026-08-04 sobre un Xcode 26.3 recién usado para compilar iOS sin problemas: al
abrir el selector de plantillas y pasar a la pestaña watchOS aparece un cartel

> **watchOS 26.2 Not Installed** — You will not be able to build or run your
> project.  `[ Get ]`

El boton `Get` descarga el runtime (`watchOS 26.2 Simulator`, varios GB). Sin
eso no hay target que compile, por mas que el wizard lo cree.

Alternativa por fuera del wizard: `Xcode → Settings… → Components`.

---

## Pasos

Ruta **verificada contra Xcode 26.3** (build 17C529). En otras versiones puede
diferir: si no coincide, corregí este doc en vez de improvisar.

1. Abrir `ios/Runner.xcworkspace` en Xcode.
2. Menu **File → New → Target…**
3. En el selector de plantillas, pestaña **watchOS** (arranca en *iOS*).
4. Bajo la seccion **Application**, elegir **App** — es la unica de esa
   seccion. Ojo de no agarrar nada de **Application Extension**, que esta
   arriba y tiene cuatro opciones (App Intents, Intents, Notification Service,
   Widget). Ninguna sirve acá.
5. **Next**. En la pantalla de opciones:
   - **Product Name**: `TreinoWatch`
   - **Team**: el de `J66AQRRM96`
   - **Organization Identifier**: `com.backhaus`
   - Radio: **Watch App for Existing iOS App** — el default es *Watch-only
     App*, que NO sirve (crea una app suelta).
   - Desplegable debajo de ese radio: **Runner**. Ver la trampa de abajo.
   - **Testing System**: `None`
6. **Finish**.
7. Confirmar que el target nuevo quedó con el Team `J66AQRRM96` en
   *Signing & Capabilities*, y con firma automática.
8. Verificar que compila: seleccionar el scheme del Watch App y buildear.

---

## ⚠️ Trampa: no apretar Enter en el wizard

**Pasó de verdad el 2026-08-04 y hubo que revertir el target entero.**

En la pantalla de opciones, **Enter equivale a "Finish"**. Si escribís el
Product Name y apretás Enter, el formulario se envía con el desplegable de la
app companion todavía en `None`, y el target nace suelto. Movete entre campos
con Tab o con el mouse, dejá el desplegable para el final, y recién ahí Finish.

### Cómo saber si te pasó

El daño NO es cosmético y no se nota a simple vista: el target aparece en el
navegador como si estuviera bien. Se detecta leyendo
`ios/Runner.xcodeproj/project.pbxproj`:

```bash
rg -n "PRODUCT_BUNDLE_IDENTIFIER|WKCompanionAppBundleIdentifier" ios/Runner.xcodeproj/project.pbxproj | rg -i "watch"
```

| Síntoma | Bien | Mal |
|---|---|---|
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.backhaus.treino.watchkitapp` | `.watchkitapp` (arranca con punto: no tuvo padre de dónde colgar) |
| `INFOPLIST_KEY_WKCompanionAppBundleIdentifier` | `com.backhaus.treino` | `""` |

Y faltan además dos cosas que el wizard sí arma cuando el desplegable está
puesto — sin ellas la app del reloj nunca se empaqueta dentro de la de iPhone:

```bash
rg -n "Embed Watch Content" ios/Runner.xcodeproj/project.pbxproj   # debe existir
rg -n "PBXTargetDependency" -A3 ios/Runner.xcodeproj/project.pbxproj  # Runner -> watch target
```

### Cómo salir

No parchear el `.pbxproj` a mano: hay que inventar UUIDs y armar tres secciones
(`PBXBuildFile`, `PBXCopyFilesBuildPhase`, `PBXTargetDependency` + su
`PBXContainerItemProxy`). Es más barato y seguro revertir y rehacer, porque lo
que crea el wizard son 5 archivos de plantilla vacíos, sin nada que perder:

```bash
git restore --staged "ios/TreinoWatch Watch App" && rm -rf "ios/TreinoWatch Watch App" && git checkout -- ios/Runner.xcodeproj/project.pbxproj
```

Cerrá Xcode ANTES de revertir, o vuelve a escribir su versión del `.pbxproj`
encima.

---

## Capabilities

`WatchConnectivity` (`WCSession`), que el change usa **solo para el handoff de
credencial** desde el teléfono al reloj, no requiere ningún capability especial
en el Apple Developer portal — a diferencia de Push Notifications, que sí
necesitaba la APNs key.

> **Sin verificar.** Esta afirmación viene del ciclo `watch-connectivity` y
> nadie la comprobó contra el portal. Si al crear el target Xcode pide un
> capability nuevo, **es señal de volver al design**, no de aprobarlo y seguir.
> Anotá acá qué pidió.

El acceso a red (necesario para la REST API de Firestore) no requiere
capability: las apps watchOS lo tienen por defecto.

---

## Verificación

- [ ] El target compila y corre en un Apple Watch **físico**.
- [ ] El simulador **no** sirve para validar pairing ni reachability — mismo
      patrón "no emulable" que FCM. Para el smoke hacen falta iPhone + Apple
      Watch reales.
- [ ] Anotar acá cualquier paso que la realidad haya contradicho, para que el
      próximo no repita el descubrimiento.

---

## Referencias

- `openspec/changes/watch-standalone-client/proposal.md` — fases y decisiones
- `openspec/changes/watch-standalone-client/explore.md` — restricciones de
  plataforma verificadas
- `functions/src/__tests__/watch-rest-session-writes-rules.test.ts` — la prueba
  de que las rules cubren el camino REST
