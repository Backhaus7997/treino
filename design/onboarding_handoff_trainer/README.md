# Handoff: Onboarding ENTRENADOR (Personal Trainer) — 5 slides — TREINO

## Overview
Onboarding walkthrough para el perfil **ENTRENADOR** de la app TREINO (Flutter), 5 slides:
Inicio (Resumen del día del coach), Entrenar (Crear planes), Feed, Coach (Alumnos), Perfil (Yo).
Cada slide combina un mockup de la pantalla real del entrenador (preview escalado dentro de un
mini-device) + headline + copy corto + CTA "SIGUIENTE" / "EMPEZAR" (última).
Dos variantes de tema — claro y oscuro — matcheando `AppPalette.mintMagentaLight` / `AppPalette.mintMagenta`.

Es el **hermano** del onboarding de atleta ya entregado: MISMO shell, contenido distinto.
Si el onboarding de atleta ya está implementado en Flutter, esto debería reusar los mismos widgets
del shell y variar solo el contenido de cada slide según el rol del usuario.

## About the Design Files
Los archivos de este bundle son **referencias de diseño hechas en HTML** — prototipos que muestran
look, layout y copy; no código de producción para copiar. La tarea es **recrear estas pantallas de
onboarding en el codebase Flutter** (`lib/features/onboarding/`, siguiendo la estructura
`features/<name>/presentation` que ya usa el repo — ver `lib/features/profile_setup/presentation/profile_setup_flow.dart`
como flujo comparable) usando widgets Flutter, `AppPalette`, `AppTheme`, `TreinoIcon` y las primitivas
de motion/widget existentes (`TreinoFadeSlideIn`, `TreinoTappable`, etc.) — NO embebiendo HTML/WebView.

## Fidelity
**High-fidelity (hifi).** No introducir hex nuevos: todo sale de `AppPalette.of(context)`.
Los previews fueron construidos a partir de screenshots reales de la app en el rol entrenador
(Inicio, Coach/Alumnos, Feed, Entrenar/Crear planes, Perfil/Yo).

## Shell compartido (idéntico al onboarding de atleta)
- Status bar (hora, señal, wifi, batería) + dynamic-island pill.
- Barra de progreso de **5 segmentos** (segmentos llenos = paso actual) + **"SALTAR"** (oculto en la última slide).
- Preview escalado de la pantalla real dentro de un **mini-device flotante con marco blanco**
  (el marco queda **blanco en ambos temas** — representa el chasis físico, no UI de la app).
- Headline: barra vertical accent (4×38) + ícono Phosphor + Barlow Condensed 700 30px.
- Body copy: Barlow 17px, color muted, `text-wrap: pretty`.
- CTA pill full-width: bg accent, 56px de alto, Barlow Condensed 700 16px, letter-spacing 2px.
- **Sin barra de home indicator** — el device real dibuja su propia gesture bar.

### Bottom nav (entrenador)
Mismas 5 tabs que el atleta, mismo tratamiento visual — ENTRENAR, FEED, INICIO, COACH, PERFIL:
- Pill flotante: inset 10px de los bordes del device, alto 46px, radio 23px, superficie translúcida + blur
  (claro: blanco ~92%; oscuro: `#181E1C` ~92%), drop shadow suave.
- **Ítem activo** = círculo accent de 40px, radio full, con ícono *fill* + label adentro,
  glow `0 0 18px rgba(44,229,162,.60)`. Foreground = `palette.bg`.
- **Ítems inactivos** = ícono *regular* + label en `palette.textMuted`, sin fondo.

## Screens / Slides

### 1 — Inicio (Resumen del día del coach) · tab INICIO activa
**Preview:** label accent "MIÉRCOLES 12 AGOSTO"; "HOLA, MATEO" + campana + avatar circular con ring accent "MP".
Card **RESUMEN DEL DÍA** con 3 stats separadas por divisores verticales: PENDIENTES (accent), COMPLETADAS (texto primario), CANCELADAS (rojo).
Sección **PRÓXIMAS SESIONES** + link accent "Agenda >": dos filas de sesión (hora + avatar-iniciales circular + nombre + "Hoy · N min" + caret); la primera lleva un **punto verde que pulsa** (sesión inminente).
Sección **ENTRENARON HOY** + link accent "Dejar feedback >": card con 2 filas (avatar gradiente, nombre, "rutina · min · kg", check-circle fill accent) separadas por hairline.
Sección **PAGOS POR COBRAR** + link accent "+ Cobro >": card con "2 cobros pendientes", detalle de vencimientos y monto total en **highlight**.
CTA interno accent: **"+ ASIGNAR RUTINA"**.
**Headline:** "TU DÍA EN UN PANTALLAZO" / ícono house.
**Copy:** "Cuántas sesiones tenés hoy, quiénes ya entrenaron y qué cobros te quedan pendientes. Todo al abrir la app."

