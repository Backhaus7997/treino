// Tests for BatchCobrarDialog's amount round-trip (Slice 2b, batch cobro —
// thousands-separator fix). MONEY-CRITICAL: the "MONTO (ARS)" field displays
// a grouped string via ThousandsSeparatorInputFormatter (e.g. "10.000"), but
// what actually gets persisted in the Payment doc must ALWAYS be a plain
// `int` — never the grouped string, never truncated at the first dot. This
// pins that contract for (1) the initState pre-fill (billing.amountArs ×
// count), (2) a trainer-typed amount that crosses the thousands boundary,
// and (3) submitting the pre-fill unedited.
//
// Mirrors appointment_detail_dialog_test.dart: real FakeFirebaseFirestore +
// AppointmentRepository (not a hand-rolled/mocktail stub) so the
// billAppointments transaction wiring itself is exercised.
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
import 'package:treino/features/coach_hub/presentation/sections/agenda/batch_cobrar_dialog.dart';
import 'package:treino/features/payments/application/billing_providers.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/l10n/app_l10n.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-batch-1';
const _kAthleteId = 'athlete-batch-1';

// ─── Factories ───────────────────────────────────────────────────────────────

Appointment _confirmedAppt(String id) => Appointment(
      id: id,
      trainerId: _kTrainerId,
      athleteId: _kAthleteId,
      athleteDisplayName: 'Ana López',
      startsAt: DateTime.utc(2026, 7, 1, 10, 0),
      durationMin: 60,
      status: AppointmentStatus.confirmed,
    );

// ─── Test harness ─────────────────────────────────────────────────────────────

/// Wraps BatchCobrarDialog behind an "abrir" button — mirrors production
/// plumbing (showDialog) so Navigator.pop() on success has a real route to
/// close.
///
/// Also pre-warms athleteBillingProvider via a Consumer that watches it
/// unconditionally — mirrors AgendaWebDayList's pre-warm (see its comment
/// "Pre-calienta la tarifa de referencia..."): a StreamProvider freshly
/// subscribed is still AsyncLoading the first microtask, and
/// BatchCobrarDialog reads it SYNCHRONOUSLY (ref.read) in initState. Without
/// this pre-warm, billing.valueOrNull is still null when the dialog opens
/// even though the override is a already-resolved Stream.value.
Widget _wrap({
  required List<Appointment> appointments,
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
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            ref.watch(athleteBillingProvider(_kAthleteId));
            return Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => BatchCobrarDialog(
                    appointments: appointments,
                    trainerId: _kTrainerId,
                    athleteName: 'Ana López',
                  ),
                ),
                child: const Text('abrir'),
              ),
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  // Deja que el pre-warm de athleteBillingProvider resuelva su primer
  // microtask ANTES de abrir el dialog (ver comentario en _wrap).
  await tester.pump();
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  group('prellenado agrupado con separador de miles', () {
    testWidgets(
      'el campo Monto muestra el prellenado con puntos, no el int plano',
      (tester) async {
        final appt = _confirmedAppt('appt-prefill');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());
        final billing = AthleteBilling(
          trainerId: _kTrainerId,
          athleteId: _kAthleteId,
          amountArs: 10000,
          cadence: BillingCadence.suelto,
          updatedAt: DateTime.utc(2026, 1, 1),
        );

        await tester.pumpWidget(
          _wrap(
            appointments: [appt],
            firestore: firestore,
            billing: billing,
          ),
        );
        await _openDialog(tester);

        // count=1 × amountArs=10000 → prellenado agrupado "10.000", NO
        // "10000" en crudo.
        expect(find.text('10.000'), findsOneWidget);
        expect(find.text('10000'), findsNothing);
      },
    );
  });

  group('el monto tipeado se redondea a int plano al guardar', () {
    testWidgets(
      'tipear "25000" → el campo muestra "25.000" y se guarda el int 25000',
      (tester) async {
        final appt = _confirmedAppt('appt-typed');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        await tester.pumpWidget(
          _wrap(appointments: [appt], firestore: firestore, billing: null),
        );
        await _openDialog(tester);

        // Único TextField visible antes del de Concepto es el de Monto (sin
        // billing no hay hint de tarifa de referencia).
        await tester.enterText(find.byType(TextField).first, '25000');
        await tester.pumpAndSettle();

        // enterText pasa por los inputFormatters reales → queda agrupado.
        expect(find.text('25.000'), findsOneWidget);

        await tester.tap(find.text('CONFIRMAR COBRO')); // i18n
        await tester.pumpAndSettle();

        final payments = await firestore.collection('payments').get();
        expect(payments.docs, hasLength(1));
        final amount = payments.docs.single.data()['amountArs'];
        expect(amount, 25000);
        expect(amount, isA<int>());
      },
    );
  });

  group('el prellenado sin editar se guarda intacto', () {
    testWidgets(
      'abrir, no tocar el campo, confirmar → se guarda amountArs × count',
      (tester) async {
        final appts = [
          _confirmedAppt('appt-batch-1'),
          _confirmedAppt('appt-batch-2'),
        ];
        for (final appt in appts) {
          await firestore
              .collection('appointments')
              .doc(appt.id)
              .set(appt.toJson());
        }
        final billing = AthleteBilling(
          trainerId: _kTrainerId,
          athleteId: _kAthleteId,
          amountArs: 8000,
          cadence: BillingCadence.suelto,
          updatedAt: DateTime.utc(2026, 1, 1),
        );

        await tester.pumpWidget(
          _wrap(appointments: appts, firestore: firestore, billing: billing),
        );
        await _openDialog(tester);

        // Prellenado: 8000 × 2 = 16000 → "16.000".
        expect(find.text('16.000'), findsOneWidget);

        await tester.tap(find.text('CONFIRMAR COBRO')); // i18n
        await tester.pumpAndSettle();

        final payments = await firestore.collection('payments').get();
        expect(payments.docs, hasLength(1));
        final amount = payments.docs.single.data()['amountArs'];
        expect(amount, 8000 * appts.length);
        expect(amount, isA<int>());

        // Ambos turnos quedaron linkeados al mismo Payment.
        for (final appt in appts) {
          final snap =
              await firestore.collection('appointments').doc(appt.id).get();
          expect(snap.data()!['paymentId'], payments.docs.single.id);
        }
      },
    );
  });
}
