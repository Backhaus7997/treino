// Harness de evidencia visual de la sección "Alumnos" del Coach Hub web
// (EVIDENCE-HARNESS).
//
// Captura 8 screenshots (goldens) del roster (AlumnosScreen, `/alumnos`) y
// del detalle de un alumno (AlumnoDetailScreen, `/alumnos/:id`, tab
// Resumen) montados DENTRO del shell real (CoachHubScaffold) con proveedores
// falsos POBLADOS (vínculos, perfiles, gyms, deudas, sesiones, mediciones,
// rutina asignada, facturación) para que el screenshot muestre data real, no
// vacío/error. Estos PNGs sirven como línea base BEFORE/AFTER para validar
// regresiones visuales de la Fase 3.
//
// Mismo patrón que test/evidence/coach_hub_dashboard_evidence_test.dart —
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
//     test/evidence/coach_hub_alumnos_evidence_test.dart
//
// Los PNGs se guardan en:
//   docs/web-trainer/evidence/fase-3/<EVIDENCE_DIR>/
//
// Matriz: (roster, detalle) × (dark, light) × (1440x900, 420x900) = 8 goldens.

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
import 'package:treino/features/coach_hub/presentation/sections/alumnos/routes.dart'
    show alumnosRoutes;
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
import 'package:treino/features/coach_hub/presentation/shell/responsive.dart'
    show kMobileBreakpoint;
import 'package:treino/features/coach_hub/presentation/shell/sidebar_registry.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/payments/application/billing_providers.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/l10n/app_l10n.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Guardián: si EVIDENCE != true, el archivo entero se salta.
// ──────────────────────────────────────────────────────────────────────────────
const bool _evidenceEnabled =
    bool.fromEnvironment('EVIDENCE', defaultValue: false);

const String _evidenceDir =
    String.fromEnvironment('EVIDENCE_DIR', defaultValue: 'before');

// ──────────────────────────────────────────────────────────────────────────────
// Fakes / stubs (mismo patrón que coach_hub_dashboard_evidence_test.dart)
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
// Factories — datos fake poblados para que el roster y el detalle muestren
// data real.
// ──────────────────────────────────────────────────────────────────────────────
const _trainerUid = 'evidence-trainer';

/// Alumno cuyo detalle se captura (`/alumnos/$_detailAthleteId`). Es el único
/// con sesiones/mediciones/rutina/facturación pobladas — el resto del roster
/// sólo necesita perfil + link para la tabla.
const _detailAthleteId = 'a1';

UserProfile _trainerProfile() => UserProfile(
      uid: _trainerUid,
      email: 'trainer@treino.app',
      displayName: 'Mateo García',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

UserPublicProfile _pub(String uid, String name, {String? gymId}) =>
    UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
      gymId: gymId,
      workoutsCount: 42,
      racha: 6,
    );

TrainerLink _link({
  required String id,
  required String athleteId,
  required TrainerLinkStatus status,
  bool sharedWithTrainer = false,
}) =>
    TrainerLink(
      id: id,
      trainerId: _trainerUid,
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 5, 1),
      acceptedAt:
          status == TrainerLinkStatus.pending ? null : DateTime.utc(2026, 5, 2),
      sharedWithTrainer: sharedWithTrainer,
    );

Gym _gym({required String id, required String name}) => Gym(
      id: id,
      name: name,
      lat: -34.58,
      lng: -58.43,
      geohash: '6gyf4b',
      source: GymSource.seed,
      createdAt: DateTime.utc(2026, 1, 1),
    );

CobroPendiente _cobro(String athleteId, int amountArs) => CobroPendiente(
      athleteId: athleteId,
      amountArs: amountArs,
      cadence: BillingCadence.mensual,
      concept: 'Mensual Julio 2026',
    );

Measurement _measurement({
  required String id,
  required DateTime recordedAt,
  required double weightKg,
}) =>
    Measurement(
      id: id,
      athleteId: _detailAthleteId,
      recordedBy: _trainerUid,
      recordedAt: recordedAt,
      weightKg: weightKg,
      fatPercentage: 18.5,
    );

