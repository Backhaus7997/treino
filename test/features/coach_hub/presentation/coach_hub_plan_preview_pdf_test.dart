// La vista previa del Coach Hub con un borrador de PDF (sin alumno dueño):
// muestra lo que suma el PDF (texto fuente, alternativa, avisos, semanas),
// no pliega las filas resueltas, y asigna a VARIOS alumnos registrando los
// alias con la asignación final.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/application/cf_providers.dart';
import 'package:treino/features/coach_hub/application/plan_import_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/domain/routine.dart';

import 'periodized_draft_fixtures.dart';

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockCallable extends Mock implements HttpsCallable {}

class _MockResult extends Mock implements HttpsCallableResult<dynamic> {}

TrainerLink _link(String athleteId) => TrainerLink(
      id: 'link-$athleteId',
      trainerId: kTrainerUid,
      athleteId: athleteId,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  useTallSurface();

  setUpAll(() => registerFallbackValue(
        const Routine(
            id: '', name: '', level: ExperienceLevel.beginner, days: []),
      ));

  late MockRoutineRepo repo;
  late List<Routine> creadas;
  late List<Map<String, dynamic>> aliases;
  late _MockFunctions functions;

  setUp(() {
    repo = MockRoutineRepo();
    creadas = [];
    aliases = [];
    when(() => repo.createAssigned(any())).thenAnswer((inv) async {
      final routine = inv.positionalArguments.first as Routine;
      creadas.add(routine);
      return routine.copyWith(id: 'r-${routine.assignedTo}');
    });
    functions = _MockFunctions();
    final addAlias = _MockCallable();
    when(() => functions.httpsCallable('addAlias')).thenReturn(addAlias);
    when(() => addAlias.call(any())).thenAnswer((inv) async {
      aliases.add(Map<String, dynamic>.from(
          inv.positionalArguments.single as Map<String, dynamic>));
      return _MockResult();
    });
  });

  /// La vista previa con [pdfDraft] y dos alumnos activos: Ana y Bruno.
  Future<void> pump(WidgetTester tester) => pumpPreview(
        tester,
        pdfDraft(),
        repo,
        extra: [
          cloudFunctionsProvider.overrideWithValue(functions),
          trainerLinksStreamProvider.overrideWith(
            (ref) => Stream.value([_link(kAthleteId), _link('ath-2')]),
          ),
          userPublicProfileProvider('ath-2').overrideWith(
            (ref) => Stream.value(
              const UserPublicProfile(uid: 'ath-2', displayName: 'Bruno'),
            ),
          ),
        ],
      );

  testWidgets(
      'muestra lo del PDF: texto fuente en cada fila (nada plegado), '
      'alternativa, avisos, semanas y el botón en bloque', (tester) async {
    await pump(tester);

    // Dos filas, dos «Ver texto del PDF»: la resuelta NO se pliega en el
    // Hub (`collapseResolved` es de mobile).
    expect(find.text('Ver texto del PDF'), findsNWidgets(2));
    expect(find.text('Sentadilla'), findsOneWidget);
    expect(find.text('Sugerencia: Remo con barra'), findsOneWidget);
    expect(find.text('Alternativa: Remo con mancuerna'), findsOneWidget);
    expect(find.text('Usar alternativa'), findsOneWidget);
    expect(find.text('Confirmar la sugerencia'), findsOneWidget);
    expect(find.textContaining(kPdfWarning), findsOneWidget);
    expect(find.text('SEMANA 2'), findsOneWidget);

    await tester.tap(find.text('Ver texto del PDF').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Remo barra 1x10 / 1x12'), findsOneWidget);
  });

  testWidgets(
      '«Usar alternativa» y asignar a DOS alumnos: una rutina por alumno y '
      'el alias de la alternativa, una vez', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Usar alternativa'));
    await tester.pumpAndSettle();
    expect(find.text('Remo con mancuerna'), findsOneWidget);
    expect(find.text('Confirmar la sugerencia'), findsNothing);

    await tester.tap(find.text('Ana'));
    await tester.pump();
    await tester.tap(find.text('Bruno'));
    await tester.pump();
    await tester.tap(find.text('ASIGNAR PLAN A 2 ATLETAS'));
    await tester.pumpAndSettle();

    expect(creadas.map((r) => r.assignedTo),
        unorderedEquals([kAthleteId, 'ath-2']));
    for (final r in creadas) {
      expect(r.assignedBy, kTrainerUid);
      expect(r.name, 'plan fuerza');
      expect(r.numWeeks, 2);
      final ids = [
        for (final d in r.days)
          for (final s in d.slots) s.exerciseId,
      ];
      expect(ids, ['sq', 'rm']);
    }
    expect(aliases, [
      {'exerciseId': 'rm', 'alias': 'Remo barra'},
    ]);
    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets('«Confirmar la sugerencia» en bloque y asignar a los dos',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Confirmar la sugerencia'));
    await tester.pumpAndSettle();
    expect(find.text('Remo con barra'), findsOneWidget);

    await tester.tap(find.text('Ana'));
    await tester.pump();
    await tester.tap(find.text('Bruno'));
    await tester.pump();
    await tester.tap(find.text('ASIGNAR PLAN A 2 ATLETAS'));
    await tester.pumpAndSettle();

    expect(creadas, hasLength(2));
    expect(aliases, [
      {'exerciseId': 'rb', 'alias': 'Remo barra'},
    ]);
    final container =
        ProviderScope.containerOf(tester.element(find.text('DASHBOARD')));
    expect(container.read(periodizedImportProvider), isNull);
  });
}
