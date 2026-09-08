// NotificacionesTab — Fase 12 WU-05.
//
// Cubre: TreinoStateSwitcher + skeleton de matriz (no spinner seco) en
// loading, la matriz real (grupos + checkboxes) en data, el save-on-toggle
// persistiendo `notificationPrefs` (preservado de W3.2), copy honesto sin
// crashear en error, y que el pie diga a dónde llega cada canal. El
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

  // WhatsApp dejó de ser una columna: prometía un canal que no existe. Estos
  // tests fijan que el dato viejo no vuelva por la ventana — hay documentos de
  // W3.2 con `whatsapp: true` guardado, y ese valor NUNCA fue un opt-in
  // informado (nadie eligió recibir WhatsApp; eligieron tildar una casilla que
  // no entregaba nada).
  group('NotifPrefs — WhatsApp ya no es un canal', () {
    Map<String, dynamic> docViejoConWhatsapp() => {
          for (final t in kNotifTypes)
            t.key: {'email': false, 'push': true, 'whatsapp': true},
        };

    test('la matriz tiene exactamente email y push', () {
      expect(NotifChannel.values, [NotifChannel.email, NotifChannel.push]);
    });

    test('un doc viejo con whatsapp no rompe la lectura', () {
      final prefs = NotifPrefs.fromFirestore(docViejoConWhatsapp());
      for (final t in kNotifTypes) {
        expect(prefs.isOn(t.key, NotifChannel.email), isFalse, reason: t.key);
        expect(prefs.isOn(t.key, NotifChannel.push), isTrue, reason: t.key);
      }
    });

    test('toFirestore no vuelve a escribir la clave whatsapp', () {
      final guardado = NotifPrefs.fromFirestore(docViejoConWhatsapp())
          .toggle(kNotifTypes.first.key, NotifChannel.email, true)
          .toFirestore();

      for (final t in kNotifTypes) {
        expect((guardado[t.key] as Map).containsKey('whatsapp'), isFalse,
            reason: '"${t.key}": el canal no existe, no se persiste.');
        expect((guardado[t.key] as Map).keys.toSet(), {'email', 'push'},
            reason: t.key);
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

    testWidgets('la matriz rinde 2 columnas y las dos son tildeables',
        (tester) async {
      await tester.pumpWidget(
        _harness(prefsStream: Stream.value(NotifPrefs.fromFirestore(null))),
      );
      await tester.pumpAndSettle();

      expect(find.text('EMAIL'), findsOneWidget);
      expect(find.text('PUSH'), findsOneWidget);
      expect(find.text('WHATSAPP'), findsNothing);

      final checkboxes = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .toList(growable: false);
      expect(checkboxes, hasLength(kNotifTypes.length * 2));

      // Ninguna casilla muerta: si una celda está, entrega. Ésa es la regla que
      // este cambio vino a instalar.
      for (final c in checkboxes) {
        expect(c.onChanged, isNotNull);
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

    testWidgets('el pie dice a dónde llega cada canal, y no promete WhatsApp',
        (tester) async {
      await tester.pumpWidget(
        _harness(prefsStream: Stream.value(NotifPrefs.fromFirestore(null))),
      );
      await tester.pumpAndSettle();

      // El pie es lo único que explica que push y email llegan a lugares
      // distintos: el push a la app del teléfono, el mail a la casilla de
      // Firebase Auth (`getAuth().getUser(uid).email` en send-queued-mail.ts).
      expect(find.textContaining('en tu teléfono'), findsOneWidget);
      expect(find.textContaining('iniciás sesión'), findsOneWidget);

      // Y ya no queda promesa de un canal inexistente en ningún lado.
      expect(find.textContaining('WhatsApp'), findsNothing);
    });
  });
}