Session _session({
  required String id,
  required DateTime startedAt,
  required DateTime finishedAt,
  required double totalVolumeKg,
}) =>
    Session(
      id: id,
      uid: _detailAthleteId,
      routineId: 'r1',
      routineName: 'PPL Intermedio',
      startedAt: startedAt,
      finishedAt: finishedAt,
      totalVolumeKg: totalVolumeKg,
      durationMin: 58,
      status: SessionStatus.finished,
      wasFullyCompleted: true,
    );

Routine _assignedRoutine() => const Routine(
      id: 'r1',
      name: 'PPL Intermedio',
      split: 'PPL',
      level: ExperienceLevel.intermediate,
      days: [
        RoutineDay(dayNumber: 1, name: 'Push', slots: []),
        RoutineDay(dayNumber: 2, name: 'Pull', slots: []),
        RoutineDay(dayNumber: 3, name: 'Legs', slots: []),
        RoutineDay(dayNumber: 4, name: 'Upper', slots: []),
      ],
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerUid,
      assignedTo: _detailAthleteId,
      visibility: RoutineVisibility.private,
      status: RoutineStatus.active,
    );

AthleteBilling _billing(String athleteId, int amountArs) => AthleteBilling(
      trainerId: _trainerUid,
      athleteId: athleteId,
      amountArs: amountArs,
      cadence: BillingCadence.mensual,
      updatedAt: DateTime.utc(2026, 7, 1),
    );

Appointment _confirmedAppointment({
  required String id,
  required String athleteId,
  required String athleteDisplayName,
  required DateTime startsAt,
}) =>
    Appointment(
      id: id,
      trainerId: _trainerUid,
      athleteId: athleteId,
      athleteDisplayName: athleteDisplayName,
      startsAt: startsAt,
      durationMin: 60,
      status: AppointmentStatus.confirmed,
    );

// ──────────────────────────────────────────────────────────────────────────────
// Carga de fuentes TTF reales desde test/fonts/ (idéntico a
// coach_hub_dashboard_evidence_test.dart — ver ese archivo para el
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
// Tema de evidencia — idéntico a coach_hub_dashboard_evidence_test.dart.
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
// entorno de test. Ver coach_hub_dashboard_evidence_test.dart para el
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
  // coach_hub_dashboard_evidence_test.dart — mismo razonamiento).
  addTearDown(() => FlutterError.onError = previousOnError);
}

