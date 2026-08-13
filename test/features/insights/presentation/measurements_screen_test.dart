import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/presentation/measurements_screen.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/measurements/presentation/widgets/measurement_progress_chart.dart';
import 'package:treino/features/measurements/presentation/log_measurement_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider, userProfileProvider;
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:treino/l10n/app_l10n.dart';

Measurement _m(DateTime at, double kg) => Measurement(
      id: 'm-${at.millisecondsSinceEpoch}',
      athleteId: 'u1',
      recordedBy: 'trainerA',
      recordedAt: at,
      weightKg: kg,
    );

UserProfile _profile({double? bodyWeightKg, int? heightCm}) => UserProfile(
      uid: 'u1',
      email: 'a@treino.app',
      displayName: 'Ana',
      role: UserRole.athlete,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      bodyWeightKg: bodyWeightKg,
      heightCm: heightCm,
    );

/// [profile] null → no se overridea `userProfileProvider` con datos (queda el
/// stream por defecto, que en test emite null → no aparece la tarjeta TUS DATOS).
Widget _wrap({
  required List<Override> overrides,
  UserProfile? profile,
}) =>
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith((ref) => Stream.value(profile)),
        // Para el form self-log que abre el botón "+".
        currentUidProvider.overrideWithValue('u1'),
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: MeasurementsScreen(uid: 'u1')),
      ),
    );

/// El copy sale del ARB, no de literales: estos tests son de comportamiento y
/// no deben romperse porque cambió una redacción. Pinear copy verbatim es tarea
/// de los `*_strings_migration_test.dart`.
AppL10n _l10n(WidgetTester tester) =>
    AppL10n.of(tester.element(find.byType(MeasurementsScreen)));

