// EspecialidadPrecioCard — Fase 11 WU-04.
//
// Cubre: selección single-select de especialidad (chips), guardado real de
// `trainerSpecialty` + `trainerMonthlyRate` (SIN `trainerOffersOnline` ni
// `trainerLocations` — evita disparar el invariante de locations del
// repo), validación de precio (mínimo/máximo/entero) bloqueando el
// guardado, y el resumen read-only de modalidad según el profile.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';
import 'package:treino/features/coach_hub/presentation/sections/perfil_publico/widgets/especialidad_precio_card.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

class _MockUserRepo extends Mock implements UserRepository {}

UserProfile _trainerProfile({
  String? trainerSpecialty = 'hipertrofia',
  int? trainerMonthlyRate = 28000,
  bool trainerOffersOnline = true,
  List<TrainerLocation> trainerLocations = const [],
}) =>
    UserProfile(
      uid: 'trainer-1',
      email: 'trainer@treino.app',
      displayName: 'Joaquín Nadal',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      trainerSpecialty: trainerSpecialty,
      trainerMonthlyRate: trainerMonthlyRate,
      trainerOffersOnline: trainerOffersOnline,
      trainerLocations: trainerLocations,
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

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userRepositoryProvider.overrideWithValue(effectiveRepo),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.dark(),
        home: Scaffold(body: EspecialidadPrecioCard(profile: profile)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return effectiveRepo;
}

void main() {
  setUpAll(() => registerFallbackValue(<String, Object?>{}));

  group('EspecialidadPrecioCard — render (WU-04)', () {
    testWidgets('renderiza card y chips de las 10 especialidades',
        (tester) async {
      await _pump(tester, profile: _trainerProfile());

      expect(find.byKey(const Key('especialidad_precio_card')), findsOneWidget);
      expect(find.text('ESPECIALIDAD'), findsOneWidget);
      expect(find.text('Hipertrofia'), findsOneWidget);
      expect(find.text('Powerlifting'), findsOneWidget);
      expect(find.text('Calistenia'), findsOneWidget);
    });

    testWidgets('GUARDAR deshabilitado sin cambios', (tester) async {
      await _pump(tester, profile: _trainerProfile());

      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('especialidad_precio_card_save_button')),
      );
      expect(saveButton.onPressed, isNull);
    });
  });

  group('EspecialidadPrecioCard — selección single-select (WU-04)', () {
    testWidgets('seleccionar un chip distinto habilita GUARDAR',
        (tester) async {
      await _pump(tester, profile: _trainerProfile());

      await tester.tap(find.text('Powerlifting'));
      await tester.pump();

      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('especialidad_precio_card_save_button')),
      );
      expect(saveButton.onPressed, isNotNull);
    });
  });

  group('EspecialidadPrecioCard — guardado real (WU-04)', () {
    testWidgets(
        'guardar con specialty distinta llama a update SOLO con '
        'trainerSpecialty y trainerMonthlyRate', (tester) async {
      final repo = _MockUserRepo();
      final usedRepo =
          await _pump(tester, profile: _trainerProfile(), repo: repo);

      await tester.tap(find.text('Powerlifting'));
      await tester.pump();

      await tester.tap(
        find.byKey(const Key('especialidad_precio_card_save_button')),
      );
      await tester.pump();
      await tester.pump();

      final captured = verify(
        () => (usedRepo as _MockUserRepo).update('trainer-1', captureAny()),
      ).captured.single as Map<String, Object?>;

      expect(captured['trainerSpecialty'], 'powerlifting');
      expect(captured['trainerMonthlyRate'], 28000);
      expect(captured.containsKey('trainerOffersOnline'), isFalse);
      expect(captured.containsKey('trainerLocations'), isFalse);
      expect(captured.length, 2);
    });

    testWidgets('guardar con precio editado llama a update con el nuevo valor',
        (tester) async {
      final repo = _MockUserRepo();
      final usedRepo =
          await _pump(tester, profile: _trainerProfile(), repo: repo);

      await tester.enterText(
        find.byKey(const Key('especialidad_precio_card_price_field')),
        '35000',
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const Key('especialidad_precio_card_save_button')),
      );
      await tester.pump();
      await tester.pump();

      final captured = verify(
        () => (usedRepo as _MockUserRepo).update('trainer-1', captureAny()),
      ).captured.single as Map<String, Object?>;

      expect(captured['trainerMonthlyRate'], 35000);
      expect(captured['trainerSpecialty'], 'hipertrofia');
    });
  });

  group('EspecialidadPrecioCard — validación de precio (WU-04)', () {
    testWidgets('precio menor al mínimo bloquea GUARDAR', (tester) async {
      await _pump(tester, profile: _trainerProfile());

      await tester.enterText(
        find.byKey(const Key('especialidad_precio_card_price_field')),
        '100',
      );
      await tester.pump();

      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('especialidad_precio_card_save_button')),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('precio mayor al máximo bloquea GUARDAR', (tester) async {
      await _pump(tester, profile: _trainerProfile());

      await tester.enterText(
        find.byKey(const Key('especialidad_precio_card_price_field')),
        '1000000',
      );
      await tester.pump();

      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('especialidad_precio_card_save_button')),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('precio vacío bloquea GUARDAR', (tester) async {
      await _pump(tester, profile: _trainerProfile());

      await tester.enterText(
        find.byKey(const Key('especialidad_precio_card_price_field')),
        '',
      );
      await tester.pump();

      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('especialidad_precio_card_save_button')),
      );
      expect(saveButton.onPressed, isNull);
    });
  });

  group('EspecialidadPrecioCard — modalidad read-only (WU-04)', () {
    testWidgets('trainerOffersOnline true muestra "Online" en el resumen',
        (tester) async {
      await _pump(
        tester,
        profile: _trainerProfile(trainerOffersOnline: true),
      );

      expect(find.byKey(const Key('especialidad_precio_card_modalidad')),
          findsOneWidget);
      expect(find.textContaining('Online'), findsOneWidget);
      expect(
        find.text('Editá tu modalidad y ubicaciones desde la app móvil.'),
        findsOneWidget,
      );
    });

    testWidgets('sin online muestra el conteo de ubicaciones', (tester) async {
      await _pump(
        tester,
        profile: _trainerProfile(
          trainerOffersOnline: false,
          trainerLocations: const [
            TrainerLocation(
              id: 'loc-1',
              type: TrainerLocationType.custom,
              customLabel: 'Box Palermo',
              lat: -34.58,
              lng: -58.43,
              geohash: 'abc12',
            ),
            TrainerLocation(
              id: 'loc-2',
              type: TrainerLocationType.custom,
              customLabel: 'Box Núñez',
              lat: -34.54,
              lng: -58.46,
              geohash: 'def34',
            ),
          ],
        ),
      );

      expect(find.textContaining('2 ubicaciones'), findsOneWidget);
    });
  });

  group('EspecialidadPrecioCard — motion (WU-04)', () {
    testWidgets('dark y light: smoke sin crash', (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await _pump(tester, profile: _trainerProfile(), theme: theme);
        expect(
          find.byKey(const Key('especialidad_precio_card')),
          findsOneWidget,
        );
      }
    });
  });
}
