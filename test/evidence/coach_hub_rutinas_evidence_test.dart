// Harness de evidencia visual de la sección "Rutinas" del Coach Hub web
// (EVIDENCE-HARNESS).
//
// Captura 8 screenshots (goldens) del selector de alumno (RutinasScreen,
// `/rutinas`) y de las rutinas asignadas a un alumno (AthleteRoutinesScreen,
// `/rutinas/:athleteId`) montados DENTRO del shell real (CoachHubScaffold)
// con proveedores falsos POBLADOS (vínculos, perfiles, rutinas asignadas)
// para que el screenshot muestre data real, no vacío/error. Estos PNGs
// sirven como línea base BEFORE/AFTER para validar regresiones visuales de
// la Fase 5.
//
// Mismo patrón que test/evidence/coach_hub_alumnos_evidence_test.dart — ver
// ese archivo para el detalle de por qué se cargan las fuentes así.
//
// IMPORTANTE: este archivo se salta por completo a menos que se pase
// --dart-define=EVIDENCE=true al test runner. Así, `flutter test` normal
// nunca lo ejecuta ni descarga nada.
//
// Regenerar capturas:
//   flutter test --update-goldens \
//     --dart-define=EVIDENCE=true \
//     --dart-define=EVIDENCE_DIR=before \
//     test/evidence/coach_hub_rutinas_evidence_test.dart
//
// Los PNGs se guardan en:
//   docs/web-trainer/evidence/fase-5/<EVIDENCE_DIR>/
//
// Matriz: (selector, rutinas-del-alumno) × (dark, light) ×
// (1440x900, 420x900) = 8 goldens.
//
// NOTA (ADR-F5-06, ver openspec/changes/redesign-coach-hub-web/plan-fase5.md):
// este harness NO monta las rutas del editor (`/routine-editor/...`) — el
// screenshot es estático, no requiere navegación al editor, por lo tanto
// cero acoplamiento con la zona PROHIBIDA
// (`routine_editor/routine_editor_web_screen.dart`,
// `routine_editor/routine_web_editability.dart`, con cambios sin commitear
// del usuario). El único acoplamiento pre-existente es el import transitivo
// de `isRoutineWebEditable` dentro de `AthleteRoutinesScreen` (ya existía
// antes de este WU, se trata como caja negra).

import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// ignore: implementation_imports
// Necesario para desactivar el fetch de red de `GoogleFonts.barlow(...)` /
// `GoogleFonts.barlowCondensed(...)` (llamados directamente por
// `rutinas_screen.dart` / `athlete_routines_screen.dart`, a diferencia del
// resto del kit que usa la fuente del theme). Sin esto, `loadFontIfNecessary`
// intenta un fetch HTTP real (bloqueado en este entorno), el `Future`
// fire-and-forget queda sin manejar y el test crashea con
// "A test overrode FlutterError.onError but..." — ver `_pumpRutinas` donde
// se puebla `gfb.assetManifest` con los TTF reales de `test/fonts/` para que
// la resolución de fuente tome el camino de asset (sin red, sin excepción).
import 'package:google_fonts/src/google_fonts_base.dart' as gfb;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/chat/application/chat_providers.dart'
    show totalUnreadCountProvider;
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/rutinas/routes.dart'
    show rutinasRoutes;
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
import 'package:treino/features/coach_hub/presentation/shell/responsive.dart'
    show kMobileBreakpoint;
import 'package:treino/features/coach_hub/presentation/shell/sidebar_registry.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/l10n/app_l10n.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Guardián: si EVIDENCE != true, el archivo entero se salta.
// ──────────────────────────────────────────────────────────────────────────────
const bool _evidenceEnabled =
    bool.fromEnvironment('EVIDENCE', defaultValue: false);

const String _evidenceDir =
    String.fromEnvironment('EVIDENCE_DIR', defaultValue: 'before');

// ──────────────────────────────────────────────────────────────────────────────
// Fakes / stubs (mismo patrón que coach_hub_alumnos_evidence_test.dart)
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
// Factories — datos fake poblados para que el selector y el detalle muestren
// data real.
// ──────────────────────────────────────────────────────────────────────────────
const _trainerUid = 'evidence-trainer';

