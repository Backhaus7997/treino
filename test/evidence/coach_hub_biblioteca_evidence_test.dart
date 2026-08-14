// Harness de evidencia visual de la sección "Biblioteca" (dir/ruta
// `biblioteca`) del Coach Hub web (EVIDENCE-HARNESS).
//
// Captura 4 screenshots (goldens) de la sección `/biblioteca` montada DENTRO
// del shell real (CoachHubScaffold) con proveedores falsos POBLADOS
// (catálogo de ejercicios reales + ejercicios personalizados + templates de
// rutina del trainer) para que el screenshot muestre data real, no
// vacío/error. Estos PNGs sirven como línea base BEFORE/AFTER para validar
// regresiones visuales de la Fase 7.
//
// Mismo patrón que test/evidence/coach_hub_nutricion_evidence_test.dart
// (Fase 6) — ver ese archivo para el detalle de por qué se cargan las
// fuentes así.
//
// IMPORTANTE: este archivo se salta por completo a menos que se pase
// --dart-define=EVIDENCE=true al test runner. Así, `flutter test` normal
// nunca lo ejecuta ni descarga nada.
//
// Regenerar capturas:
//   flutter test --update-goldens \
//     --dart-define=EVIDENCE=true \
//     --dart-define=EVIDENCE_DIR=before \
//     test/evidence/coach_hub_biblioteca_evidence_test.dart
//
// Los PNGs se guardan en:
//   docs/web-trainer/evidence/fase-7/<EVIDENCE_DIR>/
//
// Matriz: (dark, light) × (1440x900, 420x900) = 4 goldens.
//
// Guard (WU-01): la screen real (`BibliotecaWebScreen`) ya existe antes de
// esta fase (2 tabs: Ejercicios + Templates Rutinas), así que el guard exige
// directamente, a >=768px, las señales de que la overview real montó con
// data: (1) título "BIBLIOTECA" y (2) el nombre de un ejercicio real del
// catálogo fake ("Press de Banca").

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/routes.dart'
    show bibliotecaRoutes;
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
import 'package:treino/features/coach_hub/presentation/shell/responsive.dart'
    show kMobileBreakpoint;
import 'package:treino/features/coach_hub/presentation/shell/sidebar_registry.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart'
    show customExercisesForTrainerStreamProvider;
import 'package:treino/features/workout/application/exercise_providers.dart'
    show exercisesProvider;
import 'package:treino/features/workout/application/routine_providers.dart'
    show trainerTemplatesStreamProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/l10n/app_l10n.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Guardián: si EVIDENCE != true, el archivo entero se salta.
// ──────────────────────────────────────────────────────────────────────────────
const bool _evidenceEnabled =
    bool.fromEnvironment('EVIDENCE', defaultValue: false);

const String _evidenceDir =
    String.fromEnvironment('EVIDENCE_DIR', defaultValue: 'before');

