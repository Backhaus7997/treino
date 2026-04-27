# TREINO

App fitness multiplataforma (Flutter). Personal Trainers + comunidad + workout tracking.

## Stack

- **Flutter** 3.22+ / **Dart** 3
- **Riverpod 2** para state management
- **go_router** para navegación
- **Phosphor Icons** + **Barlow / Barlow Condensed** (Google Fonts)
- **Firebase** (Auth, Firestore, Storage, Functions, Messaging) — pendiente Fase 1

## Estructura

```
lib/
├── main.dart                  # entrypoint
├── app/
│   ├── app.dart               # MaterialApp.router + ProviderScope
│   ├── router.dart            # go_router con ShellRoute (5 tabs)
│   └── theme/
│       ├── app_palette.dart   # AppPalette (mintMagenta default + electricViolet)
│       ├── app_theme.dart     # ThemeData con Barlow
│       └── app_background.dart
├── core/
│   └── widgets/
│       ├── treino_icon.dart   # wrapper semántico sobre Phosphor
│       └── treino_bottom_bar.dart
└── features/
    ├── home/    workout/    feed/    coach/    profile/
```

## Cómo correr

```bash
flutter pub get
flutter run                       # elige el device disponible
flutter run -d "iPhone 16 Pro"    # simulador iOS específico
```

Hot reload: `r` en consola, hot restart: `R`.

## Documentación

La especificación completa de arquitectura, paletas, módulos y roadmap vive en
`DOCUMENTACION_FLUTTER.md` (en el repo de planificación, fuera del código).

## Roadmap

- [x] **Fase 0** — Bootstrap, tema, navegación 5 tabs.
- [ ] **Fase 1** — Auth (email + Google + Apple), Firebase, Profile setup.
- [ ] **Fase 2** — Home + Rutinas (paridad con iOS).
- [ ] **Fase 3** — Feed social.
- [ ] **Fase 4** — Workout++ (bloques, super series, IA, videos).
- [ ] **Fase 5** — Coach / Personal Trainer.
- [ ] **Fase 6** — Polish + lanzamiento.
