// Tests for AppointmentDetailDialog's Cobrar flow (Slice 2a — Agenda→cobro
// bridge, per-turno). MONEY-CRITICAL: pins that confirming a charge creates
// a real Payment doc (via the AppointmentRepository backed by a real
// FakeFirebaseFirestore — not a hand-rolled stub, so the transaction wiring
// itself is exercised) AND atomically links appointment.paymentId; that an
// already-billed turno shows "Cobrado" instead of "Cobrar" and can't be
// re-billed; that the amount defaults to the athlete's reference rate but
// stays editable; that "Vence el" is optional; and that a cancelled turno
// shows no billing action at all.
//
// Todas las strings son español hardcodeado + comentario // i18n (C-6) —
// mismo contrato que el widget bajo test.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/appointment_detail_dialog.dart';
import 'package:treino/features/payments/application/billing_providers.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-cobrar-1';
const _kAthleteId = 'athlete-cobrar-1';

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
      id: 'appt-cancelled',
      trainerId: _kTrainerId,
      athleteId: _kAthleteId,
      athleteDisplayName: 'Ana López',
      startsAt: DateTime.utc(2026, 7, 1, 10, 0),
      durationMin: 60,
      status: AppointmentStatus.cancelled,
    );

UserPublicProfile _pub() => const UserPublicProfile(
      uid: _kAthleteId,
      displayName: 'Ana López',
      displayNameLowercase: 'ana lópez',
    );

// ─── Test harness ─────────────────────────────────────────────────────────────

/// Wraps AppointmentDetailDialog behind an "abrir" button — mirrors
/// production plumbing (showDialog) so Navigator.pop() on success has a real
/// route to close. Localization delegates + es_AR locale are included ONLY
/// so the underlying Material showDatePicker renders deterministic Spanish
/// button labels ("ACEPTAR") — the widget under test itself does not use
/// AppL10n (C-6).
Widget _wrap({
  required Appointment appointment,
  required FakeFirebaseFirestore firestore,
  AthleteBilling? billing,
  bool isPast = false,
}) {
  return ProviderScope(
    overrides: [
      appointmentRepositoryProvider.overrideWithValue(
        AppointmentRepository(firestore: firestore),
      ),
      athleteBillingProvider(_kAthleteId).overrideWith(
        (ref) => Stream.value(billing),
      ),
      userPublicProfileProvider(_kAthleteId).overrideWith(
        (ref) => Stream.value(_pub()),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AppointmentDetailDialog(
                appointment: appointment,
                trainerId: _kTrainerId,
                isPast: isPast,
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// Taps [finder], first scrolling it into view — the dialog's content sits
/// inside a SingleChildScrollView taller than the default test viewport, so
/// a plain tester.tap() on a lower field/button misses (hits the scrim
/// behind it instead).
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
        final appt = _confirmedAppt(id: 'appt-happy');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());
        final billing = AthleteBilling(
          trainerId: _kTrainerId,
          athleteId: _kAthleteId,
          amountArs: 7000,
          cadence: BillingCadence.suelto,
          updatedAt: DateTime.utc(2026, 1, 1),
        );

        await tester.pumpWidget(
          _wrap(appointment: appt, firestore: firestore, billing: billing),
        );
        await _openDialog(tester);

        await _tap(tester, find.text('COBRAR')); // i18n

        // El campo Monto arranca prellenado con la tarifa de referencia,
        // agrupada de a miles por el ThousandsSeparatorInputFormatter.
        expect(find.text('7.000'), findsOneWidget);
        expect(find.textContaining('Tarifa de referencia'), findsOneWidget);

        await _tap(tester, find.text('CONFIRMAR COBRO')); // i18n

        // El dialog se cierra.
        expect(find.byType(AlertDialog), findsNothing);

        // Se creó un Payment con los datos correctos.
        final payments = await firestore.collection('payments').get();
        expect(payments.docs, hasLength(1));
        final paymentData = payments.docs.single.data();
        expect(paymentData['athleteId'], _kAthleteId);
        expect(paymentData['trainerId'], _kTrainerId);
        expect(paymentData['amountArs'], 7000);
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
        final appt = _confirmedAppt(id: 'appt-editable');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        await tester.pumpWidget(
          _wrap(appointment: appt, firestore: firestore, billing: null),
        );
        await _openDialog(tester);

        await _tap(tester, find.text('COBRAR')); // i18n

        // Sin config de billing → no se muestra la tarifa de referencia.
        expect(find.textContaining('Tarifa de referencia'), findsNothing);

        // Indices 0/1 son los TextField pre-existentes "Antes de la sesión" /
        // "Recordatorio (post)" (_beforeController/_afterController), que
        // siempre se renderizan ANTES de la sección Cobrar en este dialog.
        // Monto/Concepto del form de Cobrar son 2/3.
        await tester.enterText(find.byType(TextField).at(2), '12345');
        await tester.enterText(
            find.byType(TextField).at(3), 'Clase particular');
        await tester.pumpAndSettle();

        await _tap(tester, find.text('CONFIRMAR COBRO')); // i18n

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
        final appt =
            _confirmedAppt(id: 'appt-billed', paymentId: 'payment-existing');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        await tester.pumpWidget(
          _wrap(appointment: appt, firestore: firestore, billing: null),
        );
        await _openDialog(tester);

        expect(find.text('Cobrado'), findsOneWidget); // i18n
        expect(find.text('COBRAR'), findsNothing); // i18n
      },
    );
  });

  group('(d) Vence el opcional', () {
    testWidgets(
      'sin elegir fecha → el Payment creado tiene dueAt null',
      (tester) async {
        final appt = _confirmedAppt(id: 'appt-no-due');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        await tester.pumpWidget(
          _wrap(appointment: appt, firestore: firestore, billing: null),
        );
        await _openDialog(tester);
        await _tap(tester, find.text('COBRAR')); // i18n

        // Index 2 = Monto del form de Cobrar (0/1 son los TextField de notas
        // pre-existentes — ver comentario en el test "sin tarifa configurada").
        await tester.enterText(find.byType(TextField).at(2), '5000');
        await tester.pumpAndSettle();
        await _tap(tester, find.text('CONFIRMAR COBRO')); // i18n

        final payments = await firestore.collection('payments').get();
        expect(payments.docs.single.data()['dueAt'], isNull);
      },
    );

    testWidgets(
      'con fecha elegida → el Payment creado tiene dueAt seteado',
      (tester) async {
        final appt = _confirmedAppt(id: 'appt-with-due');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        await tester.pumpWidget(
          _wrap(appointment: appt, firestore: firestore, billing: null),
        );
        await _openDialog(tester);
        await _tap(tester, find.text('COBRAR')); // i18n
        // Index 2 = Monto del form de Cobrar (ver comentario arriba).
        await tester.enterText(find.byType(TextField).at(2), '5000');
        await tester.pumpAndSettle();

        await _tap(tester, find.text('Sin fecha de vencimiento')); // i18n
        await tester.tap(find.text('ACEPTAR'));
        await tester.pumpAndSettle();

        await _tap(tester, find.text('CONFIRMAR COBRO')); // i18n

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
      await _openDialog(tester);

      expect(find.text('COBRAR'), findsNothing); // i18n
      expect(find.text('Cobrado'), findsNothing); // i18n
    });
  });
}
