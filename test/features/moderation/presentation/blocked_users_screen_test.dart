// «Usuarios bloqueados» (#1698), contra un `FakeFirebaseFirestore`: Desbloquear
// borra la arista `blocks/` de verdad y el stream saca la fila.
//
// `CollectionReference` y `Query` están `@sealed` en `cloud_firestore`, y
// `fake_cloud_firestore` no modela `isFromCache`: para el caso de la caché fría
// (#1831) se mockea con mocktail la cadena real de la query y se ejercita
// `BlockRepository` de verdad.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/moderation/application/moderation_providers.dart';
import 'package:treino/features/moderation/presentation/blocked_users_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockCollectionReference extends Mock
    implements CollectionReference<Map<String, Object?>> {}

class _MockQuery extends Mock implements Query<Map<String, Object?>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, Object?>> {}

class _MockSnapshotMetadata extends Mock implements SnapshotMetadata {}

/// Un `QuerySnapshot` VACÍO con la procedencia que se pida. Sin red y con la
/// caché fría, Firestore devuelve exactamente esto en vez de fallar.
QuerySnapshot<Map<String, Object?>> _vacio({required bool isFromCache}) {
  final metadata = _MockSnapshotMetadata();
  when(() => metadata.isFromCache).thenReturn(isFromCache);
  final snap = _MockQuerySnapshot();
  when(() => snap.docs).thenReturn(const []);
  when(() => snap.metadata).thenReturn(metadata);
  return snap;
}

/// Un Firestore cuya query `blocks where blockerUid == 'aaa'` contesta [snap]
/// tanto por `get()` como por `snapshots()`.
FirebaseFirestore _firestoreQueContesta(
    QuerySnapshot<Map<String, Object?>> snap) {
  final firestore = _MockFirebaseFirestore();
  final blocks = _MockCollectionReference();
  final query = _MockQuery();
  when(() => firestore.collection('blocks')).thenReturn(blocks);
  when(() => blocks.where('blockerUid', isEqualTo: 'aaa')).thenReturn(query);
  when(() => query.get()).thenAnswer((_) async => snap);
  when(() => query.snapshots()).thenAnswer((_) => Stream.value(snap));
  return firestore;
}

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
      blockedUidsConfirmedProvider('aaa')
          .overrideWith((_) => Stream<List<String>>.error('sin red')),
    ]);

    expect(find.textContaining('No pudimos cargar tu lista'), findsOneWidget);
    expect(find.text('No bloqueaste a nadie.'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Reintentar'), findsOneWidget);
  });

  testWidgets('Reintentar vuelve a pedir la lista y se recupera',
      (tester) async {
    var pedidos = 0;
    await _pump(tester, const [], extra: [
      blockedUidsConfirmedProvider('aaa').overrideWith((_) {
        pedidos++;
        return pedidos == 1
            ? Stream<List<String>>.error('sin red')
            : Stream.value(const ['bbb']);
      }),
    ]);
    expect(find.textContaining('No pudimos cargar tu lista'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Reintentar'));
    await tester.pumpAndSettle();

    expect(pedidos, 2);
    expect(find.textContaining('No pudimos cargar tu lista'), findsNothing);
    expect(find.text('COACH JOE'), findsOneWidget);
  });

  // #1831: sin red y con la caché fría, un `.get()` / `.snapshots()` de una
  // query no falla: devuelve un QuerySnapshot VACÍO con `isFromCache == true`.
  // La lista lo pintaba como «No bloqueaste a nadie», que es una afirmación
  // sobre el usuario que nadie verificó (AGENTS.md §11.1).
  group('caché fría, sin red (#1831)', () {
    Future<void> montar(
        WidgetTester tester, FirebaseFirestore firestore) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreProvider.overrideWithValue(firestore),
            currentUidProvider.overrideWith((_) => 'aaa'),
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
    }

    testWidgets('vacío DESDE LA CACHÉ → error con Reintentar, no «vacío»',
        (tester) async {
      await montar(
        tester,
        _firestoreQueContesta(_vacio(isFromCache: true)),
      );

      expect(find.textContaining('No pudimos cargar tu lista'), findsOneWidget);
      expect(find.text('No bloqueaste a nadie.'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Reintentar'), findsOneWidget);
    });

    testWidgets(
        'vacío CONFIRMADO por el servidor → sí es «No bloqueaste a nadie»',
        (tester) async {
      await montar(
        tester,
        _firestoreQueContesta(_vacio(isFromCache: false)),
      );

      expect(find.text('No bloqueaste a nadie.'), findsOneWidget);
      expect(find.textContaining('No pudimos cargar tu lista'), findsNothing);
    });
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