/// Alumno cuyas rutinas se capturan (`/rutinas/$_detailAthleteId`). Es el
/// único con rutinas asignadas pobladas — el resto del selector sólo
/// necesita perfil + link para la fila.
const _detailAthleteId = 'a1';

final _athleteNames = <String, String>{
  'a1': 'Ana López',
  'a2': 'Bruno García',
  'a3': 'Carla Rodríguez', // pending → excluida del selector
  'a4': 'Diego Martínez',
};

UserProfile _trainerProfile() => UserProfile(
      uid: _trainerUid,
      email: 'trainer@treino.app',
      displayName: 'Mateo García',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
      workoutsCount: 30,
      racha: 4,
    );

TrainerLink _link({
  required String id,
  required String athleteId,
  required TrainerLinkStatus status,
}) =>
    TrainerLink(
      id: id,
      trainerId: _trainerUid,
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 5, 1),
      acceptedAt:
          status == TrainerLinkStatus.pending ? null : DateTime.utc(2026, 5, 2),
    );

RoutineDay _day(int n, String name) =>
    RoutineDay(dayNumber: n, name: name, slots: const []);

Routine _routine({
  required String id,
  required String name,
  required List<RoutineDay> days,
  required RoutineStatus status,
  int numWeeks = 1,
}) =>
    Routine(
      id: id,
      name: name,
      split: name,
      level: ExperienceLevel.intermediate,
      days: days,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerUid,
      assignedTo: _detailAthleteId,
      visibility: RoutineVisibility.private,
      status: status,
      numWeeks: numWeeks,
    );

/// Rutinas asignadas al alumno de detalle: 3 activas web-editables
/// (`numWeeks == 1`), 1 periodizada (`numWeeks == 4`, view-only en web) y 1
/// archivada (oculta hoy — `AthleteRoutinesScreen` sólo muestra `active`;
/// queda poblada para futuros filtros honestos, ADR-F5-05).
List<Routine> _assignedRoutinesFor(String athleteId) {
  if (athleteId != _detailAthleteId) return const [];
  return [
    _routine(
      id: 'r1',
      name: 'Full Body Fuerza',
      days: [
        _day(1, 'Full Body A'),
        _day(2, 'Full Body B'),
        _day(3, 'Full Body C')
      ],
      status: RoutineStatus.active,
    ),
    _routine(
      id: 'r2',
      name: 'PPL Hipertrofia',
      days: [
        _day(1, 'Push'),
        _day(2, 'Pull'),
        _day(3, 'Legs'),
        _day(4, 'Push'),
        _day(5, 'Pull'),
      ],
      status: RoutineStatus.active,
    ),
    _routine(
      id: 'r3',
      name: 'Upper Lower',
      days: [
        _day(1, 'Upper'),
        _day(2, 'Lower'),
        _day(3, 'Upper'),
        _day(4, 'Lower'),
      ],
      status: RoutineStatus.active,
    ),
    _routine(
      id: 'r4',
      name: 'Periodización Bloques',
      days: [_day(1, 'Semana 1'), _day(2, 'Semana 2')],
      status: RoutineStatus.active,
      numWeeks: 4,
    ),
    _routine(
      id: 'r5',
      name: 'Full Body Básico',
      days: [_day(1, 'Full Body')],
      status: RoutineStatus.archived,
    ),
  ];
}

// ──────────────────────────────────────────────────────────────────────────────
// Carga de fuentes TTF reales desde test/fonts/ (idéntico a
// coach_hub_alumnos_evidence_test.dart — ver ese archivo para el
// razonamiento completo de por qué se resuelve así).
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

// ──────────────────────────────────────────────────────────────────────────────
// `AssetManifest` fake que le hace creer a `package:google_fonts` que
// Barlow/BarlowCondensed ya están bundleadas como asset — así resuelve por
// `rootBundle.load(...)` (sin red, sin validación de hash) en vez de intentar
// el fetch HTTP real. Las claves son justamente los TTF reales en
// `test/fonts/` (mismos que carga `_loadTestFonts`), y el mock del canal
// `flutter/assets` en `_installFakeGoogleFontsAssets` les devuelve los bytes.
// ──────────────────────────────────────────────────────────────────────────────
const _fakeGoogleFontsAssetPaths = [
  'test/fonts/Barlow-Regular.ttf',
  'test/fonts/Barlow-Medium.ttf',
  'test/fonts/Barlow-SemiBold.ttf',
  'test/fonts/Barlow-Bold.ttf',
  'test/fonts/BarlowCondensed-Regular.ttf',
  'test/fonts/BarlowCondensed-Bold.ttf',
];

