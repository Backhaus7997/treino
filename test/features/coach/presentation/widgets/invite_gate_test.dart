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