### 2 — Entrenar (Crear planes) · tab ENTRENAR activa
**Preview:** título "CREAR PLANES" + copy "Tu espacio para armar plantillas de rutina y asignarlas a tus alumnos."
Card con borde accent: ícono users-three + "ASIGNAR A UN ALUMNO", texto "Elegí un alumno y armale el plan en su perfil. La plantilla queda guardada y la podés reutilizar.", CTA accent "VER ALUMNOS".
Card "TU BIBLIOTECA DE PLANTILLAS" + acción accent "+ NUEVA"; toggle **on** "Visible para tus alumnos" con subtexto "Tus alumnos ven todas tus plantillas en su Workout."; 4 filas de plantilla (nombre, "N días · N ejercicios", acción accent "ASIGNAR", kebab).
**Headline:** "ARMÁ TUS PLANTILLAS" / ícono barbell.
**Copy:** "Creá una plantilla de rutina una vez y asignala a los alumnos que quieras. Queda guardada en tu biblioteca para reutilizarla."

### 3 — Feed · tab FEED activa
**Preview:** título "FEED" + íconos campana / chat / búsqueda + botón "+" circular accent.
Chips de segmento AMIGOS (activo, accent) / MI GYM / PÚBLICO.
Post de texto de una alumna (avatar gradiente, nombre, "TU ALUMNA · hace 2h", chip **highlight** "ALUMNA", texto, stats kg/min/ej., reacciones heart/flame/comment con contadores).
Post con **foto** (alto ~180px, radio 14px, `object-fit: cover`), caption y reacciones.
Sección "PERSONAS DE TU GYM": 4 filas (avatar gradiente con inicial + nombre en Condensed + caret).
**Headline:** "SEGUÍ A TU COMUNIDAD" / ícono newspaper-clipping.
**Copy:** "Mirá lo que publican tus alumnos y la gente de tu gym, reaccioná a sus sesiones y conseguí alumnos nuevos."

### 4 — Coach (Alumnos) · tab COACH activa
**Preview:** pill segmentado **ALUMNOS** (activo, accent) / AGENDA.
Dos cards de alumno: avatar circular con ícono user, nombre, "Vinculado desde 27/07/2026", chip accent ACTIVO/ACTIVA,
línea de plan asignado + progreso ("Fuerza · Bloque 2" · "4 de 5 sesiones"),
botón outline accent **"PAUSAR VÍNCULO"** y botón outline neutro **"TERMINAR VÍNCULO"**.
Card de solicitud entrante: círculo highlight-tinted con user-plus, "1 solicitud entrante", "Camila Duarte quiere vincularse", caret.
**Headline:** "TUS ALUMNOS, ORDENADOS" / ícono chalkboard-teacher.
**Copy:** "Gestioná cada vínculo, pausalo o cerralo cuando haga falta, y llevá tu agenda de sesiones desde la misma pestaña."

### 5 — Perfil (Yo) · tab PERFIL activa · última slide (CTA "EMPEZAR", sin SALTAR)
**Preview:** label accent "TU CUENTA" + título "YO".
Card de identidad: avatar circular **highlight** "MP", "mateo presset", "Coach · Plan Pro", stats inline "12 ALUMNOS" / "4,8 RATING" (números en accent).
Card "PERFIL PÚBLICO" + chip accent "VISIBLE"; "Aparecés en Coach Discovery · Presencial · Online"; botones "VER PREVIEW" (outline) y "EDITAR" (accent).
Lista de tiles como cards separadas: Solicitudes entrantes (con badge highlight "1"), Disponibilidad, Mis ejercicios, **Cerrar sesión** (highlight), **Eliminar cuenta** (rojo/error).
**Headline:** "TU PERFIL PROFESIONAL" / ícono user.
**Copy:** "Mostrate en Coach Discovery, definí tu disponibilidad y respondé las solicitudes de alumnos nuevos."

