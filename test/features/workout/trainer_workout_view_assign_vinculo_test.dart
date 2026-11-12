import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinkRepositoryProvider, trainerLinksStreamProvider;
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/trainer_workout_view.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../helpers/trainer_links.dart';

/// ASIGNAR una plantilla (#1695): el picker ya filtra por vínculo vivo, pero la
/// hoja pudo quedar abierta mientras el alumno cortaba el vínculo. La última
/// barrera se lo pregunta al SERVIDOR un paso antes de escribir.

const _uid = 'trainer-1';
const _template = Routine(
  id: 'tpl-1',
  name: 'Plantilla PPL',
  split: 'PPL',
  level: ExperienceLevel.beginner,
  days: [],
  source: RoutineSource.trainerTemplate,
  assignedBy: _uid,
  visibility: RoutineVisibility.private,
);

/// Monta la vista, toca ASIGNAR y elige al alumno del picker; devuelve cuántas
/// copias asignadas quedaron escritas. El roster (la hoja) tiene vivo a `ath-1`.
Future<int> _asignar(
  WidgetTester tester,
  TrainerLinkRepository server,
) async {
  final firestore = FakeFirebaseFirestore();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWith((ref) => _uid),
      trainerLinkRepositoryProvider.overrideWithValue(server),
      trainerLinksStreamProvider
          .overrideWith((ref) => Stream.value([linkDe('ath-1')])),
      trainerTemplatesStreamProvider(_uid)
          .overrideWith((ref) => Stream.value([_template])),
      userPublicProfileProvider(_uid).overrideWith((ref) => Stream.value(
          const UserPublicProfile(
              uid: _uid,
              displayName: 'Coach Vic',
              displayNameLowercase: 'coach vic'))),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: const Scaffold(body: TrainerWorkoutView()),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('ASIGNAR'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Alumno'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final asignadas = await firestore
      .collection('routines')
      .where('assignedTo', isEqualTo: 'ath-1')
      .get();
  return asignadas.docs.length;
}

void main() {
  for (final estado in [TrainerLinkStatus.active, TrainerLinkStatus.paused]) {
    testWidgets('vínculo ${estado.name} en el servidor: asigna',
        (tester) async {
      final server = await repoConVinculos([linkDe('ath-1', status: estado)]);

      expect(await _asignar(tester, server), 1);
      expect(find.text('Plantilla asignada al alumno.'), findsOneWidget);
    });
  }

  testWidgets('el vínculo terminó con la hoja abierta: no escribe',
      (tester) async {
    final server = await repoConVinculos(
        [linkDe('ath-1', status: TrainerLinkStatus.terminated)]);

    expect(await _asignar(tester, server), 0);
    expect(
        find.text('Este alumno no tiene un vínculo vigente con vos, así que '
            'no podés asignarle una rutina.'),
        findsOneWidget);
  });

  testWidgets('el servidor no responde: no escribe y avisa', (tester) async {
    expect(await _asignar(tester, repoQueNoResponde()), 0);
    expect(find.text('No pudimos asignar la plantilla.'), findsOneWidget);
  });
}
