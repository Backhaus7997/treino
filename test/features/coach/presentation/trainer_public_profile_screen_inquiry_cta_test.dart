// #637 — el perfil público del PF tiene DOS CTAs, y el de consulta NO está
// atado al gate de vínculo.
//
// El hallazgo que motiva el issue: `TrainerContactCtaStub` deshabilita
// "PEDIR VÍNCULO" cuando el atleta ya tiene un vínculo `pending`/`active` con
// CUALQUIER PF, y muestra "YA TENÉS UN PF". O sea que un atleta que quiere
// comparar tres coaches no podía — apenas le pedía vínculo al primero, los
// otros dos quedaban bloqueados. El producto lo obligaba a ELEGIR antes de
// poder PREGUNTAR.
//
// Estos tests pinean las dos mitades del arreglo:
//   1. CONSULTAR sigue habilitado con un vínculo pendiente con OTRO PF;
//   2. el orden en pantalla — consultar primero, pedir vínculo después.
//
// Espeja el patrón `_wrap` de las suites hermanas del mismo directorio.

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

const _trainerUid = 'trainer-visited';
const _otherTrainerUid = 'trainer-already-mine';
const _athleteId = 'athlete-1';

TrainerPublicProfile _profile(String uid, String name) =>
    TrainerPublicProfile(uid: uid, displayName: name);

TrainerLink _link(TrainerLinkStatus status, String trainerId) => TrainerLink(
      id: 'link-1',
      trainerId: trainerId,
      athleteId: _athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 8, 24),
    );

Widget _wrap({TrainerLink? existingLink}) => ProviderScope(
      overrides: [
        trainerByIdProvider(_trainerUid)
            .overrideWith((ref) async => _profile(_trainerUid, 'Coach Nuevo')),
        trainerByIdProvider(_otherTrainerUid).overrideWith(
            (ref) async => _profile(_otherTrainerUid, 'Coach Actual')),
        // El stub lee el provider ANY-STATUS: es el que hace que un `pending`
        // con otro PF deshabilite el botón (QA-COA-001).
        currentAthleteLinkAnyStatusProvider
            .overrideWith((ref) async => existingLink),
        currentAthleteLinkProvider.overrideWith((ref) async => null),
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

/// `enabled` real del botón: `onPressed != null`.
bool _enabled(WidgetTester tester, Finder buttonFinder) =>
    tester.widget<ButtonStyleButton>(buttonFinder).onPressed != null;

void main() {
  group('TrainerPublicProfileScreen — CTA de consulta (#637)', () {
    testWidgets('renderiza los dos CTAs, consultar PRIMERO', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final inquiry = find.byType(TrainerInquiryCta);
      final link = find.byType(TrainerContactCtaStub);
      expect(inquiry, findsOneWidget);
      expect(link, findsOneWidget);

      // La jerarquía es posicional: el paso liviano va arriba.
      expect(
        tester.getTopLeft(inquiry).dy,
        lessThan(tester.getTopLeft(link).dy),
      );
    });

    testWidgets('CONSULTAR está habilitado sin ningún vínculo', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(
        _enabled(
            tester,
            find.descendant(
              of: find.byType(TrainerInquiryCta),
              matching: find.byType(FilledButton),
            )),
        isTrue,
      );
    });

    // EL test del issue. Con un vínculo pendiente con OTRO PF, "PEDIR VÍNCULO"
    // se apaga y dice "YA TENÉS UN PF" — pero consultar tiene que seguir vivo:
    // preguntarle a un entrenador no es cambiarse de entrenador.
    for (final status in [
      TrainerLinkStatus.pending,
      TrainerLinkStatus.active
    ]) {
      testWidgets(
          'con un vínculo ${status.name} con OTRO PF: PEDIR VÍNCULO se apaga '
          'pero CONSULTAR sigue habilitado', (tester) async {
        await tester.pumpWidget(
          _wrap(existingLink: _link(status, _otherTrainerUid)),
        );
        await tester.pumpAndSettle();

        expect(find.text('YA TENÉS UN PF'), findsOneWidget);

        expect(
          _enabled(
              tester,
              find.descendant(
                of: find.byType(TrainerContactCtaStub),
                matching: find.byType(OutlinedButton),
              )),
          isFalse,
          reason: 'el gate de "un solo PF" sigue vigente para el vínculo',
        );

        expect(
          _enabled(
              tester,
              find.descendant(
                of: find.byType(TrainerInquiryCta),
                matching: find.byType(FilledButton),
              )),
          isTrue,
          reason: 'consultar NO puede quedar atado al gate de vínculo (#637)',
        );
      });
    }
  });
}