// ──────────────────────────────────────────────────────────────────────────────
// Helper: monta el shell real (CoachHubScaffold) con el roster o el detalle
// REAL en [initialLocation], GoRouter + proveedores falsos POBLADOS.
// ──────────────────────────────────────────────────────────────────────────────
Future<void> _pumpAlumnos(
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
  // 7 vínculos: 4 activos (2 con deuda), 1 pausado, 1 pendiente, 1 terminado.
  final links = [
    _link(id: 'l1', athleteId: 'a1', status: TrainerLinkStatus.active),
    _link(
      id: 'l2',
      athleteId: 'a2',
      status: TrainerLinkStatus.active,
      sharedWithTrainer: true,
    ),
    _link(id: 'l3', athleteId: 'a3', status: TrainerLinkStatus.active),
    _link(id: 'l4', athleteId: 'a4', status: TrainerLinkStatus.paused),
    _link(id: 'l5', athleteId: 'a5', status: TrainerLinkStatus.pending),
    _link(id: 'l6', athleteId: 'a6', status: TrainerLinkStatus.terminated),
    _link(
      id: 'l7',
      athleteId: 'a7',
      status: TrainerLinkStatus.active,
      sharedWithTrainer: true,
    ),
  ];

  const gymA = 'g1';
  const gymB = 'g2';
  final gyms = [
    _gym(id: gymA, name: 'PowerHouse Palermo'),
    _gym(id: gymB, name: 'Iron Temple Belgrano'),
  ];

  final athleteNames = <String, String>{
    'a1': 'Ana López',
    'a2': 'Bruno García',
    'a3': 'Carla Rodríguez',
    'a4': 'Diego Martínez',
    'a5': 'Eva Sánchez',
    'a6': 'Fabio Torres',
    'a7': 'Gina Suárez',
  };
  final athleteGyms = <String, String>{
    'a1': gymA,
    'a2': gymA,
    'a3': gymB,
    'a4': gymB,
    'a7': gymA,
  };
  final profiles = {
    for (final entry in athleteNames.entries)
      entry.key: _pub(entry.key, entry.value, gymId: athleteGyms[entry.key]),
  };

  final now = DateTime.now().toUtc();
  final sessions = [
    _session(
      id: 's1',
      startedAt: now.subtract(const Duration(days: 1, hours: 1)),
      finishedAt: now.subtract(const Duration(days: 1)),
      totalVolumeKg: 3200,
    ),
    _session(
      id: 's2',
      startedAt: now.subtract(const Duration(days: 3, hours: 1)),
      finishedAt: now.subtract(const Duration(days: 3)),
      totalVolumeKg: 2950,
    ),
    _session(
      id: 's3',
      startedAt: now.subtract(const Duration(days: 8, hours: 1)),
      finishedAt: now.subtract(const Duration(days: 8)),
      totalVolumeKg: 2700,
    ),
  ];
  final finishedToday = [
    _session(
      id: 's0',
      startedAt: now.subtract(const Duration(hours: 1)),
      finishedAt: now,
      totalVolumeKg: 3100,
    ),
  ];
  final measurements = [
    _measurement(
      id: 'm1',
      recordedAt: now.subtract(const Duration(days: 45)),
      weightKg: 82.4,
    ),
    _measurement(
      id: 'm2',
      recordedAt: now.subtract(const Duration(days: 15)),
      weightKg: 81.0,
    ),
  ];

  final appointments = [
    _confirmedAppointment(
      id: 'ap1',
      athleteId: _detailAthleteId,
      athleteDisplayName: athleteNames[_detailAthleteId]!,
      startsAt: now.add(const Duration(days: 1, hours: 2)),
    ),
    _confirmedAppointment(
      id: 'ap2',
      athleteId: 'a3',
      athleteDisplayName: athleteNames['a3']!,
      startsAt: now.add(const Duration(days: 2)),
    ),
  ];

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
    userPublicProfilesBatchProvider.overrideWith((ref, key) async {
      final ids = key.isEmpty ? const <String>[] : key.split(',');
      return {
        for (final id in ids)
          if (profiles.containsKey(id)) id: profiles[id]!,
      };
    }),
    pagosPorCobrarProvider.overrideWith(
      (ref) => AsyncData([_cobro('a2', 20000), _cobro('a7', 15000)]),
    ),
    gymsProvider.overrideWith((ref) async => gyms),
    gymByIdProvider.overrideWith(
      (ref, id) async => gyms.where((g) => g.id == id).firstOrNull,
    ),
    finishedTodayByUidProvider.overrideWith(
      (ref, uid) async => uid == _detailAthleteId ? finishedToday : const [],
    ),
    sessionsByUidProvider.overrideWith(
      (ref, uid) async => uid == _detailAthleteId ? sessions : const [],
    ),
    measurementsForAthleteProvider.overrideWith(
      (ref, uid) =>
          Stream.value(uid == _detailAthleteId ? measurements : const []),
    ),
    assignedRoutinesProvider.overrideWith(
      (ref, uid) async =>
          uid == _detailAthleteId ? [_assignedRoutine()] : const [],
    ),
    athleteBillingProvider.overrideWith(
      (ref, uid) => Stream.value(
        uid == _detailAthleteId ? _billing(_detailAthleteId, 20000) : null,
      ),
    ),
    trainerAppointmentsStreamProvider.overrideWith(
      (ref, key) => Stream.value(appointments),
    ),
    totalUnreadCountProvider.overrideWith((ref) => 5),
  ]);
  addTearDown(container.dispose);

  // Warm providers que el shell lee en build.
  await tester.runAsync(() async {
    await container.read(authNotifierProvider.future).catchError((_) => null);
    await container.read(userProfileProvider.future).catchError((_) => null);
    await container.read(sharedPreferencesProvider.future);
  });

  // GoRouter: ShellRoute con CoachHubScaffold + rutas reales de Alumnos
  // (`/alumnos`, `/alumnos/:id`) + el resto de rutas del sidebar como stub
  // liviano, necesarias para que el sidebar resuelva GoRouterState.of(context)
  // (mismo patrón que coach_hub_dashboard_evidence_test.dart).
  final otherPaths =
      sidebarRegistry.map((i) => i.route).toSet().where((p) => p != '/alumnos');
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (ctx, state, child) => CoachHubScaffold(child: child),
        routes: [
          ...alumnosRoutes,
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
        // CRÍTICO (mismo motivo que coach_hub_dashboard_evidence_test.dart):
        // sin locale explícito, el entorno de test resuelve a 'en' y los
        // labels de Alumnos quedarían vacíos (l10n congelado en español).
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Guard de regresión, ramificado por viewport: `CoachHubScaffold` reemplaza
  // TODO el shell por `MobileBanner` bajo `kMobileBreakpoint` (768px,
  // ADR-CHW-004 — Coach Hub es desktop-only), así que a 420px NUNCA se monta
  // el roster/detalle real — capturar ese golden es intencional (documenta el
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

  // Si el locale no resuelve a español, el título del roster ("ALUMNOS")
  // queda vacío y el golden captura la pantalla en blanco sin que ningún test
  // lo detecte (matchesGoldenFile solo compara píxeles contra el propio
  // "before", igualmente roto). Falla temprano acá con un mensaje claro en
  // vez de un mismatch de imagen silencioso.
  expect(
    find.textContaining('ALUMNOS').evaluate().isNotEmpty ||
        find.textContaining('Ana López').evaluate().isNotEmpty,
    isTrue,
    reason: 'l10n español ausente o data fake no renderizada — el locale del '
        'harness no está resolviendo a es_AR o los overrides no matchearon '
        'la pantalla montada',
  );
}

