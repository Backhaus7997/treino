// Tests de `athleteEntitlementProvider` — la resolución del derecho del alumno
// contra sus DOS fuentes: el vínculo con un PF y su propia suscripción.
//
// El eje de todo el archivo es la distinción entre «dijo que no» y «todavía no
// contestó». Un `free` prematuro le muestra el sheet de límite a alguien que
// paga; por eso mientras alguna fuente no resolvió, la respuesta es `unknown`
// — que no gatea.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show currentAthleteLinkProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/paywall/application/athlete_entitlement_provider.dart';
import 'package:treino/features/paywall/domain/athlete_entitlement.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

const _uid = 'athlete-1';

TrainerLink _activeLink() => TrainerLink(
      id: 'link-1',
      trainerId: 'trainer-9',
      athleteId: _uid,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
    );

/// Container con el doc del alumno sembrado con [subscription] (o sin el campo
/// si es null) y el vínculo resuelto a [link].
Future<ProviderContainer> _containerWith({
  Map<String, Object?>? subscription,
  TrainerLink? link,
}) async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('users').doc(_uid).set({
    'uid': _uid,
    if (subscription != null) kAthleteSubscriptionField: subscription,
  });

  final container = ProviderContainer(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWithValue(_uid),
      currentAthleteLinkProvider.overrideWith((ref) async => link),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Deja que emitan el stream de Firestore y el future del vínculo.
Future<AthleteEntitlement> _settle(ProviderContainer container) async {
  final sub = container.listen(athleteEntitlementProvider, (_, __) {});
  await container.read(currentAthleteLinkProvider.future);
  await Future<void>.delayed(Duration.zero);
  return sub.read();
}

void main() {
  group('athleteEntitlementProvider', () {
    test('vínculo activo con un PF ⇒ entitled, aunque no tenga suscripción',
        () async {
      // Es la regla de la sección 2 de la spec: el alumno vinculado no paga
      // NUNCA. Su PF ya paga por ese cupo.
      final c = await _containerWith(link: _activeLink());
      expect(await _settle(c), AthleteEntitlement.entitled);
    });

    test('suscripción active ⇒ entitled sin vínculo', () async {
      final c = await _containerWith(subscription: {'status': 'active'});
      expect(await _settle(c), AthleteEntitlement.entitled);
    });

    test('suscripción en grace ⇒ entitled', () async {
      // `grace` es «el cobro falló y se está reintentando». Cortarle las
      // funciones justo ahí es la peor forma de pedirle que actualice la
      // tarjeta.
      final c = await _containerWith(subscription: {'status': 'grace'});
      expect(await _settle(c), AthleteEntitlement.entitled);
    });

    test('suscripción cancelled y sin vínculo ⇒ free', () async {
      final c = await _containerWith(subscription: {'status': 'cancelled'});
      expect(await _settle(c), AthleteEntitlement.free);
    });

    test('sin el campo athleteSubscription y sin vínculo ⇒ free', () async {
      // Ausente ⇒ free, sin backfill. Mismo criterio que `subscription` del PF.
      // Es el estado de TODOS los docs hoy: nadie escribe el campo todavía.
      final c = await _containerWith();
      expect(await _settle(c), AthleteEntitlement.free);
    });

    test('mientras el vínculo no resolvió ⇒ unknown, no free', () async {
      // La distinción que justifica el enum de tres estados. Si acá diera
      // `free`, el editor abriría el sheet de límite en la cara de alguien que
      // paga, durante el round-trip.
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc(_uid).set({'uid': _uid});

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWithValue(_uid),
          // Nunca completa: modela el read en vuelo.
          currentAthleteLinkProvider
              .overrideWith((ref) => Completer<TrainerLink?>().future),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(athleteEntitlementProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(sub.read(), AthleteEntitlement.unknown);
    });

    test('sin uid ⇒ no afirma free por la suscripción sola', () async {
      // Sin sesión no hay a quién cobrarle. Lo que importa es que no se
      // devuelva `entitled`: el gate igual no corre porque el editor de alumno
      // exige uid.
      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          currentUidProvider.overrideWithValue(null),
          currentAthleteLinkProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(athleteEntitlementProvider, (_, __) {});
      await container.read(currentAthleteLinkProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(sub.read(), isNot(AthleteEntitlement.entitled));
    });
  });

  group('AthleteEntitlement.gatesFreeLimits', () {
    test('sólo free gatea', () {
      expect(AthleteEntitlement.free.gatesFreeLimits, isTrue);
      expect(AthleteEntitlement.entitled.gatesFreeLimits, isFalse);
    });

    test('unknown NO gatea — falla ABIERTO a propósito', () {
      // El enforcement real vive en firestore.rules. Fallar cerrado acá le
      // bloquea el botón a quien paga por un parpadeo de red; fallar abierto
      // deja pasar un tap cuya escritura el servidor rebota igual.
      expect(AthleteEntitlement.unknown.gatesFreeLimits, isFalse);
    });
  });

  group('topes del plan free', () {
    test('2 días y 1 semana', () {
      // Pineados: son el contrato con `docs/paywall-alumno-suelto.md` §4 y con
      // la regla de firestore que los va a replicar. Si cambian acá sin
      // cambiar allá, el cliente y el servidor discrepan.
      expect(kFreeMaxRoutineDays, 2);
      expect(kFreeMaxRoutineWeeks, 1);
    });

    test('un día no es una opción válida de free', () {
      // Con numDays == 1, `nextPlanPosition` rota la semana en CADA sesión
      // terminada (`rolledOver = dayNumber >= numDays`). Un free de 1 día
      // quemaría 8 semanas en 8 sesiones, en silencio.
      expect(kFreeMaxRoutineDays, greaterThan(1));
    });
  });
}
