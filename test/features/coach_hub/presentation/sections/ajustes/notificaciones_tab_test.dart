// NotificacionesTab — Fase 12 WU-05.
//
// Cubre: TreinoStateSwitcher + skeleton de matriz (no spinner seco) en
// loading, la matriz real (grupos + checkboxes) en data, el save-on-toggle
// persistiendo `notificationPrefs` (preservado de W3.2), copy honesto sin
// crashear en error, y que la nota honesta de entrega siga presente. El
// resto del flujo (integración con AjustesScreen/sub-nav) ya está cubierto
// por `ajustes_screen_test.dart` — no se duplica acá.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/notificaciones_prefs.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/notificaciones_tab.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

class _MockUserRepo extends Mock implements UserRepository {}

UserProfile _trainer() => UserProfile(
      uid: 'pf1',
      email: 'sofia@treino.app',
      displayName: 'Sofía Ramírez',
      role: UserRole.trainer,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );

Widget _harness({
  required Stream<NotifPrefs> prefsStream,
  UserRepository? repo,
}) =>
    ProviderScope(
      overrides: [
        webNotificationPreferencesProvider.overrideWith((ref) => prefsStream),
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(_trainer())),
        if (repo != null) userRepositoryProvider.overrideWithValue(repo),
      ],
      // SingleChildScrollView: mismo wrapper que usa `ajustes_screen.dart`
      // en producción (_TabBody) — sin esto el contenido desborda el
      // viewport fijo de test (800x600).
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: NotificacionesTab())),
      ),
    );

void main() {
  setUpAll(() => registerFallbackValue(<String, Object?>{}));

  group('NotificacionesTab — estados async y motion (Fase 12 WU-05)', () {
    testWidgets('loading: muestra el skeleton de la matriz, no el spinner',
        (tester) async {
      final controller = StreamController<NotifPrefs>();
      addTearDown(controller.close);

      await tester.pumpWidget(_harness(prefsStream: controller.stream));
      await tester.pump();

      expect(find.byKey(const Key('notif_skeleton')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('data: muestra NOTIFICACIONES, PUSH, PAGOS y las filas',
        (tester) async {
      await tester.pumpWidget(
        _harness(prefsStream: Stream.value(NotifPrefs.fromFirestore(null))),
      );
      // pumpAndSettle: deja completar el cross-fade de TreinoStateSwitcher
      // (loading → data) antes de inspeccionar.
      await tester.pumpAndSettle();

      expect(find.text('NOTIFICACIONES'), findsOneWidget);
      expect(find.text('PUSH'), findsOneWidget);
      expect(find.text('PAGOS'), findsOneWidget);
      expect(find.text('Pago recibido'), findsOneWidget);
      expect(find.byKey(const Key('notif_skeleton')), findsNothing);
    });

    testWidgets('togglear el primer Checkbox persiste notificationPrefs',
        (tester) async {
      final repo = _MockUserRepo();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(_harness(
        prefsStream: Stream.value(NotifPrefs.fromFirestore(null)),
        repo: repo,
      ));
      await tester.pumpAndSettle();

      // Primer checkbox = pago_recibido × EMAIL (default on) → lo apago.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      final captured = verify(() => repo.update('pf1', captureAny()))
          .captured
          .single as Map<String, Object?>;
      final prefs = captured['notificationPrefs'] as Map<String, dynamic>;
      expect((prefs['pago_recibido'] as Map)['email'], false);
      expect((prefs['pago_recibido'] as Map)['push'], true);
    });

    testWidgets('error: copy honesto sin crashear', (tester) async {
      await tester.pumpWidget(
        _harness(prefsStream: Stream<NotifPrefs>.error('boom')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No se pudieron cargar tus preferencias.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('la nota honesta de entrega por email/WhatsApp sigue presente',
        (tester) async {
      await tester.pumpWidget(
        _harness(prefsStream: Stream.value(NotifPrefs.fromFirestore(null))),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('La entrega por email y WhatsApp se activa'),
        findsOneWidget,
      );
    });
  });
}
