// Aviso de perfil pausado: la otra mitad de "la pausa nunca es automática".
// Si nada pausa solo, nada puede quedar pausado sin que el PF lo vea.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/widgets/perfil_pausado_aviso.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockUserRepo extends Mock implements UserRepository {}

Future<void> _pump(
  WidgetTester tester, {
  required bool acceptingAthletes,
  UserRepository? repo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => Stream.value(
            UserProfile(
              uid: 'trainer-1',
              email: 'trainer@treino.app',
              displayName: 'Profe',
              role: UserRole.trainer,
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
              acceptingAthletes: acceptingAthletes,
            ),
          ),
        ),
        userRepositoryProvider.overrideWithValue(repo ?? _MockUserRepo()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: PerfilPausadoAviso()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _aviso = find.byKey(const Key('perfil_pausado_aviso'));

void main() {
  setUpAll(() => registerFallbackValue(<String, Object?>{}));

  testWidgets('con el perfil pausado, se ve', (tester) async {
    await _pump(tester, acceptingAthletes: false);
    expect(_aviso, findsOneWidget);
    expect(find.text('TU PERFIL ESTÁ PAUSADO'), findsOneWidget);
  });

  testWidgets('con el perfil abierto, no dibuja nada', (tester) async {
    await _pump(tester, acceptingAthletes: true);
    expect(_aviso, findsNothing);
  });

  testWidgets('REANUDAR escribe acceptingAthletes:true', (tester) async {
    final repo = _MockUserRepo();
    when(() => repo.update(any(), any())).thenAnswer((_) async {});
    await _pump(tester, acceptingAthletes: false, repo: repo);

    await tester.tap(find.byKey(const Key('perfil_pausado_reanudar')));
    await tester.pumpAndSettle();

    final escrito =
        verify(() => repo.update('trainer-1', captureAny())).captured.single;
    expect(escrito, equals({'acceptingAthletes': true}));
  });

  testWidgets('si el update falla, avisa y el aviso sigue', (tester) async {
    final repo = _MockUserRepo();
    when(() => repo.update(any(), any()))
        .thenAnswer((_) async => throw Exception('boom'));
    await _pump(tester, acceptingAthletes: false, repo: repo);

    await tester.tap(find.byKey(const Key('perfil_pausado_reanudar')));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo guardar. Probá de nuevo.'), findsOneWidget);
    expect(_aviso, findsOneWidget);
  });
}
