/// limite_de_alumnos_provider_test.dart — `limiteDeAlumnosProvider` elige entre
/// el tope que publica el servidor (`planLimits.athletes*`) y el cálculo de
/// siempre, y cambia SOLO al cruzar el borde que el servidor publicó.
///
/// Lo que protege:
///
///   1. Que el número del servidor gane sobre lo que dice la suscripción del
///      doc, y que el nombre del plan salga DEL NÚMERO (un `paused` con Plan 2
///      y tope 2 es «Free», no «Plan 2»).
///   2. Que ausente (el servidor no lo calculó) y `null` (sin tope) den cosas
///      distintas: ausente cae al cálculo del cliente, `null` es ilimitado.
///   3. Que el cambio por reloj ocurra sin que emita el perfil ni el doc, con
///      espera acotada a un minuto y el timer muerto con el provider.
///   4. Que sin la clave del servidor el resultado sea EXACTAMENTE el de antes.
library;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_async/fake_async.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/coach/application/limite_de_alumnos_provider.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

const _uid = 'pf1';

UserProfile _pf(TrainerSubscription? sub) => UserProfile(
      uid: _uid,
      email: 'sofia@treino.app',
      displayName: 'Sofía Ramírez',
      role: UserRole.trainer,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
      subscription: sub,
    );

TrainerSubscription _sub(
  SubscriptionTier tier, {
  SubscriptionStatus status = SubscriptionStatus.active,
  DateTime? fin,
}) =>
    TrainerSubscription(
      tier: tier,
      status: status,
      currentPeriodEnd: fin,
    );

/// Un firestore con `users/pf1` sembrado. `planLimits == null` = el doc sin esa
/// clave; para sembrar SIN doc se pasa [conDoc] en falso.
Future<FakeFirebaseFirestore> _firestore(
  Map<String, Object?>? planLimits, {
  bool conDoc = true,
}) async {
  final firestore = FakeFirebaseFirestore();
  if (conDoc) {
    await firestore.collection('users').doc(_uid).set({
      'uid': _uid,
      if (planLimits != null) 'planLimits': planLimits,
    });
  }
  return firestore;
}

ProviderContainer _container(
  FakeFirebaseFirestore firestore, {
  TrainerSubscription? sub,
  String? uid = _uid,
}) =>
    ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWithValue(uid),
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(_pf(sub))),
      ],
    );

/// Escucha el provider y deja asentar los streams (Riverpod agenda el refresh
/// con un `Timer` de cero, así que `elapse(Duration.zero)` y no
/// `flushMicrotasks`; ver `vigencia_del_plan_provider_test.dart`).
ProviderSubscription<LimiteDeAlumnos> _escuchar(
  FakeAsync async,
  ProviderContainer container,
) {
  final s = container.listen(limiteDeAlumnosProvider, (_, __) {});
  async.elapse(Duration.zero);
  async.elapse(Duration.zero);
  return s;
}

