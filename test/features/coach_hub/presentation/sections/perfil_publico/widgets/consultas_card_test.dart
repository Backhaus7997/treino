// ConsultasCard — el kill switch de las consultas previas en el Coach Hub
// (#637).
//
// Persiste AL TOCAR (sin botón Guardar), optimista, revierte con SnackBar si
// el `update` falla. Ver el comentario de cabecera en
// `consultas_card.dart` para el porqué del patrón (vs. IdentidadCard, que
// SÍ tiene dirty/save porque edita texto libre).
//
// Harness: la card llama `AppL10n.of(context)`, así que el `MaterialApp`
// necesita los delegates de l10n + locale es_AR — sin eso revienta con
// "Null check operator used on a null value".
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/perfil_publico/widgets/consultas_card.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockUserRepo extends Mock implements UserRepository {}

UserProfile _trainerProfile({bool acceptsInquiries = true}) => UserProfile(
      uid: 'trainer-1',
      email: 'trainer@treino.app',
      displayName: 'Joaquín Nadal',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      acceptsInquiries: acceptsInquiries,
    );

Future<UserRepository> _pump(
  WidgetTester tester, {
  required UserProfile profile,
  UserRepository? repo,
}) async {
  final effectiveRepo = repo ?? _MockUserRepo();
  // Sólo pisamos el stub por defecto cuando el caller NO trajo su propio
  // repo: un `repo` explícito puede venir pre-stubbeado para fallar (B4), y
  // re-stubbear acá encima lo volvería siempre exitoso.
  if (repo == null && effectiveRepo is _MockUserRepo) {
    when(() => effectiveRepo.update(any(), any())).thenAnswer((_) async {});
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userRepositoryProvider.overrideWithValue(effectiveRepo),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: ConsultasCard(profile: profile)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return effectiveRepo;
}

void main() {
  setUpAll(() => registerFallbackValue(<String, Object?>{}));

  group('ConsultasCard — render (#637)', () {
    testWidgets('se dibuja con el valor ON del perfil', (tester) async {
      await _pump(tester, profile: _trainerProfile(acceptsInquiries: true));

      expect(find.byKey(const Key('consultas_card')), findsOneWidget);
      final sw =
          tester.widget<Switch>(find.byKey(const Key('consultas_card_switch')));
      expect(sw.value, isTrue);
    });

    testWidgets('se dibuja con el valor OFF del perfil', (tester) async {
      await _pump(tester, profile: _trainerProfile(acceptsInquiries: false));

      final sw =
          tester.widget<Switch>(find.byKey(const Key('consultas_card_switch')));
      expect(sw.value, isFalse);
    });
  });

  group('ConsultasCard — persiste al tocar (#637)', () {
    testWidgets('tocar el switch llama a update con el mapa exacto',
        (tester) async {
      final repo = _MockUserRepo();
      final usedRepo = await _pump(
        tester,
        profile: _trainerProfile(acceptsInquiries: true),
        repo: repo,
      );

      await tester.tap(find.byKey(const Key('consultas_card_switch')));
      await tester.pumpAndSettle();

      final captured = verify(
        () => (usedRepo as _MockUserRepo).update('trainer-1', captureAny()),
      ).captured.single as Map<String, Object?>;
      expect(captured, equals({'acceptsInquiries': false}));
    });
  });

  group('ConsultasCard — optimista (#637)', () {
    testWidgets('el switch se mueve ANTES de que resuelva el update',
        (tester) async {
      final repo = _MockUserRepo();
      final completer = Completer<void>();
      when(() => repo.update(any(), any())).thenAnswer((_) => completer.future);

      await _pump(
        tester,
        profile: _trainerProfile(acceptsInquiries: true),
        repo: repo,
      );

      await tester.tap(find.byKey(const Key('consultas_card_switch')));
      // Un solo frame: el Future del update TODAVÍA no resolvió (el
      // completer sigue sin completar).
      await tester.pump();

      final sw =
          tester.widget<Switch>(find.byKey(const Key('consultas_card_switch')));
      expect(sw.value, isFalse,
          reason: 'optimista: el switch ya se movió sin esperar al server');

      // Dejamos resolver el Future pendiente para no filtrar el timer/estado
      // colgado al siguiente test.
      completer.complete();
      await tester.pumpAndSettle();
    });
  });

  group('ConsultasCard — revierte si falla (#637)', () {
    testWidgets(
        'update rechazado: el switch vuelve al valor anterior y aparece '
        'un SnackBar', (tester) async {
      final repo = _MockUserRepo();
      when(() => repo.update(any(), any()))
          .thenAnswer((_) async => throw Exception('boom'));

      await _pump(
        tester,
        profile: _trainerProfile(acceptsInquiries: true),
        repo: repo,
      );

      await tester.tap(find.byKey(const Key('consultas_card_switch')));
      await tester.pumpAndSettle();

      final sw =
          tester.widget<Switch>(find.byKey(const Key('consultas_card_switch')));
      expect(sw.value, isTrue,
          reason: 'debe revertir al valor anterior cuando el update falla');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('No se pudo guardar. Probá de nuevo.'), findsOneWidget);
    });
  });
}