void main() {
  testWidgets('2+ mediciones → renderiza el chart de progreso', (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      ownMeasurementsProvider('u1').overrideWith(
        (ref) => Stream.value([
          _m(DateTime.utc(2026, 1, 1), 80),
          _m(DateTime.utc(2026, 2, 1), 78),
        ]),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text(_l10n(tester).measurementsScreenTitle), findsOneWidget);
    expect(find.byType(MeasurementProgressChart), findsOneWidget);
  });

  testWidgets(
      'CERO mediciones → empty state sobre la EVOLUCIÓN, no un chart vacío',
      (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      ownMeasurementsProvider('u1').overrideWith((ref) => Stream.value([])),
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(MeasurementProgressChart), findsNothing);
    expect(find.text(_l10n(tester).measurementsEmptyState), findsOneWidget);
  });

  testWidgets('UNA sola medición → mensaje distinto al de cero',
      (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      ownMeasurementsProvider('u1').overrideWith(
        (ref) => Stream.value([_m(DateTime.utc(2026, 1, 1), 80)]),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(MeasurementProgressChart), findsNothing);
    expect(
      find.text(_l10n(tester).measurementsNeedsMoreData),
      findsOneWidget,
    );
    expect(find.text(_l10n(tester).measurementsEmptyState), findsNothing);
  });

  testWidgets('fallo de carga → error VISIBLE con retry, nunca card vacía',
      (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      ownMeasurementsProvider('u1').overrideWith(
        (ref) => Stream.error(Exception('boom')),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(MeasurementProgressChart), findsNothing);
    expect(find.text(_l10n(tester).coachRetryLabel), findsOneWidget);
  });

  // ── TUS DATOS: peso + altura del perfil (onboarding) ────────────────────────

  testWidgets(
      'el peso y la altura del perfil se muestran SIN mediciones del coach — '
      'un alumno sin PF deja de ver la pantalla vacía', (tester) async {
    // Éste es el caso del usuario: sin entrenador, pero cargó peso+altura en
    // el onboarding. Antes veía sólo el empty state; ahora ve sus datos.
    await tester.pumpWidget(_wrap(
      profile: _profile(bodyWeightKg: 80, heightCm: 178),
      overrides: [
        ownMeasurementsProvider('u1').overrideWith((ref) => Stream.value([])),
      ],
    ));
    await tester.pumpAndSettle();

    expect(
      find.text(_l10n(tester).measurementsProfileCardTitle),
      findsOneWidget,
    );
    expect(find.text('80 kg'), findsOneWidget);
    expect(find.text('178 cm'), findsOneWidget);
    // La evolución (chart) sigue vacía porque todavía no hay ninguna medición.
    expect(find.byType(MeasurementProgressChart), findsNothing);
    expect(find.text(_l10n(tester).measurementsEmptyState), findsOneWidget);
  });

  testWidgets('el peso decimal se muestra sin ceros de más (80.5, no 80.50)',
      (tester) async {
    await tester.pumpWidget(_wrap(
      profile: _profile(bodyWeightKg: 80.5, heightCm: 178),
      overrides: [
        ownMeasurementsProvider('u1').overrideWith((ref) => Stream.value([])),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('80.5 kg'), findsOneWidget);
  });

  testWidgets(
      'sin peso ni altura en el perfil → NO se muestra la tarjeta TUS DATOS',
      (tester) async {
    // Doc viejo previo al onboarding con Step 4: no hay nada que mostrar.
    await tester.pumpWidget(_wrap(
      profile: _profile(),
      overrides: [
        ownMeasurementsProvider('u1').overrideWith((ref) => Stream.value([])),
      ],
    ));
    await tester.pumpAndSettle();

    expect(
      find.text(_l10n(tester).measurementsProfileCardTitle),
      findsNothing,
    );
  });

  testWidgets('sólo altura (sin peso) → la tarjeta muestra sólo altura',
      (tester) async {
    await tester.pumpWidget(_wrap(
      profile: _profile(heightCm: 170),
      overrides: [
        ownMeasurementsProvider('u1').overrideWith((ref) => Stream.value([])),
      ],
    ));
    await tester.pumpAndSettle();

    expect(
      find.text(_l10n(tester).measurementsProfileCardTitle),
      findsOneWidget,
    );
    expect(find.text('170 cm'), findsOneWidget);
    expect(find.text(_l10n(tester).measurementsWeightLabel), findsNothing);
  });

  testWidgets('T6: el botón "+" abre el formulario de auto-carga (self-log)',
      (tester) async {
    await tester.pumpWidget(_wrap(
      profile: _profile(bodyWeightKg: 80),
      overrides: [
        ownMeasurementsProvider('u1').overrideWith((ref) => Stream.value([])),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(_l10n(tester).measurementsAddSelfLog));
    await tester.pumpAndSettle();

    expect(find.byType(LogMeasurementScreen), findsOneWidget);
  });

  // ── HISTORIAL: editar/borrar mediciones (#439) ──────────────────────────────
  // El comportamiento fino (dialog, orden, cap) vive en
  // measurement_history_list_test.dart; acá se verifica el CABLEADO: uid
  // correcto como gate de autoría, tag del PF, y edición self-log pre-poblada.

  testWidgets(
      '#439 historial: la fila self-logged tiene acciones y la del PF es '
      'read-only', (tester) async {
    final coachLogged = _m(DateTime.utc(2026, 1, 1), 80); // recordedBy trainerA
    final selfLogged = Measurement(
      id: 'm-own',
      athleteId: 'u1',
      recordedBy: 'u1',
      recordedAt: DateTime.utc(2026, 2, 1),
      weightKg: 78,
    );
    await tester.pumpWidget(_wrap(overrides: [
      ownMeasurementsProvider('u1').overrideWith(
        (ref) => Stream.value([coachLogged, selfLogged]),
      ),
    ]));
    await tester.pumpAndSettle();
    final l10n = _l10n(tester);

    await tester.scrollUntilVisible(
      find.text(l10n.measurementsHistoryTitle),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip(l10n.measurementHistoryEditTooltip), findsOneWidget);
    expect(
        find.byTooltip(l10n.measurementHistoryDeleteTooltip), findsOneWidget);
    expect(find.text(l10n.measurementHistoryTrainerLoggedTag), findsOneWidget);
  });

  testWidgets(
      '#439 editar una medición self-logged abre el form PRE-POBLADO en modo '
      'edición', (tester) async {
    final selfLogged = Measurement(
      id: 'm-own',
      athleteId: 'u1',
      recordedBy: 'u1',
      recordedAt: DateTime.utc(2026, 2, 1),
      weightKg: 78,
    );
    await tester.pumpWidget(_wrap(overrides: [
      ownMeasurementsProvider('u1').overrideWith(
        (ref) => Stream.value([_m(DateTime.utc(2026, 1, 1), 80), selfLogged]),
      ),
    ]));
    await tester.pumpAndSettle();
    final l10n = _l10n(tester);

    await tester.scrollUntilVisible(
      find.byTooltip(l10n.measurementHistoryEditTooltip),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.measurementHistoryEditTooltip));
    await tester.pumpAndSettle();

    expect(find.byType(LogMeasurementScreen), findsOneWidget);
    expect(find.text('GUARDAR CAMBIOS'), findsOneWidget);
    expect(find.text('78'), findsOneWidget); // peso pre-poblado
  });
}
