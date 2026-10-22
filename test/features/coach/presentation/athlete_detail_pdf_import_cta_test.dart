// «IMPORTAR DE PDF» en la ficha del alumno (docs/plan-import-pdf.md, paso
// 1): sólo con el gate en `enabled`; cargando o apagado queda sólo CREAR
// PLAN, sin reservar lugar para el CTA.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/nutrition_plan_providers.dart';
import 'package:treino/features/coach/presentation/athlete_detail_screen.dart';
import 'package:treino/features/coach_hub/application/plan_pdf_import_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

Future<void> _pump(WidgetTester tester, PdfImportGate gate) async {
  final router = GoRouter(
    initialLocation: '/coach/athlete/athlete-1',
    routes: [
      GoRoute(
        path: '/coach/athlete/:athleteId',
        builder: (_, state) => AthleteDetailScreen(
          athleteId: state.pathParameters['athleteId']!,
        ),
      ),
      GoRoute(
        path: '/workout/import-pdf/:athleteId',
        builder: (_, state) =>
            Text('import:${state.pathParameters['athleteId']}'),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      nutritionPlanProvider.overrideWith((ref, key) => Stream.value(null)),
      currentUidProvider.overrideWithValue('trainer-1'),
      userPublicProfileProvider('athlete-1').overrideWith(
        (ref) => Stream.value(const UserPublicProfile(
            uid: 'athlete-1', displayName: 'Martín García')),
      ),
      assignedRoutinesByTrainerProvider
          .overrideWith((ref, key) async => const []),
      pdfImportGateProvider.overrideWithValue(gate),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('habilitado: IMPORTAR DE PDF al lado de CREAR PLAN, y navega',
      (tester) async {
    await _pump(tester, PdfImportGate.enabled);

    final importar = find.text('IMPORTAR DE PDF');
    expect(importar, findsOneWidget);
    // Al lado, no abajo: la misma fila.
    final crear = tester.getRect(find.text('CREAR PLAN'));
    expect(tester.getRect(importar).center.dy, closeTo(crear.center.dy, 1));
    expect(tester.getRect(importar).right, lessThan(crear.left));

    await tester.tap(importar);
    await tester.pumpAndSettle();
    expect(find.text('import:athlete-1'), findsOneWidget);
  });

  for (final gate in [PdfImportGate.loading, PdfImportGate.disabled]) {
    testWidgets('${gate.name}: no hay CTA y CREAR PLAN ocupa el ancho',
        (tester) async {
      await _pump(tester, gate);

      expect(find.text('IMPORTAR DE PDF'), findsNothing);
      expect(find.byKey(const Key('athlete_detail_import_pdf')), findsNothing);
      // Sin hueco reservado: CREAR PLAN va de borde a borde (20 de gutter).
      final button = find.ancestor(
        of: find.text('CREAR PLAN'),
        matching: find.byType(ElevatedButton),
      );
      final width = tester.getSize(find.byType(MaterialApp)).width;
      expect(tester.getSize(button).width, width - 40);
    });
  }
}
