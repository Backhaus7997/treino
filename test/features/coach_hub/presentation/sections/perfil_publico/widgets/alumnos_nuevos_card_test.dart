// AlumnosNuevosCard — la pausa del PF en el Coach Hub. Mismo patrón que
// ConsultasCard (persiste al tocar, revierte si falla); acá se pinea que
// escriba EL campo de la pausa y no el de consultas.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/perfil_publico/widgets/alumnos_nuevos_card.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockUserRepo extends Mock implements UserRepository {}

UserProfile _trainer({required bool acceptingAthletes}) => UserProfile(
      uid: 'trainer-1',
      email: 'trainer@treino.app',
      displayName: 'Joaquín Nadal',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      acceptingAthletes: acceptingAthletes,
    );

Future<void> _pump(
  WidgetTester tester,
  UserRepository repo, {
  required bool acceptingAthletes,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [userRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: AlumnosNuevosCard(
            profile: _trainer(acceptingAthletes: acceptingAthletes),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Switch _switch(WidgetTester tester) =>
    tester.widget<Switch>(find.byKey(const Key('alumnos_nuevos_card_switch')));

void main() {
  setUpAll(() => registerFallbackValue(<String, Object?>{}));

  for (final abierto in [true, false]) {
    testWidgets('se dibuja con el valor del perfil ($abierto)', (tester) async {
      await _pump(tester, _MockUserRepo(), acceptingAthletes: abierto);
      expect(_switch(tester).value, abierto);
    });
  }

  testWidgets('apagarlo escribe acceptingAthletes:false y nada más',
      (tester) async {
    final repo = _MockUserRepo();
    when(() => repo.update(any(), any())).thenAnswer((_) async {});
    await _pump(tester, repo, acceptingAthletes: true);

    await tester.tap(find.byKey(const Key('alumnos_nuevos_card_switch')));
    await tester.pumpAndSettle();

    final escrito =
        verify(() => repo.update('trainer-1', captureAny())).captured.single;
    expect(escrito, equals({'acceptingAthletes': false}));
  });

  testWidgets('si el update falla vuelve al valor anterior', (tester) async {
    final repo = _MockUserRepo();
    when(() => repo.update(any(), any()))
        .thenAnswer((_) async => throw Exception('boom'));
    await _pump(tester, repo, acceptingAthletes: true);

    await tester.tap(find.byKey(const Key('alumnos_nuevos_card_switch')));
    await tester.pumpAndSettle();

    expect(_switch(tester).value, isTrue);
    expect(find.text('No se pudo guardar. Probá de nuevo.'), findsOneWidget);
  });
}