class _FakeGoogleFontsAssetManifest implements AssetManifest {
  @override
  List<String> listAssets() => _fakeGoogleFontsAssetPaths;

  @override
  List<AssetMetadata>? getAssetVariants(String key) => null;
}

/// Instala el `AssetManifest` fake + un handler del canal `flutter/assets`
/// que devuelve los TTF reales para esas claves. Ver comentario del import de
/// `google_fonts_base.dart` para el porqué.
void _installFakeGoogleFontsAssets() {
  gfb.assetManifest = _FakeGoogleFontsAssetManifest();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (ByteData? message) async {
    if (message == null) return null;
    final key = utf8.decode(message.buffer.asUint8List());
    return _readTtf(key);
  });
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
// Tema de evidencia — idéntico a coach_hub_alumnos_evidence_test.dart.
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
// entorno de test. Ver coach_hub_alumnos_evidence_test.dart para el
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
  // coach_hub_alumnos_evidence_test.dart — mismo razonamiento).
  addTearDown(() => FlutterError.onError = previousOnError);
}

// ──────────────────────────────────────────────────────────────────────────────
// Helper: monta el shell real (CoachHubScaffold) con el selector o el
// detalle REAL en [initialLocation], GoRouter + proveedores falsos
// POBLADOS.
// ──────────────────────────────────────────────────────────────────────────────
Future<void> _pumpRutinas(
  WidgetTester tester, {
  required ThemeData theme,
  required Size physicalSize,
  required String initialLocation,
}) async {
  _ignoreKnownGoogleFontsAsyncErrors();
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();

  final mockUser = _MockUser();

  // ── Datos fake poblados ──────────────────────────────────────────────────
  // 4 vínculos: active + paused + pending (excluida del selector) +
  // terminated.
  final links = [
    _link(id: 'l1', athleteId: 'a1', status: TrainerLinkStatus.active),
    _link(id: 'l2', athleteId: 'a2', status: TrainerLinkStatus.paused),
    _link(id: 'l3', athleteId: 'a3', status: TrainerLinkStatus.pending),
    _link(id: 'l4', athleteId: 'a4', status: TrainerLinkStatus.terminated),
  ];

  final profiles = {
    for (final entry in _athleteNames.entries)
      entry.key: _pub(entry.key, entry.value),
  };

  final container = ProviderContainer(overrides: [
    authNotifierProvider.overrideWith(
      () => _StubAuthNotifier(AsyncData(mockUser)),
    ),
    userProfileProvider.overrideWith(
      (ref) => Stream<UserProfile?>.value(_trainerProfile()),
    ),
    sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
    currentUidProvider.overrideWithValue(_trainerUid),
    trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
    for (final entry in profiles.entries)
      userPublicProfileProvider(entry.key).overrideWith(
        (ref) => Stream.value(entry.value),
      ),
    assignedRoutinesProvider.overrideWith(
      (ref, uid) async => _assignedRoutinesFor(uid),
    ),
    totalUnreadCountProvider.overrideWith((ref) => 3),
  ]);
  addTearDown(container.dispose);

  // Warm providers que el shell lee en build.
  await tester.runAsync(() async {
    await container.read(authNotifierProvider.future).catchError((_) => null);
    await container.read(userProfileProvider.future).catchError((_) => null);
    await container.read(sharedPreferencesProvider.future);
  });

  // GoRouter: ShellRoute con CoachHubScaffold + rutas reales de Rutinas
  // (`/rutinas`, `/rutinas/:athleteId`) + el resto de rutas del sidebar
  // como stub liviano, necesarias para que el sidebar resuelva
  // GoRouterState.of(context) (mismo patrón que
  // coach_hub_alumnos_evidence_test.dart). Las rutas del editor
  // (`/routine-editor/...`) NO se registran acá — el screenshot es
  // estático, no requiere navegar al editor (ADR-F5-06).
  final otherPaths =
      sidebarRegistry.map((i) => i.route).toSet().where((p) => p != '/rutinas');
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (ctx, state, child) => CoachHubScaffold(child: child),
        routes: [
          ...rutinasRoutes,
          for (final p in otherPaths)
            GoRoute(path: p, builder: (_, __) => const _FakeSectionBody()),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: theme,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        // CRÍTICO (mismo motivo que coach_hub_alumnos_evidence_test.dart):
        // sin locale explícito, el entorno de test resuelve a 'en' y los
        // labels de Rutinas quedarían vacíos (l10n congelado en español).
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Guard de regresión, ramificado por viewport: `CoachHubScaffold`
  // reemplaza TODO el shell por `MobileBanner` bajo `kMobileBreakpoint`
  // (768px, ADR-CHW-004 — Coach Hub es desktop-only), así que a 420px NUNCA
  // se monta el selector/detalle real — capturar ese golden es intencional
  // (documenta el placeholder "usá la app"), no un bug del harness. Sin
  // esta rama, el guard fallaría siempre a 420px con un falso positivo de
  // "l10n ausente".
  if (physicalSize.width < kMobileBreakpoint) {
    expect(
      find.textContaining('Coach Hub en escritorio').evaluate().isNotEmpty,
      isTrue,
      reason: 'MobileBanner ausente a <768px — el guard esperaba el '
          'placeholder desktop-only (ADR-CHW-004) y no lo encontró.',
    );
    return;
  }

  // Si el locale no resuelve a español, el título del selector ("RUTINAS")
  // queda vacío y el golden captura la pantalla en blanco sin que ningún
  // test lo detecte (matchesGoldenFile solo compara píxeles contra el
  // propio "before", igualmente roto). Falla temprano acá con un mensaje
  // claro en vez de un mismatch de imagen silencioso. Cubre las dos rutas:
  // el selector muestra "RUTINAS" (TreinoSectionHeader); el detalle todavía
  // no lo usa (header manual "Rutinas de $name") así que se valida por el
  // nombre del alumno.
  expect(
    find.textContaining('RUTINAS').evaluate().isNotEmpty ||
        find
            .textContaining(_athleteNames[_detailAthleteId]!)
            .evaluate()
            .isNotEmpty,
    isTrue,
    reason: 'l10n español ausente o data fake no renderizada — el locale del '
        'harness no está resolviendo a es_AR o los overrides no matchearon '
        'la pantalla montada',
  );
}

// Cuerpo de sección stub para las rutas del sidebar que no son /rutinas.
class _FakeSectionBody extends StatelessWidget {
  const _FakeSectionBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ColoredBox(color: palette.bg);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Comparador de goldens que escribe en docs/web-trainer/evidence/fase-5/<dir>/
// ──────────────────────────────────────────────────────────────────────────────
class _EvidenceComparator extends LocalFileComparator {
  _EvidenceComparator(String testFile) : super(Uri.file(testFile));

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    const basePath = 'docs/web-trainer/evidence/fase-5/$_evidenceDir';
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
    return Uri.file('docs/web-trainer/evidence/fase-5/$_evidenceDir/'
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
    _installFakeGoogleFontsAssets();
    goldenFileComparator = _EvidenceComparator(Platform.script.toFilePath());
  });

  group('Coach Hub Rutinas — evidencia visual fase-5/$_evidenceDir', () {
    for (final dark in [true, false]) {
      final palette =
          dark ? AppPalette.mintMagenta : AppPalette.mintMagentaLight;
      final modeLabel = dark ? 'dark' : 'light';

      for (final size in [const Size(1440, 900), const Size(420, 900)]) {
        final sizeLabel = '${size.width.toInt()}x${size.height.toInt()}';

        testWidgets(
          'selector $modeLabel $sizeLabel',
          (tester) async {
            await _pumpRutinas(
              tester,
              theme: _evidenceTheme(palette: palette, dark: dark),
              physicalSize: size,
              initialLocation: '/rutinas',
            );
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('rutinas_selector_${modeLabel}_$sizeLabel.png'),
            );
          },
        );

        testWidgets(
          'rutinas del alumno $modeLabel $sizeLabel',
          (tester) async {
            await _pumpRutinas(
              tester,
              theme: _evidenceTheme(palette: palette, dark: dark),
              physicalSize: size,
              initialLocation: '/rutinas/$_detailAthleteId',
            );
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('rutinas_alumno_${modeLabel}_$sizeLabel.png'),
            );
          },
        );
      }
    }
  });
}
