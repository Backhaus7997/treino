// «Usuarios bloqueados» (#1698), contra un `FakeFirebaseFirestore`: Desbloquear
// borra la arista `blocks/` de verdad y el stream saca la fila.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/moderation/application/moderation_providers.dart';
import 'package:treino/features/moderation/presentation/blocked_users_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Monta la pantalla con [blocked] sembrados (`bbb` = Coach Joe, `ccc` = Ana).
Future<FakeFirebaseFirestore> _pump(
  WidgetTester tester,
  List<String> blocked, {
  List<Override> extra = const [],
}) async {
  final fake = FakeFirebaseFirestore();
  for (final uid in blocked) {
    await fake.collection('blocks').doc('aaa_$uid').set({
      'id': 'aaa_$uid',
      'blockerUid': 'aaa',
      'blockedUid': uid,
      'members': ['aaa', uid],
      'createdAt': Timestamp.now(),
    });
  }
  final names = {'bbb': 'Coach Joe', 'ccc': 'Ana'};
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(fake),
        currentUidProvider.overrideWith((_) => 'aaa'),
        for (final e in names.entries)
          userPublicProfileProvider(e.key).overrideWith(
            (_) => Stream.value(UserPublicProfile(
              uid: e.key,
              displayName: e.value,
              displayNameLowercase: e.value.toLowerCase(),
            )),
          ),
        ...extra,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const Scaffold(body: BlockedUsersScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('lista a cada bloqueado con su nombre y la aclaración',
      (tester) async {
    await _pump(tester, ['bbb', 'ccc']);

    expect(find.text('USUARIOS BLOQUEADOS'), findsOneWidget);
    expect(find.text('COACH JOE'), findsOneWidget);
    expect(find.text('ANA'), findsOneWidget);
    expect(find.text('Desbloquear'), findsNWidgets(2));
    expect(find.textContaining('no restaura los seguimientos'), findsOneWidget);
  });

  testWidgets('Desbloquear borra SÓLO esa arista y la fila se va',
      (tester) async {
    final fake = await _pump(tester, ['bbb', 'ccc']);

    await tester.tap(find.byKey(const ValueKey('unblock-bbb')));
    await tester.pumpAndSettle();

    expect((await fake.collection('blocks').get()).docs.map((d) => d.id),
        ['aaa_ccc']);
    expect(find.text('COACH JOE'), findsNothing);
    expect(find.text('ANA'), findsOneWidget);
    expect(find.text('Desbloqueaste a Coach Joe.'), findsOneWidget);
  });

  testWidgets('si la lista NO cargó → error con Reintentar, no "vacío"',
      (tester) async {
    await _pump(tester, const [], extra: [
      blockedUidsProvider('aaa')
          .overrideWith((_) => Stream<List<String>>.error('sin red')),
    ]);

    expect(find.textContaining('No pudimos cargar tu lista'), findsOneWidget);
    expect(find.text('No bloqueaste a nadie.'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Reintentar'), findsOneWidget);
  });

  testWidgets('cuenta eliminada (sin perfil público) → lo dice',
      (tester) async {
    await _pump(tester, [
      'zzz'
    ], extra: [
      userPublicProfileProvider('zzz')
          .overrideWith((_) => Stream<UserPublicProfile?>.value(null)),
    ]);

    expect(find.text('USUARIO ELIMINADO'), findsOneWidget);
  });
}
