// #634 — la barra DURANTE la transición post-login, no en reposo.
//
// El barrido de 80 configuraciones de `treino_bottom_bar_test.dart` mide la
// barra SOLA —deliberadamente sin `Scaffold`— y siempre después de
// `pumpAndSettle()`. Eso deja tres agujeros que son justo donde vive lo que
// reporta la issue ("solo pasa después del login, no en una navegación
// normal"):
//
//   1. La barra dentro del `Scaffold` REAL del shell, en el slot
//      `bottomNavigationBar`, que es quien decide su posición y sus
//      constraints (`fullWidthConstraints`, y `bottom = size.height`).
//   2. La transición completa /login → authRedirect → /home, manejada por el
//      router de verdad, con el teclado del formulario todavía cerrándose.
//   3. Medición FRAME A FRAME. `pumpAndSettle` se saltea exactamente los
//      frames en los que un desajuste transitorio se vería.
//
// Dato medido acá que NO es una aserción, porque es la conducta actual y
// cambiarla es otra discusión: mientras el teclado se cierra,
// `MediaQuery.padding.bottom` vale 0 (el inset lo consume el teclado), así
// que el margen inferior propio de la barra es `_kBottomMarginMin` = 16. Al
// terminar de cerrarse vuelve el inset del sistema y el margen pasa a 24
// (barra de gestos de Android) o 34 (home indicator de iPhone): la barra da
// un saltito vertical de 8 a 18pt unas décimas después de aterrizar en
// INICIO. Es el único cambio de geometría exclusivo del momento post-login
// que aparece en toda la transición, y es VERTICAL — no descentra nada.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/follow_providers.dart';
import 'package:treino/features/profile/application/profile_stats_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/domain/user_session_stats.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockUser extends Mock implements User {}

/// Arranca anónimo (`AsyncData(null)`) y sube a logueado cuando el test lo
/// pide — igual que hace `AuthNotifier.signIn` al volver de Firebase.
class _FlipAuthNotifier extends AuthNotifier {
  @override
  Future<User?> build() async => null;

  void signInAs(User user) => state = AsyncData(user);
}

