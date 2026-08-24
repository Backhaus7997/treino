// RoutineDetailScreen — chip "Usar como base" (#647).
//
// La acción existe para cerrar el binario que reportaron las pruebas de
// usabilidad (plantilla tal cual ↔ pantalla en blanco), pero NO puede
// ofrecerse sobre cualquier rutina. Lo que estos tests fijan es exactamente
// dónde aparece y dónde no:
//
//   • plantilla del sistema                       → SÍ
//   • plantilla de PF PUBLICADA a la comunidad    → SÍ (publicar es el opt-in)
//   • plantilla de PF privada                     → NO (nunca estuvo en oferta)
//   • plan ASIGNADO por el PF                     → NO (es una prescripción;
//     copiarlo la convierte en sugerencia a espaldas del entrenador)
//   • rutina propia del atleta                    → NO (ya tiene "editar")
//   • viewer con rol trainer                      → NO (el PF no entrena acá)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

const _athlete = 'athlete-1';
const _chip = Key('routine_use_as_base');

const _day = RoutineDay(
  dayNumber: 1,
  name: 'Empuje',
  slots: [
    RoutineSlot(
      exerciseId: 'bench-press',
      exerciseName: 'Press de Banca',
      muscleGroup: 'chest',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 90,
    ),
  ],
);

Routine _routine({
  required RoutineSource source,
  RoutineVisibility visibility = RoutineVisibility.public,
  String? assignedBy,
  String? assignedTo,
  String? createdBy,
}) =>
    Routine(
      id: 'r-1',
      name: 'Push Pull Legs',
      split: 'PPL',
      level: ExperienceLevel.beginner,
      days: const [_day],
      source: source,
      visibility: visibility,
      assignedBy: assignedBy,
      assignedTo: assignedTo,
      createdBy: createdBy,
    );

UserProfile _profile(UserRole role) => UserProfile(
      uid: _athlete,
      email: 'a@treino.app',
      displayName: 'Ana',
      role: role,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Future<void> _pump(
  WidgetTester tester,
  Routine routine, {
  UserRole role = UserRole.athlete,
  String? uid = _athlete,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        routineByIdStreamProvider('r-1')
            .overrideWith((ref) => Stream.value(routine)),
        currentUidProvider.overrideWithValue(uid),
        userProfileProvider
            .overrideWith((ref) => Stream.value(_profile(role))),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: RoutineDetailScreen(routineId: 'r-1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('aparece sobre lo que el atleta puede copiar', () {
    testWidgets('plantilla del sistema', (tester) async {
      await _pump(tester, _routine(source: RoutineSource.system));
      expect(find.byKey(_chip), findsOneWidget);
    });

    testWidgets('plantilla de PF publicada a la comunidad', (tester) async {
      await _pump(
        tester,
        _routine(
          source: RoutineSource.trainerTemplate,
          visibility: RoutineVisibility.public,
          assignedBy: 'trainer-1',
        ),
      );
      expect(find.byKey(_chip), findsOneWidget);
    });
  });

  group('NO aparece sobre lo que no está en oferta', () {
    testWidgets('plantilla de PF privada', (tester) async {
      await _pump(
        tester,
        _routine(
          source: RoutineSource.trainerTemplate,
          visibility: RoutineVisibility.private,
          assignedBy: 'trainer-1',
        ),
      );
      expect(find.byKey(_chip), findsNothing);
    });

    testWidgets('plan asignado por el PF — es una prescripción', (tester) async {
      await _pump(
        tester,
        _routine(
          source: RoutineSource.trainerAssigned,
          visibility: RoutineVisibility.private,
          assignedBy: 'trainer-1',
          assignedTo: _athlete,
        ),
      );
      expect(find.byKey(_chip), findsNothing);
    });

    testWidgets('rutina propia del atleta — para eso está editar',
        (tester) async {
      await _pump(
        tester,
        _routine(
          source: RoutineSource.userCreated,
          visibility: RoutineVisibility.private,
          createdBy: _athlete,
        ),
      );
      expect(find.byKey(_chip), findsNothing);
    });
  });

  group('NO aparece para quien no puede tener rutinas propias', () {
    testWidgets('el PF no entrena en la app', (tester) async {
      await _pump(
        tester,
        _routine(source: RoutineSource.system),
        role: UserRole.trainer,
      );
      expect(find.byKey(_chip), findsNothing);
    });

    testWidgets('sin uid no hay dueño posible para la copia', (tester) async {
      await _pump(
        tester,
        _routine(source: RoutineSource.system),
        uid: null,
      );
      expect(find.byKey(_chip), findsNothing);
    });
  });
}
