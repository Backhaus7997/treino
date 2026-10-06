import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/application/email_gate_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

import '../helpers/mail_test_helpers.dart';

class _MockUser extends Mock implements User {}

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._user);
  final User _user;

  @override
  Future<User?> build() async {
    state = AsyncData(_user);
    return _user;
  }
}

final DateTime _kDate = DateTime.utc(2026, 1, 1);

UserProfile _profile({DateTime? bornAt}) => UserProfile(
      uid: 'athlete-uid',
      email: 'athlete@example.com',
      displayName: 'sporty',
      bornAt: bornAt,
      emailVerification:
          mailConfirmadoPara(UserRole.athlete, 'athlete@example.com'),
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

/// #1335 — la salida de `/birth-date` depende de que el servidor confirme la
/// escritura (`userProfileHasPendingWritesProvider`). El ack solo cambia la
/// metadata del snapshot: el perfil NO re-emite. Este test cablea el
/// `RouterRefreshNotifier` REAL con el redirect REAL (`authRedirect`) sobre un
/// GoRouter de pantallas vacías, y reproduce la secuencia exacta del bug.
void main() {
  testWidgets(
    'el ack del servidor (pendiente true → false, SIN re-emitir el perfil) '
    'saca al usuario de /birth-date',
    (tester) async {
      final user = _MockUser();
      when(() => user.uid).thenReturn('athlete-uid');
      when(() => user.email).thenReturn('athlete@example.com');

      final profileCtrl = StreamController<UserProfile?>.broadcast();
      final pendingCtrl = StreamController<bool>.broadcast();
      addTearDown(profileCtrl.close);
      addTearDown(pendingCtrl.close);

      final container = ProviderContainer(overrides: [
        authStateChangesProvider.overrideWith((_) => Stream.value(user)),
        authNotifierProvider.overrideWith(() => _StubAuthNotifier(user)),
        userProfileProvider.overrideWith((_) => profileCtrl.stream),
        userProfileHasPendingWritesProvider
            .overrideWith((_) => pendingCtrl.stream),
        emailGateEnabledProvider.overrideWith((_) => Stream<bool>.value(false)),
      ]);
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/birth-date',
        refreshListenable: container.read(routerRefreshNotifierProvider),
        redirect: (ctx, state) =>
            authRedirect(container.read, state.uri.toString()),
        routes: [
          GoRoute(
            path: '/birth-date',
            builder: (_, __) => const Text('birth-date'),
          ),
          GoRoute(path: '/home', builder: (_, __) => const Text('home')),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      String location() => router.routerDelegate.currentConfiguration.uri.path;

      // 1. Cuenta sin fecha: el gate la retiene.
      profileCtrl.add(_profile());
      await tester.pump(const Duration(milliseconds: 20));
      expect(location(), '/birth-date');

      // 2. Escritura optimista: el perfil trae bornAt pero hay pendiente.
      pendingCtrl.add(true);
      profileCtrl.add(_profile(bornAt: DateTime.utc(1990, 5, 20)));
      await tester.pump(const Duration(milliseconds: 20));
      expect(location(), '/birth-date',
          reason: 'con la escritura sin confirmar el gate no suelta');

      // 3. Ack del servidor: SOLO cambia el pendiente. Ninguna emisión del
      //    perfil. Si el notifier no escucha el pendiente, nadie re-evalúa el
      //    redirect y el usuario se queda acá para siempre.
      pendingCtrl.add(false);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
      expect(location(), '/home',
          reason: 'el ack tiene que re-disparar el redirect');
    },
  );
}
