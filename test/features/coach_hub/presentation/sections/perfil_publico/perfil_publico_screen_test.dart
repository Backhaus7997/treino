// PerfilPublicoScreen — Fase 11 WU-01.
//
// Cubre la versión MÍNIMA pre-rediseño (ADR-F11-01): happy path con data
// real de `userProfileProvider` (displayName, bio, especialidad, tarifa,
// modalidad), estados NO-happy (loading shimmer, error + retry, perfil
// null) y un smoke dark/light.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/perfil_publico/perfil_publico_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

UserProfile _trainerProfile({
  String? displayName = 'Joaquín Nadal',
  String? trainerBio = 'PF especializado en hipertrofia y fuerza.',
  String? trainerSpecialty = 'hipertrofia',
  int? trainerMonthlyRate = 28000,
  bool trainerOffersOnline = true,
}) =>
    UserProfile(
      uid: 'trainer-1',
      email: 'trainer@treino.app',
      displayName: displayName,
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      trainerBio: trainerBio,
      trainerSpecialty: trainerSpecialty,
      trainerMonthlyRate: trainerMonthlyRate,
      trainerOffersOnline: trainerOffersOnline,
    );

Future<void> _pump(
  WidgetTester tester, {
  Stream<UserProfile?>? profileStream,
  UserProfile? profile,
  ThemeData? theme,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => profileStream ?? Stream<UserProfile?>.value(profile),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.dark(),
        home: const Scaffold(body: PerfilPublicoScreen()),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  group('PerfilPublicoScreen — happy path (WU-01)', () {
    testWidgets('data completa renderiza todos los campos en texto plano',
        (tester) async {
      await _pump(tester, profile: _trainerProfile());

      expect(find.byKey(const Key('perfil_publico_plano')), findsOneWidget);
      expect(find.text('Joaquín Nadal'), findsOneWidget);
      expect(
        find.text('PF especializado en hipertrofia y fuerza.'),
        findsOneWidget,
      );
      expect(find.text('hipertrofia'), findsOneWidget);
      expect(find.text('\$28000/mes'), findsOneWidget);
      expect(find.text('Ofrece online'), findsOneWidget);
    });

    testWidgets('campos vacíos muestran fallback honesto (no inputs muertos)',
        (tester) async {
      await _pump(
        tester,
        profile: _trainerProfile(
          displayName: null,
          trainerBio: null,
          trainerSpecialty: null,
          trainerMonthlyRate: null,
          trainerOffersOnline: false,
        ),
      );

      expect(find.text('—'), findsOneWidget);
      expect(find.text('Todavía no cargaste una bio.'), findsOneWidget);
      expect(find.text('Sin especialidad cargada.'), findsOneWidget);
      expect(find.text('Sin tarifa cargada.'), findsOneWidget);
      expect(find.text('Solo presencial'), findsOneWidget);
    });
  });

  group('PerfilPublicoScreen — loading (WU-01)', () {
    testWidgets('perfil en loading → shimmer', (tester) async {
      final controller = StreamController<UserProfile?>();
      addTearDown(controller.close);

      await _pump(
        tester,
        profileStream: controller.stream,
        settle: false,
      );

      expect(find.byKey(const Key('perfil_publico_loading')), findsOneWidget);
      expect(find.textContaining('PERFIL PÚBLICO'), findsOneWidget);
    });
  });

  group('PerfilPublicoScreen — error (WU-01)', () {
    testWidgets('error al cargar → mensaje + retry invoca invalidate',
        (tester) async {
      await _pump(
        tester,
        profileStream: Stream<UserProfile?>.error(Exception('boom')),
      );

      expect(find.byKey(const Key('perfil_publico_error')), findsOneWidget);
      expect(
        find.text('No pudimos cargar tu perfil público.'),
        findsOneWidget,
      );

      final retryButton = find.widgetWithText(TextButton, 'Reintentar');
      expect(retryButton, findsOneWidget);

      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('perfil_publico_error')), findsOneWidget);
    });
  });

  group('PerfilPublicoScreen — perfil ausente (WU-01)', () {
    testWidgets('data con perfil null → empty state honesto', (tester) async {
      await _pump(tester, profile: null);

      expect(find.byKey(const Key('perfil_publico_empty')), findsOneWidget);
      expect(find.text('No encontramos tu perfil.'), findsOneWidget);
    });
  });

  group('PerfilPublicoScreen — motion (WU-01)', () {
    testWidgets('dark y light: smoke sin crash en data/loading/error',
        (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await _pump(tester, theme: theme, profile: _trainerProfile());
        expect(find.text('Joaquín Nadal'), findsOneWidget);
        // Reset del árbol entre escenarios: Riverpod no permite cambiar la
        // cantidad de overrides de un mismo `ProviderScope` entre rebuilds.
        await tester.pumpWidget(const SizedBox.shrink());

        await _pump(
          tester,
          theme: theme,
          profileStream: Stream<UserProfile?>.error(Exception('boom')),
        );
        expect(find.byKey(const Key('perfil_publico_error')), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });
}
