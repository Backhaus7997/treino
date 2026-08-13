import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/presentation/profile_unavailable_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

class MockUser extends Mock implements User {}

/// Stub que registra signOut sin tocar FCM ni Firebase reales.
class _RecordingAuthNotifier extends AuthNotifier {
  bool signOutCalled = false;

  @override
  Future<User?> build() async => MockUser();

  @override
  Future<void> signOut() async {
    signOutCalled = true;
    state = const AsyncData(null);
  }
}

Widget _buildApp({
  required _RecordingAuthNotifier notifier,
  required Stream<UserProfile?> Function() profileStream,
}) {
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => notifier),
      userProfileProvider.overrideWith((ref) => profileStream()),
    ],
    child: const MaterialApp(
      locale: Locale('es', 'AR'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: ProfileUnavailableScreen(),
    ),
  );
}

void main() {
  testWidgets(
      'renderiza mensaje de error + Reintentar + Cerrar sesión '
      '(el limbo #544 deja de ser mudo)', (tester) async {
    final notifier = _RecordingAuthNotifier();
    await tester.pumpWidget(_buildApp(
      notifier: notifier,
      profileStream: () =>
          Stream<UserProfile?>.error(Exception('permission-denied')),
    ));
    await tester.pump(); // el error del stream llega al provider

    // es-AR default: claves existentes reutilizadas — sin ARB nuevo.
    expect(find.text('No pudimos cargar este perfil.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  testWidgets('Reintentar invalida userProfileProvider (re-suscribe el stream)',
      (tester) async {
    final notifier = _RecordingAuthNotifier();
    var buildCount = 0;
    await tester.pumpWidget(_buildApp(
      notifier: notifier,
      profileStream: () {
        buildCount++;
        return Stream<UserProfile?>.error(Exception('permission-denied'));
      },
    ));
    await tester.pump();
    expect(buildCount, 1);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();

    expect(buildCount, 2, reason: 'el tap debe re-ejecutar el provider');
  });

  testWidgets('Cerrar sesión llama a AuthNotifier.signOut', (tester) async {
    final notifier = _RecordingAuthNotifier();
    await tester.pumpWidget(_buildApp(
      notifier: notifier,
      profileStream: () =>
          Stream<UserProfile?>.error(Exception('permission-denied')),
    ));
    await tester.pump();

    await tester.tap(find.text('Cerrar sesión'));
    await tester.pump();

    expect(notifier.signOutCalled, isTrue);
  });

  testWidgets(
      'mientras el reintento carga, el pill muestra spinner en vez del label',
      (tester) async {
    final notifier = _RecordingAuthNotifier();
    var first = true;
    await tester.pumpWidget(_buildApp(
      notifier: notifier,
      profileStream: () {
        if (first) {
          first = false;
          return Stream<UserProfile?>.error(Exception('permission-denied'));
        }
        // Reintento: stream que nunca emite → provider queda en loading.
        return const Stream<UserProfile?>.empty();
      },
    ));
    await tester.pump();
    expect(find.text('Reintentar'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
  });
}
