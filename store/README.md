# `store/` — assets y metadata de App Store y Play Store

Todo lo que las stores piden y **no** es el binario. Versionado acá para que
regenerar la vidriera sea reproducible y no dependa de que alguien saque
capturas a mano desde su cuenta real.

> Issue de origen: #629 (Fase 7 — Monetización + Lanzamiento).

---

## 1. Requisitos verificados

⚠️ **Apple y Google cambian estos números.** Los de abajo se verificaron contra
la documentación oficial el **2026-08-25**. Antes de cada release, revalidar en
las fuentes linkeadas y actualizar esta tabla en el mismo PR que sube las
capturas nuevas.

### App Store — capturas

TREINO declara `TARGETED_DEVICE_FAMILY = "1"` (**sólo iPhone**, desde el #1219)
y embebe `TreinoWatch Watch App` vía la build phase *Embed Watch Content*. O sea
**dos familias obligatorias, no tres**: el iPad ya no.

| Familia | Tamaño | Portrait (px) | Obligatorio |
|---|---|---|---|
| iPhone | 6.5" | **1284 × 2778** | Sí — cubre todos los iPhone por escalado |
| iPad | 13" | 2064 × 2752 | **No** — el binario ya no declara iPad (§6.4) |
| Apple Watch | Series 11 46mm | **416 × 496** | Sí — hay watch app embebida |

- 1 a 10 capturas por familia.
- `.png` o `.jpg`, **sin canal alpha ni transparencia**. El PNG que devuelve
  `xcrun simctl io … screenshot` **sale CON alfa** y App Store lo rechaza:
  `magick "$f" -background black -alpha remove -alpha off -strip "$f"`, y
  verificarlo con `sips -g hasAlpha`.

⚠️ **El slot de iPhone es 6.5", no 6.9".** Esta tabla decía 6.9" / 1320 × 2868,
que es lo que dice la documentación general de Apple. Pero **la pantalla de esta
ficha pidió 6.5"**, verificado en App Store Connect el **2026-09-22**, y el set
de 6.9" que se había generado nunca se pudo subir. La lección es la de la §11.1
de `AGENTS.md`: antes de generar, abrir **«View All Sizes in Media Manager»** y
leer lo que pide *esa* ficha, en vez de deducirlo de la documentación.

Simuladores que dan el tamaño exacto, sin reescalar:

| Familia | Simulador | Nota |
|---|---|---|
| iPhone 6.5" | **iPhone 14 Plus** | no viene instanciado en Xcode 26/27; el device type sí existe y se crea con `simctl create` |
| Apple Watch | **Apple Watch Series 11 (46mm)** | emparejado con el iPhone — ver «capturas del reloj» |

⚠️ **`xcrun simctl status_bar` NO existe en watchOS** («Operation not
supported»). La barra de estado del reloj no se puede fijar en 9:41 como la del
iPhone: la hora de la captura es la real. Sacar las del reloj seguidas para que
al menos coincidan entre sí.

### App Store — límites de texto

| Campo | Límite | Archivo |
|---|---|---|
| Nombre | 30 | `ios/metadata/<locale>/name.txt` |
| Subtítulo | 30 | `ios/metadata/<locale>/subtitle.txt` |
| Keywords | 100 (todas juntas, separadas por coma **sin espacio**) | `ios/metadata/<locale>/keywords.txt` |
| Texto promocional | 170 | `ios/metadata/<locale>/promotional_text.txt` |
| Descripción | 4000 | `ios/metadata/<locale>/description.txt` |
| Novedades | 4000 | `ios/metadata/<locale>/release_notes.txt` |

Nombre + subtítulo + keywords son **160 caracteres totales** y es todo lo que
Apple indexa para búsqueda. No repetir palabras entre los tres campos: cada
repetición desperdicia lugar del índice.

### Play Store — gráficos

| Asset | Especificación | Archivo |
|---|---|---|
| Ícono | **512 × 512**, PNG 32-bit con alpha, ≤ 1024 KB | `android/metadata/<locale>/images/icon.png` |
| Feature graphic | **1024 × 500**, JPEG o PNG 24-bit **sin alpha** | `android/metadata/<locale>/images/featureGraphic.png` |
| Capturas teléfono | mín. 2 · para ser elegible a recomendaciones: **4+ a 1080 × 1920** | `android/metadata/<locale>/images/phoneScreenshots/` |

- Dimensión mínima 320 px, máxima 3840 px, y el lado mayor no puede superar el
  doble del menor.
- JPEG o PNG 24-bit, sin alpha.

### Play Store — límites de texto

| Campo | Límite | Archivo |
|---|---|---|
| Nombre | 30 | `android/metadata/<locale>/title.txt` |
| Descripción corta | 80 | `android/metadata/<locale>/short_description.txt` |
| Descripción larga | 4000 | `android/metadata/<locale>/full_description.txt` |
| Novedades | 500 | `android/metadata/<locale>/changelogs/<versionCode>.txt` |

Los límites cuentan igual caracteres de ancho completo y medio.

**Fuentes**:
[Screenshot specifications — App Store Connect](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/) ·
[Graphic assets, screenshots & videos — Play Console](https://support.google.com/googleplay/android-developer/answer/9866151) ·
[Store listing character limits — Play Console](https://support.google.com/googleplay/android-developer/answer/9859152)

---

## 2. Estructura

Los nombres de carpeta y archivo siguen la convención de **fastlane**
(`deliver` para iOS, `supply` para Android). Automatizar la subida queda fuera
de #629, pero adoptando la convención ahora ese issue futuro no tiene que
renombrar nada.

```
store/
  ios/                                    ← layout de fastlane deliver
    metadata/<locale>/{name,subtitle,keywords,promotional_text,description,release_notes}.txt
    screenshots/<locale>/{iphone-6.5,ipad-13,watch}/NN_nombre.png
  android/                                ← layout de fastlane supply
    metadata/<locale>/
      {title,short_description,full_description}.txt
      changelogs/{<versionCode>.txt,default.txt}
      images/{featureGraphic.png,icon.png}
      images/{phoneScreenshots,sevenInchScreenshots,tenInchScreenshots}/NN_nombre.png
  privacy/
    data-safety.md        ← borrador del form de Play
    privacy-labels.md     ← borrador de las nutrition labels de Apple
```

⚠️ Los nombres de `android/` **no son libres**: `supply` sólo encuentra las
capturas bajo `images/phoneScreenshots` (y sus variantes de tablet) y las
release notes bajo `changelogs/<versionCode>.txt`. Cualquier otro árbol exige
preprocesado manual. El `versionCode` sale del sufijo de `pubspec.yaml`
(`version: 0.1.0+16` → `changelogs/16.txt`).

### Locales — no inventar el código

**`es-AR` no existe en ninguna de las dos stores.** Los códigos válidos son:

| Store | Español | Por qué |
|---|---|---|
| App Store Connect | **`es-MX`** | Apple sólo tiene `es-ES` y `es-MX`. Y `es-MX` ya es el *primary language* del app record (`docs/roadmap.md`, App ID `6781307745`) |
| Play Console | **`es-419`** | Es el código de español latinoamericano de Play |

El contenido sigue siendo rioplatense; lo que cambia es la carpeta bajo la que
la store lo acepta. Inglés va en `en-US` en las dos.

El prefijo numérico del archivo (`01_`, `02_`, …) fija el orden en que la store
las muestra. No es decorativo: Play y App Store ordenan alfabéticamente.

---

## 3. Guion de capturas

El mismo set en ambas stores y ambos idiomas, ordenado por lo que vende:

| # | Pantalla | Ruta en la app |
|---|---|---|
| 01 | Sesión activa (el player) | `/workout` → rutina → EMPEZAR |
| 02 | Rutina / plantillas | `/workout` |
| 03 | Insights + progresión por ejercicio | `/workout` → Historial → Insights |
| 04 | Coach — discovery de PF y plan asignado | `/coach` |
| 05 | Feed / Rankings por gym | `/feed` → swipe a Rankings |

---

## 4. Cómo regenerar todo

### 4.1 Levantar el emulador

`firebase-tools` 15+ necesita **Java 21**. El `java` del PATH de esta máquina
es 17, pero el JDK 21 ya está instalado por Homebrew — apuntale `JAVA_HOME` en
vez de tocar nada más:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@21 PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH firebase emulators:start --only firestore,auth --project treino-dev
```

⚠️ **No pinnees `firebase-tools@13` para esquivar el JDK.** Acá abajo decía eso
y el atajo tiene un costo que no se ve desde este archivo: el emulador que trae
la 13 (`cloud-firestore-emulator v1.19.8`) hace que un `get()` sobre un
documento **inexistente** tire `Service call error` en vez de devolver `null`,
que es lo que hace producción y lo que hace la v1.21.0 de la 15. `firestore.rules`
usa ese idiom a propósito para fallar abierto (`paywallEnforcedFor`,
`rutinaEsPaga`), así que con la 13 la suite de reglas se pone **roja en cuatro
tests sobre reglas que están perfectas**, y el mensaje que imprime es
`PERMISSION_DENIED` — indistinguible de un agujero real. Pasó el 2026-09-10:
alguien perdió una tarde buscando un bug inexistente. Detalle y el control
negativo que lo aísla, en la cabecera de `scripts/test_rules.sh`.

Para levantar el emulador y sembrar datos de demo la 13 alcanza, porque nada de
eso evalúa reglas. Igual no vale la pena tener dos versiones dando vueltas: el
`JAVA_HOME` de arriba es una línea.

### 4.2 Sembrar datos de demo

Una sola vez, para instalar las dependencias de los scripts:

```bash
cd scripts && npm install
```

⚠️ `scripts/package.json` pinnea `firebase-admin` a `^13`. **No subirlo a 14**:
la v14 eliminó la API namespaced (`admin.auth()`, `admin.firestore()`) y
**41 de los 48 scripts** de esa carpeta la usan. Migrarlos a los imports
modulares es un issue propio.

```bash
FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/seed_emulator_full.js
```

`seed_emulator_full.js` está guardado contra correr fuera del emulador: aborta
si no encuentra las dos variables de entorno. No necesita `sa-key.json` y no
puede tocar producción.

Siembra 13 atletas y 3 coaches con vínculos, rutinas, sesiones históricas,
posts y turnos — suficiente para que Insights y las gráficas de progresión
salgan **llenas**. Una app de fitness con gráficos vacíos no vende.

Los nombres de personas y de gimnasios del seed son **ficticios**. Los de
gimnasio lo son desde este PR — ver §6.3.

### 4.3 Correr la app contra el emulador

```bash
flutter run --dart-define=USE_EMULATOR=true -d "iPhone 17 Pro Max"
```

Si `pod install` falla con `could not find compatible versions`, el
`Podfile.lock` se desincronizó de `pubspec.yaml`. **`pod repo update` no lo
arregla** — el problema es el lockfile, no el índice de specs:

```bash
cd ios && pod update <NombreDelPod>
```

Y si `pod` revienta con `Unicode Normalization not appropriate for ASCII-8BIT`,
es Ruby sin locale UTF-8, no un problema del Podfile:

```bash
export LANG=en_US.UTF-8
```

### 4.4 Capturar

```bash
xcrun simctl io booted screenshot --type=png store/ios/screenshots/es-MX/iphone-6.5/01_sesion_activa.png
```

El simulador devuelve exactamente los píxeles del device, así que la captura ya
sale en el tamaño que pide Apple. **Nunca recortar ni reescalar a mano**: una
captura reescalada se ve blanda al lado de las nativas y Apple a veces la
rechaza por relación de aspecto.

### 4.5 Quitar el canal alpha (obligatorio)

Apple rechaza PNG con transparencia y Play la rechaza en feature graphic y
capturas. `simctl` puede dejar alpha, así que aplanar siempre antes de subir:

```bash
sips -s format png --setProperty hasAlpha false store/ios/screenshots/es-MX/iphone-6.5/01_sesion_activa.png
```

---

## 5. Reglas de contenido

- **Cero PII.** Ni nombres de alumnos reales, ni gimnasios reales, ni chats
  reales. La ficha de la store es pública para siempre.
- **Naming** (AGENTS.md §1, `docs/product.md`): **TREINO** es la marca ·
  **Coach** es el módulo del PF · **Entreno IA** es el feature de IA — nunca
  "Coach IA".
- ⚠️ **En App Store el nombre "TREINO" está ocupado.** El app record real se
  llama **"TREINO Fitness"** (`docs/roadmap.md`, App ID `6781307745`). El
  `name.txt` tiene que coincidir con eso, no con la marca a secas.
- ⚠️ **No publicitar Entreno IA.** El naming es correcto cuando el feature
  exista, pero hoy **no está implementado**: no hay ruta `/workout/ai`, ni
  `WorkoutAIView`, ni servicio generador en `lib/`. `docs/product.md` lo
  describe y `docs/roadmap.md` lo deja diferido a Fase 7 con Gemini. Anunciarlo
  en la ficha es prometer algo que el binario no entrega.
- **Tono** (`docs/product.md`): voseo rioplatense, CTAs imperativos en
  mayúsculas, sin signos de apertura, sin copy corporativo.
- **Fuera de scope, no mencionar en el copy**: Retos, Missions, Bets,
  Levels/XP, Gamificación. **Rankings sí entra** — es per-gym, opt-in del
  atleta, y es un diferencial vendible.
- **Capturas reales.** Apple rechaza mockups que no representen la app. Un
  frame de marketing *alrededor* de la captura real es aceptable; reemplazarla,
  no.

---

## 6. Bloqueantes abiertos

Estado al 2026-08-25. Ninguno se resuelve dentro de #629.

### 6.1 El set en inglés no se puede generar todavía

`lib/l10n/intl_en.arb` tiene **317 de 1055 claves con valor vacío**. Los
prefijos más golpeados caen justo sobre el guion de capturas:
`performanceChart` (21), `routineEditor` (20), `routineDetail` (14),
`workoutPicker` (12), `coachProfile` / `coachStats` / `coachLocation`.

Y aparte de esas, faltan claves enteras. El propio `flutter run` lo reporta en
cada build:

```
"en": 139 untranslated message(s).
"es": 438 untranslated message(s).
```

O sea: 139 claves ausentes **más** 317 presentes pero vacías.

Además hay strings en castellano **hardcodeados**, que ninguna traducción
alcanza: `session_player_screen.dart` tiene `'SESIÓN ACTIVA'` y
`'TERMINAR SESIÓN'`; `athlete_coach_view.dart:252,547` tiene
`'VÍNCULO PAUSADO'` y `'TERMINAR VÍNCULO'`.

Una captura en inglés hoy sale con botones vacíos y títulos en castellano.
**Las carpetas `en-US/` quedan creadas y vacías a propósito**, para que el set
en inglés entre sin mover nada de lugar cuando el l10n esté completo.

### 6.2 El build de iOS estaba roto en un checkout limpio — resuelto acá

`ios/Podfile.lock` pinneaba `TOCropViewController 2.7.4` mientras
`image_cropper ^12.2.1` exigía `~> 3.1.2`. `pod install` abortaba, así que en un
worktree nuevo no se podía compilar iOS — y sin compilar no hay capturas.

Resuelto en este PR con `pod update TOCropViewController`. Aparecieron además
`integration_test` y `package_info_plus`, que tampoco estaban en el lockfile.

Verificado: `flutter build ios --debug --no-codesign --simulator` termina con
exit 0.

### 6.3 Los gimnasios del seed eran marcas registradas — resuelto acá

`seed_emulator_full.js` usaba `Megatlon Palermo`, `SmartFit Caballito` y
`Megatlon Nueva Córdoba`: cadenas de gimnasios **reales**. Salían en la captura
de Rankings por gym y en el perfil del atleta. Peor todavía, un post sembrado
del feed se quejaba por nombre del estado de los equipos de una de ellas.

Cambiados en este PR por `Hierro Palermo`, `Cadencia Caballito` y
`Hierro Nueva Córdoba`, con el post reescrito en positivo.

⚠️ **No confundir con `scripts/seed_gyms.js`**, que sí siembra el catálogo de
gimnasios **reales**. Eso es un feature legítimo del producto (el atleta elige
su gimnasio de verdad) y no se toca. Lo que no puede pasar es que una marca
real termine en una captura de la ficha.

Antes de publicar, confirmar que los tres nombres inventados no colisionen con
un gimnasio real existente.

### 6.4 El iPad — RESUELTO el 2026-09-23: se sacó (#1219)

Esta sección planteaba dos caminos. Se tomó el segundo.

Cómo estaba la asimetría:

- **iOS**: `TARGETED_DEVICE_FAMILY = "1,2"` e `Info.plist` declara
  `UISupportedInterfaceOrientations~ipad` con las **cuatro** orientaciones.
- **Android**: `AndroidManifest.xml:39` fija `screenOrientation="portrait"`.

En Android la app era sólo teléfono y vertical, pero en iOS se ofrecía como app
de iPad rotable. **Y esa declaración de iPad nunca la eligió nadie**: el
`"1,2"` entró en `cf09068b`, el commit de `flutter create`, y no lo tocó nadie
nunca —`git log -S'TARGETED_DEVICE_FAMILY = "1,2"'` devuelve ese solo commit—.
Tampoco hay layout de tablet en `lib/`.

**Decisión (Martín, 2026-09-23): iPhone-only para la 1.0.** El caso de uso es el
teléfono en la mano en el gimnasio, y la superficie donde una pantalla grande
tiene sentido —el Coach Hub— ya es web. Soportar iPad no es tildar una casilla:
es revisar cada pantalla en otra proporción, con teclado, Split View y Stage
Manager, y Apple rechaza explícitamente la UI de iPhone estirada.

`TARGETED_DEVICE_FAMILY = "1"` en las **tres** configuraciones del PBXProject
(Debug, Release y Profile) — las del target de la Watch App quedan en `4`
porque el target pisa el valor del proyecto. Con eso las capturas de iPad
dejaron de ser obligatorias y el bloqueo «You must upload a screenshot for
13-inch iPad displays» desapareció sin subir ninguna.

Las carpetas `ipad-13/` quedan por si en una 1.1 se decide al revés.

⚠️ **Un cambio de device family invalida el build que ya esté en App Store
Connect.** Hay que subir uno nuevo, con el número de build arriba.

### 6.5 El ícono puede ser placeholder

`pubspec.yaml` documenta que `android: false` estuvo activo mucho tiempo y los
`mipmap-*/ic_launcher.png` fueron el logo de Flutter hasta que se corrigió.
Falta confirmar que `assets/icon/app_icon.png` es el ícono **definitivo** antes
de derivar el `icon-512.png` de Play. Si es placeholder, sale como issue de
diseño aparte (#629 lo excluye explícitamente).

### 6.6 Peso del repo

Las capturas son PNG grandes: 3 familias iOS + 3 Android × 5 pantallas × 2
locales. Definir si van versionadas directo o con Git LFS **antes** de commitear
el primer set — migrar a LFS después reescribe historia.
