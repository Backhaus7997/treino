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
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/paywall/application/athlete_entitlement_provider.dart';
import 'package:treino/features/paywall/domain/athlete_entitlement.dart';
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
  bool isPremium = false,
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
      isPremium: isPremium,
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
  bool? paywallEnabled,
  AthleteEntitlement? entitlement,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        routineByIdStreamProvider('r-1')
            .overrideWith((ref) => Stream.value(routine)),
        currentUidProvider.overrideWithValue(uid),
        userProfileProvider.overrideWith((ref) => Stream.value(_profile(role))),
        if (paywallEnabled != null)
          athletePaywallEnabledProvider.overrideWithValue(paywallEnabled),
        if (entitlement != null)
          athleteEntitlementProvider.overrideWithValue(entitlement),
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

    testWidgets('plan asignado por el PF — es una prescripción',
        (tester) async {
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

  // ── Catálogo pago (paywall del alumno suelto, spec §4.1.1) ────────────────
  //
  // Con `isPremium` el chip NO desaparece: cambia de significado. Sigue
  // visible —el candado de la grilla ya anticipó que esta plantilla es del
  // plan pago, y que el detalle no dijera nada sería la app cambiando de idea
  // entre dos pantallas— pero abre la hoja en vez de llevar al editor.
  group('plantilla paga del catálogo', () {
    const sheet = Key('free_plan_limit_grabber');

    /// El ícono del chip dice el estado sin necesidad de tocarlo: candado
    /// cuando está bloqueado, copiar cuando no.
    ///
    /// Se assertea así y no con un tap en los casos NO bloqueados porque ese
    /// camino navega con `context.push`, y este harness monta la pantalla sin
    /// router — el tap explotaría por el andamiaje del test, no por el código.
    IconData iconoDelChip(WidgetTester tester) =>
        (tester.widget<IconButton>(find.byKey(_chip)).icon as Icon).icon!;

    testWidgets('alumno free: el chip sigue ahí y abre la hoja', (tester) async {
      await _pump(
        tester,
        _routine(source: RoutineSource.system, isPremium: true),
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );

      expect(find.byKey(_chip), findsOneWidget,
          reason: 'esconderlo dejaría al alumno sin saber que la función existe');
      expect(iconoDelChip(tester), TreinoIcon.lock);

      await tester.tap(find.byKey(_chip));
      await tester.pumpAndSettle();
      expect(find.byKey(sheet), findsOneWidget);
    });

    testWidgets('alumno con derecho: la plantilla paga se copia normal',
        (tester) async {
      await _pump(
        tester,
        _routine(source: RoutineSource.system, isPremium: true),
        paywallEnabled: true,
        entitlement: AthleteEntitlement.entitled,
      );

      expect(iconoDelChip(tester), TreinoIcon.copy,
          reason: 'con derecho, la plantilla paga se copia como cualquier otra');
    });

    testWidgets('plantilla gratis: nada cambia aunque el paywall esté activo',
        (tester) async {
      await _pump(
        tester,
        _routine(source: RoutineSource.system),
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );

      expect(iconoDelChip(tester), TreinoIcon.copy,
          reason: 'las 3 de principiante quedan libres, con o sin paywall');
    });

    testWidgets('paywall apagado: ni la plantilla paga se gatea',
        (tester) async {
      // El estado en que esto shipea: `isPremium` ya viaja en los docs, pero
      // el flag apagado hace que no signifique nada todavía.
      await _pump(
        tester,
        _routine(source: RoutineSource.system, isPremium: true),
        paywallEnabled: false,
        entitlement: AthleteEntitlement.free,
      );

      expect(iconoDelChip(tester), TreinoIcon.copy);
      expect(find.byKey(sheet), findsNothing);
    });
  });
}
