// «Desbloquear» (#1698): `BlockRepository.unblock` no tenía un solo call site,
// así que bloquear no tenía vuelta. Estos tests montan el menú de moderación y
// `unblockUser` REALES contra un `FakeFirebaseFirestore` (la arista `blocks/`
// se borra de verdad) y afirman que el menú ofrece «Desbloquear» sólo cuando
// la persona ya está bloqueada.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/moderation/application/moderation_providers.dart';
import 'package:treino/features/moderation/data/block_repository.dart';
import 'package:treino/features/moderation/domain/report_target_kind.dart';
import 'package:treino/features/moderation/presentation/moderation_actions.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

class _ThrowingBlockRepository extends BlockRepository {
  _ThrowingBlockRepository({required super.firestore});

  @override
  Future<void> unblock(String blockerUid, String blockedUid) =>
      Future.error(StateError('sin permiso'));
}

Future<FakeFirebaseFirestore> _seed({bool blocked = true}) async {
  final fake = FakeFirebaseFirestore();
  if (blocked) {
    await fake.collection('blocks').doc('aaa_bbb').set({
      'id': 'aaa_bbb',
      'blockerUid': 'aaa',
      'blockedUid': 'bbb',
      'members': ['aaa', 'bbb'],
      'createdAt': Timestamp.now(),
    });
  }
  return fake;
}

Future<void> _openMenu(
  WidgetTester tester,
  FakeFirebaseFirestore fake, {
  String uid = 'aaa',
  BlockRepository? repo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(fake),
        currentUidProvider.overrideWith((_) => uid),
        if (repo != null) blockRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showModerationMenu(
                context,
                ref,
                targetKind: ReportTargetKind.profile,
                targetId: 'bbb',
                targetOwnerUid: 'bbb',
                targetOwnerDisplayName: 'Coach Joe',
              ),
              child: const Text('abrir menú'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir menú'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('persona NO bloqueada → el menú ofrece Bloquear, no Desbloquear',
      (tester) async {
    await _openMenu(tester, await _seed(blocked: false));

    expect(find.text('Bloquear'), findsOneWidget);
    expect(find.text('Desbloquear'), findsNothing);
  });

  testWidgets('persona YA bloqueada → el menú ofrece Desbloquear, no Bloquear',
      (tester) async {
    await _openMenu(tester, await _seed());

    expect(find.text('Desbloquear'), findsOneWidget);
    expect(find.text('Bloquear'), findsNothing);
    // Reportar sigue disponible: desbloquear no lo reemplaza.
    expect(find.text('Reportar'), findsOneWidget);
  });

  testWidgets('tocar Desbloquear borra la arista y avisa con el nombre',
      (tester) async {
    final fake = await _seed();
    await _openMenu(tester, fake);

    await tester.tap(find.text('Desbloquear'));
    await tester.pumpAndSettle();

    expect((await fake.collection('blocks').get()).docs, isEmpty);
    expect(find.text('Desbloqueaste a Coach Joe.'), findsOneWidget);
  });

  testWidgets('si el borrado falla → toast de error y la arista sigue',
      (tester) async {
    final fake = await _seed();
    await _openMenu(
      tester,
      fake,
      repo: _ThrowingBlockRepository(firestore: fake),
    );

    await tester.tap(find.text('Desbloquear'));
    await tester.pumpAndSettle();

    expect(
        find.text('No pudimos desbloquear. Probá de nuevo.'), findsOneWidget);
    expect((await fake.collection('blocks').get()).docs, hasLength(1));
  });
}
