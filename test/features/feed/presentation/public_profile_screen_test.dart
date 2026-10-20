import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_background.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/public_profile_providers.dart';
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';
import 'package:treino/features/feed/domain/public_profile_view.dart';
import 'package:treino/features/feed/presentation/public_profile_screen.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_follow_button.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/l10n/app_l10n.dart';

// Stub notifier that resolves/errors based on the injected AsyncValue.
// Must extend PublicProfileViewNotifier so the type is compatible with
// publicProfileViewProvider.overrideWith(() => ...).
class _StubPublicProfileViewNotifier extends PublicProfileViewNotifier {
  _StubPublicProfileViewNotifier(this._value);
  final AsyncValue<PublicProfileView> _value;

  @override
  Future<PublicProfileView> build(String arg) async {
    switch (_value) {
      case AsyncData<PublicProfileView>(:final value):
        return value;
      case AsyncError<PublicProfileView>(:final error):
        throw error;
      default:
        // Loading: never resolve.
        await Completer<void>().future;
        return _value.requireValue;
    }
  }
}

class _MockUser extends Mock implements User {}

User _userWithUid(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

Follow _edge(String follower, String followee, FollowStatus status) => Follow(
      id: Follow.edgeId(follower, followee),
      followerUid: follower,
      followeeUid: followee,
      status: status,
      members: [follower, followee],
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// `follows/viewer_target` — el que mira sigue al del perfil.
Follow outgoing([FollowStatus status = FollowStatus.accepted]) =>
    _edge('viewer', 'target', status);

/// `follows/target_viewer` — el del perfil sigue al que mira.
Follow incoming([FollowStatus status = FollowStatus.accepted]) =>
    _edge('target', 'viewer', status);

PublicProfileView _view({
  String authorDisplayName = 'Tincho',
  String? authorAvatarUrl,
  String? authorGymId,
  bool isSelf = false,
  bool isPublic = true,
  Follow? outgoingFollow,
  Follow? incomingFollow,
}) =>
    PublicProfileView(
      authorDisplayName: authorDisplayName,
      authorAvatarUrl: authorAvatarUrl,
      authorGymId: authorGymId,
      outgoingFollow: outgoingFollow,
      incomingFollow: incomingFollow,
      isSelf: isSelf,
      isPublic: isPublic,
    );

Widget _wrap({
  required Widget child,
  required AsyncValue<PublicProfileView> view,
  String viewerUid = 'viewer',
  FakeFirebaseFirestore? firestore,
}) {
  firestore ??= FakeFirebaseFirestore();
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      authStateChangesProvider
          .overrideWith((_) => Stream.value(_userWithUid(viewerUid))),
      publicProfileViewProvider.overrideWith(
        () => _StubPublicProfileViewNotifier(view),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('PublicProfileScreen', () {
    testWidgets(
        'SCENARIO-207: provides own back affordance, no AppBackground/SafeArea',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view()),
      ));
      await tester.pumpAndSettle();

      // Screen now wraps its body in a transparent Scaffold + AppBar so it has
      // an on-screen back affordance (mirrors TrainerPublicProfileScreen).
      // That is the screen's Scaffold plus the outer test wrapper's = 2.
      expect(find.byType(Scaffold), findsNWidgets(2));
      // #1559: la flecha ya no vive en un AppBar sino en la barra que aparece
      // al scrollear.
      expect(find.byType(AppBar), findsNothing);
      expect(
          find.byType(BackButton), findsNothing); // custom leading, not default
      expect(find.widgetWithIcon(IconButton, TreinoIcon.back), findsOneWidget);
      // Still does NOT introduce its own AppBackground — it composites over the
      // shell's AppBackground via the transparent Scaffold/AppBar. (The AppBar
      // contributes its own internal SafeArea, which is expected and harmless,
      // so we no longer assert SafeArea is absent.)
      expect(find.byType(AppBackground), findsNothing);
    });

    testWidgets(
        'SCENARIO-208: self-visit (isSelf=true) hides SEGUIR and MENSAJE',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view(isSelf: true)),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(PublicProfileFollowButton), findsNothing);
      expect(find.text('MENSAJE'), findsNothing);
      // Hero + stats still render
      expect(find.text('TINCHO'), findsOneWidget);
    });

    testWidgets('SCENARIO-209: non-self renders SEGUIR and MENSAJE buttons',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view(isSelf: false)),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(PublicProfileFollowButton), findsOneWidget);
      expect(find.text('MENSAJE'), findsOneWidget);
    });

    testWidgets('SCENARIO-227: loading state renders CircularProgressIndicator',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: const AsyncLoading(),
      ));
      // Don't settle — stay in loading
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('TINCHO'), findsNothing);
    });

    testWidgets('SCENARIO-228: error state renders graceful fallback text',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncError(Exception('boom'), StackTrace.empty),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar este perfil.'), findsOneWidget);
    });

    testWidgets('SCENARIO-230: RUTINAS PÚBLICAS tab is active by default',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('RUTINAS PÚBLICAS'), findsOneWidget);
      expect(find.text('ACTIVIDAD'), findsOneWidget);
      // Default body copy
      expect(find.text('Aún no hay rutinas públicas.'), findsOneWidget);
    });

    testWidgets('SCENARIO-231/232/233: tapping ACTIVIDAD switches body copy',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view()),
      ));
      await tester.pumpAndSettle();

      // Initially rutinas
      expect(find.text('Aún no hay rutinas públicas.'), findsOneWidget);
      expect(find.text('Aún no hay actividad reciente.'), findsNothing);

      // Tap ACTIVIDAD pill
      await tester.tap(find.text('ACTIVIDAD'));
      await tester.pumpAndSettle();

      expect(find.text('Aún no hay actividad reciente.'), findsOneWidget);
      expect(find.text('Aún no hay rutinas públicas.'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Privacy gate — Instagram-style. Header + follow button stay visible; the
  // detailed content (stats numbers, tabs) is gated to accepted followers.
  // ---------------------------------------------------------------------------
  group('PublicProfileScreen — privacy gate', () {
    testWidgets(
        'private + non-follower → hides tabs and shows "Perfil privado" notice',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view(isPublic: false)),
      ));
      await tester.pumpAndSettle();

      // Notice is visible.
      expect(find.text('Perfil privado'), findsOneWidget);
      // Tabs are NOT rendered.
      expect(find.text('RUTINAS PÚBLICAS'), findsNothing);
      expect(find.text('ACTIVIDAD'), findsNothing);
      // Follow button IS still rendered (the whole point: allow request).
      expect(find.byType(PublicProfileFollowButton), findsOneWidget);
    });

    testWidgets('private + accepted follower → shows tabs (gate lifted)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(
          _view(isPublic: false, outgoingFollow: outgoing()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Perfil privado'), findsNothing);
      expect(find.text('RUTINAS PÚBLICAS'), findsOneWidget);
      expect(find.text('ACTIVIDAD'), findsOneWidget);
    });

    testWidgets('private + isSelf → shows tabs (owner always sees own profile)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view(isPublic: false, isSelf: true)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Perfil privado'), findsNothing);
      expect(find.text('RUTINAS PÚBLICAS'), findsOneWidget);
    });

    testWidgets('public + non-follower → shows tabs (no gate)', (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view(isPublic: true)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Perfil privado'), findsNothing);
      expect(find.text('RUTINAS PÚBLICAS'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // MENSAJE — REQ-FOLLOW-012 / SCENARIO-845.
  //
  // La elegibilidad es la arista ENTRANTE: le puedo escribir a alguien sólo si
  // esa persona ME SIGUE. Es el espejo literal de `chatCreateOk` en las rules —
  // abrir un chat es poder mandar el primer mensaje.
  //
  // NO es el OR de las dos direcciones. El OR era el espejo de la regla vieja,
  // cuando `friendships` tenía un doc por par y las dos direcciones eran el
  // mismo hecho. Si el cliente y las rules no coinciden exactamente, el UX
  // miente en una dirección o en la otra: o el botón está habilitado y el envío
  // rebota con permission-denied, o está gris cuando el servidor sí lo permite.
  // ---------------------------------------------------------------------------
  group('PublicProfileScreen — gate del botón MENSAJE', () {
    /// Lee el nodo semántico del pill MENSAJE. Se afirma sobre `enabled`,
    /// NUNCA sobre anchos de texto: en este repo `google_fonts` no carga en
    /// tests y todo se mide con una fallback más ancha.
    bool messageButtonSemanticEnabled(WidgetTester tester) {
      final finder = find.bySemanticsLabel('Mensaje');
      if (finder.evaluate().isEmpty) return false;
      final node = tester.getSemantics(finder);
      return node.flagsCollection.isEnabled == Tristate.isTrue;
    }

    testWidgets('sin ninguna arista → MENSAJE deshabilitado', (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('MENSAJE'), findsOneWidget);
      expect(messageButtonSemanticEnabled(tester), isFalse);
    });

    testWidgets('entrante pending → MENSAJE deshabilitado (todavía no aceptó)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(
          _view(incomingFollow: incoming(FollowStatus.pending)),
        ),
      ));
      await tester.pumpAndSettle();

      expect(messageButtonSemanticEnabled(tester), isFalse);
    });

    // SCENARIO-845 — EL DISCRIMINADOR.
    testWidgets('lo sigo pero NO me sigue → MENSAJE DESHABILITADO',
        (tester) async {
      // Si esto se implementara con la arista saliente (o con el OR de las
      // dos), este test se pone rojo. Es el caso donde el servidor deniega:
      // `chatCreateOk` exige `followAccepted(otro, yo)`, y acá `otro` no me
      // sigue.
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(
          _view(outgoingFollow: outgoing(), incomingFollow: null),
        ),
      ));
      await tester.pumpAndSettle();

      expect(messageButtonSemanticEnabled(tester), isFalse,
          reason:
              'seguirlo no me habilita a escribirle: él tiene que seguirme');
    });

    // SCENARIO-845 — el espejo.
    testWidgets('me sigue aunque yo no lo siga → MENSAJE HABILITADO',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(
          _view(outgoingFollow: null, incomingFollow: incoming()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(messageButtonSemanticEnabled(tester), isTrue,
          reason:
              'su arista entrante alcanza: puedo mandarle el primer mensaje');
    });

    testWidgets('par mutuo → MENSAJE habilitado', (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(
          _view(outgoingFollow: outgoing(), incomingFollow: incoming()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(messageButtonSemanticEnabled(tester), isTrue);
    });

    testWidgets('isSelf → MENSAJE row is not rendered at all (own profile)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view(isSelf: true)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('MENSAJE'), findsNothing);
      expect(find.text('SEGUIR'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // #1476 — MENSAJE también se habilita por CHAT EXISTENTE o VÍNCULO vigente.
  //
  // La rama social de `chatCreateOk` (el otro me sigue) no es la única: la rama
  // `linkId` no depende de ningún follow, y un chat que ya existe se abre sin
  // pasar por la regla de creación. El PF veía a su propio alumno, con el chat
  // abierto, con MENSAJE gris.
  // ---------------------------------------------------------------------------
  group('PublicProfileScreen — MENSAJE por chat existente o vínculo (#1476)',
      () {
    bool messageEnabled(WidgetTester tester) {
      final finder = find.bySemanticsLabel('Mensaje');
      if (finder.evaluate().isEmpty) return false;
      return tester.getSemantics(finder).flagsCollection.isEnabled ==
          Tristate.isTrue;
    }

    Future<void> pumpProfile(
      WidgetTester tester,
      FakeFirebaseFirestore firestore,
    ) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        // Sin ninguna arista: la única salida es el chat o el vínculo.
        view: AsyncData(_view()),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();
    }

    Future<void> seedLink(
      FakeFirebaseFirestore firestore, {
      required String trainerId,
      required String athleteId,
      required String status,
    }) =>
        firestore.collection('trainer_links').doc('link-1').set({
          'id': 'link-1',
          'trainerId': trainerId,
          'athleteId': athleteId,
          'status': status,
          'requestedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        });

    testWidgets('chat ya abierto entre los dos → MENSAJE habilitado',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('chats').doc('target_viewer').set({
        'chatId': 'target_viewer',
        'members': ['target', 'viewer'],
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'lastMessageAt': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
      });

      await pumpProfile(tester, firestore);

      expect(messageEnabled(tester), isTrue);
      semantics.dispose();
    });

    testWidgets('chat con OTRA persona no habilita MENSAJE', (tester) async {
      final semantics = tester.ensureSemantics();
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('chats').doc('other_viewer').set({
        'chatId': 'other_viewer',
        'members': ['other', 'viewer'],
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'lastMessageAt': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
      });

      await pumpProfile(tester, firestore);

      expect(messageEnabled(tester), isFalse);
      semantics.dispose();
    });

    testWidgets('soy el PF y es mi alumno (vínculo activo) → habilitado',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final firestore = FakeFirebaseFirestore();
      await seedLink(
        firestore,
        trainerId: 'viewer',
        athleteId: 'target',
        status: 'active',
      );

      await pumpProfile(tester, firestore);

      expect(messageEnabled(tester), isTrue);
      semantics.dispose();
    });

    testWidgets('soy el alumno y es mi PF (vínculo pausado) → habilitado',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final firestore = FakeFirebaseFirestore();
      await seedLink(
        firestore,
        trainerId: 'target',
        athleteId: 'viewer',
        status: 'paused',
      );

      await pumpProfile(tester, firestore);

      expect(messageEnabled(tester), isTrue);
      semantics.dispose();
    });

    for (final status in ['pending', 'terminated']) {
      testWidgets('vínculo $status NO habilita MENSAJE', (tester) async {
        final semantics = tester.ensureSemantics();
        final firestore = FakeFirebaseFirestore();
        await seedLink(
          firestore,
          trainerId: 'viewer',
          athleteId: 'target',
          status: status,
        );

        await pumpProfile(tester, firestore);

        expect(messageEnabled(tester), isFalse);
        semantics.dispose();
      });
    }

    testWidgets('vínculo con OTRO alumno no habilita MENSAJE', (tester) async {
      final semantics = tester.ensureSemantics();
      final firestore = FakeFirebaseFirestore();
      await seedLink(
        firestore,
        trainerId: 'viewer',
        athleteId: 'someone-else',
        status: 'active',
      );

      await pumpProfile(tester, firestore);

      expect(messageEnabled(tester), isFalse);
      semantics.dispose();
    });

    testWidgets('deshabilitado: tocar MENSAJE explica por qué con un toast',
        (tester) async {
      await pumpProfile(tester, FakeFirebaseFirestore());

      await tester.tap(find.text('MENSAJE'));
      await tester.pump();

      // Es el toast del kit (`showTreinoToast`, #1560), no un SnackBar a mano:
      // lleva el ícono de tipo `info` junto al mensaje.
      final toast = find.byType(SnackBar);
      expect(toast, findsOneWidget);
      expect(
        find.descendant(
          of: toast,
          matching:
              find.text('Para escribirle, esta persona tiene que seguirte.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: toast,
          matching: find.byIcon(TreinoIcon.infoCircle),
        ),
        findsOneWidget,
      );
    });

    testWidgets('deshabilitado: la etiqueta a11y explica por qué',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpProfile(tester, FakeFirebaseFirestore());

      expect(
        find.bySemanticsLabel(RegExp('esta persona tiene que seguirte')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('próximamente')), findsNothing);
      semantics.dispose();
    });
  });

  // #1476 — "WORKOUTS" estaba hardcodeado en inglés en una UI en español.
  group('PublicProfileScreen — stats en español (#1476)', () {
    testWidgets('el contador de entrenos dice ENTRENOS, no WORKOUTS',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ENTRENOS'), findsOneWidget);
      expect(find.text('WORKOUTS'), findsNothing);
    });
  });

  // #1477 / #1559 — los posts pasaban por debajo de la flecha y el ⋮ sueltos.
  group('PublicProfileScreen — barra al scrollear (#1477, #1559)', () {
    testWidgets('sin fondo arriba (sobre el hero) y con fondo al scrollear',
        (tester) async {
      // Pantalla baja para que el perfil sí scrollee.
      tester.view.physicalSize = const Size(390, 420);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view()),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('treino-top-bar-surface')), findsNothing);

      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      final surface = tester.widget<Opacity>(
        find.byKey(const Key('treino-top-bar-surface')),
      );
      expect(
        surface.opacity,
        1.0,
        reason: 'sin fondo, los posts pasan por debajo de la flecha y el ⋮',
      );
    });
  });

  group('PublicProfileScreen — moderación (moderacion-reporte-y-bloqueo)', () {
    testWidgets('menú de moderación visible en el header para un perfil ajeno',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view(authorDisplayName: 'Tincho')),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(TreinoIcon.dotsThree), findsOneWidget);
    });

    testWidgets('menú de moderación ausente en el propio perfil',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view(isSelf: true)),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(TreinoIcon.dotsThree), findsNothing);
    });

    testWidgets('tocar el menú abre Reportar/Bloquear', (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view(authorDisplayName: 'Tincho')),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(TreinoIcon.dotsThree));
      await tester.pumpAndSettle();

      expect(find.text('Reportar'), findsOneWidget);
      expect(find.text('Bloquear'), findsOneWidget);
    });
  });
}
