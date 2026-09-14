// La pantalla de autoservicio del paywall: qué alumnos quedaron fuera del cupo
// del PF y qué significa eso.
//
// El grueso de estos tests es sobre el COPY, y no por prolijidad. Hay dos
// mentiras posibles y las dos son caras:
//
//  1. Decirle al PF que su plan lo frenó cuando no se puede probar. Y su
//     simétrica, que es peor porque suena tranquilizadora: decirle que el cupo
//     NO lo explica cuando tampoco se puede probar.
//  2. Escribirlo de forma que entienda que el ALUMNO perdió algo. No lo
//     perdió: conserva rutinas, historial y chat. La fricción la come el
//     entrenador, nunca el alumno.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/blocked_athletes_providers.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/blocked_students_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/coach_hub/presentation/widgets/skeleton/coach_hub_skeleton.dart';

UserProfile _trainer({TrainerSubscription? subscription}) => UserProfile(
      uid: 'pf1',
      email: 'pf@test.com',
      displayName: 'Profe',
      role: UserRole.trainer,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      subscription: subscription,
    );

TrainerSubscription _sub(
  SubscriptionTier tier, {
  SubscriptionStatus status = SubscriptionStatus.active,
  DateTime? currentPeriodEnd,
}) =>
    TrainerSubscription(
      tier: tier,
      status: status,
      currentPeriodEnd: currentPeriodEnd,
    );

/// En qué estado está el doc del PF. No alcanza con «hay o no hay
/// suscripción»: el perfir que TODAVÍA no llegó y el que llegó vacío tienen
/// que decir cosas distintas, y el bug que estos tests cierran era
/// confundirlos.
enum _ProfileState {
  /// El stream emitió el perfil.
  loaded,

  /// El stream todavía no emitió nada.
  loading,

  /// El stream emitió `null`: sin sesión, o el stream de auth erroró.
  missing,
}

/// Monta la pantalla dentro de un router mínimo — el CTA abre el paywall, que
/// a su vez puede hacer `context.push`.
Widget _harness({
  required AsyncValue<BlockedAthletes> blocked,
  TrainerSubscription? subscription,
  Map<String, UserPublicProfile> profiles = const {},
  _ProfileState profileState = _ProfileState.loaded,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const BlockedStudentsScreen()),
      GoRoute(
        path: '/ajustes',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('AJUSTES'))),
      ),
      GoRoute(
        path: '/facturacion/planes',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('PRICING'))),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      blockedAthletesProvider.overrideWith(
        // `overrideWith` de un StreamProvider quiere un Stream; un
        // `AsyncLoading` se representa con uno que nunca emite, y un error
        // con uno que sólo emite el error.
        (ref) => switch (blocked) {
          AsyncData(:final value) => Stream.value(value),
          AsyncError(:final error) => Stream<BlockedAthletes>.error(error),
          _ => const Stream<BlockedAthletes>.empty(),
        },
      ),
      userProfileProvider.overrideWith(
        (ref) => switch (profileState) {
          _ProfileState.loaded => Stream<UserProfile?>.value(
              _trainer(subscription: subscription),
            ),
          _ProfileState.missing => Stream<UserProfile?>.value(null),
          _ProfileState.loading => const Stream<UserProfile?>.empty(),
        },
      ),
      for (final key in _batchKeys(blocked))
        userPublicProfilesBatchProvider(key)
            .overrideWith((ref) async => profiles),
    ],
    child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
  );
}

/// La key del provider batcheado sale de los IDS BLOQUEADOS, no del mapa de
/// perfiles: es la que arma la pantalla (uids ordenados y unidos por comas), y
/// justamente los casos donde falta un perfil son los que tienen que seguir
/// matcheando el override.
List<String> _batchKeys(AsyncValue<BlockedAthletes> blocked) {
  final ids = blocked.valueOrNull?.ids;
  if (ids == null || ids.isEmpty) return const [];
  return [(ids.toList()..sort()).join(',')];
}

/// Todo el texto renderizado, aplanado. Los asserts de copy miran el conjunto:
/// da igual en qué widget cayó cada frase.
String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join(' | ');

