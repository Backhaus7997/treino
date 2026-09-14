import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/pending_invite_providers.dart';
import 'package:treino/features/coach/data/pending_invite_store.dart';
import 'package:treino/features/coach/presentation/widgets/invite_gate.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

UserProfile _trainer(String uid) => UserProfile(
      uid: uid,
      email: '$uid@gettreino.com',
      displayName: 'Profe',
      role: UserRole.trainer,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Future<PendingInviteStore> _storeWith(String? trainerId) async {
  SharedPreferences.setMockInitialValues({});
  final store = PendingInviteStore(await SharedPreferences.getInstance());
  // La memoria estática sobrevive entre instancias porque en producción une
  // router y gate; limpiarla acá evita que un test herede la intención de otro.
  await store.limpiar();
  if (trainerId != null) await store.guardar(trainerId);
  return store;
}

Future<void> _pumpGate(
  WidgetTester tester, {
  required UserProfile profile,
  required PendingInviteStore? store,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith((_) => Stream.value(profile)),
        pendingInviteStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: InviteGate()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('La invitación despierta al gate —', () {
    // Reportado en un iPhone 16 con la app instalada: el link abre TREINO,
    // pero el diálogo NO aparece. Hay que navegar a otra pantalla y volver a
    // la home para verlo.
    //
    // La causa es el latch: se marca en `build`, ANTES de saber si la
    // resolución pudo hacer algo. Si en ese instante la invitación todavía no
    // está capturada —o las prefs no resolvieron—, `_resolver` se rinde y el
    // latch ya quedó puesto: no reintenta nunca. Salir y volver remonta el
    // widget con el latch limpio, y por eso "se arregla" solo.
    testWidgets(
        'una invitación que llega DESPUÉS de montado abre el diálogo '
        'sin remontar nada', (tester) async {
      final store = await _storeWith(null);
      await _pumpGate(tester, profile: _trainer('pf-1'), store: store);

      // Todavía nada: no había invitación cuando el gate se montó.
      expect(find.byType(AlertDialog), findsNothing);

      // Ahora llega el deep link, con la home YA montada. Es el caso real:
      // el botón de /abrir/alumno abre la app que ya estaba corriendo.
      await store.guardar('pf-1');
      await tester.pumpAndSettle();

      expect(
        find.text('ESTE ES TU LINK DE INVITACIÓN'),
        findsOneWidget,
        reason: 'el gate tiene que reaccionar a la invitación, no sólo al '
            'perfil',
      );
    });

    testWidgets('las prefs que resuelven tarde no se pierden la invitación',
        (tester) async {
      // `pendingInviteStoreProvider` devuelve null mientras SharedPreferences
      // no resolvió. El gate no puede darse por resuelto en ese estado.
      SharedPreferences.setMockInitialValues({});
      final store = PendingInviteStore(await SharedPreferences.getInstance());
      await store.limpiar();
      await store.guardar('pf-1');

      final storeProvider = StateProvider<PendingInviteStore?>((_) => null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider
                .overrideWith((_) => Stream.value(_trainer('pf-1'))),
            pendingInviteStoreProvider.overrideWith(
              (ref) => ref.watch(storeProvider),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: InviteGate()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      // Resuelven las prefs.
      final scope = tester.element(find.byType(InviteGate));
      ProviderScope.containerOf(scope).read(storeProvider.notifier).state =
          store;
      await tester.pumpAndSettle();

      expect(
        find.text('ESTE ES TU LINK DE INVITACIÓN'),
        findsOneWidget,
        reason: 'rendirse porque las prefs no estaban listas no puede ser '
            'definitivo',
      );
    });
  });

  testWidgets('un entrenador que tocó un link ajeno recibe feedback',
      (tester) async {
    final store = await _storeWith('pf-otro');

    await _pumpGate(tester, profile: _trainer('pf-1'), store: store);

    expect(find.text('ESTE LINK ES PARA ALUMNOS'), findsOneWidget);
    expect(await store.leer(), isNull, reason: 'el aviso no debe reaparecer');
  });

  testWidgets('un entrenador que prueba su propio link recibe feedback',
      (tester) async {
    final store = await _storeWith('pf-1');

    await _pumpGate(tester, profile: _trainer('pf-1'), store: store);

    expect(find.text('ESTE ES TU LINK DE INVITACIÓN'), findsOneWidget);
    expect(await store.leer(), isNull, reason: 'el aviso no debe reaparecer');
  });

  testWidgets('un arranque normal sin invitación no muestra ruido',
      (tester) async {
    final store = await _storeWith(null);

    await _pumpGate(tester, profile: _trainer('pf-1'), store: store);

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('prefs todavía sin resolver no inventa una intención',
      (tester) async {
    await _pumpGate(tester, profile: _trainer('pf-1'), store: null);

    expect(find.byType(AlertDialog), findsNothing);
  });
}
