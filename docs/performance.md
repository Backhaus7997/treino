# Performance — TREINO

Reglas de performance, batería y rebuilds. La app corre en mobile — cada rebuild innecesario y cada render pesado degrada la experiencia y consume batería. Estas reglas son **no negociables**.

## State management

- Todo el estado **vive en Riverpod 2** (`AsyncNotifier`, `Notifier`, `Provider`, `StateProvider` cuando aplica).
- **No** usar `setState` en widgets que tienen lógica de negocio. Reservalo sólo para estado *puramente local de presentación* (animaciones, controllers, focus) en `StatefulWidget`s pequeños.
- **No** usar `InheritedWidget` ni `ChangeNotifier` directos. Si hace falta, encapsular detrás de Riverpod.

## Evitar rebuilds innecesarios

- `Consumer` y `ref.watch` **siempre del provider más chico posible**. Nunca watchear un provider grande para leer un solo campo.
- Usar `select` para granularidad fina:
  ```dart
  final name = ref.watch(userProfileProvider.select((p) => p.fullName));
  ```
- Splittear widgets: el subtree que rebuildea cuando cambia un dato, debe ser el más chico posible (extraer a un widget hijo y watchear adentro).
- Marcar widgets como `const` siempre que se pueda. `prefer_const_constructors` está activo en lints.
- **No** anidar `Consumer` innecesariamente: uno chico cerca de la hoja > uno grande que envuelve media pantalla.
- Para listas largas: usar `ListView.builder` / `SliverList.builder` (no `ListView(children: [...])`).

## Renders pesados

- **Imágenes remotas**: siempre `cached_network_image` con `memCacheWidth` y `memCacheHeight` ajustados al tamaño real de pantalla. Nunca cargar 4K en una thumbnail.
- **Animaciones**: preferir implícitas (`AnimatedContainer`, `AnimatedOpacity`) antes que `AnimationController`. Si usás controller, **dispose** en `dispose()`.
- **Opacity** sobre subtrees grandes es caro: usar `FadeTransition` o `AnimatedOpacity` (que bypassan el repaint).
- **Sombras y blurs**: medir antes de dejarlos en producción. `BackdropFilter` es muy caro — reservar a casos puntuales.
- **No** abrir streams Firestore que nunca cierran. Cancelar suscripciones en el `dispose` del Notifier.

## Batería

- **Timers**: pausar cuando la app va a background (usar `AppLifecycleState`).
- **Geolocalización**: no leer pasivamente — sólo on-demand cuando el usuario toca "Buscar PFs cerca de mí".
- **Polling de Firestore**: usar listeners en vez de polling. Y cerrarlos al salir de la pantalla.
- **Wake-lock**: nunca a menos que sea explícitamente necesario (ej. Workout Player con timer corriendo). Liberar al salir.

## Testing visual / multi-device

Antes de mergear cualquier PR que toque UI, probar en al menos:

### Tamaños de pantalla

- iPhone SE (3rd gen) — ancho 375pt, pantalla chica.
- iPhone 15 Pro Max — ancho 430pt, pantalla grande con notch dinámico.
- iPad mini — modo retrato y landscape (responsive).
- Android: Pixel 5 (340dp) y Pixel 7 Pro (412dp).

### Sistemas operativos

- iOS 16 mínimo (deployment target).
- iOS 17/18 (current).
- Android API 24 mínimo.
- Android 14 (API 34, target).

### Modos y orientación

- Modo oscuro siempre (la app es dark-only, no hay light theme).
- Portrait por defecto. Landscape opcional excepto en **Workout Player** que sí debe soportarlo (útil para pantalla del gym apoyada en banco).

### Densidad de texto

Probar con dynamic type / font scale grande (Settings → Display → Text Size). El layout no debe romperse.

Si no podés probar en algún device físico, usar simuladores. La skill `flutter-build-responsive-layout` ayuda a manejar `MediaQuery` y `LayoutBuilder` para que el código sea adaptive desde el primer commit.

## Profiling cuando algo se siente lento

1. `flutter run --profile` en device físico (no simulator — el simulator miente para performance).
2. Abrir DevTools (`d` en consola) → tab **Performance** → grabar interacción → buscar frames > 16ms.
3. Tab **CPU Profiler** para encontrar funciones costosas.
4. Si rebuilds son el problema: tab **Performance** → "Track Widget builds" → ver qué se está rebuildando que no debería.