void main() {
  group('BlockedStudentsScreen — estados', () {
    testWidgets('mientras carga la lista no afirma nada', (tester) async {
      await tester.pumpWidget(_harness(blocked: const AsyncLoading()));
      await tester.pump();

      expect(find.byType(CoachHubSkeleton), findsOneWidget);
      // Lo importante del loading: NO decir «ninguno» todavía. Un PF que llegó
      // acá porque algo le rebotó leería eso como «no es tu plan» y se iría.
      expect(_allText(tester), isNot(contains('NINGUNO')));
    });

    testWidgets('mientras el perfil no cargó tampoco afirma un plan', (
      tester,
    ) async {
      // `userProfileProvider` pasa por auth y por `UserRepository.watch`, que
      // descarta la primera snapshot de cache fría — o sea que la ventana no
      // es un frame, es una ida y vuelta de red. Con un `?? free` en el medio,
      // un Plan 3 leía durante esa ventana «tu plan Free incluye 2 alumnos» y
      // un botón para comprarle el Plan 1.
      await tester.pumpWidget(
        _harness(
          blocked: const AsyncData(BlockedAthletes.published({'a1'})),
          profileState: _ProfileState.loading,
        ),
      );
      await tester.pump();

      expect(find.byType(CoachHubSkeleton), findsOneWidget);
      final text = _allText(tester);
      expect(text, isNot(contains('Free')));
      expect(text, isNot(contains('2 alumnos')));
      expect(find.text('AMPLIAR MI PLAN'), findsNothing);
    });

    testWidgets('un read fallido se muestra, no se traga como lista vacía', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(blocked: AsyncError(Exception('boom'), StackTrace.empty)),
      );
      await tester.pumpAndSettle();

      expect(find.text('NO PUDIMOS CARGAR TU CUPO'), findsOneWidget);
      // Un error que se dibuja como «no tenés ninguno» sería la respuesta
      // opuesta a la verdadera.
      expect(_allText(tester), isNot(contains('NINGUNO')));
    });

    testWidgets('sin alumnos afuera, descarta el cupo como causa', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          blocked: const AsyncData(BlockedAthletes.published(<String>{})),
          subscription: _sub(SubscriptionTier.plan1),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NINGUNO'), findsOneWidget);
      final text = _allText(tester);
      expect(text, contains('Plan 1'));
      // El valor real del estado vacío: dejar de mandarlo a mirar facturación.
      expect(text, contains('no fue por el cupo de tu plan'));
    });

    testWidgets('lista SIN PUBLICAR no se dibuja como «ninguno»', (
      tester,
    ) async {
      // El caso permanente de hoy: `blockedAthleteIds` sólo existe después de
      // que la CF corre sobre ese PF. Sin el campo no se sabe nada, y «no fue
      // por el cupo de tu plan» es la afirmación más cara de la pantalla —
      // despide al PF diciéndole que deje de mirar el único lugar donde podía
      // estar la respuesta.
      await tester.pumpWidget(
        _harness(
          blocked: const AsyncData(BlockedAthletes.unpublished),
          subscription: _sub(SubscriptionTier.plan1),
        ),
      );
      await tester.pumpAndSettle();

      final text = _allText(tester);
      expect(text, isNot(contains('NINGUNO')));
      expect(text, isNot(contains('no fue por el cupo de tu plan')));
      expect(find.text('TODAVÍA NO LO SABEMOS'), findsOneWidget);
    });

    testWidgets(
      'vacío con la suscripción caída NO descarta el cupo',
      (tester) async {
        // Plan 2 pausado: el límite EFECTIVO ya cayó a Free (2), lo dice
        // `effective-limit.ts`. Hoy nadie quedó afuera, pero es el PF que MÁS
        // necesita mirar facturación — y la versión anterior de esta pantalla
        // le decía «tu plan incluye 15 alumnos, no fue por el cupo».
        await tester.pumpWidget(
          _harness(
            blocked: const AsyncData(BlockedAthletes.published(<String>{})),
            subscription: _sub(
              SubscriptionTier.plan2,
              status: SubscriptionStatus.paused,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final text = _allText(tester);
        expect(text, isNot(contains('no fue por el cupo de tu plan')));
        expect(text, isNot(contains('15 alumnos')));
        expect(text, contains('límite del plan Free'));
        expect(find.text('REGULARIZAR MI SUSCRIPCIÓN'), findsOneWidget);
      },
    );
  });

  group('BlockedStudentsScreen — con alumnos afuera del cupo', () {
    Future<void> pumpTwo(
      WidgetTester tester, {
      TrainerSubscription? subscription,
    }) async {
      await tester.pumpWidget(
        _harness(
          blocked: const AsyncData(BlockedAthletes.published({'a1', 'a2'})),
          subscription: subscription ?? _sub(SubscriptionTier.free),
          profiles: const {
            'a1': UserPublicProfile(uid: 'a1', displayName: 'Ana'),
            'a2': UserPublicProfile(uid: 'a2', displayName: 'Beto'),
          },
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lista a cada alumno por nombre', (tester) async {
      await pumpTwo(tester);

      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Beto'), findsOneWidget);
      expect(find.text('ALUMNOS EN SOLO LECTURA'), findsOneWidget);
    });

    testWidgets('nombra el plan, el cupo y cuántos quedaron afuera', (
      tester,
    ) async {
      await pumpTwo(tester);

      final text = _allText(tester);
      expect(text, contains('Free'));
      expect(text, contains('2 alumnos')); // el cupo de Free
      expect(text, contains('estos 2')); // cuántos quedaron afuera
    });

    testWidgets('no afirma una resta de cabezas que no cierra', (
      tester,
    ) async {
      // El tope es de CARGA PONDERADA, no de cabezas: un alumno pausado pesa
      // 0.5 (`weighted-load.ts`). Un PF con 9 alumnos y 6 pausados pesa 6.0 y
      // NO superó un tope de 7 — decirle «tu plan incluye 7 y hoy tenés más»
      // lo deja contando una resta que no cierra contra su propia lista.
      await pumpTwo(tester, subscription: _sub(SubscriptionTier.plan1));

      final text = _allText(tester);
      expect(text, isNot(contains('hoy tenés más')));
      expect(text, contains('superó ese cupo'));
      expect(text, contains('pausado cuenta mitad'));
    });

    testWidgets('dice explícitamente qué conserva el alumno', (tester) async {
      await pumpTwo(tester);

      // Es la primera pregunta que se hace el PF («¿qué perdió mi alumno?») y
      // la respuesta es NADA. Si esta frase se cae, el copy pasa a sugerir lo
      // contrario por omisión.
      final text = _allText(tester);
      expect(text, contains('siguen entrenando'));
      expect(text, contains('historial'));
      expect(text, contains('chat'));
    });

    testWidgets('el copy nunca sugiere que el alumno perdió algo', (
      tester,
    ) async {
      await pumpTwo(tester);

      final text = _allText(tester).toLowerCase();
      for (final lie in [
        'sin acceso',
        'perdió el acceso',
        'dado de baja',
        'lo eliminamos',
        'alumno bloqueado',
      ]) {
        expect(text, isNot(contains(lie)), reason: 'copy dice "$lie"');
      }
      // «Bloqueado» a secas se lee como un castigo AL ALUMNO. La etiqueta que
      // se muestra describe lo que le pasa al PF sobre él.
      expect(find.text('solo lectura'), findsNWidgets(2));
    });

    testWidgets('un perfil que no cargó no borra la fila', (tester) async {
      // El PF necesita ver que son N aunque falte un nombre; una fila que
      // desaparece le da un conteo equivocado.
      await tester.pumpWidget(
        _harness(
          blocked: const AsyncData(BlockedAthletes.published({'a1', 'a2'})),
          subscription: _sub(SubscriptionTier.free),
          profiles: const {
            'a1': UserPublicProfile(uid: 'a1', displayName: 'Ana'),
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Alumno'), findsOneWidget);
    });
  });

  group('BlockedStudentsScreen — la causa sólo se afirma si se puede probar',
      () {
    Future<void> pumpOne(
      WidgetTester tester, {
      TrainerSubscription? subscription,
      _ProfileState profileState = _ProfileState.loaded,
    }) async {
      await tester.pumpWidget(
        _harness(
          blocked: const AsyncData(BlockedAthletes.published({'a1'})),
          subscription: subscription,
          profileState: profileState,
          profiles: const {
            'a1': UserPublicProfile(uid: 'a1', displayName: 'Ana'),
          },
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('suscripción caída: habla de cobro, no de upsell', (
      tester,
    ) async {
      // Ofrecerle un plan MÁS CARO a quien ya compró uno y no está al día es
      // el mensaje equivocado: lo que necesita es regularizar.
      await pumpOne(
        tester,
        subscription:
            _sub(SubscriptionTier.plan2, status: SubscriptionStatus.paused),
      );

      final text = _allText(tester);
      expect(text, contains('no esté al día'));
      expect(text, contains('límite del plan Free'));
      expect(find.text('REGULARIZAR MI SUSCRIPCIÓN'), findsOneWidget);
      expect(find.text('AMPLIAR MI PLAN'), findsNothing);
    });

    testWidgets('gracia conserva el derecho: sigue siendo problema de cupo', (
      tester,
    ) async {
      // Durante la gracia no se castiga el primer cobro fallido, así que si
      // igual hay alumnos afuera es porque el tier se quedó chico.
      await pumpOne(
        tester,
        subscription:
            _sub(SubscriptionTier.plan1, status: SubscriptionStatus.grace),
      );

      expect(_allText(tester), contains('Tu plan Plan 1 incluye 7 alumnos'));
      expect(find.text('AMPLIAR MI PLAN'), findsOneWidget);
    });

    testWidgets('cancelada con período pagado: dice el hecho, no el límite', (
      tester,
    ) async {
      // Antes esto caía en «suscripción caída» y decía dos cosas falsas: que
      // su límite era el de Free (2) mientras el servidor le aplicaba 15
      // (`effective-limit.test.ts`: «cancelled before currentPeriodEnd → still
      // paid tier»), y «REGULARIZAR MI SUSCRIPCIÓN» a alguien que dentro del
      // período pagado lo que necesita es un plan más grande.
      //
      // De qué lado de `currentPeriodEnd` estamos pide el reloj, y el reloj
      // crudo está prohibido en Coach (ratchet de `no_raw_clock_scan_test`).
      // Así que no se decide: se dice lo comprobable.
      await pumpOne(
        tester,
        subscription: _sub(
          SubscriptionTier.plan2,
          status: SubscriptionStatus.cancelled,
          // Instante elegido para que UTC y ART NO coincidan: 01:30 UTC del
          // 16/3 son las 22:30 ART del 15/3. Con una fecha de mediodía el
          // test pasaría igual leyendo los campos crudos y no probaría nada.
          currentPeriodEnd: DateTime.utc(2026, 3, 16, 1, 30),
        ),
      );

      final text = _allText(tester);
      expect(text, contains('Cancelaste tu suscripción'));
      // El día ARGENTINO, no el UTC: entre las 21:00 y las 23:59 ART el día
      // UTC ya es el siguiente, y el PF leería su vencimiento corrido un día.
      expect(text, isNot(contains('16/3')));
      expect(text, contains('15/3'));
      // Ninguna de las dos afirmaciones de límite, porque cuál rige HOY es
      // justo lo que no se sabe.
      expect(text, isNot(contains('Tu plan Plan 2 incluye')));
      expect(text, isNot(contains('Mientras tu suscripción no esté al día')));
      // Y ningún CTA: los dos lados de la fecha se arreglan con botones
      // opuestos.
      expect(find.text('AMPLIAR MI PLAN'), findsNothing);
      expect(find.text('REGULARIZAR MI SUSCRIPCIÓN'), findsNothing);
    });

    testWidgets('cancelada SIN período pagado sí cayó a Free', (
      tester,
    ) async {
      // Sin `currentPeriodEnd` no hay período que el servidor tenga que
      // respetar, así que no hay ambigüedad y la causa vuelve a ser de cobro.
      await pumpOne(
        tester,
        subscription: _sub(
          SubscriptionTier.plan2,
          status: SubscriptionStatus.cancelled,
        ),
      );

      expect(_allText(tester), contains('límite del plan Free'));
      expect(find.text('REGULARIZAR MI SUSCRIPCIÓN'), findsOneWidget);
    });

    testWidgets('plan sin límite y al día: no inventa que llegó al tope', (
      tester,
    ) async {
      // Estado contradictorio (no debería pasar). Decir «llegaste al límite de
      // tu plan» sería falso, y «AMPLIAR MI PLAN» vendería un arreglo que no
      // arregla nada: el plan ya es ilimitado.
      await pumpOne(tester, subscription: _sub(SubscriptionTier.plan3));

      final text = _allText(tester);
      expect(text, contains('no tiene tope de alumnos'));
      expect(text, contains('esto no es por el cupo'));
      expect(find.text('AMPLIAR MI PLAN'), findsNothing);
      expect(find.text('REGULARIZAR MI SUSCRIPCIÓN'), findsNothing);
    });

    testWidgets('sin el doc del PF no nombra ningún plan ni ofrece CTA', (
      tester,
    ) async {
      // El perfil llegó como `null` — sin sesión, o el stream de auth erroró y
      // `user_providers.dart` emite null de forma PERMANENTE. Ahí el estado
      // falso no se corrige nunca, así que asumir Free/active sería mentirle
      // al PF para siempre.
      await pumpOne(tester, profileState: _ProfileState.missing);

      final text = _allText(tester);
      expect(text, contains('No pudimos leer tu plan'));
      // La lista SÍ se muestra: es autoritativa y no depende del perfil.
      expect(find.text('Ana'), findsOneWidget);
      // Pero no se adivina cuál de los dos arreglos ofrecer: los dos son el
      // mensaje equivocado para el otro caso.
      expect(find.text('AMPLIAR MI PLAN'), findsNothing);
      expect(find.text('REGULARIZAR MI SUSCRIPCIÓN'), findsNothing);
      expect(text, isNot(contains('Free')));
    });

    testWidgets('un tier sin límite nunca renderiza la palabra "null"', (
      tester,
    ) async {
      // `weightLimit == null` es SIN LÍMITE, no un dato faltante. Ya se
      // publicó una vez un «Hasta null alumnos» por interpolarlo directo.
      await tester.pumpWidget(
        _harness(
          blocked: const AsyncData(BlockedAthletes.published(<String>{})),
          subscription: _sub(SubscriptionTier.plan3),
        ),
      );
      await tester.pumpAndSettle();

      expect(_allText(tester), isNot(contains('null')));
      expect(_allText(tester), contains('alumnos sin límite'));
    });
  });

  group('BlockedStudentsScreen — salida a facturación', () {
    testWidgets('el CTA abre el paywall de plan', (tester) async {
      await tester.pumpWidget(
        _harness(
          blocked: const AsyncData(BlockedAthletes.published({'a1'})),
          subscription: _sub(SubscriptionTier.free),
          profiles: const {
            'a1': UserPublicProfile(uid: 'a1', displayName: 'Ana'),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('AMPLIAR MI PLAN'));
      await tester.pumpAndSettle();

      expect(find.text('LLEGASTE AL LÍMITE DE TU PLAN'), findsOneWidget);
    });

    testWidgets('con la suscripción caída abre la rama de reactivación', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          blocked: const AsyncData(BlockedAthletes.published({'a1'})),
          subscription:
              _sub(SubscriptionTier.plan2, status: SubscriptionStatus.paused),
          profiles: const {
            'a1': UserPublicProfile(uid: 'a1', displayName: 'Ana'),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('REGULARIZAR MI SUSCRIPCIÓN'));
      await tester.pumpAndSettle();

      expect(find.text('TU SUSCRIPCIÓN ESTÁ SUSPENDIDA'), findsOneWidget);
      // Y NO el upsell, que es el mensaje opuesto para quien ya pagó.
      expect(find.text('LLEGASTE AL LÍMITE DE TU PLAN'), findsNothing);
    });
  });

  group('BlockedStudentsScreen — layout', () {
    testWidgets('entra en ventana angosta con textScale 2.0', (tester) async {
      // Precedente en este repo: un overflow que ningún test agarró porque
      // todos fijaban Size(1440, 900).
      //
      // La ruta vive SÓLO en el router del Coach Hub (`coach_hub_router.dart`
      // hace `...facturacionPlanesRoutes`); el router móvil registra a mano
      // `/facturacion/planes` y nada más. Así que el escenario real no es un
      // teléfono: es la ventana del Coach Hub angostada, con el textScale del
      // sistema aplicado igual. El ancho de 375 es un piso deliberado.
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        _harness(
          blocked:
              const AsyncData(BlockedAthletes.published({'a1', 'a2', 'a3'})),
          subscription: _sub(SubscriptionTier.free),
          profiles: const {
            'a1': UserPublicProfile(uid: 'a1', displayName: 'Ana'),
            'a2': UserPublicProfile(uid: 'a2', displayName: 'Beto'),
            'a3': UserPublicProfile(uid: 'a3', displayName: 'Caro'),
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ALUMNOS EN SOLO LECTURA'), findsOneWidget);
    });
  });
}