// Cuerpo de sección stub para las rutas del sidebar que no son /alumnos.
class _FakeSectionBody extends StatelessWidget {
  const _FakeSectionBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ColoredBox(color: palette.bg);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Comparador de goldens que escribe en docs/web-trainer/evidence/fase-3/<dir>/
// ──────────────────────────────────────────────────────────────────────────────
class _EvidenceComparator extends LocalFileComparator {
  _EvidenceComparator(String testFile) : super(Uri.file(testFile));

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    const basePath = 'docs/web-trainer/evidence/fase-3/$_evidenceDir';
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
    return Uri.file('docs/web-trainer/evidence/fase-3/$_evidenceDir/'
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

  group('Coach Hub Alumnos — evidencia visual fase-3/$_evidenceDir', () {
    for (final dark in [true, false]) {
      final palette =
          dark ? AppPalette.mintMagenta : AppPalette.mintMagentaLight;
      final modeLabel = dark ? 'dark' : 'light';

      for (final size in [const Size(1440, 900), const Size(420, 900)]) {
        final sizeLabel = '${size.width.toInt()}x${size.height.toInt()}';

        testWidgets(
          'roster $modeLabel $sizeLabel',
          (tester) async {
            await _pumpAlumnos(
              tester,
              theme: _evidenceTheme(palette: palette, dark: dark),
              physicalSize: size,
              initialLocation: '/alumnos',
            );
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('alumnos_roster_${modeLabel}_$sizeLabel.png'),
            );
          },
        );

        testWidgets(
          'detalle $modeLabel $sizeLabel',
          (tester) async {
            await _pumpAlumnos(
              tester,
              theme: _evidenceTheme(palette: palette, dark: dark),
              physicalSize: size,
              initialLocation: '/alumnos/$_detailAthleteId',
            );
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('alumnos_detalle_${modeLabel}_$sizeLabel.png'),
            );
          },
        );
      }
    }
  });
}
