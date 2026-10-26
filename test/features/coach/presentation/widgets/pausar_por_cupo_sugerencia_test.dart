// Sugerencia de pausar el perfil con el cupo lleno. Es una SUGERENCIA: estos
// tests pinean cuándo aparece, que pausar escriba el campo, y que no aparezca
// cuando no tiene nada que ofrecer.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/widgets/pausar_por_cupo_sugerencia.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockUserRepo extends Mock implements UserRepository {}

UserProfile _trainer({bool acceptingAthletes = true}) => UserProfile(
      uid: 'trainer-1',
      email: 'trainer@treino.app',
      displayName: 'Profe',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      acceptingAthletes: acceptingAthletes,
    );

Future<void> _pump(
  WidgetTester tester, {
  required double carga,
  required int? tope,
  bool acceptingAthletes = true,
  UserRepository? repo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => Stream.value(_trainer(acceptingAthletes: acceptingAthletes)),
        ),
        userRepositoryProvider.overrideWithValue(repo ?? _MockUserRepo()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: PausarPorCupoSugerencia(carga: carga, tope: tope),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _sugerencia = find.byKey(const Key('pausar_por_cupo_sugerencia'));

void main() {
  setUpAll(() => registerFallbackValue(<String, Object?>{}));

  group('sugerirPausaPorCupo', () {
    test('al tope exacto sugiere: con carga == tope ya no entra nadie', () {
      expect(
        sugerirPausaPorCupo(carga: 2, tope: 2, tomandoAlumnos: true),
        isTrue,
      );
    });

    test('por debajo del tope, sin tope, o ya pausado: no', () {
      expect(
        sugerirPausaPorCupo(carga: 1.5, tope: 2, tomandoAlumnos: true),
        isFalse,
      );
      expect(
        sugerirPausaPorCupo(carga: 40, tope: null, tomandoAlumnos: true),
        isFalse,
        reason: 'sin tope no hay cupo que se llene',
      );
      expect(
        sugerirPausaPorCupo(carga: 2, tope: 2, tomandoAlumnos: false),
        isFalse,
        reason: 'ya pausado no hay nada que sugerir',
      );
    });
  });

  testWidgets('al tope y abierto, aparece', (tester) async {
    await _pump(tester, carga: 7, tope: 7);
    expect(_sugerencia, findsOneWidget);
    expect(find.text('LLEGASTE AL TOPE DE TU PLAN'), findsOneWidget);
  });

  testWidgets('ya pausado, no aparece aunque esté al tope', (tester) async {
    await _pump(tester, carga: 7, tope: 7, acceptingAthletes: false);
    expect(_sugerencia, findsNothing);
  });

  testWidgets('PAUSAR PERFIL escribe acceptingAthletes:false', (tester) async {
    final repo = _MockUserRepo();
    when(() => repo.update(any(), any())).thenAnswer((_) async {});
    await _pump(tester, carga: 2, tope: 2, repo: repo);

    await tester.tap(find.byKey(const Key('pausar_por_cupo_pausar')));
    await tester.pumpAndSettle();

    final escrito =
        verify(() => repo.update('trainer-1', captureAny())).captured.single;
    expect(escrito, equals({'acceptingAthletes': false}));
  });

  testWidgets('"Ahora no" la esconde sin escribir nada', (tester) async {
    final repo = _MockUserRepo();
    await _pump(tester, carga: 2, tope: 2, repo: repo);

    await tester.tap(find.byKey(const Key('pausar_por_cupo_ahora_no')));
    await tester.pumpAndSettle();

    expect(_sugerencia, findsNothing);
    verifyNever(() => repo.update(any(), any()));
  });
}
