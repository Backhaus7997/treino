// IdentidadCard — Fase 11 WU-03.
//
// Cubre: render read-only de displayName/avatar, edición inline de la bio
// con save real (persiste `trainerBio` vía `userRepository.update`), botón
// GUARDAR deshabilitado sin cambios, y el deep-link «Editar foto y nombre»
// navegando a `/ajustes` (Cuenta) en vez de duplicar el uploader de avatar.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/perfil_publico/widgets/identidad_card.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

class _MockUserRepo extends Mock implements UserRepository {}

UserProfile _trainerProfile({
  String? displayName = 'Joaquín Nadal',
  String? trainerBio =
      'PF especializado en hipertrofia y fuerza, con foco en técnica.',
  String? avatarUrl,
}) =>
    UserProfile(
      uid: 'trainer-1',
      email: 'trainer@treino.app',
      displayName: displayName,
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      trainerBio: trainerBio,
      avatarUrl: avatarUrl,
    );

Future<UserRepository> _pump(
  WidgetTester tester, {
  required UserProfile profile,
  UserRepository? repo,
  ThemeData? theme,
}) async {
  final effectiveRepo = repo ?? _MockUserRepo();
  if (effectiveRepo is _MockUserRepo) {
    when(() => effectiveRepo.update(any(), any())).thenAnswer((_) async {});
  }

  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/perfil-publico',
    routes: [
      GoRoute(
        path: '/perfil-publico',
        builder: (_, __) => Scaffold(body: IdentidadCard(profile: profile)),
      ),
      GoRoute(
        path: '/ajustes',
        builder: (_, __) => const Scaffold(body: Text('AJUSTES_SCREEN_MARKER')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userRepositoryProvider.overrideWithValue(effectiveRepo),
      ],
      child: MaterialApp.router(
        theme: theme ?? AppTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return effectiveRepo;
}

void main() {
  setUpAll(() => registerFallbackValue(<String, Object?>{}));

  group('IdentidadCard — render read-only (WU-03)', () {
    testWidgets('muestra displayName y avatar sin permitir edición inline',
        (tester) async {
      await _pump(tester, profile: _trainerProfile());

      expect(find.byKey(const Key('identidad_card')), findsOneWidget);
      expect(find.byKey(const Key('identidad_card_avatar')), findsOneWidget);
      expect(
          find.byKey(const Key('identidad_card_display_name')), findsOneWidget);
      expect(find.text('Joaquín Nadal'), findsOneWidget);
      expect(find.text('Editar foto y nombre'), findsOneWidget);
    });
  });

  group('IdentidadCard — bio inline (WU-03)', () {
    testWidgets('GUARDAR deshabilitado sin cambios en la bio', (tester) async {
      await _pump(tester, profile: _trainerProfile());

      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('identidad_card_save_button')),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('editar bio y tocar GUARDAR llama a update con trainerBio',
        (tester) async {
      final repo = _MockUserRepo();
      final usedRepo =
          await _pump(tester, profile: _trainerProfile(), repo: repo);

      await tester.enterText(
        find.byKey(const Key('identidad_card_bio_field')),
        'Nueva bio con más de veinte caracteres de largo.',
      );
      await tester.pump();

      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('identidad_card_save_button')),
      );
      expect(saveButton.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('identidad_card_save_button')));
      await tester.pump();
      await tester.pump();

      final captured = verify(
        () => (usedRepo as _MockUserRepo).update('trainer-1', captureAny()),
      ).captured.single as Map<String, Object?>;
      expect(captured['trainerBio'],
          'Nueva bio con más de veinte caracteres de largo.');
    });

    testWidgets('bio vacía o corta no habilita GUARDAR', (tester) async {
      await _pump(tester, profile: _trainerProfile());

      await tester.enterText(
        find.byKey(const Key('identidad_card_bio_field')),
        'muy corta',
      );
      await tester.pump();

      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('identidad_card_save_button')),
      );
      expect(saveButton.onPressed, isNull);
    });
  });

  group('IdentidadCard — deep-link (WU-03)', () {
    testWidgets('«Editar foto y nombre» navega a /ajustes', (tester) async {
      await _pump(tester, profile: _trainerProfile());

      await tester.tap(find.text('Editar foto y nombre'));
      await tester.pumpAndSettle();

      expect(find.text('AJUSTES_SCREEN_MARKER'), findsOneWidget);
    });
  });

  group('IdentidadCard — motion (WU-03)', () {
    testWidgets('dark y light: smoke sin crash', (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await _pump(tester, profile: _trainerProfile(), theme: theme);
        expect(find.byKey(const Key('identidad_card')), findsOneWidget);
      }
    });
  });
}
