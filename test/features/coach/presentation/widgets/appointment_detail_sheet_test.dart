// Tests for AppointmentDetailSheet's Cobrar flow (Slice 2a — Agenda→cobro
// bridge, per-turno, MOBILE surface). Mirrors
// test/features/coach_hub/presentation/sections/agenda/appointment_detail_dialog_test.dart
// (the web dialog's equivalent suite) — same 5 scenarios from the task spec,
// adapted to a showModalBottomSheet host. Unlike the web dialog (hardcoded
// Spanish + `// i18n`, contract C-6), this widget uses AppL10n — asserted
// strings below are the es_AR translations from intl_es_AR.arb.
//
// MONEY-CRITICAL: pins that confirming a charge creates a real Payment doc
// (via AppointmentRepository backed by a real FakeFirebaseFirestore — not a
// hand-rolled stub, so the billAppointment transaction wiring itself is
// exercised) AND atomically links appointment.paymentId; that an
// already-billed turno shows "Cobrado" instead of "Cobrar" and can't be
// re-billed; that the amount defaults to the athlete's reference rate but
// stays editable; that "Vence el" is optional; and that a cancelled turno
// shows no billing action at all.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/presentation/widgets/appointment_detail_sheet.dart';
import 'package:treino/features/payments/application/billing_providers.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/l10n/app_l10n.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-cobrar-mobile-1';
const _kAthleteId = 'athlete-cobrar-mobile-1';

// ─── Factories ───────────────────────────────────────────────────────────────

Appointment _confirmedAppt({
  required String id,
  String? paymentId,
}) =>
    Appointment(
      id: id,
      trainerId: _kTrainerId,
      athleteId: _kAthleteId,
      athleteDisplayName: 'Ana López',
      startsAt: DateTime.utc(2026, 7, 1, 10, 0),
      durationMin: 60,
      status: AppointmentStatus.confirmed,
      paymentId: paymentId,
    );

Appointment _cancelledAppt() => Appointment(
      id: 'appt-cancelled-mobile',
      trainerId: _kTrainerId,
      athleteId: _kAthleteId,
      athleteDisplayName: 'Ana López',
      startsAt: DateTime.utc(2026, 7, 1, 10, 0),
      durationMin: 60,
      status: AppointmentStatus.cancelled,
    );

// ─── Test harness ─────────────────────────────────────────────────────────────

