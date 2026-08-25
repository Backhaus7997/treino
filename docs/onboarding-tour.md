# Onboarding de la app — tour de bienvenida

> **DISEÑO A REVISAR.** El tour funciona y pasa el quality gate, pero su estética
> todavía no está aprobada. No existe mockup de onboarding en
> [`design-decisions.md`](./design-decisions.md), así que esto se construyó
> derivando el lenguaje visual de pantallas ya aprobadas (`WelcomeScreen` y
> `ProfileSetupFlow`), no copiando una imagen fuente.

Issue: [#627](https://github.com/Backhaus7997/treino/issues/627).

## Qué es

Cinco slides que corren **una sola vez por usuario**, apenas pasa el login. Se
puede saltear desde la primera. Es un overlay, no un gate del router: `authRedirect()`
no se toca (ver #429 / #499 / #615).

- **Alumno mobile** — INICIO · ENTRENAR · FEED · COACH · PERFIL
- **Entrenador mobile** — las mismas cinco tabs, con copy propio
- **Coach Hub web** — ocho slides, una por sección del sidebar

## La decisión que hay que entender antes de tocar nada

Cada slide muestra un dibujo esquemático de la pantalla que explica
([`onboarding_illustration.dart`](../lib/features/onboarding/presentation/onboarding_illustration.dart)),
**no una captura**. Se evaluaron las tres opciones:

| Opción | Por qué no |
|---|---|
| Capturas reales del simulador | La app arranca en `ThemeMode.system` y tiene tema claro y oscuro: una imagen estática está mal para la mitad de los usuarios. Además COACH y FEED muestran nombres de entrenadores, precios y gente real, que quedarían embebidos en el binario |
| Los PNG de `docs/app-alumno/` | Son oscuros, traen marco de iPhone dibujado, faltan varias pantallas (ENTRENAR del PF, AGENDA web) y algunos ya no coinciden con la app: el mockup de FEED no tiene la tab RANKINGS |

El dibujo esquemático resuelve las tres cosas: lee `AppPalette`, así que es
correcto en ambos temas; pesa cero; y no lleva datos de nadie.

### Y sobre todo: no se desactualiza en silencio

Este es el punto. Una captura envejece **sin avisar** — la app cambia, el PNG se
queda, y nadie se entera hasta que un usuario lo nota. El esquema no puede hacer
eso: está escrito en Dart contra los mismos tokens que la app, y cuando deja de
coincidir el arreglo es una edición visible en un archivo de código, revisable en
un diff.

Las ilustraciones citan en su doc comment de dónde sale cada dato:

- El orden de las tabs viene de `TreinoBottomBar._items` — **ENTRENAR · FEED ·
  INICIO · COACH · PERFIL**. INICIO va al medio, no primero
- Cada pill viene del `_labels` de esa pantalla: `['TU ENTRENO', 'PLANTILLAS']`
  en ENTRENAR, `['FEED', 'RANKINGS']` en el FEED del alumno, `['ALUMNOS',
  'AGENDA']` en el COACH del PF
- El FEED del entrenador **no** tiene RANKINGS, así que su ilustración no dibuja
  el pill

**Si cambiás una tab, un pill o el orden del sidebar, actualizá también la
ilustración correspondiente.** Es un `const` de tres líneas.

## Cómo se persiste

`users/{uid}.onboardingSeen = { athleteMobile: 1, trainerMobile: 1, trainerWeb: 1 }`.

`shouldShow` compara con `<`, no con `!=`, así que subir `currentVersion` re-muestra
el tour a **toda la base** de esa superficie. Es una decisión de producto disfrazada
de constante: subila en su propio PR, nunca como efecto secundario de editar copy.

El controller escribe el **mapa completo**, no un parcial de una clave:
`fake_cloud_firestore` 3.1.0 no hace merge profundo de mapas anidados
(`mock_document_reference.dart`, `_setRawData`), Firestore real sí. Un parcial pasa
en producción y pisa las otras claves en los tests.

## Para volver a verlo en QA

El flag vive en Firestore, así que **reinstalar la app no lo resetea**. Sin
credenciales de admin, la única palanca es subir `currentVersion` temporalmente.
[`scripts/reset_onboarding_cards.js`](../scripts/reset_onboarding_cards.js) hace el
reset, pero necesita `GOOGLE_APPLICATION_CREDENTIALS` y todavía apunta a las claves
viejas por módulo — hay que migrarlo a las tres claves por superficie antes de usarlo.

## Tests

- [`onboarding_illustration_test.dart`](../test/features/onboarding/presentation/onboarding_illustration_test.dart)
  — las 18 ilustraciones renderizan sin overflow a 40 / 130 / 300 pt y en ambos
  temas. Los 40pt no son un tamaño real: son el guard del `FittedBox`, que es lo
  único que evita que cada dimensión fija de adentro sea un overflow esperando una
  pantalla chica. Sacando el `FittedBox`, el test falla
- [`onboarding_tour_view_test.dart`](../test/features/onboarding/presentation/onboarding_tour_view_test.dart)
  — navegación, skip, target táctil de 44pt y layout a 320×568 con textScale 2x
