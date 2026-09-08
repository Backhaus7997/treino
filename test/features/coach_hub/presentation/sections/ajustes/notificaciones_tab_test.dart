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

  // Encontrado en revisión automática (Codex, P2 sobre el PR #997): ocultar la
  // casilla no alcanzaba. `toFirestore` serializa desde `_matrix`, no desde lo
  // que la UI muestra, así que un `whatsapp: true` viejo sobrevivía a cada
  // guardado y el día que el canal exista esos PF recibirían mensajes que
  // creían haber apagado. La UI decía "off" y el dato decía "on".
  group('NotifPrefs — WhatsApp no se persiste mientras el canal no exista', () {
    Map<String, dynamic> conWhatsappPrendido() => {
          for (final t in kNotifTypes)
            t.key: {'email': false, 'push': true, 'whatsapp': true},
        };

    test('un true guardado se lee como false', () {
      final prefs = NotifPrefs.fromFirestore(conWhatsappPrendido());
      for (final t in kNotifTypes) {
        expect(prefs.isOn(t.key, NotifChannel.whatsapp), isFalse,
            reason: t.key);
      }
    });

    test('guardar de nuevo NO re-serializa el true viejo: lo limpia', () {
      final prefs = NotifPrefs.fromFirestore(conWhatsappPrendido());
      // Togglear OTRA columna es lo que dispara el guardado real en la UI.
      final guardado = prefs
          .toggle(kNotifTypes.first.key, NotifChannel.email, true)
          .toFirestore();

      for (final t in kNotifTypes) {
        expect((guardado[t.key] as Map)['whatsapp'], false, reason: t.key);
      }
    });

    test('email y push conservan lo que el PF eligió', () {
      final prefs = NotifPrefs.fromFirestore(conWhatsappPrendido());
      final guardado = prefs.toFirestore();
      for (final t in kNotifTypes) {
        expect((guardado[t.key] as Map)['email'], false, reason: t.key);
        expect((guardado[t.key] as Map)['push'], true, reason: t.key);
      }
    });
  });

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

    testWidgets('data: muestra NOTIFICACIONES, PUSH, ALUMNOS y las filas',
        (tester) async {
      await tester.pumpWidget(
        _harness(prefsStream: Stream.value(NotifPrefs.fromFirestore(null))),
      );
      // pumpAndSettle: deja completar el cross-fade de TreinoStateSwitcher
      // (loading → data) antes de inspeccionar.
      await tester.pumpAndSettle();

      expect(find.text('NOTIFICACIONES'), findsOneWidget);
      expect(find.text('PUSH'), findsOneWidget);
      expect(find.text('ALUMNOS'), findsOneWidget);
      expect(find.text('Nueva solicitud de vinculación'), findsOneWidget);
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

      // Primer checkbox = nueva_solicitud × EMAIL (default on) → lo apago.
      // `nueva_solicitud` es una de las dos filas de kEmailBackedTypes.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      final captured = verify(() => repo.update('pf1', captureAny()))
          .captured
          .single as Map<String, Object?>;
      final prefs = captured['notificationPrefs'] as Map<String, dynamic>;
      expect((prefs['nueva_solicitud'] as Map)['email'], false);
      expect((prefs['nueva_solicitud'] as Map)['push'], true);
    });

    testWidgets('WhatsApp está deshabilitado pero Email y Push siguen activos',
        (tester) async {
      await tester.pumpWidget(
        _harness(prefsStream: Stream.value(NotifPrefs.fromFirestore(null))),
      );
      await tester.pumpAndSettle();

      final checkboxes = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .toList(growable: false);
      expect(checkboxes, hasLength(kNotifTypes.length * 3));

      for (var row = 0; row < kNotifTypes.length; row++) {
        expect(checkboxes[row * 3].onChanged, isNotNull, reason: 'Email');
        expect(checkboxes[row * 3 + 1].onChanged, isNotNull, reason: 'Push');
        expect(checkboxes[row * 3 + 2].onChanged, isNull, reason: 'WhatsApp');
      }
    });

    // Regresión: la columna se pudo tildar desde W3.2, así que hay PF con
    // `whatsapp: true` guardado. Deshabilitar la casilla sin bajar el valor la
    // dejaría tildada Y sin forma de destildarla — o sea, prometiendo entrega
    // por un canal que no existe y encima trabando el control. Peor que antes.
    testWidgets('WhatsApp se ve destildado aunque haya un true guardado',
        (tester) async {
      final guardado = NotifPrefs.fromFirestore(<String, dynamic>{
        for (final t in kNotifTypes)
          t.key: <String, dynamic>{
            'email': false,
            'push': true,
            'whatsapp': true,
          },
      });

      await tester.pumpWidget(_harness(prefsStream: Stream.value(guardado)));
      await tester.pumpAndSettle();

      final checkboxes = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .toList(growable: false);

      for (var row = 0; row < kNotifTypes.length; row++) {
        expect(checkboxes[row * 3 + 2].value, isFalse,
            reason: 'WhatsApp fila $row');
      }
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
        find.textContaining('WhatsApp se activa'),
        findsOneWidget,
      );
    });
  });
}
