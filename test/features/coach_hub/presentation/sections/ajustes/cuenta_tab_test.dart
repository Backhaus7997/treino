// CuentaTab — Fase 12 WU-03.
//
// Cubre: TreinoStateSwitcher + skeleton (no spinner seco) en loading, datos
// reales en data, copy honesto sin crashear en error, y el deep-link
// tappable «perfil público» → /perfil-publico. El resto de la lógica de
// guardado (GUARDAR CAMBIOS, foto, zona peligrosa) ya está cubierto por
// ajustes_screen_test.dart — no se duplica acá.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/cuenta_tab.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// El save (GUARDAR CAMBIOS/foto/zona peligrosa) ya se cubre con mocks reales
// en `ajustes_screen_test.dart` — acá no se ejercita, así que no hace falta
// mockear `userRepositoryProvider`/`avatarWebUploaderProvider`.
UserProfile _trainer() => UserProfile(
      uid: 'pf1',
      email: 'sofia@treino.app',
      displayName: 'Sofía Ramírez',
      role: UserRole.trainer,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );

Widget _harness({required Stream<UserProfile?> profileStream}) => ProviderScope(
      overrides: [
        userProfileProvider.overrideWith((ref) => profileStream),
        trainerLinksStreamProvider
            .overrideWith((ref) => Stream<List<TrainerLink>>.value(const [])),
      ],
      // SingleChildScrollView: mismo wrapper que usa `ajustes_screen.dart`
      // en producción (_TabBody) — sin esto el contenido de Cuenta desborda
      // el viewport fijo de test (800x600).
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: CuentaTab())),
      ),
    );

void main() {
  group('CuentaTab — estados async y motion (Fase 12 WU-03)', () {
    testWidgets('loading: muestra el skeleton, no el spinner seco',
        (tester) async {
      final controller = StreamController<UserProfile?>();
      addTearDown(controller.close);

      await tester.pumpWidget(_harness(profileStream: controller.stream));
      await tester.pump();

      expect(find.byKey(const Key('cuenta_skeleton')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('data: muestra INFORMACIÓN PERSONAL y los datos del perfil',
        (tester) async {
      await tester.pumpWidget(
        _harness(profileStream: Stream.value(_trainer())),
      );
      // pumpAndSettle: deja completar el cross-fade de TreinoStateSwitcher
      // (loading → data) antes de inspeccionar — a mitad del fade ambos
      // estados conviven apilados (_topAlignedLayout).
      await tester.pumpAndSettle();

      expect(find.text('INFORMACIÓN PERSONAL'), findsOneWidget);
      expect(find.text('Sofía Ramírez'), findsOneWidget);
      expect(find.text('sofia@treino.app'), findsOneWidget);
      expect(find.byKey(const Key('cuenta_skeleton')), findsNothing);
    });

    testWidgets('error: copy honesto sin crashear', (tester) async {
      await tester.pumpWidget(
        _harness(profileStream: Stream<UserProfile?>.error('boom')),
      );
      await tester.pumpAndSettle();

      expect(find.text('No se pudo cargar tu cuenta.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el caption enlaza a perfil público (elemento tappable)',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _harness(profileStream: Stream.value(_trainer())),
      );
      await tester.pumpAndSettle();

      final linkFinder = find.byKey(const Key('cuenta_perfil_publico_link'));
      expect(linkFinder, findsOneWidget);

      final semantics = tester.getSemantics(linkFinder);
      expect(semantics.flagsCollection.isButton, isTrue,
          reason: 'el deep-link a perfil público debe exponer '
              'Semantics(button: true)');

      handle.dispose();
    });
  });
}
