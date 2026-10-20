// Layout estilo Spotify de las tres pantallas de entrada (bienvenida, login,
// registro): orden de los bloques, botones sociales a ancho completo y el
// cambio Login <-> Registro con `pushReplacement` (la bienvenida queda abajo).
//
// Los widget tests corren como Android por defecto; el back por gesto se prueba
// forzando iOS por el tema (igual que router_auth_swipe_back_test.dart).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_logo.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/presentation/login_screen.dart';
import 'package:treino/features/auth/presentation/register_screen.dart';
import 'package:treino/features/auth/presentation/welcome_screen.dart';
import 'package:treino/features/auth/presentation/widgets/auth_pill_button.dart';
import 'package:treino/features/auth/presentation/widgets/auth_secondary_button.dart';
import 'package:treino/features/auth/presentation/widgets/terms_checkbox.dart';
import 'package:treino/features/auth/presentation/widgets/terms_notice_text.dart';
import 'package:treino/features/auth/presentation/widgets/trainer_inquiry_card.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

class _LoggedOutAuthNotifier extends AuthNotifier {
  @override
  Future<User?> build() async {
    state = const AsyncData(null);
    return null;
  }
}

Future<GoRouter> _pumpApp(WidgetTester tester, String start) async {
  final container = ProviderContainer(
    overrides: [
      authNotifierProvider.overrideWith(_LoggedOutAuthNotifier.new),
      userProfileProvider
          .overrideWith((ref) => Stream<UserProfile?>.value(null)),
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(authNotifierProvider.future);

  final router = buildRouter(
    refreshListenable: ValueNotifier<int>(0),
    read: container.read,
  );
  router.go(start);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark().copyWith(platform: TargetPlatform.iOS),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _swipeBack(WidgetTester tester) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final gesture = await tester.startGesture(Offset(4, size.height / 2));
  for (var i = 0; i < 10; i++) {
    await gesture.moveBy(Offset(size.width * 0.07, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void _expectSocialStackedFullWidth(WidgetTester tester) {
  final buttons = find.byType(AuthSecondaryButton);
  expect(buttons, findsNWidgets(2));
  final google = tester.getRect(buttons.at(0));
  final apple = tester.getRect(buttons.at(1));
  final cta = tester.getRect(find.byType(AuthPillButton).first);

  expect(tester.widget<AuthSecondaryButton>(buttons.at(0)).label,
      'Continuar con Google');
  expect(tester.widget<AuthSecondaryButton>(buttons.at(1)).label,
      'Continuar con Apple');
  // Google arriba de Apple, 12 px de separación, mismo ancho que el CTA verde.
  expect(apple.top - google.bottom, 12);
  expect(google.left, apple.left);
  expect(google.width, cta.width);
  expect(apple.width, cta.width);
}

void main() {
  group('LoginScreen', () {
    testWidgets(
        'orden: título, campos, ENTRAR, social, leyenda, tarjeta, '
        'cambio a Registro', (tester) async {
      await _pumpApp(tester, '/login');

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(TreinoLogo), findsNothing);
      expect(find.text('BIENVENIDO'), findsNothing);

      double top(Finder f) => tester.getRect(f).top;
      final ys = <double>[
        top(find.text('Iniciar sesión').first),
        top(find.byType(TextFormField).at(0)),
        top(find.byType(TextFormField).at(1)),
        top(find.text('Olvidé la contraseña')),
        top(find.byType(AuthPillButton)),
        top(find.text('O iniciá sesión con')),
        top(find.byType(AuthSecondaryButton).at(0)),
        top(find.byType(AuthSecondaryButton).at(1)),
        top(find.byType(TermsNoticeText)),
        top(find.byType(TrainerInquiryCard)),
        top(find.text('¿No tenés cuenta?')),
        top(find.text('Registrate')),
      ];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]),
            reason: 'el bloque $i tiene que ir debajo del ${i - 1}');
      }
    });

    testWidgets('Google arriba de Apple, ambos a ancho completo',
        (tester) async {
      await _pumpApp(tester, '/login');
      _expectSocialStackedFullWidth(tester);
    });

    testWidgets(
        '«Registrate» es un blanco táctil de al menos 48 pt anunciado '
        'como botón', (tester) async {
      await _pumpApp(tester, '/login');

      final link = find.ancestor(
        of: find.text('Registrate'),
        matching: find.byType(GestureDetector),
      );
      expect(tester.getSize(link.first).height, greaterThanOrEqualTo(48));
      expect(
        find
            .ancestor(
                of: find.text('Registrate'), matching: find.byType(Semantics))
            .evaluate()
            .any((e) => (e.widget as Semantics).properties.button == true),
        isTrue,
      );
    });

    testWidgets('«Registrate» REEMPLAZA a Login: atrás vuelve a la bienvenida',
        (tester) async {
      final router = await _pumpApp(tester, '/welcome');
      router.push('/login');
      await tester.pumpAndSettle();

      await _tapText(tester, 'Registrate');
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);

      await _swipeBack(tester);

      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });
  });

  group('RegisterScreen', () {
    testWidgets(
        'orden: título, campos, términos, CTA, social, leyenda, '
        'tarjeta, cambio a Login', (tester) async {
      await _pumpApp(tester, '/register');

      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.byType(TreinoLogo), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(2));

      double top(Finder f) => tester.getRect(f).top;
      final ys = <double>[
        top(find.text('Crear una cuenta')),
        top(find.byType(TextFormField).at(0)),
        top(find.byType(TextFormField).at(1)),
        top(find.byType(TermsCheckbox)),
        top(find.byType(AuthPillButton)),
        top(find.text('O registrate con')),
        top(find.byType(AuthSecondaryButton).at(0)),
        top(find.byType(AuthSecondaryButton).at(1)),
        top(find.byType(TermsNoticeText)),
        top(find.byType(TrainerInquiryCard)),
        top(find.text('¿Ya tenés cuenta?')),
        top(find.text('Iniciá sesión')),
      ];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]),
            reason: 'el bloque $i tiene que ir debajo del ${i - 1}');
      }
    });

    testWidgets('Google arriba de Apple, ambos a ancho completo',
        (tester) async {
      await _pumpApp(tester, '/register');
      _expectSocialStackedFullWidth(tester);
    });

    testWidgets(
        '«Iniciá sesión» REEMPLAZA a Registro: atrás vuelve a la '
        'bienvenida', (tester) async {
      final router = await _pumpApp(tester, '/welcome');
      router.push('/register');
      await tester.pumpAndSettle();

      await _tapText(tester, 'Iniciá sesión');
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(RegisterScreen), findsNothing);

      await _swipeBack(tester);

      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });
  });
}