/// Wraps AppointmentDetailSheet behind an "abrir" button that opens it via
/// [showModalBottomSheet] — mirrors production plumbing (trainer_dashboard_tab
/// .dart) so Navigator.pop() on success has a real route to close.
Widget _wrap({
  required Appointment appointment,
  required FakeFirebaseFirestore firestore,
  AthleteBilling? billing,
}) {
  return ProviderScope(
    overrides: [
      appointmentRepositoryProvider.overrideWithValue(
        AppointmentRepository(firestore: firestore),
      ),
      athleteBillingProvider(_kAthleteId).overrideWith(
        (ref) => Stream.value(billing),
      ),
      // Empty/seeded fake Firestore — the sheet's athlete-header stream reads
      // userPublicProfiles/{athleteId} directly; falls back to
      // appointment.athleteDisplayName when the doc doesn't exist.
      firestoreProvider.overrideWithValue(firestore),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => AppointmentDetailSheet(
                appointment: appointment,
                trainerId: _kTrainerId,
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// Taps [finder], first scrolling it into view — the sheet's Cobrar form adds
/// enough height to push the confirm button past the default test viewport.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  group('(a)+(c) Cobrar happy path — default amount, editable', () {
    testWidgets(
      'monto arranca en la tarifa de referencia; confirmar crea Payment y '
      'marca el turno como cobrado',
      (tester) async {
        final appt = _confirmedAppt(id: 'appt-happy-mobile');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());
        final billing = AthleteBilling(
          trainerId: _kTrainerId,
          athleteId: _kAthleteId,
          amountArs: 8000,
          cadence: BillingCadence.suelto,
          updatedAt: DateTime.utc(2026, 1, 1),
        );

        await tester.pumpWidget(
          _wrap(appointment: appt, firestore: firestore, billing: billing),
        );
        await _openSheet(tester);

        await _tap(tester, find.text('COBRAR'));

        // El campo Monto arranca prellenado con la tarifa de referencia.
        expect(find.text('8000'), findsOneWidget);
        expect(find.textContaining('Tarifa de referencia'), findsOneWidget);

        await _tap(tester, find.text('CONFIRMAR COBRO'));

        // El sheet se cerró (el form ya no está en el árbol).
        expect(find.text('CONFIRMAR COBRO'), findsNothing);

        // Se creó un Payment con los datos correctos.
        final payments = await firestore.collection('payments').get();
        expect(payments.docs, hasLength(1));
        final paymentData = payments.docs.single.data();
        expect(paymentData['athleteId'], _kAthleteId);
        expect(paymentData['trainerId'], _kTrainerId);
        expect(paymentData['amountArs'], 8000);
        expect(paymentData['status'], 'pending');

        // El turno quedó marcado como cobrado (mismo id que el Payment).
        final apptSnap =
            await firestore.collection('appointments').doc(appt.id).get();
        expect(apptSnap.data()!['paymentId'], payments.docs.single.id);
      },
    );

    testWidgets(
      'sin tarifa configurada → campo vacío editable; el trainer puede '
      'cambiar el monto y el concepto',
      (tester) async {
        final appt = _confirmedAppt(id: 'appt-editable-mobile');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        await tester.pumpWidget(
          _wrap(appointment: appt, firestore: firestore, billing: null),
        );
        await _openSheet(tester);

        await _tap(tester, find.text('COBRAR'));

        // Sin config de billing → no se muestra la tarifa de referencia.
        expect(find.textContaining('Tarifa de referencia'), findsNothing);

        await tester.enterText(find.byType(TextField).at(0), '12345');
        await tester.enterText(
            find.byType(TextField).at(1), 'Clase particular');
        await tester.pumpAndSettle();

        await _tap(tester, find.text('CONFIRMAR COBRO'));

        final payments = await firestore.collection('payments').get();
        expect(payments.docs.single.data()['amountArs'], 12345);
        expect(payments.docs.single.data()['concept'], 'Clase particular');
      },
    );
  });

  group('(b) turno ya cobrado', () {
    testWidgets(
      'muestra "Cobrado" en vez de "COBRAR" y no ofrece re-cobro',
      (tester) async {
        final appt = _confirmedAppt(
            id: 'appt-billed-mobile', paymentId: 'payment-existing');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        await tester.pumpWidget(
          _wrap(appointment: appt, firestore: firestore, billing: null),
        );
        await _openSheet(tester);

        expect(find.text('Cobrado'), findsOneWidget);
        expect(find.text('COBRAR'), findsNothing);
      },
    );
  });

  group('(d) Vence el opcional', () {
    testWidgets(
      'sin elegir fecha → el Payment creado tiene dueAt null',
      (tester) async {
        final appt = _confirmedAppt(id: 'appt-no-due-mobile');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        await tester.pumpWidget(
          _wrap(appointment: appt, firestore: firestore, billing: null),
        );
        await _openSheet(tester);
        await _tap(tester, find.text('COBRAR'));

        await tester.enterText(find.byType(TextField).at(0), '5000');
        await tester.pumpAndSettle();
        await _tap(tester, find.text('CONFIRMAR COBRO'));

        final payments = await firestore.collection('payments').get();
        expect(payments.docs.single.data()['dueAt'], isNull);
      },
    );

    testWidgets(
      'con fecha elegida → el Payment creado tiene dueAt seteado',
      (tester) async {
        final appt = _confirmedAppt(id: 'appt-with-due-mobile');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        await tester.pumpWidget(
          _wrap(appointment: appt, firestore: firestore, billing: null),
        );
        await _openSheet(tester);
        await _tap(tester, find.text('COBRAR'));
        await tester.enterText(find.byType(TextField).at(0), '5000');
        await tester.pumpAndSettle();

        await _tap(tester, find.text('Sin fecha de vencimiento'));
        await tester.tap(find.text('ACEPTAR'));
        await tester.pumpAndSettle();

        await _tap(tester, find.text('CONFIRMAR COBRO'));

        final payments = await firestore.collection('payments').get();
        expect(payments.docs.single.data()['dueAt'], isNotNull);
      },
    );
  });

  group('(e) turno cancelled', () {
    testWidgets('no muestra ninguna acción de cobro', (tester) async {
      final appt = _cancelledAppt();
      await firestore
          .collection('appointments')
          .doc(appt.id)
          .set(appt.toJson());

      await tester.pumpWidget(
        _wrap(appointment: appt, firestore: firestore, billing: null),
      );
      await _openSheet(tester);

      expect(find.text('COBRAR'), findsNothing);
      expect(find.text('Cobrado'), findsNothing);
    });
  });
}
