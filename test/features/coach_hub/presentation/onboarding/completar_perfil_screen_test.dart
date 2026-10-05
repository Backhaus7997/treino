import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/auth/presentation/widgets/auth_input.dart';
import 'package:treino/features/auth/presentation/widgets/terms_checkbox.dart';
import 'package:treino/features/coach_hub/presentation/onboarding/completar_perfil_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile_setup/presentation/widgets/born_at_field.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Cuenta cuántas veces algo llama a `AuthService.signOut()`: el camino que
/// cuelga en web. La pantalla NO debe tocarlo nunca.
class _AuthServiceEspia implements AuthService {
  int signOuts = 0;

  @override
  Future<void> signOut() async => signOuts++;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _RepoFalible extends UserRepository {
  _RepoFalible({required super.firestore});

  Object? errorEnUpdate;

  @override
  Future<void> update(
    String uid,
    Map<String, Object?> partial, {
    bool grantLocationConsent = false,
  }) {
    final e = errorEnUpdate;
    if (e != null) throw e;
    return super
        .update(uid, partial, grantLocationConsent: grantLocationConsent);
  }
}

enum _Paso { age, identity, pf }

void main() {
  late FakeFirebaseFirestore firestore;
  late _RepoFalible repo;
  late _AuthServiceEspia auth;
  late int cerrarSesionCalls;
  Object? cerrarSesionError;
  DateTime? fechaElegida;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = _RepoFalible(firestore: firestore);
    auth = _AuthServiceEspia();
    cerrarSesionCalls = 0;
    cerrarSesionError = null;
    fechaElegida = null;
  });

  /// Siembra el perfil del paso pedido. `age`: sin `bornAt`. `identity`: con
  /// `bornAt` y sin `displayName`. `pf`: con las dos y sin perfil profesional.
  Future<void> sembrar(_Paso paso, {Map<String, Object?>? extra}) async {
    final now = DateTime.utc(2026, 1, 1);
    await firestore.collection('users').doc('u1').set({
      'uid': 'u1',
      'email': 'pf@test.com',
      'displayName': paso == _Paso.pf || paso == _Paso.age ? 'Mateo' : null,
      'role': 'trainer',
      'createdAt': now,
      'updatedAt': now,
      if (paso != _Paso.age) 'bornAt': DateTime.utc(1990, 5, 20),
      ...?extra,
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    required ThemeData theme,
    Size size = const Size(1280, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          userRepositoryProvider.overrideWithValue(repo),
          userProfileProvider.overrideWith((ref) => repo.watch('u1')),
          authServiceProvider.overrideWithValue(auth),
        ],
        child: MaterialApp(
          theme: theme,
          locale: const Locale('es', 'AR'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: CompletarPerfilScreen(
            cerrarSesion: () async {
              cerrarSesionCalls++;
              final e = cerrarSesionError;
              if (e != null) throw e;
            },
            elegirFecha: (context, actual) async => fechaElegida,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<Map<String, Object?>> usuario() async =>
      (await firestore.collection('users').doc('u1').get()).data()!;

  AppL10n l10nDe(WidgetTester tester) =>
      AppL10n.of(tester.element(find.byType(CompletarPerfilScreen)));

  final temas = <String, ThemeData Function()>{
    'dark': AppTheme.dark,
    'light': AppTheme.light,
  };

  for (final entry in temas.entries) {
    group('CompletarPerfilScreen (${entry.key})', () {
      // SCENARIO-CHW-ONB-020
      testWidgets('no dibuja el shell y acota el contenido a 560 px',
          (tester) async {
        await sembrar(_Paso.age);
        await pump(tester, theme: entry.value());

        expect(find.byType(CoachHubScaffold), findsNothing);
        final caja = find.byKey(const ValueKey('completar-perfil-contenido'));
        expect(caja, findsOneWidget);
        expect(tester.getSize(caja).width, lessThanOrEqualTo(560));
      });

      // SCENARIO-CHW-ONB-021 (en cada uno de los tres pasos)
      for (final paso in _Paso.values) {
        testWidgets('«Cerrar sesión» en ${paso.name} va por el seam directo',
            (tester) async {
          await sembrar(paso);
          await pump(tester, theme: entry.value());
          final l10n = l10nDe(tester);

          await tester.tap(find.text(l10n.authProfileSignOut));
          await tester.pump();

          expect(cerrarSesionCalls, 1);
          expect(auth.signOuts, 0, reason: 'AuthService.signOut cuelga en web');
        });

        testWidgets('si cerrar sesión falla en ${paso.name}, muestra el error',
            (tester) async {
          await sembrar(paso);
          cerrarSesionError = Exception('boom');
          await pump(tester, theme: entry.value());
          final l10n = l10nDe(tester);

          await tester.tap(find.text(l10n.authProfileSignOut));
          await tester.pump();
          await tester.pump();

          expect(find.text(l10n.coachHubSignOutError), findsOneWidget);
          expect(auth.signOuts, 0);
        });
      }

      // SCENARIO-CHW-ONB-022
      testWidgets('ningún paso ofrece cancelar la cuenta', (tester) async {
        for (final paso in _Paso.values) {
          await firestore.clearPersistence();
          await sembrar(paso);
          await pump(tester, theme: entry.value());
          expect(find.textContaining('Cancelar cuenta'), findsNothing);
          expect(find.textContaining('Eliminar cuenta'), findsNothing);
          expect(find.textContaining('/welcome'), findsNothing);
        }
      });

      // SCENARIO-CHW-ONB-026
      testWidgets('edad: 12 años muestra el error y no escribe',
          (tester) async {
        await sembrar(_Paso.age);
        final ahora = DateTime.now();
        fechaElegida = DateTime.utc(ahora.year - 12, ahora.month, ahora.day);
        await pump(tester, theme: entry.value());
        final l10n = l10nDe(tester);

        await tester.tap(find.byType(BornAtField));
        await tester.pump();
        await tester.tap(find.text(l10n.coachHubOnboardingContinue));
        await tester.pump();
        await tester.pump();

        expect(find.text('Tenés que tener 13 años para usar TREINO'),
            findsOneWidget);
        expect((await usuario()).containsKey('bornAt'), isFalse);
      });

      // SCENARIO-CHW-ONB-027 (lado widget) y 045
      testWidgets('edad: una fecha válida escribe bornAt y pasa a identidad',
          (tester) async {
        await sembrar(_Paso.age, extra: {'displayName': null});
        fechaElegida = DateTime.utc(1990, 5, 20);
        await pump(tester, theme: entry.value());
        final l10n = l10nDe(tester);

        // 045: un PF que solo falla la edad ve únicamente `age`.
        expect(find.byType(BornAtField), findsOneWidget);
        expect(find.byType(AuthInput), findsNothing);

        await tester.tap(find.byType(BornAtField));
        await tester.pump();
        await tester.tap(find.text(l10n.coachHubOnboardingContinue));
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect((await usuario())['bornAt'], isNotNull);
        expect(find.byType(BornAtField), findsNothing);
        expect(find.byType(AuthInput), findsNWidgets(2));
      });

      // SCENARIO-CHW-ONB-023
      testWidgets('identidad: campos vacíos o en blanco no escriben',
          (tester) async {
        await sembrar(_Paso.identity,
            extra: {'termsAcceptedAt': DateTime.utc(2026)});
        await pump(tester, theme: entry.value());
        final l10n = l10nDe(tester);

        await tester.enterText(find.byType(TextFormField).at(0), '   ');
        await tester.enterText(find.byType(TextFormField).at(1), '');
        await tester.tap(find.text(l10n.coachHubOnboardingContinue));
        await tester.pump();
        await tester.pump();

        expect(find.text(l10n.coachHubOnboardingFirstNameRequired),
            findsOneWidget);
        expect(
            find.text(l10n.coachHubOnboardingLastNameRequired), findsOneWidget);
        expect((await usuario())['displayName'], isNull);
      });

      // SCENARIO-CHW-ONB-029 + camino feliz de 024/030
      testWidgets('identidad: sin marcar términos el botón está deshabilitado',
          (tester) async {
        await sembrar(_Paso.identity);
        await pump(tester, theme: entry.value());
        final l10n = l10nDe(tester);

        await tester.enterText(find.byType(TextFormField).at(0), 'Ana');
        await tester.enterText(find.byType(TextFormField).at(1), 'Pérez');
        await tester.pump();

        expect(find.byType(TermsCheckbox), findsOneWidget);
        TreinoButton continuar() => tester.widget<TreinoButton>(
            find.widgetWithText(TreinoButton, l10n.coachHubOnboardingContinue));
        expect(continuar().onPressed, isNull);
        expect((await usuario())['displayName'], isNull);

        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        expect(continuar().onPressed, isNotNull);

        await tester.tap(find.text(l10n.coachHubOnboardingContinue));
        await tester.pump();
        await tester.pump();
        await tester.pump();

        final u = await usuario();
        expect(u['displayName'], 'Ana Pérez');
        expect(u['termsAcceptedAt'], isNotNull);
        // La etapa recalculada es `pf`: ya no hay campos de nombre (el
        // `AuthInput` que queda es el buscador de lugares, no el de identidad).
        expect(find.text(l10n.coachHubOnboardingFirstNameLabel), findsNothing);
        expect(find.byKey(const Key('onboarding-pf-bio')), findsOneWidget);
      });

      testWidgets('identidad: con evidencia previa no muestra el checkbox',
          (tester) async {
        await sembrar(_Paso.identity,
            extra: {'termsAcceptedAt': DateTime.utc(2026)});
        await pump(tester, theme: entry.value());

        expect(find.byType(TermsCheckbox), findsNothing);
      });

      // SCENARIO-CHW-ONB-028
      testWidgets('un error de escritura se muestra y rehabilita el botón',
          (tester) async {
        await sembrar(_Paso.age);
        fechaElegida = DateTime.utc(1990, 5, 20);
        repo.errorEnUpdate = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        );
        await pump(tester, theme: entry.value());
        final l10n = l10nDe(tester);

        await tester.tap(find.byType(BornAtField));
        await tester.pump();
        await tester.tap(find.text(l10n.coachHubOnboardingContinue));
        await tester.pump();
        await tester.pump();

        expect(find.text(l10n.coachHubOnboardingSaveError), findsOneWidget);
        final boton = tester.widget<TreinoButton>(
            find.widgetWithText(TreinoButton, l10n.coachHubOnboardingContinue));
        expect(boton.onPressed, isNotNull);
        expect(boton.loading, isFalse);
        expect(find.byType(BornAtField), findsOneWidget);
      });

      // SCENARIO-CHW-ONB-047 y 053
      for (final paso in _Paso.values) {
        for (final ancho in <double>[360, 1280]) {
          testWidgets(
              '${paso.name} a $ancho px: sin overflow ni campos de alumno',
              (tester) async {
            await sembrar(paso);
            await pump(tester, theme: entry.value(), size: Size(ancho, 800));

            expect(tester.takeException(), isNull);
            for (final prohibido in [
              'gimnasio',
              'experiencia',
              'género',
              'peso',
              'altura',
              'avatar',
              'foto',
            ]) {
              expect(
                  find.textContaining(RegExp(prohibido, caseSensitive: false)),
                  findsNothing,
                  reason: prohibido);
            }
          });
        }
      }
    });
  }
}
