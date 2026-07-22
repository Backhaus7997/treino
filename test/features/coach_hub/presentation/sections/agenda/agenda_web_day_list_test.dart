// Tests for AgendaWebDayList's multi-select flow (Slice 2b — cobro por LOTE
// desde la agenda). MONEY-CRITICAL: pins that entering selection mode shows
// checkboxes only on confirmed+unbilled turnos; that selecting the first
// turno LOCKS the batch to that athlete (other athletes become
// non-selectable); that the "COBRAR (N)" bar opens BatchCobrarDialog with
// the amount defaulted to N × the athlete's reference rate (editable) and
// the concept defaulted to "N sesiones"; and that confirming creates exactly
// ONE Payment covering all N turnos, clears the selection, and flips every
// turno to "Cobrado".
//
// Todas las strings son español hardcodeado + comentario // i18n (C-6) —
// mismo contrato que los widgets bajo test.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/agenda_web_day_list.dart';
import 'package:treino/features/payments/application/billing_providers.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-lote-1';
const _kAthleteA = 'athlete-lote-a';
const _kAthleteB = 'athlete-lote-b';
final _kDay = DateTime.utc(2026, 7, 1);

// ─── Factories ───────────────────────────────────────────────────────────────

Appointment _confirmedAppt({
  required String id,
  required int hour,
  String athleteId = _kAthleteA,
  String athleteName = 'Ana López',
  String? paymentId,
}) =>
    Appointment(
      id: id,
      trainerId: _kTrainerId,
      athleteId: athleteId,
      athleteDisplayName: athleteName,
      startsAt: DateTime.utc(2026, 7, 1, hour, 0),
      durationMin: 60,
      status: AppointmentStatus.confirmed,
      paymentId: paymentId,
    );

// ─── Test harness ─────────────────────────────────────────────────────────────

/// Wraps [AgendaWebDayList] the same way `agenda_web_screen.dart` does for
/// the narrow (fillHeight:false) layout: shrink-wrap Column inside a
/// SingleChildScrollView, so content never needs a bounded ancestor height.
/// Localization delegates + es_AR are included ONLY so the underlying
/// Material showDatePicker (inside BatchCobrarDialog) renders deterministic
/// Spanish labels — AgendaWebDayList/BatchCobrarDialog themselves do not use
/// AppL10n (C-6), same rationale as appointment_detail_dialog_test.dart.
Widget _wrap({
  required FakeFirebaseFirestore firestore,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      appointmentRepositoryProvider.overrideWithValue(
        AppointmentRepository(firestore: firestore),
      ),
      ...extraOverrides,
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AgendaWebDayList(
            trainerId: _kTrainerId,
            selectedDay: _kDay,
            rangeFrom: DateTime.utc(2026, 6, 1),
            rangeTo: DateTime.utc(2026, 8, 1),
          ),
        ),
      ),
    ),
  );
}

Override _noProfile(String athleteId) => userPublicProfileProvider(athleteId)
    .overrideWith((ref) => Stream.value(null));

Override _billingFor(String athleteId, AthleteBilling? billing) =>
    athleteBillingProvider(athleteId)
        .overrideWith((ref) => Stream.value(billing));

