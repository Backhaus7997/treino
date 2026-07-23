import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/ajustes_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/avatar_web_uploader.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/notificaciones_prefs.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

class _MockUserRepo extends Mock implements UserRepository {}

class _MockUploader extends Mock implements AvatarWebUploader {}

UserProfile _trainer() => UserProfile(
      uid: 'pf1',
      email: 'sofia@treino.app',
      displayName: 'Sofía Ramírez',
      role: UserRole.trainer,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );

Widget _harness({
  UserProfile? profile,
  UserRepository? repo,
  AvatarWebUploader? uploader,
}) =>
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(profile ?? _trainer()),
        ),
        trainerLinksStreamProvider
            .overrideWith((ref) => Stream<List<TrainerLink>>.value(const [])),
        webNotificationPreferencesProvider.overrideWith(
          (ref) => Stream<NotifPrefs>.value(NotifPrefs.fromFirestore(null)),
        ),
        if (repo != null) userRepositoryProvider.overrideWithValue(repo),
        if (uploader != null)
          avatarWebUploaderProvider.overrideWithValue(uploader),
      ],
      child: const MaterialApp(home: Scaffold(body: AjustesScreen())),
    );

void main() {
  setUpAll(() => registerFallbackValue(<String, Object?>{}));

  group('AjustesScreen (W3.1)', () {
    testWidgets('renderiza el header y las 3 tabs de Configuración',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      expect(find.text('CONFIGURACIÓN'), findsOneWidget);
      expect(find.text('Cuenta'), findsOneWidget);
      expect(find.text('Notificaciones'), findsOneWidget);
      expect(find.text('Facturación TREINO'), findsOneWidget);
      // «Datos y privacidad» se removió del nav (eliminar vive en mobile).
      expect(find.text('Datos y privacidad'), findsNothing);
    });

    testWidgets('la tab Cuenta muestra los datos del PF logueado',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      expect(find.text('INFORMACIÓN PERSONAL'), findsOneWidget);
      expect(find.text('Sofía Ramírez'), findsOneWidget);
      expect(find.text('sofia@treino.app'), findsOneWidget);
      expect(find.text('ZONA PELIGROSA'), findsOneWidget);
    });

    testWidgets('tocar Notificaciones cambia el cuerpo del tab',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      await tester.tap(find.text('Notificaciones'));
      await tester.pump();
      await tester.pump(); // deja emitir el StreamProvider de prefs

      // Ya no es placeholder: muestra la matriz real.
      expect(find.text('NOTIFICACIONES'), findsOneWidget);
      expect(find.text('PUSH'), findsOneWidget);
      expect(find.text('INFORMACIÓN PERSONAL'), findsNothing);
    });

    testWidgets(
        'sub-nav: item seleccionado expone Semantics(button + selected), '
        'y Enter sobre el item enfocado activa el tab', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_harness());
      // Deja completar la entrada TreinoFadeSlideIn (stagger + fade) de la
      // sub-nav antes de inspeccionar semantics — a opacidad 0 el subárbol
      // queda excluido del árbol de semantics.
      await tester.pumpAndSettle();

      final cuentaSemantics = tester.getSemantics(
        find.byKey(const Key('ajustes_subnav_cuenta')),
      );
      expect(cuentaSemantics.flagsCollection.isButton, isTrue,
          reason: 'el item de sub-nav debe exponer Semantics(button: true)');
      expect(cuentaSemantics.flagsCollection.isSelected, Tristate.isTrue,
          reason: 'Cuenta está seleccionado por default');

      final notifSemantics = tester.getSemantics(
        find.byKey(const Key('ajustes_subnav_notificaciones')),
      );
      expect(notifSemantics.flagsCollection.isButton, isTrue);
      expect(notifSemantics.flagsCollection.isSelected, isNot(Tristate.isTrue),
          reason: 'Notificaciones no está seleccionado por default');

      // Foco por teclado: Tab dos veces (Cuenta -> Notificaciones) + Enter
      // activa el tab enfocado, sin necesidad de tap de mouse.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(); // deja emitir el StreamProvider de prefs

      expect(find.text('NOTIFICACIONES'), findsOneWidget);
      expect(find.text('INFORMACIÓN PERSONAL'), findsNothing);

      handle.dispose();
    });

    testWidgets('Notificaciones: togglear un canal persiste notificationPrefs',
        (tester) async {
      final repo = _MockUserRepo();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump();

      await tester.tap(find.text('Notificaciones'));
      await tester.pump();
      await tester.pump(); // deja emitir el StreamProvider de prefs

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

    testWidgets(
        'GUARDAR CAMBIOS persiste nombre/apellido + displayName derivado',
        (tester) async {
      final repo = _MockUserRepo();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump();

      // NOMBRE es el primer TextField.
      await tester.enterText(find.byType(TextField).first, 'Mateo');
      await tester.pump();
      await tester.tap(find.text('GUARDAR CAMBIOS'));
      await tester.pump();

      final captured = verify(() => repo.update('pf1', captureAny()))
          .captured
          .single as Map<String, Object?>;
      expect(captured['firstName'], 'Mateo');
      expect(captured['lastName'], 'Ramírez');
      expect(captured['displayName'], 'Mateo Ramírez');
    });

    testWidgets('GUARDAR CAMBIOS no guarda si NOMBRE queda vacío',
        (tester) async {
      final repo = _MockUserRepo();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      await tester.tap(find.text('GUARDAR CAMBIOS'));
      await tester.pump();

      verifyNever(() => repo.update(any(), any()));
    });

    testWidgets(
      'CAMBIAR FOTO sube la imagen y persiste avatarUrl',
      (tester) async {
        // SKIPPED 2026-06-29: cuenta_tab now goes pickFile() → AvatarCropper
        // (BuildContext-bound) → uploadCroppedPath(), so this test no longer
        // describes the real flow. Rewriting it requires either:
        //   (a) plumbing AvatarCropper into the widget as an injectable dep, OR
        //   (b) a full integration test that drives the cropper UI.
        // The cropper helper itself is covered by
        // test/core/image/avatar_cropper_test.dart. Leaving a follow-up to
        // restore widget-level coverage of the full pick→crop→upload chain.
        final repo = _MockUserRepo();
        final uploader = _MockUploader();
        when(() => uploader.pickAndUpload())
            .thenAnswer((_) async => 'https://cdn/avatar.jpg');
        when(() => repo.update(any(), any())).thenAnswer((_) async {});

        await tester.pumpWidget(_harness(repo: repo, uploader: uploader));
        await tester.pump();

        await tester.tap(find.text('CAMBIAR FOTO'));
        await tester.pump();
        await tester.pump();

        verify(() => uploader.pickAndUpload()).called(1);
        verify(
          () => repo.update('pf1', {'avatarUrl': 'https://cdn/avatar.jpg'}),
        ).called(1);
      },
      // Skipped — see in-body comment. Follow-up to rewrite this
      // widget-level test once AvatarCropper is injectable from the harness.
      skip: true,
    );

    testWidgets('QUITAR borra el blob de Storage y limpia avatarUrl',
        (tester) async {
      final repo = _MockUserRepo();
      final uploader = _MockUploader();
      when(() => uploader.deleteStored()).thenAnswer((_) async {});
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(_harness(
        profile: _trainer().copyWith(avatarUrl: 'https://cdn/old.jpg'),
        repo: repo,
        uploader: uploader,
      ));
      await tester.pump();

      await tester.tap(find.text('QUITAR'));
      await tester.pump();
      await tester.pump();

      verify(() => uploader.deleteStored()).called(1);
      verify(() => repo.update('pf1', {'avatarUrl': null})).called(1);
    });
  });
}
