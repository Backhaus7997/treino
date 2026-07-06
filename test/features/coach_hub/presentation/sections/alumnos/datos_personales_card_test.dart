// Widget tests for the _DatosPersonalesCard inside _ResumenTab.
//
// Exercises the card through AlumnoDetailScreen (Resumen is the default tab),
// with ProviderScope overrides for all providers the screen depends on.
//
// Covered:
//   - null ProfileShare (athlete not opted in) → empty-state copy
//   - full ProfileShare (all fields) → each field renders correctly
//   - partial ProfileShare (only phone + weight) → only those fields show
//   - updatedAt hint renders "actualizado hoy" / "actualizado hace N días"

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/locale_resolver.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';
import 'package:treino/features/coach/application/profile_share_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/profile_share.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/payments/application/billing_providers.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/payments/application/payment_providers.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/gender.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/exercise_progression_providers.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

const _trainerUid = 't1';
const _athleteUid = 'a1';

UserPublicProfile _profile() =>
    const UserPublicProfile(uid: _athleteUid, displayName: 'Sofía');

/// Builds the minimal list of provider overrides required to render
/// AlumnoDetailScreen without hitting Firestore. The [shareStream] is the
/// override for [profileShareProvider(athleteId)].
List<Override> _overrides(Stream<ProfileShare?> shareStream) => [
      currentUidProvider.overrideWithValue(_trainerUid),
      userPublicProfileProvider
          .overrideWith((ref, id) => Stream.value(_profile())),
      trainerLinksStreamProvider.overrideWith((ref) => Stream.value(const [])),
      pagosPorCobrarProvider
          .overrideWith((ref) => const AsyncData(<CobroPendiente>[])),
      trainerPaymentsProvider.overrideWith((ref) => Stream.value(const [])),
      athleteBillingProvider.overrideWith((ref, id) => Stream.value(null)),
      measurementsForAthleteProvider
          .overrideWith((ref, id) => Stream.value(const [])),
      performanceTestsForAthleteProvider
          .overrideWith((ref, id) => Stream.value(const [])),
      sessionsByUidProvider.overrideWith((ref, id) => const []),
      assignedRoutinesProvider.overrideWith((ref, id) => const []),
      coachSessionSetLogsProvider.overrideWith((ref, key) async => const []),
      athleteExerciseListProvider.overrideWith((ref, uid) async => const []),
      exerciseProgressionProvider.overrideWith(
        (ref, key) async => ExerciseProgression.empty(
          exerciseId: key.exerciseId,
          exerciseName: '',
        ),
      ),
      athleteNoteProvider.overrideWith((ref, key) => Stream.value(null)),
      trainerAppointmentsStreamProvider
          .overrideWith((ref, key) => Stream.value(const [])),
      lastWeightByExerciseProvider.overrideWith((ref, uid) async => const {}),
      userProfileProvider.overrideWith((ref) => Stream.value(null)),
      profileShareProvider.overrideWith(
        (ref, athleteId) => shareStream,
      ),
    ];

Widget _wrap(Stream<ProfileShare?> shareStream) => ProviderScope(
      overrides: _overrides(shareStream),
      child: MaterialApp(
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        localeResolutionCallback: (l, s) =>
            resolveLocale(l ?? const Locale('es', 'AR'), s),
        theme: AppTheme.dark(),
        home: const Scaffold(body: AlumnoDetailScreen(athleteId: _athleteUid)),
      ),
    );

void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
      'Resumen: null share → empty-state copy shown in DATOS PERSONALES card',
      (tester) async {
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(Stream.value(null)));
    await tester.pumpAndSettle();

    expect(find.text('DATOS PERSONALES'), findsOneWidget);
    expect(
      find.text('El alumno no compartió sus datos personales.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'Resumen: full ProfileShare → all fields visible with correct values',
      (tester) async {
    _useDesktopViewport(tester);

    final bornAt = DateTime.utc(1992, 3, 15);
    // updatedAt = today UTC so the hint reads "actualizado hoy"
    final updatedAt = DateTime.now().toUtc();

    final share = ProfileShare(
      trainerId: _trainerUid,
      phone: '+54 9 11 1234-5678',
      bornAt: bornAt,
      heightCm: 170,
      bodyWeightKg: 65.5,
      gender: Gender.female,
      experienceLevel: ExperienceLevel.intermediate,
      updatedAt: updatedAt,
    );

    await tester.pumpWidget(_wrap(Stream.value(share)));
    await tester.pumpAndSettle();

    expect(find.text('DATOS PERSONALES'), findsOneWidget);

    // Empty state should NOT appear
    expect(
      find.text('El alumno no compartió sus datos personales.'),
      findsNothing,
    );

    // Shared fields
    expect(find.text('+54 9 11 1234-5678'), findsOneWidget);
    expect(find.text('Femenino'), findsOneWidget);
    expect(find.text('Intermedio'), findsOneWidget);
    expect(find.text('170 cm'), findsOneWidget);
    expect(find.text('65.5 kg'), findsOneWidget);

    // updatedAt hint (today → "actualizado hoy")
    expect(find.text('actualizado hoy'), findsOneWidget);
  });

  testWidgets(
      'Resumen: partial ProfileShare (phone + bodyWeightKg only) → only those fields',
      (tester) async {
    _useDesktopViewport(tester);

    final share = ProfileShare(
      trainerId: _trainerUid,
      phone: '+54 9 11 9999-0000',
      bodyWeightKg: 80.0,
    );

    await tester.pumpWidget(_wrap(Stream.value(share)));
    await tester.pumpAndSettle();

    expect(find.text('+54 9 11 9999-0000'), findsOneWidget);
    expect(find.text('80 kg'), findsOneWidget);

    // Fields not set should NOT appear as labels
    expect(find.text('Altura'), findsNothing);
    expect(find.text('Género'), findsNothing);
    expect(find.text('Nivel'), findsNothing);
    expect(find.text('Fecha de nacimiento'), findsNothing);
  });

  testWidgets(
      'Resumen: ProfileShare with updatedAt 2 days ago → "actualizado hace 2 días"',
      (tester) async {
    _useDesktopViewport(tester);

    final twoDaysAgo = DateTime.now().toUtc().subtract(const Duration(days: 2));
    final share = ProfileShare(
      trainerId: _trainerUid,
      heightCm: 175,
      updatedAt: twoDaysAgo,
    );

    await tester.pumpWidget(_wrap(Stream.value(share)));
    await tester.pumpAndSettle();

    expect(find.text('actualizado hace 2 días'), findsOneWidget);
  });
}
