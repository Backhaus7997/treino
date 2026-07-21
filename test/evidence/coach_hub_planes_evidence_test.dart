// Harness de evidencia visual de la sección "Planes comerciales" del Coach
// Hub web (EVIDENCE-HARNESS).
//
// Captura 4 screenshots (goldens) de la pantalla de planes (`/planes`)
// montada DENTRO del shell real (CoachHubScaffold). Hoy la ruta renderiza
// el placeholder [ProximamenteScreen] (Fase W1) — estos PNGs documentan el
// estado BEFORE de la Fase 10 (rediseño de la sección real).
//
// Mismo patrón que test/evidence/coach_hub_pagos_evidence_test.dart — ver
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
//     test/evidence/coach_hub_planes_evidence_test.dart
//
// Los PNGs se guardan en:
//   docs/web-trainer/evidence/fase-10/<EVIDENCE_DIR>/
//
// Matriz: (dark, light) × (1440x900, 420x900) = 4 goldens.

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
import 'package:treino/features/coach_hub/presentation/sections/planes/routes.dart'
    show planesRoutes;
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
import 'package:treino/features/coach_hub/presentation/shell/responsive.dart'
    show kMobileBreakpoint;
import 'package:treino/features/coach_hub/presentation/shell/sidebar_registry.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Guardián: si EVIDENCE != true, el archivo entero se salta.
// ──────────────────────────────────────────────────────────────────────────────
const bool _evidenceEnabled =
    bool.fromEnvironment('EVIDENCE', defaultValue: false);

const String _evidenceDir =
    String.fromEnvironment('EVIDENCE_DIR', defaultValue: 'before');

// ──────────────────────────────────────────────────────────────────────────────
// Fakes / stubs (mismo patrón que coach_hub_pagos_evidence_test.dart)
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

const _trainerUid = 'evidence-trainer';

UserProfile _trainerProfile() => UserProfile(
      uid: _trainerUid,
      email: 'trainer@treino.app',
      displayName: 'Mateo García',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      paymentAlias: 'trainer.mp',
    );

// ──────────────────────────────────────────────────────────────────────────────
// Carga de fuentes TTF reales desde test/fonts/ (idéntico a
// coach_hub_pagos_evidence_test.dart — ver ese archivo para el razonamiento
// completo de por qué se resuelve así).
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
// Tema de evidencia — idéntico a coach_hub_pagos_evidence_test.dart.
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
// entorno de test. Ver coach_hub_pagos_evidence_test.dart para el
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
  // coach_hub_pagos_evidence_test.dart — mismo razonamiento).
  addTearDown(() => FlutterError.onError = previousOnError);
}

// ──────────────────────────────────────────────────────────────────────────────
// Helper: monta el shell real (CoachHubScaffold) con la pantalla de planes
// (hoy placeholder [ProximamenteScreen]) en `/planes`, GoRouter + proveedores
// falsos.
// ──────────────────────────────────────────────────────────────────────────────
Future<void> _pumpPlanes(
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
  ]);
  addTearDown(container.dispose);

  // Warm providers que el shell lee en build.
  await tester.runAsync(() async {
    await container.read(authNotifierProvider.future).catchError((_) => null);
    await container.read(userProfileProvider.future).catchError((_) => null);
    await container.read(sharedPreferencesProvider.future);
  });

  // GoRouter: ShellRoute con CoachHubScaffold + rutas reales de Planes
  // (`/planes`) + el resto de rutas del sidebar como stub liviano, necesarias
  // para que el sidebar resuelva GoRouterState.of(context) (mismo patrón que
  // coach_hub_pagos_evidence_test.dart). `/planes` se excluye del loop porque
  // ya la aporta `planesRoutes`.
  final otherPaths =
      sidebarRegistry.map((i) => i.route).toSet().where((p) => p != '/planes');
  final router = GoRouter(
    initialLocation: '/planes',
    routes: [
      ShellRoute(
        builder: (ctx, state, child) => CoachHubScaffold(child: child),
        routes: [
          ...planesRoutes,
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
        // CRÍTICO (mismo motivo que coach_hub_pagos_evidence_test.dart): sin
        // locale explícito, el entorno de test resuelve a 'en' y los labels
        // quedarían vacíos (l10n congelado en español).
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Guard de regresión, ramificado por viewport: `CoachHubScaffold` reemplaza
  // TODO el shell por `MobileBanner` bajo `kMobileBreakpoint` (768px,
  // ADR-CHW-004 — Coach Hub es desktop-only), así que a 420px NUNCA se monta
  // la pantalla real — capturar ese golden es intencional (documenta el
  // placeholder "usá la app"), no un bug del harness. Sin esta rama, el guard
  // fallaría siempre a 420px con un falso positivo.
  if (physicalSize.width < kMobileBreakpoint) {
    expect(
      find.textContaining('Coach Hub en escritorio').evaluate().isNotEmpty,
      isTrue,
      reason: 'MobileBanner ausente a <768px — el guard esperaba el '
          'placeholder desktop-only (ADR-CHW-004) y no lo encontró.',
    );
    return;
  }

  // Guard endurecido: confirma que la pantalla de Planes (hoy el placeholder
  // ProximamenteScreen, Fase W1) está montada.
  expect(
    find.text('PLANES COMERCIALES').evaluate().isNotEmpty ||
        find.textContaining('Planes comerciales').evaluate().isNotEmpty,
    isTrue,
    reason: 'Título "Planes comerciales" ausente — la ruta /planes no se '
        'montó (regresión o l10n español ausente).',
  );
  expect(
    find.textContaining('Próximamente').evaluate().isNotEmpty,
    isTrue,
    reason: 'Placeholder "Próximamente" ausente — esta evidencia BEFORE '
        'documenta el estado placeholder de la sección (Fase W1); si este '
        'guard falla, la sección real ya está cableada y hay que actualizar '
        'el harness para reflejarlo.',
  );
}

// Cuerpo de sección stub para las rutas del sidebar que no son /planes.
class _FakeSectionBody extends StatelessWidget {
  const _FakeSectionBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ColoredBox(color: palette.bg);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Comparador de goldens que escribe en docs/web-trainer/evidence/fase-10/<dir>/
// ──────────────────────────────────────────────────────────────────────────────
class _EvidenceComparator extends LocalFileComparator {
  _EvidenceComparator(String testFile) : super(Uri.file(testFile));

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    const basePath = 'docs/web-trainer/evidence/fase-10/$_evidenceDir';
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
    return Uri.file('docs/web-trainer/evidence/fase-10/$_evidenceDir/'
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

  group('Coach Hub Planes — evidencia visual fase-10/$_evidenceDir', () {
    for (final dark in [true, false]) {
      final palette =
          dark ? AppPalette.mintMagenta : AppPalette.mintMagentaLight;
      final modeLabel = dark ? 'dark' : 'light';

      for (final size in [const Size(1440, 900), const Size(420, 900)]) {
        final sizeLabel = '${size.width.toInt()}x${size.height.toInt()}';

        testWidgets(
          'planes $modeLabel $sizeLabel',
          (tester) async {
            await _pumpPlanes(
              tester,
              theme: _evidenceTheme(palette: palette, dark: dark),
              physicalSize: size,
            );
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('planes_${modeLabel}_$sizeLabel.png'),
            );
          },
        );
      }
    }
  });
}