void main() {
  tearDown(AppClock.unfreeze);

  final ahora = DateTime.utc(2026, 10, 1, 15);
  setUp(() => AppClock.freeze(ahora.toLocal()));

  group('el número del servidor manda', () {
    test('paused con Plan 2 en el doc y athletes 2 → tope 2, nombre Free',
        () async {
      final firestore = await _firestore({'athletes': 2});
      fakeAsync((async) {
        final container = _container(
          firestore,
          sub: _sub(SubscriptionTier.plan2, status: SubscriptionStatus.paused),
        );
        final limite = _escuchar(async, container);

        expect(limite.read(), (tope: 2, tier: SubscriptionTier.free));
        container.dispose();
      });
    });

    test('piso prepago: athletes null con Plan 1 en el doc → sin tope, Plan 3',
        () async {
      final firestore = await _firestore({'athletes': null});
      fakeAsync((async) {
        final container =
            _container(firestore, sub: _sub(SubscriptionTier.plan1));
        final limite = _escuchar(async, container);

        expect(limite.read(), (tope: null, tier: SubscriptionTier.plan3));
        container.dispose();
      });
    });

    test('un tope que ninguna tabla tiene → el número, sin nombre de plan',
        () async {
      final firestore = await _firestore({'athletes': 9});
      fakeAsync((async) {
        final container =
            _container(firestore, sub: _sub(SubscriptionTier.plan1));
        final limite = _escuchar(async, container);

        expect(limite.read(), (tope: 9, tier: null));
        container.dispose();
      });
    });
  });

  group('ausente ≠ null', () {
    test('la MISMA suscripción da resultados distintos', () async {
      final conNull = await _firestore({'athletes': null});
      final sinClave = await _firestore({'customExercises': 60});
      fakeAsync((async) {
        final a = _container(conNull, sub: _sub(SubscriptionTier.plan1));
        final b = _container(sinClave, sub: _sub(SubscriptionTier.plan1));
        final limiteA = _escuchar(async, a);
        final limiteB = _escuchar(async, b);

        expect(limiteA.read(), (tope: null, tier: SubscriptionTier.plan3));
        expect(limiteB.read(), (tope: 7, tier: SubscriptionTier.plan1));
        expect(limiteA.read(), isNot(limiteB.read()));
        a.dispose();
        b.dispose();
      });
    });

    test('sin `planLimits`, sin doc y sin uid: el cálculo de siempre',
        () async {
      final sinPlanLimits = await _firestore(null);
      final sinDoc = await _firestore(null, conDoc: false);
      fakeAsync((async) {
        for (final c in [
          _container(sinPlanLimits, sub: _sub(SubscriptionTier.plan2)),
          _container(sinDoc, sub: _sub(SubscriptionTier.plan2)),
          _container(sinDoc, sub: _sub(SubscriptionTier.plan2), uid: null),
        ]) {
          final limite = _escuchar(async, c);
          expect(limite.read(), (tope: 15, tier: SubscriptionTier.plan2));
          c.dispose();
        }
      });
    });

    test('sin clave, es idéntico al cálculo de antes: baja vencida → Free',
        () async {
      final firestore = await _firestore({'customExercises': 60});
      fakeAsync((async) {
        final container = _container(
          firestore,
          sub: _sub(
            SubscriptionTier.plan1,
            status: SubscriptionStatus.cancelled,
            fin: ahora.subtract(const Duration(days: 7)),
          ),
        );
        final limite = _escuchar(async, container);

        expect(limite.read(), (tope: 2, tier: SubscriptionTier.free));
        container.dispose();
      });
    });

    test('sin clave, Plan 3 no tiene tope aunque el doc traiga weightLimit',
        () async {
      final firestore = await _firestore(null);
      fakeAsync((async) {
        final container = _container(
          firestore,
          sub: const TrainerSubscription(
            tier: SubscriptionTier.plan3,
            status: SubscriptionStatus.active,
            weightLimit: 15,
          ),
        );
        final limite = _escuchar(async, container);

        expect(limite.read(), (tope: null, tier: SubscriptionTier.plan3));
        container.dispose();
      });
    });

    test('la clave aparece después: el provider pasa del cálculo al servidor',
        () async {
      final firestore = await _firestore(null);
      fakeAsync((async) {
        final container =
            _container(firestore, sub: _sub(SubscriptionTier.plan2));
        final limite = _escuchar(async, container);
        expect(limite.read(), (tope: 15, tier: SubscriptionTier.plan2));

        firestore.collection('users').doc(_uid).update({
          'planLimits': {'athletes': 7},
        });
        async.elapse(Duration.zero);
        async.elapse(Duration.zero);

        expect(limite.read(), (tope: 7, tier: SubscriptionTier.plan1));
        container.dispose();
      });
    });
  });

  group('el borde que publica el servidor', () {
    final hasta = ahora.add(const Duration(hours: 1));

    Map<String, Object?> conBorde({int? despues = 2}) => {
          'athletes': 7,
          'athletesHasta': Timestamp.fromDate(hasta),
          'athletesDespues': despues,
        };

    test('al cruzarlo pasa a athletesDespues, sin que nadie emita', () async {
      final firestore = await _firestore(conBorde());
      fakeAsync((async) {
        final container =
            _container(firestore, sub: _sub(SubscriptionTier.plan1));
        final limite = _escuchar(async, container);
        expect(limite.read(), (tope: 7, tier: SubscriptionTier.plan1));

        // Sólo pasa la hora: ni el perfil ni el doc emiten de nuevo.
        AppClock.freeze(hasta.add(const Duration(minutes: 1)).toLocal());
        async.elapse(const Duration(hours: 1));

        expect(limite.read(), (tope: 2, tier: SubscriptionTier.free));
        container.dispose();
      });
    });

    test('athletesDespues null con borde: pasa a sin tope', () async {
      final firestore = await _firestore(conBorde(despues: null));
      fakeAsync((async) {
        final container =
            _container(firestore, sub: _sub(SubscriptionTier.plan1));
        final limite = _escuchar(async, container);
        expect(limite.read().tope, 7);

        AppClock.freeze(hasta.add(const Duration(minutes: 1)).toLocal());
        async.elapse(const Duration(hours: 1));

        expect(limite.read(), (tope: null, tier: SubscriptionTier.plan3));
        container.dispose();
      });
    });

    test('un borde que ya pasó al arrancar rige de entrada y no agenda nada',
        () async {
      final firestore = await _firestore({
        'athletes': 7,
        'athletesHasta': Timestamp.fromDate(
          ahora.subtract(const Duration(days: 1)),
        ),
        'athletesDespues': 2,
      });
      fakeAsync((async) {
        final container =
            _container(firestore, sub: _sub(SubscriptionTier.plan1));
        final limite = _escuchar(async, container);

        expect(limite.read(), (tope: 2, tier: SubscriptionTier.free));
        expect(async.pendingTimers, isEmpty);
        container.dispose();
      });
    });

    // El segundo motivo del tope de un minuto, igual que en la vigencia: si el
    // reloj salta el borde sin que el timer lo vea, se corrige en la próxima
    // re-evaluación.
    test('si el reloj salta el borde, se corrige en a lo sumo un minuto',
        () async {
      final firestore = await _firestore(conBorde());
      fakeAsync((async) {
        final container =
            _container(firestore, sub: _sub(SubscriptionTier.plan1));
        final limite = _escuchar(async, container);
        expect(limite.read().tope, 7);

        AppClock.freeze(hasta.add(const Duration(hours: 3)).toLocal());
        async.elapse(const Duration(minutes: 1));

        expect(limite.read().tope, 2);
        container.dispose();
      });
    });

    test('ninguna espera pasa de un minuto, con el borde a un mes', () async {
      final firestore = await _firestore({
        'athletes': 7,
        'athletesHasta': Timestamp.fromDate(
          ahora.add(const Duration(days: 30)),
        ),
        'athletesDespues': 2,
      });
      fakeAsync((async) {
        final container =
            _container(firestore, sub: _sub(SubscriptionTier.plan1));
        _escuchar(async, container);

        expect(async.pendingTimers, hasLength(1));
        expect(
          async.pendingTimers.single.duration,
          lessThanOrEqualTo(const Duration(minutes: 1)),
        );
        container.dispose();
      });
    });

    // El timer va un milisegundo DESPUÉS del borde: el `Timer` de web trunca a
    // milisegundos, y uno que dispara antes vería que el borde no llegó y se
    // reagendaría en loop.
    test('con el borde a menos de un minuto, espera lo que falta + 1 ms',
        () async {
      final firestore = await _firestore({
        'athletes': 7,
        'athletesHasta': Timestamp.fromDate(
          ahora.add(const Duration(seconds: 20)),
        ),
        'athletesDespues': 2,
      });
      fakeAsync((async) {
        final container =
            _container(firestore, sub: _sub(SubscriptionTier.plan1));
        _escuchar(async, container);

        expect(
          async.pendingTimers.single.duration,
          const Duration(seconds: 20, milliseconds: 1),
        );
        container.dispose();
      });
    });

    test('cuando se va el último que lo mira, el timer se cancela', () async {
      final firestore = await _firestore(conBorde());
      fakeAsync((async) {
        final container =
            _container(firestore, sub: _sub(SubscriptionTier.plan1));
        final limite = _escuchar(async, container);
        expect(async.pendingTimers, hasLength(1));

        limite.close();
        async.elapse(Duration.zero);

        expect(async.pendingTimers, isEmpty);
        container.dispose();
      });
    });

    test('sin borde publicado no agenda nada', () async {
      final firestore = await _firestore({
        'athletes': 7,
        'athletesHasta': null,
        'athletesDespues': null,
      });
      fakeAsync((async) {
        final container =
            _container(firestore, sub: _sub(SubscriptionTier.plan1));
        final limite = _escuchar(async, container);

        expect(limite.read().tope, 7);
        expect(async.pendingTimers, isEmpty);
        container.dispose();
      });
    });
  });
}
