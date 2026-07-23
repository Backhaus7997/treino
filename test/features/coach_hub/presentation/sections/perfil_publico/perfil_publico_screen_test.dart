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

      final plano = find.byKey(const Key('perfil_publico_plano'));
      expect(plano, findsOneWidget);
      // WU-02: el displayName y la tarifa también aparecen en el
      // `CoachDiscoveryPreviewCard` de la columna derecha — se scopea la
      // búsqueda al bloque plano de la izquierda para desambiguar.
      expect(
        find.descendant(of: plano, matching: find.text('Joaquín Nadal')),
        findsOneWidget,
      );
      // WU-03: la bio también aparece editable en `IdentidadCard` (columna
      // izquierda, arriba del bloque plano) — se scopea al bloque plano.
      expect(
        find.descendant(
          of: plano,
          matching: find.text('PF especializado en hipertrofia y fuerza.'),
        ),
        findsOneWidget,
      );
      expect(find.text('hipertrofia'), findsOneWidget);
      expect(
        find.descendant(of: plano, matching: find.text('\$28000/mes')),
        findsOneWidget,
      );
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

      // WU-02: displayName null y sin rating/reseñas también degradan a "—"
      // en el `CoachDiscoveryPreviewCard` — se scopea al bloque plano.
      expect(
        find.descendant(
          of: find.byKey(const Key('perfil_publico_plano')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
      expect(find.text('Todavía no cargaste una bio.'), findsOneWidget);
      expect(find.text('Sin especialidad cargada.'), findsOneWidget);
      expect(find.text('Sin tarifa cargada.'), findsOneWidget);
      expect(find.text('Solo presencial'), findsOneWidget);
    });
  });

  group('PerfilPublicoScreen — loading (WU-01/WU-05)', () {
    testWidgets('perfil en loading → shimmer (no spinner seco)',
        (tester) async {
      final controller = StreamController<UserProfile?>();
      addTearDown(controller.close);

      await _pump(
        tester,
        profileStream: controller.stream,
        settle: false,
      );

      expect(find.byKey(const Key('perfil_publico_loading')), findsOneWidget);
      expect(find.textContaining('PERFIL PÚBLICO'), findsOneWidget);
      // WU-05: nada de spinner->data seco — el shimmer imita la grilla real
      // de dos columnas (dos cards izquierda + card preview derecha).
      expect(find.byType(CircularProgressIndicator), findsNothing);
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

  group('PerfilPublicoScreen — banner de perfil incompleto (WU-05)', () {
    testWidgets('trainerProfileComplete == false → muestra banner honesto',
        (tester) async {
      await _pump(
        tester,
        profile: _trainerProfile(trainerBio: null),
      );

      expect(
        find.byKey(const Key('perfil_publico_incomplete_banner')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Coach Discovery'),
        findsWidgets,
      );
    });

    testWidgets('trainerProfileComplete == true → NO muestra banner',
        (tester) async {
      await _pump(tester, profile: _trainerProfile());

      expect(
        find.byKey(const Key('perfil_publico_incomplete_banner')),
        findsNothing,
      );
    });
  });

  group('PerfilPublicoScreen — responsive (WU-05)', () {
    testWidgets('ancho angosto (compact) → layout apilado en una columna',
        (tester) async {
      tester.view.physicalSize = const Size(820, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith(
              (ref) => Stream<UserProfile?>.value(_trainerProfile()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: PerfilPublicoScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('perfil_publico_columns_stacked')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('perfil_publico_columns_desktop')),
        findsNothing,
      );
    });

    testWidgets('ancho amplio (desktop) → layout de dos columnas',
        (tester) async {
      await _pump(tester, profile: _trainerProfile());

      expect(
        find.byKey(const Key('perfil_publico_columns_desktop')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('perfil_publico_columns_stacked')),
        findsNothing,
      );
    });
  });

  group('PerfilPublicoScreen — motion (WU-01)', () {
    testWidgets('dark y light: smoke sin crash en data/loading/error',
        (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await _pump(tester, theme: theme, profile: _trainerProfile());
        expect(
          find.descendant(
            of: find.byKey(const Key('perfil_publico_plano')),
            matching: find.text('Joaquín Nadal'),
          ),
          findsOneWidget,
        );
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
