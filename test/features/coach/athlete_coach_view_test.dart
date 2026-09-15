import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/athlete_coach_view.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/presentation/trainers_list_screen.dart';
import 'package:treino/features/payments/application/mi_cuota_provider.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        // Keep Firestore out of these widget tests. The payments "Tu cuota"
        // section (miCuotaProvider) reads firestoreProvider, which has no
        // Firebase app in unit tests.
        miCuotaProvider.overrideWith(
          (ref) => const AsyncValue<MiCuotaState?>.data(null),
        ),
        // QA-COA-001: the view/harness now read currentAthleteLinkAnyStatusProvider
        // for the card-vs-discovery decision. Bridge it to whatever each test
        // overrides currentAthleteLinkProvider with, so the existing per-test
        // overrides keep driving the view unchanged.
        currentAthleteLinkAnyStatusProvider.overrideWith(
            (ref) => ref.watch(currentAthleteLinkProvider.future).asStream()),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: child),
      ),
    );

TrainerLink _makeLink({
  TrainerLinkStatus status = TrainerLinkStatus.active,
  String trainerId = 'trainer-1',
  bool sharedWithTrainer = false,
}) =>
    TrainerLink(
      id: 'link-1',
      trainerId: trainerId,
      athleteId: 'athlete-1',
      status: status,
      requestedAt: DateTime.utc(2026, 5, 18, 10, 0),
      acceptedAt: status == TrainerLinkStatus.active
          ? DateTime.utc(2026, 5, 18, 12, 0)
          : null,
      sharedWithTrainer: sharedWithTrainer,
    );

UserPublicProfile _makePub({String displayName = 'Coach Joe'}) =>
    UserPublicProfile(
      uid: 'trainer-1',
      displayName: displayName,
      displayNameLowercase: displayName.toLowerCase(),
    );