// ──────────────────────────────────────────────────────────────────────────────
// Fakes / stubs (mismo patrón que coach_hub_nutricion_evidence_test.dart)
// ──────────────────────────────────────────────────────────────────────────────
class _MockUser extends Mock implements User {}

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AsyncValue<User?> _fixedState;

  @override
  Future<User?> build() async {
    state = _fixedState;
    return _fixedState.valueOrNull;
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Factories — catálogo de ejercicios reales, ejercicios personalizados y
// templates de rutina del trainer, todo con datos de dominio reales (nada
// inventado de negocio).
// ──────────────────────────────────────────────────────────────────────────────
const _trainerUid = 'evidence-trainer';

UserProfile _trainerProfile() => UserProfile(
      uid: _trainerUid,
      email: 'trainer@treino.app',
      displayName: 'Mateo García',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// ~8 ejercicios reales del catálogo (`docs/exercises_catalog.json` es la
/// fuente real en producción; acá se hardcodea un subconjunto representativo
/// con el mismo shape del modelo `Exercise`).
List<Exercise> _catalogExercises() => const [
      Exercise(
        id: 'ex-press-banca',
        name: 'Press de Banca',
        muscleGroup: 'chest',
        category: 'compound',
        equipment: EquipmentType.barra,
        defaultRestSeconds: 120,
      ),
      Exercise(
        id: 'ex-sentadilla',
        name: 'Sentadilla',
        muscleGroup: 'quads',
        category: 'compound',
        equipment: EquipmentType.barra,
        defaultRestSeconds: 150,
      ),
      Exercise(
        id: 'ex-peso-muerto',
        name: 'Peso Muerto',
        muscleGroup: 'back',
        category: 'compound',
        equipment: EquipmentType.barra,
        defaultRestSeconds: 180,
      ),
      Exercise(
        id: 'ex-curl-biceps',
        name: 'Curl de Bíceps',
        muscleGroup: 'biceps',
        category: 'isolation',
        equipment: EquipmentType.mancuerna,
        defaultRestSeconds: 60,
      ),
      Exercise(
        id: 'ex-press-militar',
        name: 'Press Militar',
        muscleGroup: 'shoulders',
        category: 'compound',
        equipment: EquipmentType.barra,
        defaultRestSeconds: 90,
      ),
      Exercise(
        id: 'ex-remo-mancuerna',
        name: 'Remo con Mancuerna',
        muscleGroup: 'back',
        category: 'compound',
        equipment: EquipmentType.mancuerna,
        defaultRestSeconds: 90,
      ),
      Exercise(
        id: 'ex-extension-triceps',
        name: 'Extensión de Tríceps',
        muscleGroup: 'triceps',
        category: 'isolation',
        equipment: EquipmentType.cable,
        defaultRestSeconds: 60,
      ),
      Exercise(
        id: 'ex-plancha',
        name: 'Plancha',
        muscleGroup: 'core',
        category: 'isolation',
        equipment: EquipmentType.pesoCorporal,
        defaultRestSeconds: 45,
      ),
    ];

/// 2 ejercicios personalizados del trainer (para poblar la mezcla catálogo ∪
/// custom que arma `bibliotecaExercisesProvider`).
List<CustomExercise> _customExercises() {
  final now = DateTime.now().toUtc();
  return [
    CustomExercise(
      id: 'custom-hip-thrust',
      ownerId: _trainerUid,
      name: 'Hip Thrust con Barra',
      muscleGroup: 'glutes',
      equipment: EquipmentType.barra,
      defaultRestSeconds: 120,
      createdAt: now.subtract(const Duration(days: 30)),
      updatedAt: now.subtract(const Duration(days: 10)),
    ),
    CustomExercise(
      id: 'custom-face-pull',
      ownerId: _trainerUid,
      name: 'Face Pull en Polea',
      muscleGroup: 'shoulders',
      equipment: EquipmentType.cable,
      defaultRestSeconds: 60,
      createdAt: now.subtract(const Duration(days: 20)),
      updatedAt: now.subtract(const Duration(days: 5)),
    ),
  ];
}

/// 2 templates de rutina del trainer (`RoutineSource.trainerTemplate`) para
/// poblar el tab "Templates Rutinas".
List<Routine> _trainerTemplates() => const [
      Routine(
        id: 'tpl-fuerza-full-body',
        name: 'Fuerza Full Body',
        split: 'Full Body',
        level: ExperienceLevel.beginner,
        days: [],
        source: RoutineSource.trainerTemplate,
        assignedBy: _trainerUid,
        estimatedMinutesPerDay: 60,
      ),
      Routine(
        id: 'tpl-ppl-hipertrofia',
        name: 'PPL Hipertrofia',
        split: 'PPL',
        level: ExperienceLevel.intermediate,
        days: [],
        source: RoutineSource.trainerTemplate,
        assignedBy: _trainerUid,
        estimatedMinutesPerDay: 75,
      ),
    ];

// ──────────────────────────────────────────────────────────────────────────────
// Carga de fuentes TTF reales desde test/fonts/ (idéntico a
// coach_hub_nutricion_evidence_test.dart — ver ese archivo para el
// razonamiento completo).
// ──────────────────────────────────────────────────────────────────────────────
Future<void> _loadTestFonts() async {
  await _loadFontFamily(AppFonts.barlow, [
    'test/fonts/Barlow-Regular.ttf',
    'test/fonts/Barlow-Medium.ttf',
    'test/fonts/Barlow-SemiBold.ttf',
    'test/fonts/Barlow-Bold.ttf',
  ]);

  await _loadFontFamily(AppFonts.barlowCondensed, [
    'test/fonts/BarlowCondensed-Regular.ttf',
    'test/fonts/BarlowCondensed-Bold.ttf',
  ]);

  await _loadPhosphorFonts();
}

Future<ByteData?> _readTtf(String path) async {
  final file = File(path);
  if (!file.existsSync()) return null;
  return ByteData.sublistView(await file.readAsBytes());
}

Future<void> _loadFontFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final bytes = await _readTtf(path);
    if (bytes != null) loader.addFont(Future.value(bytes));
  }
  await loader.load();
}

