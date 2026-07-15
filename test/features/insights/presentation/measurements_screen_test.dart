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

const _emptyState =
    'Tu entrenador todavía no registró mediciones. Cuando las tengas, tu evolución aparece acá.';

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

    expect(find.text('MEDIDAS'), findsOneWidget);
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
    expect(find.text(_emptyState), findsOneWidget);
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
      find.text(
          'Con una sola medición no hay progreso que mostrar. Falta al menos una más.'),
      findsOneWidget,
    );
    expect(find.text(_emptyState), findsNothing);
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
    expect(find.text('Reintentar'), findsOneWidget);
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

    expect(find.text('TUS DATOS'), findsOneWidget);
    expect(find.text('80 kg'), findsOneWidget);
    expect(find.text('178 cm'), findsOneWidget);
    // La evolución (chart) sigue vacía porque no hay mediciones del PF.
    expect(find.byType(MeasurementProgressChart), findsNothing);
    expect(find.text(_emptyState), findsOneWidget);
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

    expect(find.text('TUS DATOS'), findsNothing);
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

    expect(find.text('TUS DATOS'), findsOneWidget);
    expect(find.text('170 cm'), findsOneWidget);
    expect(find.text('Peso'), findsNothing);
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

    // El tooltip del "+" (measurementsAddSelfLog, es_AR).
    await tester.tap(find.byTooltip('Cargar medición'));
    await tester.pumpAndSettle();

    expect(find.byType(LogMeasurementScreen), findsOneWidget);
  });
}
