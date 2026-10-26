// Pausa del PF (`acceptingAthletes == false`) vista desde el perfil público.
//
// Lo que pinean estos tests:
//   1. el alumno sin vínculo ve "NO TOMA ALUMNOS" con el motivo, y no ve el
//      CTA de consulta (las rules rechazarían las dos cosas);
//   2. el alumno que YA está con este PF sigue viendo su vínculo: la pausa es
//      para alumnos nuevos, y esconder el CTA le borraba "TU PERSONAL
//      TRAINER";
//   3. con vínculo con OTRO PF, la pausa le gana a "YA TENÉS UN PF".
//
// Espeja el `_wrap` de trainer_public_profile_screen_inquiry_cta_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/presentation/trainer_public_profile_screen.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_contact_cta_stub.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_inquiry_cta.dart';
import 'package:treino/features/reviews/application/review_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

const _trainerUid = 'trainer-pausado';
const _otherTrainerUid = 'trainer-otro';
const _athleteId = 'athlete-1';

TrainerLink _link(TrainerLinkStatus status, String trainerId) => TrainerLink(
      id: 'link-1',
      trainerId: trainerId,
      athleteId: _athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 10, 1),
    );

Widget _wrap({
  TrainerLink? existingLink,
  bool acceptingAthletes = false,
  bool vinculoCargando = false,
}) =>
    ProviderScope(
      overrides: [
        trainerByIdProvider(_trainerUid).overrideWith(
          (ref) async => TrainerPublicProfile(
            uid: _trainerUid,
            displayName: 'Coach Pausa',
            acceptingAthletes: acceptingAthletes,
          ),
        ),
        trainerByIdProvider(_otherTrainerUid).overrideWith(
          (ref) async => const TrainerPublicProfile(
            uid: _otherTrainerUid,
            displayName: 'Coach Actual',
          ),
        ),
        currentAthleteLinkAnyStatusProvider.overrideWith(
          (ref) => vinculoCargando
              ? const Stream<TrainerLink?>.empty()
              : Stream.value(existingLink),
        ),
        currentAthleteLinkProvider.overrideWith((ref) => Stream.value(null)),
        trainerReviewsProvider(_trainerUid)
            .overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const TrainerPublicProfileScreen(uid: _trainerUid),
      ),
    );

Finder get _linkButton => find.descendant(
      of: find.byType(TrainerContactCtaStub),
      matching: find.byType(OutlinedButton),
    );

bool _enabled(WidgetTester tester) =>
    tester.widget<ButtonStyleButton>(_linkButton).onPressed != null;

void main() {
  group('TrainerPublicProfileScreen — PF pausado', () {
    testWidgets('sin vínculo: NO TOMA ALUMNOS, deshabilitado, sin consulta',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('NO TOMA ALUMNOS'), findsOneWidget);
      expect(
        find.text('Coach Pausa no está tomando alumnos nuevos por ahora.'),
        findsOneWidget,
      );
      expect(_enabled(tester), isFalse);
      expect(find.byType(TrainerInquiryCta), findsNothing);
    });

    testWidgets('abierto: el CTA de vínculo sigue igual que siempre',
        (tester) async {
      await tester.pumpWidget(_wrap(acceptingAthletes: true));
      await tester.pumpAndSettle();

      expect(find.text('NO TOMA ALUMNOS'), findsNothing);
      expect(_enabled(tester), isTrue);
      expect(find.byType(TrainerInquiryCta), findsOneWidget);
    });

    for (final (status, label) in [
      (TrainerLinkStatus.active, 'TU PERSONAL TRAINER'),
      (TrainerLinkStatus.pending, 'SOLICITUD PENDIENTE'),
    ]) {
      testWidgets(
          'el alumno con vínculo ${status.name} con ESTE PF sigue viendo '
          '"$label"', (tester) async {
        await tester
            .pumpWidget(_wrap(existingLink: _link(status, _trainerUid)));
        await tester.pumpAndSettle();

        expect(find.text(label), findsOneWidget);
        expect(find.text('NO TOMA ALUMNOS'), findsNothing);
      });
    }

    // Regresión: con el vínculo sin resolver no se sabe si el alumno ya es de
    // este PF, y la pausa parpadeaba antes de "TU PERSONAL TRAINER".
    testWidgets('con el vínculo cargando no anuncia la pausa', (tester) async {
      await tester.pumpWidget(_wrap(vinculoCargando: true));
      await tester.pumpAndSettle();

      expect(find.text('NO TOMA ALUMNOS'), findsNothing);
      expect(_enabled(tester), isFalse, reason: 'deshabilitado mientras carga');
    });

    testWidgets('con vínculo con OTRO PF, la pausa le gana a YA TENÉS UN PF',
        (tester) async {
      await tester.pumpWidget(
        _wrap(existingLink: _link(TrainerLinkStatus.active, _otherTrainerUid)),
      );
      await tester.pumpAndSettle();

      expect(find.text('NO TOMA ALUMNOS'), findsOneWidget);
      expect(find.text('YA TENÉS UN PF'), findsNothing);
    });
  });
}
