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
import 'package:go_router/go_router.dart';
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

/// La hoja de límite del plan free. Se identifica por el grabber porque es la
/// única parte de la hoja que no depende del motivo que la abrió.
const sheet = Key('free_plan_limit_grabber');

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

UserProfile _profile(UserRole role, [String? activeRoutineId]) => UserProfile(
      uid: _athlete,
      email: 'a@treino.app',
      displayName: 'Ana',
      role: role,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      activeRoutineId: activeRoutineId,
    );

Future<void> _pump(
  WidgetTester tester,
  Routine routine, {
  UserRole role = UserRole.athlete,
  String? uid = _athlete,
  String? activeRoutineId,
  bool? paywallEnabled,
  AthleteEntitlement? entitlement,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        routineByIdStreamProvider('r-1')
            .overrideWith((ref) => Stream.value(routine)),
        currentUidProvider.overrideWithValue(uid),
        userProfileProvider.overrideWith(
          (ref) => Stream.value(_profile(role, activeRoutineId)),
        ),
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

/// Igual que [_pump] pero con un router de verdad, y devuelve a dónde se
/// navegó (o `null` si no se navegó).
///
/// Hace falta para el gate de EMPEZAR y sólo ahí: los demás tests miran íconos
/// y hojas, que no necesitan rutas. Acá la aserción ES la navegación — que un
/// alumno free NO llegue a `/workout/session/...` sobre una plantilla paga, y
/// que sí llegue sobre una de principiante. Sin router, el caso negativo no se
/// puede distinguir de "el botón no hizo nada".
Future<String? Function()> _pumpConRouter(
  WidgetTester tester,
  Routine routine, {
  bool? paywallEnabled,
  AthleteEntitlement? entitlement,
}) async {
  String? pushed;
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const RoutineDetailScreen(routineId: 'r-1'),
      ),
      GoRoute(
        path: '/workout/session/:routineId/:dayNumber',
        builder: (_, state) {
          pushed = state.matchedLocation;
          return const Scaffold(body: Center(child: Text('session-stub')));
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        routineByIdStreamProvider('r-1')
            .overrideWith((ref) => Stream.value(routine)),
        currentUidProvider.overrideWithValue(_athlete),
        userProfileProvider.overrideWith(
          (ref) => Stream.value(_profile(UserRole.athlete)),
        ),
        if (paywallEnabled != null)
          athletePaywallEnabledProvider.overrideWithValue(paywallEnabled),
        if (entitlement != null)
          athleteEntitlementProvider.overrideWithValue(entitlement),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return () => pushed;
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
    /// El ícono del chip dice el estado sin necesidad de tocarlo: candado
    /// cuando está bloqueado, copiar cuando no.
    ///
    /// Se assertea así y no con un tap en los casos NO bloqueados porque ese
    /// camino navega con `context.push`, y este harness monta la pantalla sin
    /// router — el tap explotaría por el andamiaje del test, no por el código.
    IconData iconoDelChip(WidgetTester tester) =>
        (tester.widget<IconButton>(find.byKey(_chip)).icon as Icon).icon!;

    testWidgets('alumno free: el chip sigue ahí y abre la hoja',
        (tester) async {
      await _pump(
        tester,
        _routine(source: RoutineSource.system, isPremium: true),
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );

      expect(find.byKey(_chip), findsOneWidget,
          reason:
              'esconderlo dejaría al alumno sin saber que la función existe');
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
          reason:
              'con derecho, la plantilla paga se copia como cualquier otra');
    });

    testWidgets('plantilla GRATIS: copiarla también es del plan pago',
        (tester) async {
      // Este test afirmaba lo contrario —"las 3 de principiante quedan libres,
      // con o sin paywall"— y esa expectativa estaba mal por dos motivos
      // independientes. Se deja escrito porque el error es fácil de repetir.
      //
      // 1. La spec le da fila PROPIA y sin calificar por nivel:
      //    `docs/paywall-alumno-suelto.md` §4, "Editar / personalizar una
      //    plantilla del catálogo | free: no | pago: sí". Seguir una de
      //    principiante es gratis; COPIARLA no. Son dos filas distintas de la
      //    misma tabla, y el gate viejo leía una sola.
      //
      // 2. Cuando esto se escribió había ADEMÁS un motivo de forma: las tres
      //    plantillas de principiante tienen 3 días
      //    (`docs/video-catalog-audit/improved-templates.json`) contra un
      //    `kFreeMaxRoutineDays` que entonces valía 2, así que "copiar gratis"
      //    terminaba siempre igual — el alumno cargaba todo el editor, tocaba
      //    Guardar, y `firestore.rules` lo rebotaba con "No tenés permisos.
      //    Recargá la app.".
      //
      //    **Ese segundo motivo YA NO EXISTE**: el tope pasó a 3 justamente
      //    para disolver esa incoherencia, y hoy una copia de 3 días entra en
      //    la forma free. Se deja escrito porque explica de dónde salió el
      //    gate, pero quien lea esto tiene que saber que lo único que lo
      //    sostiene ahora es el punto 1 — la política. Si mañana el producto
      //    abre personalizar, no queda ninguna deuda de forma atrás.
      await _pump(
        tester,
        _routine(source: RoutineSource.system),
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );

      expect(iconoDelChip(tester), TreinoIcon.lock,
          reason: 'personalizar CUALQUIER plantilla del catálogo es plan pago');

      await tester.tap(find.byKey(_chip));
      await tester.pumpAndSettle();
      expect(find.byKey(sheet), findsOneWidget,
          reason: 'se frena en la ENTRADA, no al guardar: si no, pierde todo '
              'el trabajo contra un mensaje que no explica nada');
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

  // ── "Seguir esta plantilla" (§4.1: seguir sin copiar) ─────────────────────
  //
  // La otra mitad de "Usar como base". Copiar es "quiero MI versión de esto";
  // seguir es "quiero hacer esto tal cual", sin consumir cupo de rutinas
  // propias ni heredar los días de la plantilla.
  group('seguir una plantilla sin copiarla', () {
    const seguir = Key('routine_follow_template');

    testWidgets('aparece sobre una plantilla del sistema', (tester) async {
      await _pump(tester, _routine(source: RoutineSource.system));
      expect(find.byKey(seguir), findsOneWidget);
    });

    testWidgets('NO aparece sobre una plantilla publicada por un PF',
        (tester) async {
      // Se puede copiar pero no seguir: su dueño puede despublicarla y el
      // marcador quedaría apuntando a la nada sin que el atleta hiciera nada.
      await _pump(
        tester,
        _routine(
          source: RoutineSource.trainerTemplate,
          visibility: RoutineVisibility.public,
          assignedBy: 'trainer-1',
        ),
      );
      expect(find.byKey(seguir), findsNothing);
      expect(find.byKey(_chip), findsOneWidget,
          reason: 'copiarla sí se puede — son dos permisos distintos');
    });

    testWidgets('NO aparece sobre un plan del PF ni sobre la rutina propia',
        (tester) async {
      await _pump(
        tester,
        _routine(
          source: RoutineSource.trainerAssigned,
          assignedBy: 'trainer-1',
          assignedTo: _athlete,
        ),
      );
      expect(find.byKey(seguir), findsNothing);

      await _pump(
        tester,
        _routine(source: RoutineSource.userCreated, createdBy: _athlete),
      );
      expect(find.byKey(seguir), findsNothing);
    });

    testWidgets('el PF no la ve: no entrena en la app', (tester) async {
      await _pump(
        tester,
        _routine(source: RoutineSource.system),
        role: UserRole.trainer,
      );
      expect(find.byKey(seguir), findsNothing);
    });

    testWidgets('si ya la sigue, el botón queda deshabilitado', (tester) async {
      // Para cambiar de rutina activa se elige OTRA. Un botón que la desactiva
      // dejaría al atleta sin ninguna, que no es algo que haya pedido.
      await _pump(
        tester,
        _routine(source: RoutineSource.system),
        activeRoutineId: 'r-1',
      );
      final boton = tester.widget<IconButton>(find.byKey(seguir));
      expect(boton.onPressed, isNull);
      expect((boton.icon as Icon).icon, TreinoIcon.check);
    });

    testWidgets('si no la sigue, el botón está habilitado', (tester) async {
      await _pump(
        tester,
        _routine(source: RoutineSource.system),
        activeRoutineId: 'otra-cosa',
      );
      final boton = tester.widget<IconButton>(find.byKey(seguir));
      expect(boton.onPressed, isNotNull);
      expect((boton.icon as Icon).icon, TreinoIcon.play);
    });

    // ── El gate del catálogo pago sobre SEGUIR ───────────────────────────
    //
    // Este era el agujero: `_follow` escribía `activeRoutineId` sin consultar
    // entitlement, así que el candado tapaba la grilla y "Usar como base" y
    // dejaba abierta la puerta del medio.

    testWidgets('plantilla PAGA + alumno free: candado y hoja, no la sigue',
        (tester) async {
      await _pump(
        tester,
        _routine(source: RoutineSource.system, isPremium: true),
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );

      final boton = tester.widget<IconButton>(find.byKey(seguir));
      expect((boton.icon as Icon).icon, TreinoIcon.lock);

      await tester.tap(find.byKey(seguir));
      await tester.pumpAndSettle();
      expect(find.byKey(sheet), findsOneWidget);
    });

    testWidgets('plantilla de PRINCIPIANTE: seguirla sigue siendo gratis',
        (tester) async {
      // La contracara de "copiarla es pago". Si este test se pusiera rojo
      // junto con el de copiar, el catálogo quedaría cerrado entero para el
      // free — que es exactamente lo que la spec NO quiere (§3.3).
      await _pump(
        tester,
        _routine(source: RoutineSource.system),
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );

      final boton = tester.widget<IconButton>(find.byKey(seguir));
      expect((boton.icon as Icon).icon, TreinoIcon.play);
      expect(boton.onPressed, isNotNull);
    });

    testWidgets('con derecho, la plantilla paga se sigue normal',
        (tester) async {
      await _pump(
        tester,
        _routine(source: RoutineSource.system, isPremium: true),
        paywallEnabled: true,
        entitlement: AthleteEntitlement.entitled,
      );

      final boton = tester.widget<IconButton>(find.byKey(seguir));
      expect((boton.icon as Icon).icon, TreinoIcon.play);
      expect(boton.onPressed, isNotNull);
    });
  });

  // ── EMPEZAR (§4.1.1: el camino corto) ─────────────────────────────────────
  //
  // Seguir NO es requisito para entrenar: `_startActionVisible` devolvía `true`
  // incondicional sobre una plantilla del sistema, así que gatear sólo "Seguir"
  // dejaba el camino corto abierto — se entra al detalle y se toca EMPEZAR.
  //
  // El gate va sobre la ACCIÓN y nunca sobre la VISIBILIDAD, por #641: un guard
  // que esconda el botón encoge el ocupante mientras el padre sigue reservando
  // la altura de la barra fijada.
  group('EMPEZAR sobre una plantilla del catálogo', () {
    testWidgets('plantilla PAGA + alumno free: hoja, y NO entra a la sesión',
        (tester) async {
      final pushed = await _pumpConRouter(
        tester,
        _routine(source: RoutineSource.system, isPremium: true),
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );

      expect(find.text('EMPEZAR'), findsOneWidget,
          reason: 'esconderlo rompería el slot fijado (#641) y además no le '
              'enseñaría a nadie que la función existe');

      await tester.tap(find.text('EMPEZAR'));
      await tester.pumpAndSettle();

      expect(find.byKey(sheet), findsOneWidget);
      expect(pushed(), isNull,
          reason: 'este era el camino corto: sin gatear acá, alcanzaba con '
              'entrar al detalle y tocar EMPEZAR');
    });

    testWidgets('plantilla de PRINCIPIANTE: entrenarla es gratis',
        (tester) async {
      final pushed = await _pumpConRouter(
        tester,
        _routine(source: RoutineSource.system),
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );

      await tester.tap(find.text('EMPEZAR'));
      await tester.pumpAndSettle();

      expect(find.byKey(sheet), findsNothing,
          reason: 'entrenar el catálogo de principiante es gratis (§3.3)');
      expect(pushed(), '/workout/session/r-1/1');
    });

    testWidgets('paywall apagado: ni la plantilla paga se gatea',
        (tester) async {
      final pushed = await _pumpConRouter(
        tester,
        _routine(source: RoutineSource.system, isPremium: true),
        paywallEnabled: false,
        entitlement: AthleteEntitlement.free,
      );

      await tester.tap(find.text('EMPEZAR'));
      await tester.pumpAndSettle();

      expect(find.byKey(sheet), findsNothing);
      expect(pushed(), '/workout/session/r-1/1');
    });

    testWidgets('con derecho, la plantilla paga se entrena normal',
        (tester) async {
      final pushed = await _pumpConRouter(
        tester,
        _routine(source: RoutineSource.system, isPremium: true),
        paywallEnabled: true,
        entitlement: AthleteEntitlement.entitled,
      );

      await tester.tap(find.text('EMPEZAR'));
      await tester.pumpAndSettle();

      expect(pushed(), '/workout/session/r-1/1');
    });
  });
}
