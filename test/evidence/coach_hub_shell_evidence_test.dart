// Harness de evidencia visual del shell del Coach Hub web (EVIDENCE-HARNESS).
//
// Captura 4 screenshots (goldens) del shell real (scaffold + sidebar + topbar)
// con un cuerpo de sección liviano y proveedores falsos. Estos PNGs sirven como
// línea base BEFORE/AFTER para validar regresiones visuales entre fases.
//
// IMPORTANTE: este archivo se salta por completo a menos que se pase
// --dart-define=EVIDENCE=true al test runner. Así, `flutter test` normal nunca
// lo ejecuta ni descarga nada.
//
// Regenerar capturas:
//   flutter test --update-goldens \
//     --dart-define=EVIDENCE=true \
//     --dart-define=EVIDENCE_DIR=before \
//     test/evidence/
//
// Los PNGs se guardan en:
//   docs/web-trainer/evidence/fase-1/<EVIDENCE_DIR>/
//
// Matriz: dark 1440x900, dark 420x900, light 1440x900, light 420x900.

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
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_registry.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Guardián: si EVIDENCE != true, el archivo entero se salta.
// ──────────────────────────────────────────────────────────────────────────────
const bool _evidenceEnabled =
    bool.fromEnvironment('EVIDENCE', defaultValue: false);

const String _evidenceDir =
    String.fromEnvironment('EVIDENCE_DIR', defaultValue: 'before');

// ──────────────────────────────────────────────────────────────────────────────
// Fakes / stubs (igual patrón que coach_hub_router_shell_test.dart)
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

UserProfile _trainerProfile() => UserProfile(
      uid: 'evidence-uid',
      email: 'trainer@treino.app',
      displayName: 'Mateo García',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

// ──────────────────────────────────────────────────────────────────────────────
// Carga de fuentes TTF reales desde test/fonts/
// Registramos los bytes bajo las familias "Barlow" y "BarlowCondensed" para que
// Flutter las encuentre cuando el tema las declare via fontFamily/fontFamilyFallback.
// ──────────────────────────────────────────────────────────────────────────────
Future<void> _loadTestFonts() async {
  await _loadFontFamily('Barlow', [
    'test/fonts/Barlow-Regular.ttf',
    'test/fonts/Barlow-Medium.ttf',
    'test/fonts/Barlow-SemiBold.ttf',
    'test/fonts/Barlow-Bold.ttf',
  ]);

  await _loadFontFamily('BarlowCondensed', [
    'test/fonts/BarlowCondensed-Regular.ttf',
    'test/fonts/BarlowCondensed-Bold.ttf',
  ]);
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
// Tema de evidencia: construye el theme directamente con fontFamily 'Barlow'
// (registrada via FontLoader) en lugar de pasar por google_fonts, que intentaría
// cargar fonts de la red (bloqueada en entorno de test). El resultado visual es
// idéntico: mismos colores, pesos y radios que AppTheme.dark()/light().
// ──────────────────────────────────────────────────────────────────────────────
ThemeData _evidenceTheme({required AppPalette palette, required bool dark}) {
  final base = dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);

  // TextTheme con Barlow (cargada desde TTF local) en lugar de GoogleFonts.barlow.
  final textTheme = base.textTheme.apply(
    fontFamily: 'Barlow',
    bodyColor: palette.textPrimary,
    displayColor: palette.textPrimary,
  );

  // Headings con BarlowCondensed Bold (igual que AppTheme).
  const condensedStyle = TextStyle(
    fontFamily: 'BarlowCondensed',
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
// Helper: monta el shell real con GoRouter + proveedores falsos.
// El sidebar necesita GoRouterState.of(context), por eso usamos ShellRoute.
// ──────────────────────────────────────────────────────────────────────────────
Future<void> _pumpShell(
  WidgetTester tester, {
  required ThemeData theme,
  required Size physicalSize,
}) async {
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
    trainerLinksStreamProvider
        .overrideWith((ref) => Stream.value(const <TrainerLink>[])),
  ]);
  addTearDown(container.dispose);

  // Warm providers que el shell lee en build.
  await tester.runAsync(() async {
    await container.read(authNotifierProvider.future).catchError((_) => null);
    await container.read(userProfileProvider.future).catchError((_) => null);
    await container.read(sharedPreferencesProvider.future);
  });

  // GoRouter mínimo: ShellRoute con CoachHubScaffold + rutas del registry.
  final paths = sidebarRegistry.map((i) => i.route).toSet().toList();
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        builder: (ctx, state, child) => CoachHubScaffold(child: child),
        routes: [
          for (final p in paths)
            GoRoute(
              path: p,
              builder: (_, __) => const _FakeSectionBody(),
            ),
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
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Cuerpo de sección liviano para la evidencia.
class _FakeSectionBody extends StatelessWidget {
  const _FakeSectionBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ColoredBox(
      color: palette.bg,
      child: Center(
        child: Text(
          'Dashboard',
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 18,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Comparador de goldens que escribe en docs/web-trainer/evidence/fase-1/<dir>/
// ──────────────────────────────────────────────────────────────────────────────
class _EvidenceComparator extends LocalFileComparator {
  _EvidenceComparator(String testFile) : super(Uri.file(testFile));

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    const basePath = 'docs/web-trainer/evidence/fase-1/$_evidenceDir';
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
    return Uri.file('docs/web-trainer/evidence/fase-1/$_evidenceDir/'
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

  group('Coach Hub Shell — evidencia visual fase-1/$_evidenceDir', () {
    testWidgets(
      'dark 1440x900',
      (tester) async {
        await _pumpShell(
          tester,
          theme: _evidenceTheme(palette: AppPalette.mintMagenta, dark: true),
          physicalSize: const Size(1440, 900),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('shell_dark_1440x900.png'),
        );
      },
    );

    testWidgets(
      'dark 420x900',
      (tester) async {
        await _pumpShell(
          tester,
          theme: _evidenceTheme(palette: AppPalette.mintMagenta, dark: true),
          physicalSize: const Size(420, 900),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('shell_dark_420x900.png'),
        );
      },
    );

    testWidgets(
      'light 1440x900',
      (tester) async {
        await _pumpShell(
          tester,
          theme:
              _evidenceTheme(palette: AppPalette.mintMagentaLight, dark: false),
          physicalSize: const Size(1440, 900),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('shell_light_1440x900.png'),
        );
      },
    );

    testWidgets(
      'light 420x900',
      (tester) async {
        await _pumpShell(
          tester,
          theme:
              _evidenceTheme(palette: AppPalette.mintMagentaLight, dark: false),
          physicalSize: const Size(420, 900),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('shell_light_420x900.png'),
        );
      },
    );
  });
}
