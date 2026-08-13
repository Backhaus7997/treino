import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/presentation/trainer_dashboard_tab.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfileProvider;
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// QA H3: el "Resumen del día" hacía `apptAsync.valueOrNull ?? []`, colapsando
// loading Y error a 0/0/0 — un permission-denied (App Check no registrado) se
// leía como un día tranquilo. Ahora distingue los estados con `.when`, igual
// que su hermano _ProximasSesionesList (mismo provider).

const _kTrainer = 'trainer-1';

UserProfile _trainer() => UserProfile(
      uid: _kTrainer,
      email: 'mateo@test.com',
      displayName: 'Mateo',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _pump(
  WidgetTester tester, {
  required Override apptOverride,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_kTrainer),
        userProfileProvider.overrideWith((ref) => Stream.value(_trainer())),
        userPublicProfileProvider.overrideWith(
          (ref, uid) => Stream<UserPublicProfile?>.value(null),
        ),
        trainerLinksStreamProvider
            .overrideWith((ref) => Stream.value(const <TrainerLink>[])),
        apptOverride,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: TrainerDashboardTab()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('Resumen del día — estados del stream de turnos', () {
    testWidgets('error → muestra mensaje, NO 0/0/0', (tester) async {
      await _pump(
        tester,
        apptOverride: trainerAppointmentsStreamProvider.overrideWith(
          (ref, key) =>
              Stream<List<Appointment>>.error(Exception('permission-denied')),
        ),
      );

      expect(
          find.text('No pudimos cargar el resumen del día.'), findsOneWidget);
      // La fila de stats se reemplaza entera: sus labels desaparecen, así que
      // el PF no ve "0 PENDIENTES / 0 COMPLETADAS / 0 CANCELADAS" mintiendo.
      expect(find.text('PENDIENTES'), findsNothing);
    });

    testWidgets('data (día vacío legítimo) → 0/0/0 real, sin mensaje de error',
        (tester) async {
      await _pump(
        tester,
        apptOverride: trainerAppointmentsStreamProvider.overrideWith(
          (ref, key) => Stream.value(const <Appointment>[]),
        ),
      );

      // Con data real, 0/0/0 SÍ es correcto (día sin turnos) — y no hay error.
      expect(find.text('No pudimos cargar el resumen del día.'), findsNothing);
      expect(find.text('PENDIENTES'), findsOneWidget);
      expect(find.text('COMPLETADAS'), findsOneWidget);
    });

    testWidgets('loading → guiones, sin 0 ni mensaje de error', (tester) async {
      final controller = StreamController<List<Appointment>>();
      addTearDown(controller.close);
      await _pump(
        tester,
        apptOverride: trainerAppointmentsStreamProvider
            .overrideWith((ref, key) => controller.stream),
      );

      // Nunca emite → loading. Los stat columns muestran "—", no "0".
      expect(find.text('No pudimos cargar el resumen del día.'), findsNothing);
      expect(find.text('PENDIENTES'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
    });
  });
}