UserProfile _profile() => UserProfile(
      uid: 'uid-test',
      email: 'test@test.com',
      displayName: 'Test User',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

const _labels = ['ENTRENAR', 'FEED', 'INICIO', 'COACH', 'PERFIL'];

/// Perfil de dispositivo: ancho lógico + inset inferior del sistema en reposo.
typedef _Device = ({String name, double width, double bottomInset});

/// Una foto de la geometría de la barra en un frame.
class _Frame {
  _Frame({
    required this.n,
    required this.bar,
    required this.pill,
    required this.tabs,
    required this.index,
  });

  final int n;
  final Rect bar;
  final Rect pill;
  final List<Rect> tabs;
  final int index;

  @override
  String toString() => 'frame $n · idx=$index · '
      'bar=[${bar.left.toStringAsFixed(1)}..${bar.right.toStringAsFixed(1)}] '
      'cx=${bar.center.dx.toStringAsFixed(2)} '
      'top=${bar.top.toStringAsFixed(1)} bottom=${bar.bottom.toStringAsFixed(1)} '
      'pillCx=${pill.center.dx.toStringAsFixed(2)} '
      'tabCx=${tabs[index].center.dx.toStringAsFixed(2)} '
      'tabW=${tabs.map((t) => t.width.toStringAsFixed(2)).join('/')}';
}

/// Caja visual de la barra: el `ClipRRect` que envuelve el vidrio.
Rect _barRect(WidgetTester tester) => tester.getRect(
      find
          .descendant(
            of: find.byType(TreinoBottomBar),
            matching: find.byType(ClipRRect),
          )
          .first,
    );

/// Rect REAL del pill de gradient: `AnimatedPositioned` no tiene RenderObject
/// propio, así que `getRect` baja a la caja que efectivamente se pinta, con su
/// parentData ya aplicada por el `Stack`.
Rect _pillRect(WidgetTester tester) => tester.getRect(
      find.descendant(
        of: find.byType(TreinoBottomBar),
        matching: find.byType(AnimatedPositioned),
      ),
    );

_Frame? _capture(WidgetTester tester, int n) {
  if (find.byType(TreinoBottomBar).evaluate().isEmpty) return null;
  return _Frame(
    n: n,
    bar: _barRect(tester),
    pill: _pillRect(tester),
    tabs: [for (final l in _labels) tester.getRect(find.bySemanticsLabel(l))],
    index: tester
        .widget<TreinoBottomBar>(find.byType(TreinoBottomBar))
        .currentIndex,
  );
}

void main() {
  /// Alto del teclado con el que se envía el formulario de login.
  const keyboard = 320.0;

  const devices = <_Device>[
    // Android más común: barra de gestos de 24.
    (name: 'Android 393dp', width: 393, bottomInset: 24),
    // iPhone SE / 13 mini / 8: 375pt es donde `resolveBarLayout` está más
    // cerca del umbral entre el margen ideal (20) y el apretado (12).
    (name: 'iPhone 375pt', width: 375, bottomInset: 34),
  ];

  late _MockUser user;

  setUp(() {
    user = _MockUser();
    when(() => user.uid).thenReturn('uid-test');
    when(() => user.email).thenReturn('test@test.com');
  });

  for (final device in devices) {
    testWidgets(
        'la barra queda centrada y el pill pegado a su tab en TODOS los frames '
        'de la transición login → /home — ${device.name} (#634)',
        (tester) async {
      tester.view.physicalSize = Size(device.width, 852);
      tester.view.devicePixelRatio = 1;
      // Estado "teclado abierto": el sistema le da el inset inferior al
      // teclado, así que `padding.bottom` es 0 y `viewInsets.bottom` es el
      // alto del teclado. `viewPadding` conserva el inset del dispositivo.
      tester.view.padding = const FakeViewPadding(bottom: 0);
      tester.view.viewPadding = FakeViewPadding(bottom: device.bottomInset);
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.reset);

      final authCtrl = StreamController<User?>.broadcast();
      final profileCtrl = StreamController<UserProfile?>.broadcast();
      addTearDown(authCtrl.close);
      addTearDown(profileCtrl.close);

      final container = ProviderContainer(overrides: [
        authStateChangesProvider.overrideWith((_) => authCtrl.stream),
        authNotifierProvider.overrideWith(_FlipAuthNotifier.new),
        userProfileProvider.overrideWith((_) => profileCtrl.stream),
        userSessionStatsProvider.overrideWith(
          (_) async => const UserSessionStats(
            totalSessions: 0,
            totalVolumeKg: 0,
            streak: 0,
          ),
        ),
        pendingFollowRequestCountProvider('').overrideWith((_) => 0),
        pendingFollowRequestCountProvider('uid-test').overrideWith((_) => 0),
        pendingReceivedStreamProvider('').overrideWith((_) => Stream.value([])),
        pendingReceivedStreamProvider('uid-test')
            .overrideWith((_) => Stream.value([])),
      ]);
      addTearDown(container.dispose);

      // El `refreshListenable` REAL: es quien re-dispara el redirect cuando
      // llegan el auth y el snapshot del perfil. Con un ValueNotifier de
      // adorno la transición no sería la de producción.
      final router = buildRouter(
        refreshListenable: container.read(routerRefreshNotifierProvider),
        read: container.read,
      );
      router.go('/login');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(TreinoBottomBar), findsNothing,
          reason: 'sanity: en /login no hay barra');

      // ── El login vuelve OK ──────────────────────────────────────────────
      (container.read(authNotifierProvider.notifier) as _FlipAuthNotifier)
          .signInAs(user);
      authCtrl.add(user);

      final frames = <_Frame>[];
      // 60 frames ≈ 1 s: cubre el cierre del teclado (~250 ms), la llegada
      // del perfil, el redirect y las animaciones implícitas de la barra
      // (`AppMotion.slow` = 320 ms).
      for (var i = 0; i < 60; i++) {
        // El teclado se cierra en ~15 frames; recién cuando termina el
        // sistema devuelve el inset del dispositivo a `padding`.
        final remaining = keyboard * (1 - (i / 15)).clamp(0.0, 1.0);
        tester.view.viewInsets = FakeViewPadding(bottom: remaining);
        tester.view.padding =
            FakeViewPadding(bottom: remaining > 0 ? 0 : device.bottomInset);

        // El snapshot del perfil llega unos frames después del auth, como en
        // producción (Firestore).
        if (i == 4) profileCtrl.add(_profile());

        await tester.pump(const Duration(milliseconds: 16));
        final f = _capture(tester, i);
        if (f != null) frames.add(f);
      }

      expect(frames, isNotEmpty, reason: 'la barra nunca se montó');
      for (final f in frames) {
        printOnFailure(f.toString());
      }

      for (final f in frames) {
        expect(f.bar.center.dx, closeTo(device.width / 2, 0.01),
            reason: 'la barra no está centrada en pantalla — $f');
        for (final t in f.tabs) {
          expect(t.width, closeTo(f.tabs.first.width, 0.01),
              reason:
                  'los tabs no se reparten el ancho en partes iguales — $f');
        }
        // El desajuste que sí existe cuando la barra cambia de ancho: el
        // `AnimatedPositioned` del pill interpola `left`/`width` durante
        // `AppMotion.slow` mientras el `Row` de `Expanded` se reacomoda de
        // golpe. Acá se fija que en la transición post-login NO pase.
        expect(f.pill.center.dx, closeTo(f.tabs[f.index].center.dx, 0.01),
            reason: 'el pill no está centrado en su tab — $f');
        expect(f.index, 2, reason: 'post-login el tab activo es INICIO — $f');
      }
    });
  }
}
