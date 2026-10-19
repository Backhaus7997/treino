// #1515 — MI AGENDA: el alumno cancela con más de 24 h y, con menos, le avisa
// a su PF por chat.
//
// Decisión de producto (Martín, 2026-10-16): con menos de 24 h NO hay estado
// nuevo en el turno — «AVISAR A MI PF» abre el chat, y el PF (que desde #1492
// cancela a menos de 24 h) decide.
//
// Los horarios se arman relativos a un reloj congelado, y los márgenes son
// anchos a propósito (3 h y 3 días) para que el resultado no dependa de la
// zona horaria de la máquina: la tarjeta mide el "ya empezó" en wall-clock y
// las 24 h contra el instante real, como el servidor.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/domain/wall_clock.dart';
import 'package:treino/features/coach/presentation/athlete_agenda_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

const _kTrainer = 'trainer-1515';
const _kAthlete = 'athlete-1515';

final _link = TrainerLink(
  id: 'link-1515',
  trainerId: _kTrainer,
  athleteId: _kAthlete,
  status: TrainerLinkStatus.active,
  requestedAt: DateTime.utc(2026, 5, 1),
  acceptedAt: DateTime.utc(2026, 5, 2),
  sharedWithTrainer: true,
);

Appointment _appt(String id, DateTime startsAt) => Appointment(
      id: id,
      trainerId: _kTrainer,
      athleteId: _kAthlete,
      athleteDisplayName: 'Martín',
      startsAt: startsAt,
      durationMin: 60,
      status: AppointmentStatus.confirmed,
    );

Widget _wrap(Appointment appt, FakeFirebaseFirestore firestore) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: AppointmentTile(appointment: appt, now: nowWall()),
        ),
      ),
      GoRoute(
        path: '/coach/chat/:chatId',
        builder: (_, state) => Scaffold(
          body: Text(
            'chat ${state.pathParameters['chatId']} '
            'con ${state.uri.queryParameters['other']}',
          ),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appointmentRepositoryProvider.overrideWithValue(
        AppointmentRepository(firestore: firestore),
      ),
      userPublicProfileProvider.overrideWith((ref, uid) => Stream.value(null)),
      currentAthleteLinkProvider.overrideWith((ref) => Stream.value(_link)),
      chatForLinkProvider.overrideWith(
        (ref, link) async => Chat(
          chatId: 'chat-1515',
          members: [link.athleteId, link.trainerId],
          createdAt: DateTime.utc(2026, 5, 2),
        ),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    AppClock.freeze(DateTime(2026, 7, 1, 9, 0));
  });
  tearDown(AppClock.unfreeze);

  testWidgets('con más de 24 h: CANCELAR cancela como alumno', (tester) async {
    final appt = _appt('t-lejos', nowWall().add(const Duration(days: 3)));
    await firestore.collection('appointments').doc(appt.id).set(appt.toJson());

    await tester.pumpWidget(_wrap(appt, firestore));
    await tester.pumpAndSettle();

    expect(find.text('AVISAR A MI PF'), findsNothing);
    await tester.tap(find.text('CANCELAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, cancelar'));
    await tester.pumpAndSettle();

    final data =
        (await firestore.collection('appointments').doc(appt.id).get()).data()!;
    expect(data['status'], 'cancelled');
    expect(data['cancelledBy'], _kAthlete,
        reason: 'la firma tiene que ser del alumno: el Path 1 la pinea');
    // El aviso es el toast del kit (showTreinoToastOn): el mensaje va con el
    // ícono de éxito, que un SnackBar crudo no tiene.
    final toast = find.byType(SnackBar);
    expect(
      find.descendant(of: toast, matching: find.text('Reserva cancelada.')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: toast, matching: find.byIcon(TreinoIcon.check)),
      findsOneWidget,
    );
  });

  testWidgets('con menos de 24 h: no hay CANCELAR; AVISAR A MI PF abre el chat',
      (tester) async {
    final appt = _appt('t-cerca', nowWall().add(const Duration(hours: 3)));

    await tester.pumpWidget(_wrap(appt, firestore));
    await tester.pumpAndSettle();

    expect(find.text('CANCELAR'), findsNothing);
    expect(
      find.text('Faltan menos de 24 h: si no podés ir, avisale a tu PF.'),
      findsOneWidget,
    );

    await tester.tap(find.text('AVISAR A MI PF'));
    await tester.pumpAndSettle();

    expect(find.text('chat chat-1515 con $_kTrainer'), findsOneWidget);
  });

  testWidgets('con la sesión empezada no hay ninguna acción', (tester) async {
    final appt =
        _appt('t-empezada', nowWall().subtract(const Duration(minutes: 30)));

    await tester.pumpWidget(_wrap(appt, firestore));
    await tester.pumpAndSettle();

    expect(find.text('CANCELAR'), findsNothing);
    expect(find.text('AVISAR A MI PF'), findsNothing);
  });
}
