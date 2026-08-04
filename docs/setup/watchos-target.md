# Setup: target watchOS

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
