// Harness de evidencia visual del Dashboard ("Hoy") del Coach Hub web
// (EVIDENCE-HARNESS).
//
// Captura 4 screenshots (goldens) del dashboard REAL
// (CoachHubDashboardScreen) montado dentro del shell (CoachHubScaffold) en
// la ruta /dashboard, con proveedores falsos POBLADOS (KPIs, pendientes,
// próximas sesiones, vencimientos, inactivos) para que el screenshot
// muestre data real, no vacío. Estos PNGs sirven como línea base
// BEFORE/AFTER para validar regresiones visuales entre fases.
//
// Mismo patrón que test/evidence/coach_hub_shell_evidence_test.dart —
// ver ese archivo para el detalle de por qué se cargan las fuentes así.
//
// IMPORTANTE: este archivo se salta por completo a menos que se pase
// --dart-define=EVIDENCE=true al test runner. Así, `flutter test` normal
// nunca lo ejecuta ni descarga nada.
//
// Regenerar capturas:
//   flutter test --update-goldens \
//     --dart-define=EVIDENCE=true \
//     --dart-define=EVIDENCE_DIR=before \
//     test/evidence/coach_hub_dashboard_evidence_test.dart
//
// Los PNGs se guardan en:
//   docs/web-trainer/evidence/fase-2/<EVIDENCE_DIR>/
//
// Matriz: dark 1440x900, dark 420x900, light 1440x900, light 420x900.

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
import 'package:treino/features/chat/application/chat_providers.dart'
    show totalUnreadCountProvider;
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/application/aggregate_adherence_provider.dart';
import 'package:treino/features/coach_hub/application/inactivos_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_registry.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
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
// Fakes / stubs (mismo patrón que coach_hub_shell_evidence_test.dart)
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
// Factories — datos fake poblados para que el dashboard muestre data real.
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

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
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
      requestedAt: DateTime.utc(2026, 1, 1),
    );

Appointment _confirmedAppointment({
  required String id,
  required String athleteDisplayName,
  required DateTime startsAt,
}) =>
    Appointment(
      id: id,
      trainerId: _trainerUid,
      athleteId: 'evidence-athlete-$id',
      athleteDisplayName: athleteDisplayName,
      startsAt: startsAt,
      durationMin: 60,
      status: AppointmentStatus.confirmed,
    );

Payment _paidPayment({
  required String id,
  required int amountArs,
  required String athleteId,
  required DateTime paidAt,
}) =>
    Payment(
      id: id,
      trainerId: _trainerUid,
      athleteId: athleteId,
      amountArs: amountArs,
      concept: 'Mensualidad',
      status: PaymentStatus.paid,
      createdAt: paidAt,
      paidAt: paidAt,
    );

Payment _vencidoPayment({
  required String id,
  required int amountArs,
  required String athleteId,
  required DateTime createdAt,
}) =>
    Payment(
      id: id,
      trainerId: _trainerUid,
      athleteId: athleteId,
      amountArs: amountArs,
      concept: 'Mensualidad',
      status: PaymentStatus.pending,
      createdAt: createdAt,
    );

// ──────────────────────────────────────────────────────────────────────────────
// Carga de fuentes TTF reales desde test/fonts/ (idéntico a
// coach_hub_shell_evidence_test.dart — ver ese archivo para el razonamiento
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
// Tema de evidencia — idéntico a coach_hub_shell_evidence_test.dart.
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
// (llamado inline en varios puntos del dashboard REAL — violación que la
// Fase 2 corrige, no responsabilidad de este harness) cuando intenta
// resolver la fuente por red y la red está bloqueada en el entorno de test.
// Sin esto, `matchesGoldenFile` (que fuerza turnos async reales para
// codificar el PNG) le da tiempo al fetch fallido a propagarse como
// excepción no capturada y hace fallar el test — el PNG capturado en sí no
// se ve afectado (el texto cae al fallback del sistema para esos elementos
// puntuales, igual que en cualquier entorno sin red).
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
  // CRÍTICO: restaurar el handler original al cerrar el test. Sin esto, el
  // framework de test (`TestWidgetsFlutterBinding._runTest.handleUncaughtError`)
  // invoca `FlutterError.onError` para registrar `_pendingExceptionDetails`
  // en errores async no capturados (fuera de este handler); si sigue
  // apuntando a este filtro, el swallow rompe ese bookkeeping interno y el
  // test falla con la aserción "A test overrode FlutterError.onError but
  // either failed to return it to its original state".
  addTearDown(() => FlutterError.onError = previousOnError);
}

