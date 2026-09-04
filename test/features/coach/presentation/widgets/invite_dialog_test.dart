import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/invite_outcome.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/presentation/widgets/invite_dialog.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

class _MockRepo extends Mock implements TrainerLinkRepository {}

TrainerLink _link(String trainerId) => TrainerLink(
      id: 'link-viejo',
      trainerId: trainerId,
      athleteId: 'atleta',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime(2026),
    );

Future<void> _pump(
  WidgetTester tester,
  InviteOutcome outcome, {
  required _MockRepo repo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('atleta'),
        trainerLinkRepositoryProvider.overrideWithValue(repo),
        // El nombre es decorativo: el diálogo tiene que andar sin él.
        userPublicProfileProvider('pf-nuevo').overrideWith((_) => Stream.value(null)),
        userPublicProfileProvider('pf-1').overrideWith((_) => Stream.value(null)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showInviteDialog(ctx, outcome),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(TrainerLinkStatus.pending);
  });

  group('caso D — ya vinculado con el MISMO PF', () {
    testWidgets('no ofrece vincular de nuevo ni toca el repositorio',
        (tester) async {
      final repo = _MockRepo();
      await _pump(tester, const InviteYaVinculado('pf-1'), repo: repo);

      expect(find.text('YA ESTÁN VINCULADOS'), findsOneWidget);
      // El corazón del caso D: abrir el link dos veces no puede duplicar nada.
      verifyNever(() => repo.request(
            trainerId: any(named: 'trainerId'),
            athleteId: any(named: 'athleteId'),
          ));
      verifyNever(() => repo.terminate(any(), reason: any(named: 'reason')));
    });
  });

  group('caso E — vinculado a OTRO PF', () {
    testWidgets('Cancelar no modifica NINGUNA asociación', (tester) async {
      final repo = _MockRepo();
      await _pump(
        tester,
        InviteRequiereDesvincular(
          nuevoTrainerId: 'pf-nuevo',
          vinculoActual: _link('pf-viejo'),
        ),
        repo: repo,
      );

      expect(find.text('YA TENÉS ENTRENADOR'), findsOneWidget);
      await tester.tap(find.byKey(const Key('invite_dialog_cancel')));
      await tester.pumpAndSettle();

      // Lo más importante del caso E. Un alumno que cancela tiene que quedar
      // exactamente como estaba.
      verifyNever(() => repo.terminate(any(), reason: any(named: 'reason')));
      verifyNever(() => repo.request(
            trainerId: any(named: 'trainerId'),
            athleteId: any(named: 'athleteId'),
          ));
      expect(find.text('YA TENÉS ENTRENADOR'), findsNothing, reason: 'cierra');
    });

    testWidgets('Desvincular y continuar: termina PRIMERO, pide después',
        (tester) async {
      final repo = _MockRepo();
      when(() => repo.terminate(any(), reason: any(named: 'reason')))
          .thenAnswer((_) async {});
      when(() => repo.request(
            trainerId: any(named: 'trainerId'),
            athleteId: any(named: 'athleteId'),
          )).thenAnswer((_) async => _link('pf-nuevo'));

      await _pump(
        tester,
        InviteRequiereDesvincular(
          nuevoTrainerId: 'pf-nuevo',
          vinculoActual: _link('pf-viejo'),
        ),
        repo: repo,
      );
      await tester.tap(find.byKey(const Key('invite_dialog_confirm')));
      await tester.pumpAndSettle();

      // El orden NO es intercambiable: primero se libera el cupo, después se
      // pide el nuevo. Al revés, el request choca con el vínculo vivo.
      verifyInOrder([
        () => repo.terminate('link-viejo', reason: 'switched_trainer'),
        () => repo.request(trainerId: 'pf-nuevo', athleteId: 'atleta'),
      ]);
    });

    testWidgets('si el backend falla NO dice que se vinculó', (tester) async {
      final repo = _MockRepo();
      when(() => repo.terminate(any(), reason: any(named: 'reason')))
          .thenThrow(StateError('sin permisos'));

      await _pump(
        tester,
        InviteRequiereDesvincular(
          nuevoTrainerId: 'pf-nuevo',
          vinculoActual: _link('pf-viejo'),
        ),
        repo: repo,
      );
      await tester.tap(find.byKey(const Key('invite_dialog_confirm')));
      await tester.pumpAndSettle();

      // Dejar al alumno creyendo que se vinculó cuando el backend rechazó es
      // el peor final posible: espera rutinas de alguien que no lo tiene.
      expect(find.byKey(const Key('invite_dialog_error')), findsOneWidget);
      expect(find.text('YA TENÉS ENTRENADOR'), findsOneWidget,
          reason: 'el diálogo NO se cierra: el alumno tiene que ver el error');
      verifyNever(() => repo.request(
            trainerId: any(named: 'trainerId'),
            athleteId: any(named: 'athleteId'),
          ));
    });

    testWidgets('no se cierra tocando el fondo', (tester) async {
      final repo = _MockRepo();
      await _pump(
        tester,
        InviteRequiereDesvincular(
          nuevoTrainerId: 'pf-nuevo',
          vinculoActual: _link('pf-viejo'),
        ),
        repo: repo,
      );

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Cambiar de entrenador no se decide con un toque distraído.
      expect(find.text('YA TENÉS ENTRENADOR'), findsOneWidget);
    });
  });

  group('caso C — sin PF', () {
    testWidgets('vincula sin terminar nada', (tester) async {
      final repo = _MockRepo();
      when(() => repo.request(
            trainerId: any(named: 'trainerId'),
            athleteId: any(named: 'athleteId'),
          )).thenAnswer((_) async => _link('pf-nuevo'));

      await _pump(tester, const InvitePuedeVincular('pf-nuevo'), repo: repo);
      await tester.tap(find.byKey(const Key('invite_dialog_confirm')));
      await tester.pumpAndSettle();

      verify(() => repo.request(trainerId: 'pf-nuevo', athleteId: 'atleta'))
          .called(1);
      verifyNever(() => repo.terminate(any(), reason: any(named: 'reason')));
    });

    testWidgets('"Ahora no" no vincula nada', (tester) async {
      final repo = _MockRepo();
      await _pump(tester, const InvitePuedeVincular('pf-nuevo'), repo: repo);

      await tester.tap(find.byKey(const Key('invite_dialog_cancel')));
      await tester.pumpAndSettle();

      verifyNever(() => repo.request(
            trainerId: any(named: 'trainerId'),
            athleteId: any(named: 'athleteId'),
          ));
    });
  });
}