void main() {
  group('AthleteCoachView', () {
    testWidgets(
        'REQ-COACH-LINK-001: sin link → renderiza TrainersListScreen (discovery)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AthleteCoachView(),
        overrides: [
          currentAthleteLinkProvider.overrideWith((ref) => Stream.value(null)),
          trainerDiscoveryProvider.overrideWith((_) async => []),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byType(TrainersListScreen), findsOneWidget);
    });

    testWidgets(
        'REQ-COACH-LINK-002: status active → muestra info del PF + terminar',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AthleteCoachView(),
        overrides: [
          currentAthleteLinkProvider
              .overrideWith((ref) => Stream.value(_makeLink())),
          userPublicProfileProvider('trainer-1')
              .overrideWith((ref) => Stream.value(_makePub())),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('TU PERSONAL TRAINER'), findsOneWidget);
      expect(find.text('Coach Joe'), findsOneWidget);
      expect(find.text('TERMINAR VÍNCULO'), findsOneWidget);
    });

    // Los tres accesos eran `OutlinedButton` idénticos, en el orden en que se
    // fueron agregando: agenda, nutrición, archivos. Sin jerarquía visual
    // ninguno "entraba" más que otro, y el más importante quedaba en el medio.
    //
    // Se testea el ORDEN y la JERARQUÍA juntos porque por separado cada uno
    // pasa con el bug del otro puesto: reordenar sin destacar deja tres
    // botones iguales, y destacar sin reordenar deja el primario en el medio.
    testWidgets('el plan nutricional va primero y es el único relleno',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AthleteCoachView(),
        overrides: [
          currentAthleteLinkProvider
              .overrideWith((ref) => Stream.value(_makeLink())),
          userPublicProfileProvider('trainer-1')
              .overrideWith((ref) => Stream.value(_makePub())),
        ],
      ));
      await tester.pumpAndSettle();

      final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));
      final yNutricion =
          tester.getTopLeft(find.text(l10n.athleteNutritionPlanButtonLabel)).dy;
      final yArchivos =
          tester.getTopLeft(find.text(l10n.athleteFilesButtonLabel)).dy;
      final yAgenda = tester.getTopLeft(find.text(l10n.agendaButtonLabel)).dy;

      expect(yNutricion, lessThan(yArchivos),
          reason: 'el plan nutricional es lo que el alumno viene a buscar');
      expect(yArchivos, lessThan(yAgenda),
          reason: 'la agenda queda última: hoy aporta poco dato propio');

      // EL contrato, y el que este PR rompió en su primera versión: el CTA
      // relleno es UNO POR PANTALLA (ver la grilla en `TreinoButtonTokens`).
      // Acá ya lo ocupa «MENSAJE», así que ninguno de los tres accesos puede
      // ser relleno — si lo fuera, habría dos verdes compitiendo y la
      // jerarquía que este test protege no significaría nada.
      //
      // Lo encontró Codex en la review. La versión anterior de este test
      // acotaba la afirmación a los tres accesos y por eso pasaba en verde con
      // el segundo CTA puesto.
      expect(find.byType(ElevatedButton), findsOneWidget,
          reason: 'el único relleno de la pantalla es MENSAJE');

      // Y la jerarquía entre los tres sale del COLOR del texto, no del
      // relleno: el plan nutricional en acento, los otros dos en neutro.
      Color colorDe(String etiqueta) =>
          tester.widget<Text>(find.text(etiqueta)).style?.color ??
          DefaultTextStyle.of(
            tester.element(find.text(etiqueta)),
          ).style.color!;

      final palette = AppPalette.of(
        tester.element(find.text(l10n.athleteFilesButtonLabel)),
      );
      expect(colorDe(l10n.athleteNutritionPlanButtonLabel), palette.accentText,
          reason: 'el plan nutricional es el destacado de los tres');
      for (final neutro in [
        l10n.athleteFilesButtonLabel,
        l10n.agendaButtonLabel,
      ]) {
        expect(colorDe(neutro), palette.textPrimary,
            reason: '$neutro es secundario de verdad');
      }
    });

    testWidgets('Fase B: status active → muestra botón MENSAJE',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AthleteCoachView(),
        overrides: [
          currentAthleteLinkProvider
              .overrideWith((ref) => Stream.value(_makeLink())),
          userPublicProfileProvider('trainer-1')
              .overrideWith((ref) => Stream.value(_makePub())),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('MENSAJE'), findsOneWidget);
    });

    testWidgets('Fase B: status pending → NO muestra botón MENSAJE',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AthleteCoachView(),
        overrides: [
          currentAthleteLinkProvider.overrideWith((ref) =>
              Stream.value(_makeLink(status: TrainerLinkStatus.pending))),
          userPublicProfileProvider('trainer-1')
              .overrideWith((ref) => Stream.value(_makePub())),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('MENSAJE'), findsNothing);
    });

    // SCEN-CHLM-018 — paused state shows TERMINAR VÍNCULO only.
    //
    // Background: before this change, _ActionRow returned SizedBox.shrink()
    // for the paused case — leaving the athlete with zero affordances when
    // the PF paused the link from Coach Hub. The minimum fix is one button:
    // TERMINAR VÍNCULO. Resume is a PF-only action (no button on the
    // athlete side).
    testWidgets(
        'SCEN-CHLM-018: status paused → muestra TERMINAR VÍNCULO y no muestra MENSAJE',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AthleteCoachView(),
        overrides: [
          currentAthleteLinkProvider.overrideWith((ref) =>
              Stream.value(_makeLink(status: TrainerLinkStatus.paused))),
          userPublicProfileProvider('trainer-1')
              .overrideWith((ref) => Stream.value(_makePub())),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('TERMINAR VÍNCULO'), findsOneWidget);
      // MENSAJE only renders for active; verify it does NOT bleed into paused.
      expect(find.text('MENSAJE'), findsNothing);
      // CANCELAR SOLICITUD is pending-only.
      expect(find.text('CANCELAR SOLICITUD'), findsNothing);
    });

    testWidgets(
        'REQ-COACH-LINK-003: status pending → muestra esperando + cancelar',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AthleteCoachView(),
        overrides: [
          currentAthleteLinkProvider.overrideWith((ref) =>
              Stream.value(_makeLink(status: TrainerLinkStatus.pending))),
          userPublicProfileProvider('trainer-1')
              .overrideWith((ref) => Stream.value(_makePub())),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('SOLICITUD ENVIADA'), findsOneWidget);
      expect(find.text('Esperando confirmación'), findsOneWidget);
      expect(find.text('CANCELAR SOLICITUD'), findsOneWidget);
    });

    testWidgets(
        'REQ-COACH-LINK-004: loading state → spinner mientras provider resuelve',
        (tester) async {
      final completer = Completer<TrainerLink?>();
      addTearDown(() {
        if (!completer.isCompleted) completer.complete(null);
      });
      await tester.pumpWidget(_wrap(
        const AthleteCoachView(),
        overrides: [
          currentAthleteLinkProvider
              .overrideWith((ref) => completer.future.asStream()),
        ],
      ));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  // ── Auto-share info label (replaces manual toggle) ────────────────────────
  //
  // The "Compartir historial con mi PF" toggle was removed in
  // trainer-athlete-set-logs. History is now auto-shared via the
  // syncSessionShareOnTrainerLink Cloud Function when the link is active.
  // The UI shows a static informational label instead.

  group('auto-share info label', () {
    testWidgets(
      'active link → shows informational share text (no toggle)',
      (tester) async {
        await tester.pumpWidget(_wrap(
          const AthleteCoachView(),
          overrides: [
            currentAthleteLinkProvider
                .overrideWith((ref) => Stream.value(_makeLink())),
            userPublicProfileProvider('trainer-1')
                .overrideWith((ref) => Stream.value(_makePub())),
          ],
        ));
        await tester.pumpAndSettle();

        expect(
          find.text('Tu PF puede ver tu historial de entrenamiento.'),
          findsOneWidget,
        );
        // No toggle present.
        expect(find.byType(SwitchListTile), findsNothing);
        expect(find.text('Compartir historial con mi PF'), findsNothing);
      },
    );

    testWidgets(
      'pending link → informational text NOT shown (label is active-only)',
      (tester) async {
        await tester.pumpWidget(_wrap(
          const AthleteCoachView(),
          overrides: [
            currentAthleteLinkProvider.overrideWith((ref) =>
                Stream.value(_makeLink(status: TrainerLinkStatus.pending))),
            userPublicProfileProvider('trainer-1')
                .overrideWith((ref) => Stream.value(_makePub())),
          ],
        ));
        await tester.pumpAndSettle();

        expect(
          find.text('Tu PF puede ver tu historial de entrenamiento.'),
          findsNothing,
        );
      },
    );
  });

  // ── Unread dot on coach card (athlete side) ────────────────────────────────

  group('AthleteCoachView — unread dot on coach card', () {
    testWidgets(
        'hasUnreadFromProvider(trainerId) true → unread dot on coach card',
        (tester) async {
      const trainerId = 'trainer-1';
      await tester.pumpWidget(_wrap(
        const AthleteCoachViewTestHarness(),
        overrides: [
          currentAthleteLinkProvider.overrideWith(
              (ref) => Stream.value(_makeLink(trainerId: trainerId))),
          userPublicProfileProvider(trainerId)
              .overrideWith((ref) => Stream.value(_makePub())),
          hasUnreadFromProvider(trainerId).overrideWith((ref) => true),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unread-dot-trainer-1')), findsOneWidget);
    });

    testWidgets(
        'hasUnreadFromProvider(trainerId) false → no unread dot on coach card',
        (tester) async {
      const trainerId = 'trainer-1';
      await tester.pumpWidget(_wrap(
        const AthleteCoachViewTestHarness(),
        overrides: [
          currentAthleteLinkProvider.overrideWith(
              (ref) => Stream.value(_makeLink(trainerId: trainerId))),
          userPublicProfileProvider(trainerId)
              .overrideWith((ref) => Stream.value(_makePub())),
          hasUnreadFromProvider(trainerId).overrideWith((ref) => false),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unread-dot-trainer-1')), findsNothing);
    });
  });
}