AthleteBilling _rate(String athleteId, int amountArs) => AthleteBilling(
      trainerId: _kTrainerId,
      athleteId: athleteId,
      amountArs: amountArs,
      cadence: BillingCadence.suelto,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  Future<void> seed(List<Appointment> appts) async {
    for (final a in appts) {
      await firestore.collection('appointments').doc(a.id).set(a.toJson());
    }
  }

  group('modo selección — toggle y lock por alumno', () {
    testWidgets(
      '"Seleccionar" muestra checkboxes; elegir el primer turno lockea el '
      'alumno y deja el checkbox del otro alumno no-interactivo',
      (tester) async {
        await seed([
          _confirmedAppt(
              id: 'a1',
              hour: 9,
              athleteId: _kAthleteA,
              athleteName: 'Ana López'),
          _confirmedAppt(
              id: 'b1',
              hour: 10,
              athleteId: _kAthleteB,
              athleteName: 'Bruno Díaz'),
        ]);

        await tester.pumpWidget(_wrap(
          firestore: firestore,
          extraOverrides: [
            _noProfile(_kAthleteA),
            _noProfile(_kAthleteB),
            _billingFor(_kAthleteA, null),
            _billingFor(_kAthleteB, null),
          ],
        ));
        await tester.pumpAndSettle();

        // Sin modo selección: no hay checkboxes, sí el toggle.
        expect(find.byType(Checkbox), findsNothing);
        expect(find.text('Seleccionar'), findsOneWidget); // i18n

        await tester.tap(find.text('Seleccionar'));
        await tester.pumpAndSettle();

        // Modo selección: 2 checkboxes (uno por turno, ambos billable).
        expect(find.byType(Checkbox), findsNWidgets(2));
        expect(find.text('Elegí los turnos a cobrar'), findsOneWidget); // i18n

        // Elegir el turno de Ana lockea el lote a ese alumno.
        await tester.tap(find.text('Ana López'));
        await tester.pumpAndSettle();

        expect(find.text('1 seleccionado'), findsOneWidget); // i18n
        expect(find.text('COBRAR (1)'), findsOneWidget); // i18n

        // Tocar el turno de Bruno (otro alumno) es un no-op: sigue en 1.
        await tester.tap(find.text('Bruno Díaz'));
        await tester.pumpAndSettle();

        expect(find.text('1 seleccionado'), findsOneWidget); // i18n
        expect(find.text('COBRAR (1)'), findsOneWidget); // i18n
        expect(find.text('2 seleccionados'), findsNothing); // i18n
      },
    );

    testWidgets(
      'long-press sobre un turno billable entra en modo selección y lo '
      'selecciona en el mismo gesto',
      (tester) async {
        await seed([_confirmedAppt(id: 'a1', hour: 9)]);

        await tester.pumpWidget(_wrap(
          firestore: firestore,
          extraOverrides: [
            _noProfile(_kAthleteA),
            _billingFor(_kAthleteA, null)
          ],
        ));
        await tester.pumpAndSettle();

        await tester.longPress(find.text('Ana López'));
        await tester.pumpAndSettle();

        expect(find.text('1 seleccionado'), findsOneWidget); // i18n
        expect(find.text('COBRAR (1)'), findsOneWidget); // i18n
      },
    );

    testWidgets(
      'un turno ya cobrado nunca muestra checkbox en modo selección (sólo '
      'el chip "Cobrado")',
      (tester) async {
        await seed([
          _confirmedAppt(id: 'a1', hour: 9, paymentId: 'payment-existing'),
        ]);

        await tester.pumpWidget(_wrap(
          firestore: firestore,
          extraOverrides: [
            _noProfile(_kAthleteA),
            _billingFor(_kAthleteA, null)
          ],
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Seleccionar'));
        await tester.pumpAndSettle();

        expect(find.byType(Checkbox), findsNothing);
        expect(find.byTooltip('Cobrado'), findsOneWidget); // i18n
      },
    );

    testWidgets('"Cancelar" en modo selección limpia todo y vuelve al toggle',
        (tester) async {
      await seed([_confirmedAppt(id: 'a1', hour: 9)]);

      await tester.pumpWidget(_wrap(
        firestore: firestore,
        extraOverrides: [_noProfile(_kAthleteA), _billingFor(_kAthleteA, null)],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Seleccionar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ana López'));
      await tester.pumpAndSettle();
      expect(find.text('COBRAR (1)'), findsOneWidget);

      await tester.tap(find.text('Cancelar')); // i18n
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Seleccionar'), findsOneWidget);
      expect(find.text('COBRAR (1)'), findsNothing);
    });
  });

  group('BatchCobrarDialog — monto default N × tarifa, editable', () {
    testWidgets(
      'COBRAR (N) abre el dialog con monto = N × tarifa de referencia y '
      'concepto default "N sesiones"; el trainer puede editar el monto y '
      'ese es el que persiste',
      (tester) async {
        await seed([
          _confirmedAppt(id: 'a1', hour: 9),
          _confirmedAppt(id: 'a2', hour: 10),
        ]);

        await tester.pumpWidget(_wrap(
          firestore: firestore,
          extraOverrides: [
            _noProfile(_kAthleteA),
            _billingFor(_kAthleteA, _rate(_kAthleteA, 5000)),
          ],
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Seleccionar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ana López').first);
        await tester.pumpAndSettle();
        // Selecciona el 2do turno también (mismo alumno).
        await tester.tap(find.text('Ana López').last);
        await tester.pumpAndSettle();
        expect(find.text('COBRAR (2)'), findsOneWidget);

        await tester.tap(find.text('COBRAR (2)'));
        await tester.pumpAndSettle();

        // Monto default = 2 × 5000 = 10000, mostrado agrupado en el TextField.
        expect(find.text('10.000'), findsOneWidget);
        expect(find.textContaining('Tarifa de referencia'), findsOneWidget);
        expect(
            find.text('2 sesiones'), findsOneWidget); // i18n, concepto default

        // Editar el monto — el trainer cambia el default.
        await tester.enterText(find.text('10.000'), '9999');
        await tester.pumpAndSettle();

        await tester.tap(find.text('CONFIRMAR COBRO')); // i18n
        await tester.pumpAndSettle();

        final payments = await firestore.collection('payments').get();
        expect(payments.docs, hasLength(1));
        expect(payments.docs.single.data()['amountArs'], equals(9999));
        expect(payments.docs.single.data()['concept'], equals('2 sesiones'));
        expect(payments.docs.single.data()['athleteId'], equals(_kAthleteA));
      },
    );

    testWidgets(
      'sin tarifa configurada → monto arranca vacío (editable, no bloquea '
      'el flujo)',
      (tester) async {
        await seed([_confirmedAppt(id: 'a1', hour: 9)]);

        await tester.pumpWidget(_wrap(
          firestore: firestore,
          extraOverrides: [
            _noProfile(_kAthleteA),
            _billingFor(_kAthleteA, null)
          ],
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Seleccionar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ana López'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('COBRAR (1)'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Tarifa de referencia'), findsNothing);
        expect(
            find.text('1 sesión'), findsOneWidget); // i18n, singular correcto
      },
    );
  });

  group('post-cobro — confirma, marca los N turnos y limpia la selección', () {
    testWidgets(
      'confirmar el lote crea 1 Payment, marca los N turnos como Cobrado y '
      'sale del modo selección',
      (tester) async {
        await seed([
          _confirmedAppt(id: 'a1', hour: 9),
          _confirmedAppt(id: 'a2', hour: 10),
        ]);

        await tester.pumpWidget(_wrap(
          firestore: firestore,
          extraOverrides: [
            _noProfile(_kAthleteA),
            _billingFor(_kAthleteA, _rate(_kAthleteA, 5000)),
          ],
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Seleccionar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ana López').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ana López').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('COBRAR (2)'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('CONFIRMAR COBRO'));
        await tester.pumpAndSettle();

        // Dialog cerrado.
        expect(find.byType(AlertDialog), findsNothing);

        // Los 2 turnos quedan marcados con el MISMO paymentId.
        final snap1 =
            await firestore.collection('appointments').doc('a1').get();
        final snap2 =
            await firestore.collection('appointments').doc('a2').get();
        expect(snap1.data()!['paymentId'], isNotNull);
        expect(snap1.data()!['paymentId'], equals(snap2.data()!['paymentId']));

        // Volvió al modo no-selección: sin checkboxes, botón "Seleccionar" de
        // nuevo, y las 2 tarjetas muestran el chip "Cobrado".
        expect(find.byType(Checkbox), findsNothing);
        expect(find.text('Seleccionar'), findsOneWidget);
        expect(find.byTooltip('Cobrado'), findsNWidgets(2)); // i18n
      },
    );
  });
}
