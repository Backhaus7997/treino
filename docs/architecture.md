# Arquitectura — TREINO

Stack, estructura de carpetas, modelos y memoria persistente.

## Stack

- **Flutter** 3.41 / **Dart** ^3.5.0
- **State management**: `flutter_riverpod` 2 (`AsyncNotifier`, `Notifier`, `Provider`, `StateProvider`)
- **Routing**: `go_router` 14 con `ShellRoute` para tab bar
- **Tipografía**: `google_fonts` (Barlow + Barlow Condensed)
- **Íconos**: `phosphor_flutter` (regular + fill)
- **Modelos**: `freezed_annotation` + `json_annotation` + `build_runner` + `freezed` + `json_serializable`
- **Lints**: `flutter_lints` 4 (`analysis_options.yaml` extiende `flutter.yaml`)
- **Firebase**: `firebase_core` (init en Etapa 1 ✅). El resto se suma por etapas en Fase 1 (ver [roadmap.md](./roadmap.md)).
- **MCP local**: Engram (memoria persistente, `engram mcp`)

## Estructura de carpetas

Feature-first en `lib/features/<name>/`. Compartido en `lib/app/` y `lib/core/`.

```
lib/
├── main.dart                    # entrypoint: ProviderScope + Firebase.initializeApp
├── firebase_options.dart        # generado por flutterfire configure (no editar a mano)
├── app/
│   ├── app.dart                 # MaterialApp.router
│   ├── router.dart              # go_router con ShellRoute (5 tabs)
│   └── theme/
│       ├── app_palette.dart     # AppPalette ThemeExtension (mintMagenta + electricViolet)
│       ├── app_theme.dart       # ThemeData con Barlow
│       └── app_background.dart  # Container con ink full-bleed
├── core/
│   ├── widgets/
│   │   ├── treino_icon.dart     # wrapper semántico sobre Phosphor
│   │   └── treino_bottom_bar.dart
│   └── utils/
└── features/
    ├── home/        view: HomeScreen, state: <home_notifier>, data: <repository>
    ├── workout/     rutinas, player, ejercicios, historial
    ├── feed/        amigos · comunidad · público
    ├── coach/       PF discovery, chat, agenda, planes asignados
    └── profile/     ajustes, paleta, gym, datos personales
```

Por feature:

```
features/<name>/
├── view/         # widgets de pantalla y subcomponentes
├── state/        # Notifiers / Providers de Riverpod
└── data/         # Repositories (interface) + Impl Firestore
```

## Modelos

Siempre con **freezed** + **json_serializable**:

```dart
@freezed
class UserProfile with _$UserProfile {
  const factory UserProfile({
    required String uid,
    required String username,
    required UserRole role,
    String? gymId,
    String? avatarUrl,
    // ...
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);
}
```

Después de editar un archivo freezed, correr:

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Firestore mapping

Cada modelo expone `fromFirestore()` / `toFirestore()` factories en un archivo helper:

```dart
extension UserProfileFirestore on UserProfile {
  Map<String, dynamic> toFirestore() => toJson();

  static UserProfile fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return UserProfile.fromJson({...data, 'uid': doc.id});
  }
}
```

## Memoria persistente (Engram)

Engram MCP guarda decisiones bajo `--project treino`. **Es local por máquina** — cada dev tiene su propia DB.

### Memorias clave existentes

| Topic key | Tipo | Contenido |
|---|---|---|
| `sdd-init/treino` | architecture | Contexto completo del proyecto (stack, decisiones, naming) |
| `sdd/treino/testing-capabilities` | config | Test runners, layers, coverage tools detectados |
| `skill-registry` | config | Catálogo de skills disponibles |

### Recuperar contexto en una sesión nueva

```bash
engram context treino
engram search "<query>" --project treino
```

### Guardar decisiones nuevas

```bash
engram save "<title>" "<content>" \
  --type decision \
  --project treino \
  --topic "<unique-key>"
```

Para que el agente lo haga automático, se invoca el tool MCP `mem_save`. Está documentado para que agentes lo llamen proactivamente cuando se toman decisiones (ver [`../AGENTS.md`](../AGENTS.md)).

### Lo que Engram NO resuelve

- **No se comparte** entre máquinas. Si un dev guarda algo, otro dev no lo ve.
- Para decisiones que **deben** ser team-wide, escribirlas en `docs/` y commitearlas.
- Si en algún momento queremos team-wide, migrar a modo `hybrid` (Engram local + `openspec/` versionado en git).

## Documentación adicional

- **Especificación completa de producto y diseño** (paletas, módulos, roadmap, mocks): `~/Desktop/TREINO-Documentacion-Flutter.{md,html}` (también en el repo gymrankiOS de planning).
- **Skills disponibles** en este proyecto: [`../.atl/skill-registry.md`](../.atl/skill-registry.md) (24 skills indexadas).
- **Brand assets**: paleta y logos del PDF `brand_palette_v2.pdf`.