// ──────────────────────────────────────────────────────────────────────────────
// Helper: monta el shell real (CoachHubScaffold) con el dashboard REAL en
// /dashboard, GoRouter + proveedores falsos POBLADOS.
// ──────────────────────────────────────────────────────────────────────────────
Future<void> _pumpDashboard(
  WidgetTester tester, {
  required ThemeData theme,
  required Size physicalSize,
}) async {
  _ignoreKnownGoogleFontsAsyncErrors();
  // Constraints finitas — el dashboard usa `constraints.maxHeight.isFinite`
  // como parte del guard de layout de dos columnas (`wide`), igual que
  // agenda_web_screen.dart. Sin un tamaño de viewport real, maxHeight sería
  // infinito y el layout de dos columnas nunca se activaría en 1440x900.
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();

  final mockUser = _MockUser();

  // ── Datos fake poblados ──────────────────────────────────────────────────
  final links = [
    _link(id: 'l1', athleteId: 'a1', status: TrainerLinkStatus.active),
    _link(id: 'l2', athleteId: 'a2', status: TrainerLinkStatus.active),
    _link(id: 'l3', athleteId: 'a3', status: TrainerLinkStatus.active),
    _link(id: 'l4', athleteId: 'a4', status: TrainerLinkStatus.pending),
    _link(id: 'l5', athleteId: 'a5', status: TrainerLinkStatus.pending),
  ];

  final now = DateTime.now().toUtc();
  final monthStart = DateTime.utc(now.year, now.month, 1);

  final buckets = PagosBuckets(
    vencidos: [
      _vencidoPayment(
        id: 'p1',
        amountArs: 20000,
        athleteId: 'a1',
        createdAt: monthStart.subtract(const Duration(days: 40)),
      ),
      _vencidoPayment(
        id: 'p2',
        amountArs: 15000,
        athleteId: 'a2',
        createdAt: monthStart.subtract(const Duration(days: 20)),
      ),
    ],
    porVencer: const [],
    pagados: [
      _paidPayment(
        id: 'p3',
        amountArs: 18000,
        athleteId: 'a3',
        paidAt: monthStart.add(const Duration(days: 2)),
      ),
      _paidPayment(
        id: 'p4',
        amountArs: 22000,
        athleteId: 'a1',
        paidAt: monthStart.add(const Duration(days: 5)),
      ),
    ],
    todos: const [],
  );

  final appointments = [
    _confirmedAppointment(
      id: 's1',
      athleteDisplayName: 'Ana López',
      startsAt: now.add(const Duration(hours: 1)),
    ),
    _confirmedAppointment(
      id: 's2',
      athleteDisplayName: 'Bruno García',
      startsAt: now.add(const Duration(hours: 3)),
    ),
    _confirmedAppointment(
      id: 's3',
      athleteDisplayName: 'Carla Rodríguez',
      startsAt: now.add(const Duration(days: 1, hours: 2)),
    ),
    _confirmedAppointment(
      id: 's4',
      athleteDisplayName: 'Diego Martínez',
      startsAt: now.add(const Duration(days: 2)),
    ),
  ];

  const inactiveIds = ['i1', 'i2', 'i3'];

  final athleteNames = <String, String>{
    'a1': 'Ana López',
    'a2': 'Bruno García',
    'a3': 'Carla Rodríguez',
    'a4': 'Diego Martínez',
    'a5': 'Eva Sánchez',
    'i1': 'Fabio Torres',
    'i2': 'Gina Suárez',
    'i3': 'Hugo Fernández',
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
    pagosBucketsProvider.overrideWith((ref) => AsyncData(buckets)),
    inactivosProvider.overrideWith(
      (ref) async => const InactivosResult(inactiveAthleteIds: inactiveIds),
    ),
    aggregateAdherenceProvider.overrideWith((ref) async => 84.0),
    trainerAppointmentsStreamProvider.overrideWith(
      (ref, key) => Stream.value(appointments),
    ),
    totalUnreadCountProvider.overrideWith((ref) => 5),
    for (final entry in athleteNames.entries)
      userPublicProfileProvider(entry.key).overrideWith(
        (ref) => Stream.value(_pub(entry.key, entry.value)),
      ),
  ]);
  addTearDown(container.dispose);

  // Warm providers que el shell lee en build.
  await tester.runAsync(() async {
    await container.read(authNotifierProvider.future).catchError((_) => null);
    await container.read(userProfileProvider.future).catchError((_) => null);
    await container.read(sharedPreferencesProvider.future);
  });

  // GoRouter mínimo: ShellRoute con CoachHubScaffold + rutas del registry.
  // La ruta /dashboard monta el dashboard REAL; el resto (necesarias para
  // que el sidebar resuelva GoRouterState.of(context)) queda con un stub
  // liviano, igual que coach_hub_shell_evidence_test.dart.
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
              builder: (_, __) => p == '/dashboard'
                  ? const CoachHubDashboardScreen()
                  : const _FakeSectionBody(),
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

// Cuerpo de sección stub para las rutas del sidebar que no son /dashboard.
class _FakeSectionBody extends StatelessWidget {
  const _FakeSectionBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ColoredBox(color: palette.bg);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Comparador de goldens que escribe en docs/web-trainer/evidence/fase-2/<dir>/
// ──────────────────────────────────────────────────────────────────────────────
class _EvidenceComparator extends LocalFileComparator {
  _EvidenceComparator(String testFile) : super(Uri.file(testFile));

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    const basePath = 'docs/web-trainer/evidence/fase-2/$_evidenceDir';
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
    return Uri.file('docs/web-trainer/evidence/fase-2/$_evidenceDir/'
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

  group('Coach Hub Dashboard — evidencia visual fase-2/$_evidenceDir', () {
    testWidgets(
      'dark 1440x900',
      (tester) async {
        await _pumpDashboard(
          tester,
          theme: _evidenceTheme(palette: AppPalette.mintMagenta, dark: true),
          physicalSize: const Size(1440, 900),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('dashboard_dark_1440x900.png'),
        );
      },
    );

    testWidgets(
      'dark 420x900',
      (tester) async {
        await _pumpDashboard(
          tester,
          theme: _evidenceTheme(palette: AppPalette.mintMagenta, dark: true),
          physicalSize: const Size(420, 900),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('dashboard_dark_420x900.png'),
        );
      },
    );

    testWidgets(
      'light 1440x900',
      (tester) async {
        await _pumpDashboard(
          tester,
          theme:
              _evidenceTheme(palette: AppPalette.mintMagentaLight, dark: false),
          physicalSize: const Size(1440, 900),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('dashboard_light_1440x900.png'),
        );
      },
    );

    testWidgets(
      'light 420x900',
      (tester) async {
        await _pumpDashboard(
          tester,
          theme:
              _evidenceTheme(palette: AppPalette.mintMagentaLight, dark: false),
          physicalSize: const Size(420, 900),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('dashboard_light_420x900.png'),
        );
      },
    );
  });
}