## Interactions & Behavior
- SALTAR (arriba derecha) → saltar onboarding, equivalente a llegar al final.
- SIGUIENTE → avanza; en la última slide el botón dice EMPEZAR y cierra el onboarding.
- Los 5 segmentos del progreso se llenan de izquierda a derecha según el índice de slide.
- El **punto verde de la próxima sesión** (slide 1) pulsa en loop: pulso suave de `box-shadow`,
  ~1.8s, ease-in-out. Sutil, no llamativo (`AnimatedContainer` / `TweenAnimationBuilder` sobre el glow).
- Sin otros requisitos de animación; las transiciones entre slides usan la convención del app.

## State Management
Puramente presentacional — sin data async en el flujo. Los previews muestran datos **representativos**,
no providers en vivo. Único estado: índice de slide (0–4), típicamente un `PageController`
como el que ya usa `profile_setup_flow.dart`.

## Datos de ejemplo
Los números y nombres son de muestra y deliberadamente "habitados" (los screenshots reales estaban
casi vacíos: 0 pendientes, "Nadie entrenó hoy todavía", biblioteca con una plantilla de prueba).
El onboarding debe mostrar el estado **poblado** — es material promocional del producto, no data real:
Mateo Presset (coach), alumnos Lucía Ammal / Agustín Sosa / Franco Molina / Camila Duarte,
3 pendientes · 5 completadas · 1 cancelada, 4 plantillas, $64.000 por cobrar, 12 alumnos · 4,8 rating.
Si el equipo prefiere los valores exactos de las capturas (2 alumnos, "— rating"), cambiar solo esos literales.

## Design Tokens
De `lib/app/theme/app_palette.dart` — **no hardcodear hex, usar `AppPalette.of(context)`**.

**Claro (`AppPalette.mintMagentaLight`)**
- accent `#2CE5A2`, highlight `#C123E0`
- bg `#FAFAFA`, bgCard `#FFFFFF`
- border `rgba(0,0,0,.10)`, textPrimary `#0F1513`, textMuted `rgba(0,0,0,.55–.60)`

**Oscuro (`AppPalette.mintMagenta`)**
- accent `#2CE5A2`, highlight `#C123E0`
- bg `#0A0A0A`, bgCard `#0F1513`
- border `rgba(255,255,255,.10)`, textPrimary `#FFFFFF`, textMuted `rgba(255,255,255,.55–.60)`
- **Detalle de flip de tema:** todo foreground sobre superficie accent (label del CTA, ícono/label de la tab activa,
  iniciales de avatar, ícono "+") usa `palette.bg` según `onPrimary: palette.bg` de `AppTheme` —
  en oscuro es **tinta oscura (`#0A0A0A`)**, NO blanco.
- El **marco del mini-device sigue blanco en oscuro** (chasis físico).

**Tipografía:** Barlow (body 400/500/600/700) + Barlow Condensed (headings/labels 600/700), Google Fonts, per `app_theme.dart`.
**Radios:** cards 20px, pills/botones 999px (stadium), chips 999px, tiles chicos 12–18px.
**Íconos:** Phosphor (`phosphor_flutter` / `TreinoIcon`), regular por defecto, **fill** para activo/seleccionado.
Íconos usados: house, barbell, newspaper-clipping, chalkboard-teacher, user, bell, chat-circle, magnifying-glass,
plus, caret-right, check-circle (fill), users-three, user-plus, sparkle, sign-out, trash, dots-three-vertical, heart/flame (fill).

## Assets
- `assets/feed-post-photo.png` — foto del post con imagen en la slide 3. Es un stand-in de una
  **foto subida por el usuario**; en la app viene del campo de imagen del post model.

## Files
- `Onboarding Entrenador - Claro.dc.html` — tema claro, las 5 slides.
- `Onboarding Entrenador - Oscuro.dc.html` — tema oscuro, las 5 slides.
- `support.js` — runtime para abrir los HTML en el browser (no es parte del diseño).

Abrí cualquiera de los dos HTML en el browser para ver las 5 slides en una tira horizontal
(no es un deck swipeable).
