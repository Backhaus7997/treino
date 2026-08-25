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

TREINO declara `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone **y** iPad) y embebe
`TreinoWatch Watch App` vía la build phase *Embed Watch Content*. Eso significa
que **las tres familias son obligatorias**, no sólo iPhone.

| Familia | Tamaño | Portrait (px) | Obligatorio |
|---|---|---|---|
| iPhone | 6.9" | **1320 × 2868** | Sí — cubre todos los iPhone por escalado |
| iPad | 13" | **2064 × 2752** | Sí — la app corre en iPad |
| Apple Watch | Series 11 46mm | **416 × 496** | Sí — hay watch app embebida |

- 1 a 10 capturas por familia.
- `.png` o `.jpg`, **sin canal alpha ni transparencia**.
- Los tamaños menores los escala Apple solo — con 6.9" y 13" alcanza.

Simuladores que ya están instalados en la máquina y dan el tamaño exacto:
`iPhone 17 Pro Max`, `iPad Pro 13-inch (M5)`, `Apple Watch Series 11 (46mm)`.

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
| Ícono | **512 × 512**, PNG 32-bit con alpha, ≤ 1024 KB | `android/graphics/icon-512.png` |
| Feature graphic | **1024 × 500**, JPEG o PNG 24-bit **sin alpha** | `android/graphics/feature-graphic.png` |
| Capturas teléfono | mín. 2 · para ser elegible a recomendaciones: **4+ a 1080 × 1920** | `android/screenshots/<locale>/phone/` |

- Dimensión mínima 320 px, máxima 3840 px, y el lado mayor no puede superar el
  doble del menor.
- JPEG o PNG 24-bit, sin alpha.

### Play Store — límites de texto

| Campo | Límite | Archivo |
|---|---|---|
| Nombre | 30 | `android/metadata/<locale>/title.txt` |
| Descripción corta | 80 | `android/metadata/<locale>/short_description.txt` |
| Descripción larga | 4000 | `android/metadata/<locale>/full_description.txt` |
| Novedades | 500 | `android/metadata/<locale>/release_notes.txt` |

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
  ios/
    screenshots/<locale>/{iphone-6.9,ipad-13,watch}/NN_nombre.png
    metadata/<locale>/{name,subtitle,keywords,promotional_text,description,release_notes}.txt
  android/
    screenshots/<locale>/{phone,tablet-7,tablet-10}/NN_nombre.png
    graphics/{icon-512.png,feature-graphic.png}
    metadata/<locale>/{title,short_description,full_description,release_notes}.txt
  privacy/
    data-safety.md        ← borrador del form de Play
    privacy-labels.md     ← borrador de las nutrition labels de Apple
```

Locales: `es-AR` y `en-US`.

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

`firebase-tools` 15+ necesita **Java 21**. Si la máquina tiene 17, pinnear la
versión 13 en vez de actualizar el JDK:

```bash
npx -y firebase-tools@13 emulators:start --only firestore,auth --project treino-dev
```

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
gimnasio lo son desde este PR — ver §6.2.

### 4.3 Correr la app contra el emulador

```bash
flutter run --dart-define=USE_EMULATOR=true -d "iPhone 17 Pro Max"
```

Si falla con `CocoaPods's specs repository is too out-of-date`, actualizar el
índice de specs y reintentar. Tarda varios minutos:

```bash
pod repo update
```

### 4.4 Capturar

```bash
xcrun simctl io booted screenshot --type=png store/ios/screenshots/es-AR/iphone-6.9/01_sesion_activa.png
```

El simulador devuelve exactamente los píxeles del device, así que la captura ya
sale en el tamaño que pide Apple. **Nunca recortar ni reescalar a mano**: una
captura reescalada se ve blanda al lado de las nativas y Apple a veces la
rechaza por relación de aspecto.

### 4.5 Quitar el canal alpha (obligatorio)

Apple rechaza PNG con transparencia y Play la rechaza en feature graphic y
capturas. `simctl` puede dejar alpha, así que aplanar siempre antes de subir:

```bash
sips -s format png --setProperty hasAlpha false store/ios/screenshots/es-AR/iphone-6.9/01_sesion_activa.png
```

---

## 5. Reglas de contenido

- **Cero PII.** Ni nombres de alumnos reales, ni gimnasios reales, ni chats
  reales. La ficha de la store es pública para siempre.
- **Naming** (AGENTS.md §1, `docs/product.md`): **TREINO** es la marca ·
  **Coach** es el módulo del PF · **Entreno IA** es el feature de IA — nunca
  "Coach IA".
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

### 6.2 Los gimnasios del seed eran marcas registradas — resuelto acá

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

### 6.3 El iPad es obligatorio en Apple y quizá nunca se probó

Asimetría entre las dos plataformas:

- **iOS**: `TARGETED_DEVICE_FAMILY = "1,2"` e `Info.plist` declara
  `UISupportedInterfaceOrientations~ipad` con las **cuatro** orientaciones.
- **Android**: `AndroidManifest.xml:39` fija `screenOrientation="portrait"`.

O sea: en Android la app es sólo teléfono y sólo vertical, pero en iOS se
ofrece como app de iPad rotable. Apple **exige** capturas de iPad 13" para
publicar, y esas capturas van a mostrar el layout de iPad tal como está hoy.

Antes de capturar, abrir la app en `iPad Pro 13-inch (M5)` y mirar si el layout
aguanta. Si es una UI de teléfono estirada, hay dos caminos y los dos son
decisión de producto, no de este issue:

1. Arreglar el layout de iPad.
2. Bajar `TARGETED_DEVICE_FAMILY` a `1` (sólo iPhone) y sacar el iPad de la
   ficha — con eso las capturas de iPad dejan de ser obligatorias.

Las carpetas `ipad-13/` quedan creadas para cualquiera de los dos desenlaces.

### 6.4 El ícono puede ser placeholder

`pubspec.yaml` documenta que `android: false` estuvo activo mucho tiempo y los
`mipmap-*/ic_launcher.png` fueron el logo de Flutter hasta que se corrigió.
Falta confirmar que `assets/icon/app_icon.png` es el ícono **definitivo** antes
de derivar el `icon-512.png` de Play. Si es placeholder, sale como issue de
diseño aparte (#629 lo excluye explícitamente).

### 6.5 Peso del repo

Las capturas son PNG grandes: 3 familias iOS + 3 Android × 5 pantallas × 2
locales. Definir si van versionadas directo o con Git LFS **antes** de commitear
el primer set — migrar a LFS después reescribe historia.
