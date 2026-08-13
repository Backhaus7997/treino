import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/presentation/trainer_dashboard_tab.dart'
    show AddSueltoSheetTestHarness;
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart'
    show argentinaNow, argentinaUtcOffset;
import 'package:treino/features/payments/application/payment_providers.dart'
    show paymentRepositoryProvider;
import 'package:treino/features/payments/data/payment_repository.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

// Slice 1 follow-up — manual charges own their due date.
//
// Deleting generateDuePayments removed the only dueAt writer, so a pending
// charge created via the "+ Cobro" sheet never reached the dueAt-based
// Vencidos bucket (pagos_buckets_provider.dart falls back to the legacy
// calendar-month rule) and never triggered the notifyOverduePayments CF
// (whose `dueAt <= now` query excludes docs missing the field). The sheet now
// offers an OPTIONAL "Vence el" date; these tests pin its contract:
//
//   1. no date picked      → Payment persisted with dueAt == null (unchanged)
//   2. date picked         → dueAt == 23:59:59 ART of the chosen day (as UTC
//                            instant), matching the old CF normalization so
//                            "vence el 15" is not overdue at 00:01 of the 15th
//   3. date picked+cleared → dueAt == null again (the field is optional both
//                            ways)
//
// The dueAt-based Vencidos bucketing itself is already pinned by
// test/features/payments/application/pagos_buckets_vencido_test.dart
// (SCENARIO-VENC-08: past dueAt + current-month createdAt → vencidos).

const _kTrainerId = 'trainer-uid-due';
const _kAthleteId = 'athlete-uid-due';

// ─── Stub repository ─────────────────────────────────────────────────────────

/// Captura el [Payment] pasado a [add] — el assert central de estos tests.
class _StubPaymentRepository extends Fake implements PaymentRepository {
  Payment? captured;

  @override
  Future<void> add(Payment payment) async {
    captured = payment;
  }
}

// ─── Factories ───────────────────────────────────────────────────────────────

TrainerLink _activeLink() => TrainerLink(
      id: 'link-$_kAthleteId',
      trainerId: _kTrainerId,
      athleteId: _kAthleteId,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 1),
      sharedWithTrainer: true,
    );

UserPublicProfile _pub() => const UserPublicProfile(
      uid: _kAthleteId,
      displayName: 'Ana López',
      displayNameLowercase: 'ana lópez',
    );

// ─── Harness ─────────────────────────────────────────────────────────────────

/// Monta un botón "abrir" que abre el sheet vía [showModalBottomSheet] —
/// mismo plumbing que producción, para que el `Navigator.pop()` del submit
/// tenga una ruta real que cerrar.
Widget _app(_StubPaymentRepository repo) => ProviderScope(
      overrides: [
        trainerLinksStreamProvider.overrideWith(
          (ref) => Stream.value([_activeLink()]),
        ),
        userPublicProfileProvider(_kAthleteId).overrideWith(
          (ref) => Stream.value(_pub()),
        ),
        paymentRepositoryProvider.overrideWithValue(repo),
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
                builder: (_) =>
                    const AddSueltoSheetTestHarness(trainerId: _kTrainerId),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

/// Abre el sheet y completa alumno + monto + concepto (deja "Vence el" vacío).
Future<void> _openAndFillRequired(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();

  // Alumno
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ana López').last);
  await tester.pumpAndSettle();

  // Monto + concepto (los dos únicos TextField del sheet).
  await tester.enterText(find.byType(TextField).at(0), '5000');
  await tester.enterText(find.byType(TextField).at(1), 'Clase de verano');
  await tester.pumpAndSettle();
}

String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

void main() {
  testWidgets(
    'sin fecha elegida → Payment pending con dueAt null',
    (tester) async {
      final repo = _StubPaymentRepository();
      await tester.pumpWidget(_app(repo));
      await _openAndFillRequired(tester);

      await tester.tap(find.text('AGREGAR COBRO'));
      await tester.pumpAndSettle();

      final p = repo.captured;
      expect(p, isNotNull);
      expect(p!.status, PaymentStatus.pending);
      expect(p.amountArs, 5000);
      expect(p.dueAt, isNull);
    },
  );

  testWidgets(
    'con fecha elegida → dueAt = 23:59:59 ART del día elegido (instante UTC)',
    (tester) async {
      final repo = _StubPaymentRepository();
      // El picker abre con initialDate = hoy ART; ACEPTAR confirma ese día.
      final todayArt = argentinaNow();

      await tester.pumpWidget(_app(repo));
      await _openAndFillRequired(tester);

      // Abrir el date picker desde el campo "Vence el".
      await tester.tap(find.text('Sin fecha de vencimiento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();

      // El campo muestra la fecha elegida (dd/MM/yyyy).
      expect(find.text(_fmt(todayArt)), findsOneWidget);

      await tester.tap(find.text('AGREGAR COBRO'));
      await tester.pumpAndSettle();

      final p = repo.captured;
      expect(p, isNotNull);
      // 23:59:59 ART == +3h como instante UTC (misma normalización que usaba
      // la CF generateDuePayments para fin de período).
      final expectedDueAt = DateTime.utc(
        todayArt.year,
        todayArt.month,
        todayArt.day,
        23,
        59,
        59,
      ).add(argentinaUtcOffset);
      expect(p!.dueAt, equals(expectedDueAt));
      expect(p.dueAt!.isUtc, isTrue);
    },
  );

  testWidgets(
    'fecha elegida y luego quitada (X) → dueAt vuelve a null',
    (tester) async {
      final repo = _StubPaymentRepository();
      final todayArt = argentinaNow();

      await tester.pumpWidget(_app(repo));
      await _openAndFillRequired(tester);

      await tester.tap(find.text('Sin fecha de vencimiento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();
      expect(find.text(_fmt(todayArt)), findsOneWidget);

      // Quitar la fecha con el botón X del campo.
      await tester.tap(
        find.bySemanticsLabel('Quitar fecha de vencimiento'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sin fecha de vencimiento'), findsOneWidget);

      await tester.tap(find.text('AGREGAR COBRO'));
      await tester.pumpAndSettle();

      expect(repo.captured, isNotNull);
      expect(repo.captured!.dueAt, isNull);
    },
  );
}
