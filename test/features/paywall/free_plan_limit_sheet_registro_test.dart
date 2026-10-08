// free_plan_limit_sheet_registro_test.dart — que el tope tocado quede anotado.
//
// ─── Qué cuida este archivo ─────────────────────────────────────────────────
//
// El alumno que choca un tope del plan free es el momento de mayor intención
// que hay: está tratando de hacer algo y se topa con una pared. Pero la app NO
// PUEDE decirle dónde se paga — la Guideline 3.1.3(f) exime del IAP a las apps
// companion siempre que no haya compras adentro **ni llamados a comprar
// afuera**, y ese amparo es lo que sostiene el cobro del entrenador.
//
// La salida es un mail, y para mandarlo el backend tiene que enterarse de que
// el intento existió. Los ocho lugares que abren la hoja son de cliente puro y
// no escribían nada: el backend no sabía.
//
// ─── La línea que no se puede cruzar ────────────────────────────────────────
//
// Lo que se escribe es INVISIBLE. La hoja no cambia una palabra, no aparece
// ningún botón, y Apple revisa la interfaz. Una anotación que el usuario no ve
// no es un llamado a comprar.
//
// Un «te mandamos un mail» impreso en la hoja SÍ lo sería, porque señalizaría
// el camino de compra desde adentro del binario. Ese guard vive en
// `superficie_de_cobro_alumno_test.dart`, junto a sus hermanos.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/paywall/presentation/free_plan_limit_sheet.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

class _RepoFalso extends Mock implements UserRepository {}

/// Monta un botón que abre la hoja, con los providers que la anotación usa.
Future<void> _montar(
  WidgetTester tester, {
  required UserRepository repo,
  String? uid = 'a1',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userRepositoryProvider.overrideWithValue(repo),
        currentUidProvider.overrideWithValue(uid),
      ],
      child: MaterialApp(
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showFreePlanLimitSheet(
                context,
                limit: FreePlanLimit.routineCount,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue('');
  });

  testWidgets('abrir la hoja anota el tope tocado, con cuál fue',
      (tester) async {
    final repo = _RepoFalso();
    when(() => repo.registrarTopeTocado(any(), any())).thenAnswer((_) async {});

    await _montar(tester, repo: repo);
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // El `kind` viaja: sin él, el mail no puede distinguir «se quedó sin
    // rutinas» de «quiso una plantilla paga», que son dos mensajes distintos.
    verify(() =>
            repo.registrarTopeTocado('a1', FreePlanLimit.routineCount.name))
        .called(1);
  });

  testWidgets('⚠️ sin sesión no anota nada', (tester) async {
    // La hoja se puede abrir en un estado sin uid resuelto. Escribir con un
    // uid vacío ensuciaría un documento ajeno o ninguno.
    final repo = _RepoFalso();
    when(() => repo.registrarTopeTocado(any(), any())).thenAnswer((_) async {});

    await _montar(tester, repo: repo, uid: null);
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    verifyNever(() => repo.registrarTopeTocado(any(), any()));
  });

  testWidgets('⚠️ si la anotación falla, la hoja abre igual', (tester) async {
    // LA aserción del archivo. Que el usuario no vea el mensaje que explica por
    // qué no puede hacer algo —porque falló una anotación que no le importa—
    // sería cambiarle un límite explicado por uno mudo.
    final repo = _RepoFalso();
    when(() => repo.registrarTopeTocado(any(), any()))
        .thenThrow(Exception('firestore caido'));

    await _montar(tester, repo: repo);
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // La hoja está en pantalla: hay un bottom sheet montado.
    expect(find.byType(BottomSheet), findsOneWidget);
  });
}
