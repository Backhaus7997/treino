## Resumen

<!-- 1-2 oraciones describiendo qué hace este PR y por qué. -->

## Tipo de cambio

- [ ] feat — nueva feature
- [ ] fix — bug fix
- [ ] chore — mantenimiento / setup
- [ ] refactor — cambio que no agrega feature ni arregla bug
- [ ] docs — sólo documentación
- [ ] test — sólo tests
- [ ] style — formato, comentarios, etc.
- [ ] perf — mejora de performance

## Issue relacionado

Closes #<!-- número -->

<!-- Si no hay issue, explicá brevemente la motivación. -->

## Cambios

<!-- Bullets explicando QUÉ cambió. No copies el diff entero. -->

-
-
-

## Cómo probarlo

<!-- Pasos concretos para que el reviewer reproduzca el cambio. -->

1.
2.
3.

## Quality gates

- [ ] `flutter analyze` → 0 issues
- [ ] `dart format .` aplicado
- [ ] `flutter test` → verde (si hay tests para lo que tocaste)
- [ ] Si toqué freezed: corrí `dart run build_runner build --delete-conflicting-outputs`
- [ ] Actualicé AGENTS.md / CONTRIBUTING.md si cambié reglas o flujo

## Performance & UI (si tocaste UI o estado)

- [ ] No usé `setState` para estado de negocio (sólo Riverpod)
- [ ] Watcheo del provider más chico posible (`select` cuando aplica)
- [ ] Widgets `const` donde se pudo
- [ ] Listas con `ListView.builder` / `SliverList.builder` si pueden crecer
- [ ] Imágenes con `cached_network_image` + `memCacheWidth/Height` razonables
- [ ] Streams / timers / controllers correctamente disposeados
- [ ] Probé en pantalla **chica** (iPhone SE / Pixel 5)
- [ ] Probé en pantalla **grande** (iPhone 15 Pro Max / Pixel 7 Pro)
- [ ] Probé en **iOS** y **Android** (al menos una versión de cada)
- [ ] Probé con **font scale grande** (Settings → Display → Text Size)
- [ ] Si introduje algo potencialmente costoso (animaciones, blurs, listas grandes): corrí `flutter run --profile` en device físico y verifiqué que los frames están < 16ms

## SDD (cambios no triviales)

- [ ] No aplica (cambio trivial)
- [ ] `/sdd-new <name>` ejecutado, todas las fases pasan (`sdd-verify` ok)
- [ ] Decisiones clave guardadas en Engram bajo `--project treino`

## Capturas (si tocaste UI)

<!-- Antes / Después. Drag & drop al editor de GitHub. -->

## Notas para el reviewer

<!-- Cosas que querés que el reviewer mire con más cuidado, o decisiones que dudaste. -->