Future<String> _resolvePackageRoot(String packageName) async {
  final configFile = File('.dart_tool/package_config.json');
  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
  final packages = config['packages'] as List<dynamic>;
  final pkg = packages.cast<Map<String, dynamic>>().firstWhere(
        (p) => p['name'] == packageName,
        orElse: () => throw StateError(
          'Package "$packageName" not found in .dart_tool/package_config.json',
        ),
      );
  final rootUri = pkg['rootUri'] as String;
  // rootUri puede ser absoluto (file:///...) o relativo a package_config.json
  // — Uri.resolve maneja ambos casos correctamente.
  final resolved = configFile.absolute.uri.resolve(rootUri);
  return resolved.toFilePath();
}

Future<void> _loadPhosphorFonts() async {
  const styleToAsset = {
    'Regular': 'Phosphor.ttf',
    'Fill': 'Phosphor-Fill.ttf',
    'Bold': 'Phosphor-Bold.ttf',
  };

  final packageRoot = await _resolvePackageRoot('phosphor_flutter');

  for (final entry in styleToAsset.entries) {
    final loader = FontLoader('packages/phosphor_flutter/Phosphor${entry.key}');
    final ttfPath =
        '$packageRoot/lib/fonts/${entry.value}'.replaceAll('\\', '/');
    final bytes = await _readTtf(ttfPath);
    if (bytes != null) loader.addFont(Future.value(bytes));
    await loader.load();
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Tema de evidencia — idéntico a coach_hub_nutricion_evidence_test.dart.
// ──────────────────────────────────────────────────────────────────────────────
ThemeData _evidenceTheme({required AppPalette palette, required bool dark}) {
  final base = dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);

  final textTheme = base.textTheme.apply(
    fontFamily: AppFonts.barlow,
    bodyColor: palette.textPrimary,
    displayColor: palette.textPrimary,
  );

  const condensedStyle = TextStyle(
    fontFamily: AppFonts.barlowCondensed,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );
  final finalTextTheme = textTheme.copyWith(
    displayLarge: textTheme.displayLarge?.merge(condensedStyle),
    displayMedium: textTheme.displayMedium?.merge(condensedStyle),
    headlineLarge: textTheme.headlineLarge?.merge(condensedStyle),
    headlineMedium: textTheme.headlineMedium?.merge(condensedStyle),
    headlineSmall: textTheme.headlineSmall?.merge(condensedStyle),
    titleLarge: textTheme.titleLarge?.merge(condensedStyle),
  );

  return base.copyWith(
    scaffoldBackgroundColor: palette.bg,
    colorScheme: (dark ? ColorScheme.dark : ColorScheme.light)(
      primary: palette.accent,
      onPrimary: palette.bg,
      secondary: palette.highlight,
      onSecondary: palette.textPrimary,
      surface: palette.bgCard,
      onSurface: palette.textPrimary,
      error: palette.danger,
    ),
    textTheme: finalTextTheme,
    extensions: [palette],
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Silencia el ruido async conocido de `GoogleFonts.barlowCondensed(...)`
// cuando intenta resolver la fuente por red y la red está bloqueada en el
// entorno de test. Ver coach_hub_nutricion_evidence_test.dart para el
// razonamiento completo.
// ──────────────────────────────────────────────────────────────────────────────
void _ignoreKnownGoogleFontsAsyncErrors() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    final isGoogleFontsNetworkError = message.contains('google_fonts') ||
        message.contains('Failed to load font') ||
        message.contains('allowRuntimeFetching');
    if (isGoogleFontsNetworkError) return;
    previousOnError?.call(details);
  };
  // CRÍTICO: restaurar el handler original al cerrar el test (ver
  // coach_hub_nutricion_evidence_test.dart — mismo razonamiento).
  addTearDown(() => FlutterError.onError = previousOnError);
}

// ──────────────────────────────────────────────────────────────────────────────
// Helper: monta el shell real (CoachHubScaffold) con la sección de Biblioteca
// en `/biblioteca`, GoRouter + proveedores falsos POBLADOS.
// ──────────────────────────────────────────────────────────────────────────────
Future<void> _pumpBiblioteca(
  WidgetTester tester, {
  required ThemeData theme,
  required Size physicalSize,
}) async {
  _ignoreKnownGoogleFontsAsyncErrors();
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();

  final mockUser = _MockUser();

  final container = ProviderContainer(overrides: [
    authNotifierProvider.overrideWith(
      () => _StubAuthNotifier(AsyncData(mockUser)),
    ),
    userProfileProvider.overrideWith(
      (ref) => Stream<UserProfile?>.value(_trainerProfile()),
    ),
    sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
    currentUidProvider.overrideWithValue(_trainerUid),
    exercisesProvider.overrideWith((ref) => Future.value(_catalogExercises())),
    customExercisesForTrainerStreamProvider(_trainerUid)
        .overrideWith((ref) => Stream.value(_customExercises())),
    trainerTemplatesStreamProvider(_trainerUid)
        .overrideWith((ref) => Stream.value(_trainerTemplates())),
  ]);
  addTearDown(container.dispose);

  // Warm providers que el shell y la sección leen en build.
  await tester.runAsync(() async {
    await container.read(authNotifierProvider.future).catchError((_) => null);
    await container.read(userProfileProvider.future).catchError((_) => null);
    await container.read(sharedPreferencesProvider.future);
    await container
        .read(exercisesProvider.future)
        .catchError((_) => <Exercise>[]);
  });

  // GoRouter: ShellRoute con CoachHubScaffold + rutas reales de Biblioteca
  // (`/biblioteca`) + el resto de rutas del sidebar como stub liviano,
  // necesarias para que el sidebar resuelva GoRouterState.of(context) (mismo
  // patrón que coach_hub_nutricion_evidence_test.dart). `/biblioteca` se
  // excluye del loop porque ya la aporta `bibliotecaRoutes` — evita GoRoute
  // duplicada (biblioteca SÍ está en `sidebarRegistry`).
  final otherPaths = sidebarRegistry
      .map((i) => i.route)
      .toSet()
      .where((p) => p != '/biblioteca');
  final router = GoRouter(
    initialLocation: '/biblioteca',
    routes: [
      ShellRoute(
        builder: (ctx, state, child) => CoachHubScaffold(child: child),
        routes: [
          ...bibliotecaRoutes,
          for (final p in otherPaths)
            GoRoute(path: p, builder: (_, __) => const _FakeSectionBody()),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  // NOTA (WU-01, evidencia BEFORE): los widgets de Biblioteca (legado,
  // pre-Fase 7) llaman `GoogleFonts.barlow(...)`/`GoogleFonts.barlowCondensed(...)`
  // directamente (en vez de `AppFonts` + tema, como el resto del kit v2) —
  // esto dispara un intento real de fetch de red del `.ttf`, que en el
  // sandbox de test (sin red) rechaza el `Future` interno del paquete
  // `google_fonts` de forma NO controlada por el árbol de widgets (no pasa
  // por `FlutterError.onError`, sino por el manejador de errores async de la
  // zona del test — ver `handleUncaughtError` en
  // `package:flutter_test/src/binding.dart`). `_ignoreKnownGoogleFontsAsyncErrors`
  // (arriba) no alcanza a silenciarlo porque ese codepath exige que
  // `_pendingExceptionDetails` quede seteado tras cualquier `reportError`,
  // así que hace falta interceptar el error ANTES de que llegue a la zona
  // del test: se envuelve el pump completo en una zona hija propia
  // (`runZonedGuarded`) y se descarta ahí el ruido conocido de red de
  // `google_fonts`, dejando pasar cualquier otro error real hacia el test.
  final completer = Completer<void>();
  runZonedGuarded(() async {
    try {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: theme,
            debugShowCheckedModeBanner: false,
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            // CRÍTICO (mismo motivo que coach_hub_nutricion_evidence_test.dart):
            // sin locale explícito, el entorno de test resuelve a 'en' y los
            // labels de Biblioteca quedarían vacíos (l10n congelado en español).
            locale: const Locale('es', 'AR'),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (!completer.isCompleted) completer.complete();
    } catch (error, stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    }
  }, (error, stack) {
    final message = error.toString();
    final isGoogleFontsNetworkError = message.contains('google_fonts') ||
        message.contains('Failed to load font') ||
        message.contains('allowRuntimeFetching');
    if (isGoogleFontsNetworkError) return; // ruido de red conocido — se ignora.
    if (!completer.isCompleted) completer.completeError(error, stack);
  });
  await completer.future;

  // Guard de regresión, ramificado por viewport: `CoachHubScaffold` reemplaza
  // TODO el shell por `MobileBanner` bajo `kMobileBreakpoint` (768px,
  // ADR-CHW-004 — Coach Hub es desktop-only), así que a 420px NUNCA se monta
  // la sección real — capturar ese golden es intencional (documenta el
  // placeholder "usá la app"), no un bug del harness. Sin esta rama, el guard
  // fallaría siempre a 420px con un falso positivo de "l10n ausente".
  if (physicalSize.width < kMobileBreakpoint) {
    expect(
      find.textContaining('Coach Hub en escritorio').evaluate().isNotEmpty,
      isTrue,
      reason: 'MobileBanner ausente a <768px — el guard esperaba el '
          'placeholder desktop-only (ADR-CHW-004) y no lo encontró.',
    );
    return;
  }

  // Guard: la screen real (`BibliotecaWebScreen`) exige dos señales de que
  // montó con data real, no un error/empty silencioso.
  final hasTitle = find.text('BIBLIOTECA').evaluate().isNotEmpty;
  expect(
    hasTitle,
    isTrue,
    reason: 'El título "BIBLIOTECA" no apareció — la ruta /biblioteca no '
        'montó la screen real (regresión o l10n español ausente).',
  );

  final hasExercise =
      find.textContaining('Press de Banca').evaluate().isNotEmpty;
  expect(
    hasExercise,
    isTrue,
    reason: 'El ejercicio fake "Press de Banca" no apareció — el catálogo '
        '(exercisesProvider) no se renderizó como cards reales en el tab '
        'Ejercicios.',
  );
}

// Cuerpo de sección stub para las rutas del sidebar que no son /biblioteca.
class _FakeSectionBody extends StatelessWidget {
  const _FakeSectionBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ColoredBox(color: palette.bg);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Comparador de goldens que escribe en docs/web-trainer/evidence/fase-7/<dir>/
// ──────────────────────────────────────────────────────────────────────────────
class _EvidenceComparator extends LocalFileComparator {
  _EvidenceComparator(String testFile) : super(Uri.file(testFile));

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    const basePath = 'docs/web-trainer/evidence/fase-7/$_evidenceDir';
    final dir = Directory(basePath);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final file = File('$basePath/${golden.pathSegments.last}');
    if (autoUpdateGoldenFiles || !file.existsSync()) {
      file.writeAsBytesSync(imageBytes);
      return true;
    }
    return super.compare(imageBytes, golden);
  }

  @override
  Uri getTestUri(Uri key, int? version) {
    return Uri.file('docs/web-trainer/evidence/fase-7/$_evidenceDir/'
        '${key.pathSegments.last}');
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Suite de evidencia
// ──────────────────────────────────────────────────────────────────────────────
void main() {
  if (!_evidenceEnabled) {
    // El bloque completo se salta → no hay test que falle ni ralentice CI.
    test(
        'evidence suite skipped (pasa --dart-define=EVIDENCE=true para activar)',
        () {},
        skip: true);
    return;
  }

  setUpAll(() async {
    await _loadTestFonts();
    goldenFileComparator = _EvidenceComparator(Platform.script.toFilePath());
  });

  group('Coach Hub Biblioteca — evidencia visual fase-7/$_evidenceDir', () {
    for (final dark in [true, false]) {
      final palette =
          dark ? AppPalette.mintMagenta : AppPalette.mintMagentaLight;
      final modeLabel = dark ? 'dark' : 'light';

      for (final size in [const Size(1440, 900), const Size(420, 900)]) {
        final sizeLabel = '${size.width.toInt()}x${size.height.toInt()}';

        testWidgets(
          'biblioteca $modeLabel $sizeLabel',
          (tester) async {
            await _pumpBiblioteca(
              tester,
              theme: _evidenceTheme(palette: palette, dark: dark),
              physicalSize: size,
            );
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('biblioteca_${modeLabel}_$sizeLabel.png'),
            );
          },
        );
      }
    }
  });
}
