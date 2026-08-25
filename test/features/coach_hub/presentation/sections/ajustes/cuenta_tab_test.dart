// CuentaTab — Fase 12 WU-03/WU-04.
//
// Cubre: TreinoStateSwitcher + skeleton (no spinner seco) en loading, datos
// reales en data, copy honesto sin crashear en error, el deep-link tappable
// «perfil público» → /perfil-publico, y las confirmaciones honestas de la
// zona peligrosa (WU-04) vía TreinoDialog. El resto de la lógica de guardado
// (GUARDAR CAMBIOS, foto) ya está cubierto por ajustes_screen_test.dart — no
// se duplica acá.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/cuenta_tab.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

class _MockUserRepo extends Mock implements UserRepository {}

// El save de INFORMACIÓN PERSONAL (GUARDAR CAMBIOS/foto) ya se cubre con
// mocks reales en `ajustes_screen_test.dart` — acá solo se mockea
// `userRepositoryProvider` para probar que la zona peligrosa NO dispara
// ninguna mutación (WU-04).
UserProfile _trainer() => UserProfile(
      uid: 'pf1',
      email: 'sofia@treino.app',
      displayName: 'Sofía Ramírez',
      role: UserRole.trainer,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );

Widget _harness({
  required Stream<UserProfile?> profileStream,
  UserRepository? repo,
}) =>
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith((ref) => profileStream),
        trainerLinksStreamProvider
            .overrideWith((ref) => Stream<List<TrainerLink>>.value(const [])),
        if (repo != null) userRepositoryProvider.overrideWithValue(repo),
      ],
      // SingleChildScrollView: mismo wrapper que usa `ajustes_screen.dart`
      // en producción (_TabBody) — sin esto el contenido de Cuenta desborda
      // el viewport fijo de test (800x600).
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: CuentaTab())),
      ),
    );

void main() {
  setUpAll(() => registerFallbackValue(<String, Object?>{}));

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

  group('CuentaTab — zona peligrosa: confirmaciones honestas (Fase 12 WU-04)',
      () {
    // Copy honesto: sin backend real de pausar/eliminar desde la web, el
    // dialog debe mencionar la app móvil o dejar explícito que es
    // "próximamente" — nunca prometer una acción que no ejecuta nada.
    bool honestCopy(Widget widget) {
      if (widget is! Text) return false;
      final text = (widget.data ?? '').toLowerCase();
      return text.contains('app') ||
          text.contains('móvil') ||
          text.contains('movil') ||
          text.contains('próximamente') ||
          text.contains('proximamente');
    }

    testWidgets(
        'tocar ELIMINAR CUENTA abre un TreinoDialog honesto (no ejecuta '
        'nada)', (tester) async {
      final repo = _MockUserRepo();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        _harness(profileStream: Stream.value(_trainer()), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('ELIMINAR CUENTA'));
      await tester.tap(find.text('ELIMINAR CUENTA'));
      await tester.pumpAndSettle();

      expect(find.byType(TreinoDialog), findsOneWidget);
      expect(find.byWidgetPredicate(honestCopy), findsWidgets);
      verifyNever(() => repo.update(any(), any()));
    });

    testWidgets(
        'el dialog de ELIMINAR CUENTA: Cancelar lo cierra sin mutar la '
        'cuenta', (tester) async {
      final repo = _MockUserRepo();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        _harness(profileStream: Stream.value(_trainer()), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('ELIMINAR CUENTA'));
      await tester.tap(find.text('ELIMINAR CUENTA'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dialog_secondary_button')));
      await tester.pumpAndSettle();

      expect(find.byType(TreinoDialog), findsNothing);
      verifyNever(() => repo.update(any(), any()));
    });

    testWidgets(
        'el dialog de ELIMINAR CUENTA: confirmar (Entendido) tampoco muta '
        'la cuenta', (tester) async {
      final repo = _MockUserRepo();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        _harness(profileStream: Stream.value(_trainer()), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('ELIMINAR CUENTA'));
      await tester.tap(find.text('ELIMINAR CUENTA'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dialog_primary_button')));
      await tester.pumpAndSettle();

      expect(find.byType(TreinoDialog), findsNothing);
      verifyNever(() => repo.update(any(), any()));
    });

    testWidgets('tocar PAUSAR CUENTA abre un TreinoDialog honesto',
        (tester) async {
      final repo = _MockUserRepo();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        _harness(profileStream: Stream.value(_trainer()), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('PAUSAR CUENTA'));
      await tester.tap(find.text('PAUSAR CUENTA'));
      await tester.pumpAndSettle();

      expect(find.byType(TreinoDialog), findsOneWidget);
      expect(find.byWidgetPredicate(honestCopy), findsWidgets);
      verifyNever(() => repo.update(any(), any()));
    });
  });
}
