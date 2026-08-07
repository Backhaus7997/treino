import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_follow_button.dart';
import 'package:treino/features/feed/presentation/widgets/unfriend_confirmation_sheet.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(Widget w, FakeFirebaseFirestore firestore) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: w),
      ),
    );

Follow _edge(String follower, String followee, FollowStatus status) => Follow(
      id: Follow.edgeId(follower, followee),
      followerUid: follower,
      followeeUid: followee,
      status: status,
      members: [follower, followee],
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// `follows/viewer_target` — yo sigo al del perfil.
Follow _outgoing(FollowStatus status) => _edge('viewer', 'target', status);

/// `follows/target_viewer` — el del perfil me sigue a mí.
Follow _incoming(FollowStatus status) => _edge('target', 'viewer', status);

Future<void> _seed(FakeFirebaseFirestore firestore, Follow edge) => firestore
    .collection('follows')
    .doc(edge.id)
    .set({...edge.toJson(), 'createdAt': Timestamp.now()});

void main() {
  group('PublicProfileFollowButton — mapa de estados', () {
    testWidgets('SCENARIO-219: sin ninguna arista → SEGUIR', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_wrap(
        const PublicProfileFollowButton(
          outgoingFollow: null,
          incomingFollow: null,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();

      expect(find.text('SEGUIR'), findsOneWidget);
    });

    testWidgets('SCENARIO-220: saliente pending → SOLICITUD ENVIADA',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          outgoingFollow: _outgoing(FollowStatus.pending),
          incomingFollow: null,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();

      expect(find.text('SOLICITUD ENVIADA'), findsOneWidget);
    });

    testWidgets('SCENARIO-221: SOLICITUD ENVIADA con Opacity(0.6)',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          outgoingFollow: _outgoing(FollowStatus.pending),
          incomingFollow: null,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();

      final opacityFinder = find.ancestor(
        of: find.text('SOLICITUD ENVIADA'),
        matching: find.byType(Opacity),
      );
      expect(opacityFinder, findsOneWidget);
      expect(tester.widget<Opacity>(opacityFinder).opacity, equals(0.6));
    });

    testWidgets('SCENARIO-222: sin saliente + entrante pending → ACEPTAR',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          outgoingFollow: null,
          incomingFollow: _incoming(FollowStatus.pending),
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();

      expect(find.text('ACEPTAR'), findsOneWidget);
    });

    testWidgets('SCENARIO-223: saliente accepted → SIGUIENDO con check',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          outgoingFollow: _outgoing(FollowStatus.accepted),
          incomingFollow: null,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();

      expect(find.text('SIGUIENDO'), findsOneWidget);
      expect(find.byIcon(TreinoIcon.check), findsOneWidget);
    });
  });

  // Los dos casos que el modelo viejo NO PODÍA REPRESENTAR. Con un doc por par,
  // "yo lo sigo" y "él me sigue" eran el mismo hecho, así que estos dos estados
  // ni existían como opción.
  group('PublicProfileFollowButton — asimetría (SCENARIO-823)', () {
    testWidgets('me sigue pero yo no a él → SEGUIR, no SIGUIENDO',
        (tester) async {
      // Éste es el bug de producto que el cambio de modelo arregla: antes, que
      // alguien te siguiera te mostraba "SIGUIENDO" en SU perfil, como si vos
      // lo siguieras a él.
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          outgoingFollow: null,
          incomingFollow: _incoming(FollowStatus.accepted),
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();

      expect(find.text('SEGUIR'), findsOneWidget);
      expect(find.text('SIGUIENDO'), findsNothing);
    });

    testWidgets('PRECEDENCIA: la arista saliente manda sobre la entrante',
        (tester) async {
      // Yo lo sigo (accepted) Y él me mandó solicitud (pending). El pill muestra
      // MI estado saliente; la solicitud entrante se resuelve desde el inbox.
      // Sin esta regla los dos estados compiten por el mismo botón.
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          outgoingFollow: _outgoing(FollowStatus.accepted),
          incomingFollow: _incoming(FollowStatus.pending),
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();

      expect(find.text('SIGUIENDO'), findsOneWidget);
      expect(find.text('ACEPTAR'), findsNothing);
    });
  });

  group('PublicProfileFollowButton — escrituras', () {
    testWidgets('SCENARIO-224: tap SEGUIR escribe la arista SALIENTE',
        (tester) async {
      final firestore = FakeFirebaseFirestore();

      await tester.pumpWidget(_wrap(
        const PublicProfileFollowButton(
          outgoingFollow: null,
          incomingFollow: null,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();
      await tester.tap(find.text('SEGUIR'));
      await tester.pumpAndSettle();

      // El doc id NO se ordena: 'viewer_target', no 'target_viewer'.
      final snap = await firestore
          .collection('follows')
          .doc(Follow.edgeId('viewer', 'target'))
          .get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['followerUid'], equals('viewer'));
      expect(snap.data()!['followeeUid'], equals('target'));
      expect(snap.data()!['status'], equals('pending'));

      // Y la dirección inversa NO se crea.
      final inversa = await firestore
          .collection('follows')
          .doc(Follow.edgeId('target', 'viewer'))
          .get();
      expect(inversa.exists, isFalse);
    });

    testWidgets('SCENARIO-224b: sobre cuenta pública la arista nace accepted',
        (tester) async {
      final firestore = FakeFirebaseFirestore();

      await tester.pumpWidget(_wrap(
        const PublicProfileFollowButton(
          outgoingFollow: null,
          incomingFollow: null,
          viewerUid: 'viewer',
          targetUid: 'target',
          targetIsPublic: true,
        ),
        firestore,
      ));
      await tester.pump();
      await tester.tap(find.text('SEGUIR'));
      await tester.pumpAndSettle();

      final snap = await firestore
          .collection('follows')
          .doc(Follow.edgeId('viewer', 'target'))
          .get();
      expect(snap.data()!['status'], equals('accepted'));
    });

    testWidgets('SCENARIO-225: tap ACEPTAR promueve la arista ENTRANTE',
        (tester) async {
      // La que se acepta es la del OTRO hacia mí. Si tocara la saliente, se
      // estaría auto-aceptando una solicitud que nadie mandó.
      final firestore = FakeFirebaseFirestore();
      final incoming = _incoming(FollowStatus.pending);
      await _seed(firestore, incoming);

      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          outgoingFollow: null,
          incomingFollow: incoming,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();
      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();

      final snap = await firestore.collection('follows').doc(incoming.id).get();
      expect(snap.data()!['status'], equals('accepted'));
    });

    testWidgets('SCENARIO-226: tap SIGUIENDO abre el sheet y no escribe solo',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final outgoing = _outgoing(FollowStatus.accepted);
      await _seed(firestore, outgoing);

      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          outgoingFollow: outgoing,
          incomingFollow: null,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();
      await tester.tap(find.text('SIGUIENDO'));
      await tester.pumpAndSettle();

      // Sin confirmar, la arista sigue viva.
      final snap = await firestore.collection('follows').doc(outgoing.id).get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['status'], equals('accepted'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // REQ-FOLLOW-006 / SCENARIO-807 — cancelar una solicitud enviada.
  //
  // Hasta acá "SOLICITUD ENVIADA" tenía `onTap: null`: mandabas una solicitud a
  // una cuenta privada y NO HABÍA NINGUNA FORMA de arrepentirte desde la app.
  // ─────────────────────────────────────────────────────────────────────────
  group('PublicProfileFollowButton — cancelar solicitud enviada', () {
    testWidgets('tap en SOLICITUD ENVIADA abre el sheet de confirmación',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final outgoing = _outgoing(FollowStatus.pending);
      await _seed(firestore, outgoing);

      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          outgoingFollow: outgoing,
          incomingFollow: null,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();
      await tester.tap(find.text('SOLICITUD ENVIADA'));
      await tester.pumpAndSettle();

      expect(find.byType(UnfriendConfirmationSheet), findsOneWidget);
    });

    testWidgets('confirmar borra la arista SALIENTE pendiente', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final outgoing = _outgoing(FollowStatus.pending);
      await _seed(firestore, outgoing);
      // La inversa existe y NO se puede tocar: cancelar mi solicitud no puede
      // sacarme de encima a alguien que ya me seguía.
      final incoming = _incoming(FollowStatus.accepted);
      await _seed(firestore, incoming);

      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          outgoingFollow: outgoing,
          incomingFollow: incoming,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();
      await tester.tap(find.text('SOLICITUD ENVIADA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANCELAR SOLICITUD'));
      await tester.pumpAndSettle();

      expect(
        (await firestore.collection('follows').doc(outgoing.id).get()).exists,
        isFalse,
      );
      expect(
        (await firestore.collection('follows').doc(incoming.id).get()).exists,
        isTrue,
        reason: 'cancelar mi solicitud nunca toca la dirección inversa',
      );
    });

    testWidgets('el copy del sheet habla de la solicitud, no de eliminar',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final outgoing = _outgoing(FollowStatus.pending);
      await _seed(firestore, outgoing);

      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          outgoingFollow: outgoing,
          incomingFollow: null,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();
      await tester.tap(find.text('SOLICITUD ENVIADA'));
      await tester.pumpAndSettle();

      // Reusa el mismo sheet que dejar de seguir, pero NO puede decir
      // "eliminar": no hay nada aceptado que eliminar todavía.
      expect(find.textContaining('solicitud'), findsWidgets);
      expect(find.textContaining('Eliminar amistad'), findsNothing);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AGENTS.md — TreinoTappable REEMPLAZA a GestureDetector, no lo envuelve.
  // ─────────────────────────────────────────────────────────────────────────
  group('PublicProfileFollowButton — a11y y tappable', () {
    Future<void> pumpState(
      WidgetTester tester, {
      Follow? outgoing,
      Follow? incoming,
    }) async {
      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          outgoingFollow: outgoing,
          incomingFollow: incoming,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        FakeFirebaseFirestore(),
      ));
      await tester.pump();
    }

    testWidgets('los 4 estados usan TreinoTappable y ningún GestureDetector',
        (tester) async {
      final estados = <String, List<Follow?>>{
        'SEGUIR': [null, null],
        'SIGUIENDO': [_outgoing(FollowStatus.accepted), null],
        'SOLICITUD ENVIADA': [_outgoing(FollowStatus.pending), null],
        'ACEPTAR': [null, _incoming(FollowStatus.pending)],
      };

      for (final entry in estados.entries) {
        await pumpState(tester,
            outgoing: entry.value[0], incoming: entry.value[1]);

        expect(find.text(entry.key), findsOneWidget,
            reason: 'precondición del estado ${entry.key}');
        expect(find.byType(TreinoTappable), findsWidgets,
            reason: '${entry.key} debe usar TreinoTappable');

        // `TreinoTappable` usa un GestureDetector adentro, así que no se puede
        // exigir cero: lo que AGENTS.md prohíbe es un GestureDetector PROPIO,
        // fuera del tappable del sistema. Se afirma exactamente eso.
        final propios = find
            .byType(GestureDetector)
            .evaluate()
            .where((e) => find
                .ancestor(
                  of: find.byWidget(e.widget),
                  matching: find.byType(TreinoTappable),
                )
                .evaluate()
                .isEmpty)
            .length;
        expect(propios, equals(0),
            reason: '${entry.key} no puede tener un GestureDetector propio');
      }
    });

    testWidgets('cada estado expone un semantics de botón con su propio label',
        (tester) async {
      final vistos = <String>{};
      final estados = <List<Follow?>>[
        [null, null],
        [_outgoing(FollowStatus.accepted), null],
        [_outgoing(FollowStatus.pending), null],
        [null, _incoming(FollowStatus.pending)],
      ];

      for (final e in estados) {
        await pumpState(tester, outgoing: e[0], incoming: e[1]);
        final semantics = tester.widget<Semantics>(
          find
              .byWidgetPredicate(
                (w) => w is Semantics && w.properties.button == true,
              )
              .first,
        );
        final label = semantics.properties.label;
        expect(label, isNotNull);
        vistos.add(label!);
      }

      expect(vistos.length, equals(4),
          reason: 'los 4 estados tienen que sonar distinto en el lector');
    });
  });
}
