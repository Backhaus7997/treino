import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';
import 'package:treino/features/auth/presentation/widgets/terms_notice_text.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:treino/core/widgets/treino_logo.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_login_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

Future<void> _pumpLogin(WidgetTester tester, {required ThemeData theme}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const CoachHubLoginScreen(),
      ),
    ),
  );
  await tester.pump();
}

/// Contraste WCAG entre dos colores opacos.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  // La marca del login era el texto «TREINO» en magenta sobre «COACH HUB»: una
  // marca distinta a la de la app móvil y a la del sidebar del propio Coach
  // Hub. Ahora es el wordmark oficial.
  group('marca del login', () {
    testWidgets(
        'es el TreinoLogo y ya no el texto suelto «TREINO»; «COACH HUB» queda',
        (tester) async {
      await _pumpLogin(tester, theme: AppTheme.dark());

      expect(find.byType(TreinoLogo), findsOneWidget);
      // Igualdad exacta: el pie del login también dice "TREINO" (dentro de una
      // frase) y no es la marca.
      expect(
        find.text('TREINO'),
        findsNothing,
        reason: 'la marca volvió a escribirse como texto',
      );
      expect(find.text('COACH HUB'), findsOneWidget);
    });

    testWidgets('el wordmark encabeza el título, no lo pisa', (tester) async {
      await _pumpLogin(tester, theme: AppTheme.dark());

      final logoBottom = tester.getBottomLeft(find.byType(TreinoLogo)).dy;
      final titleTop = tester.getTopLeft(find.text('COACH HUB')).dy;
      expect(logoBottom, lessThanOrEqualTo(titleTop));
    });

    // El login se ve en claro u oscuro según el sistema (`ThemeMode.system`).
    testWidgets('tema oscuro: el wordmark va en accent', (tester) async {
      await _pumpLogin(tester, theme: AppTheme.dark());

      expect(
        tester.widget<TreinoLogo>(find.byType(TreinoLogo)).color,
        AppPalette.mintMagenta.accent,
      );
    });

    testWidgets(
        'tema claro: el wordmark NO va en accent (1,57:1 sobre el papel) y se '
        'lee', (tester) async {
      await _pumpLogin(tester, theme: AppTheme.light());

      const palette = AppPalette.mintMagentaLight;
      final logo = tester.widget<TreinoLogo>(find.byType(TreinoLogo));
      expect(logo.color, isNot(palette.accent));
      expect(logo.color, palette.textPrimary);
      expect(_contrast(logo.color!, palette.bg), greaterThanOrEqualTo(3));
      // Sin halo mint sobre el fondo claro.
      expect(logo.glow, isFalse);
    });
  });

  group('login social (Google / Apple por popup)', () {
    for (final entry in {
      'oscuro': AppTheme.dark(),
      'claro': AppTheme.light(),
    }.entries) {
      testWidgets('tema ${entry.key}: formulario, Google y Apple conviven',
          (tester) async {
        final notifier = _FakePopupNotifier();
        await _pumpLoginSocial(tester, notifier, theme: entry.value);

        expect(find.byType(TextFormField), findsNWidgets(2));
        expect(_boton('INGRESAR'), findsOneWidget);
        expect(_boton('GOOGLE'), findsOneWidget);
        expect(_boton('APPLE'), findsOneWidget);
        expect(find.text('O CONTINUÁ CON'), findsOneWidget);
      });
    }

    testWidgets('tap en Google y en Apple llama a su método del notifier',
        (tester) async {
      final notifier = _FakePopupNotifier();
      await _pumpLoginSocial(tester, notifier);

      await tester.tap(_boton('GOOGLE'));
      await tester.pump();
      expect(notifier.llamadas, ['google']);
      notifier.gate.complete();
      await tester.pump();

      notifier.gate = Completer<void>();
      await tester.tap(_boton('APPLE'));
      await tester.pump();
      expect(notifier.llamadas, ['google', 'apple']);
      notifier.gate.complete();
      await tester.pump();
    });

    testWidgets(
        'mientras Google está en curso: solo Google muestra spinner y los '
        'tres botones (incluido INGRESAR) quedan deshabilitados',
        (tester) async {
      final notifier = _FakePopupNotifier();
      await _pumpLoginSocial(tester, notifier);

      await tester.tap(_boton('GOOGLE'));
      await tester.pump();

      expect(_botonWidget(tester, 'GOOGLE').loading, isTrue);
      expect(_botonWidget(tester, 'APPLE').loading, isFalse);
      expect(_botonWidget(tester, 'INGRESAR').loading, isFalse);
      expect(_botonWidget(tester, 'GOOGLE').onPressed, isNotNull,
          reason: 'loading ya lo bloquea el propio botón');
      expect(_botonWidget(tester, 'APPLE').onPressed, isNull);
      expect(_botonWidget(tester, 'INGRESAR').onPressed, isNull);

      // Un segundo tap en Apple no llega al notifier.
      await tester.tap(_boton('APPLE'), warnIfMissed: false);
      await tester.pump();
      expect(notifier.llamadas, ['google']);

      notifier.gate.complete();
      await tester.pump();
      expect(_botonWidget(tester, 'APPLE').onPressed, isNotNull);
      expect(_botonWidget(tester, 'INGRESAR').onPressed, isNotNull);
    });

    testWidgets('mientras Apple está en curso solo Apple muestra spinner',
        (tester) async {
      final notifier = _FakePopupNotifier();
      await _pumpLoginSocial(tester, notifier);

      await tester.tap(_boton('APPLE'));
      await tester.pump();

      expect(_botonWidget(tester, 'APPLE').loading, isTrue);
      expect(_botonWidget(tester, 'GOOGLE').loading, isFalse);
      expect(_botonWidget(tester, 'GOOGLE').onPressed, isNull);
      expect(_botonWidget(tester, 'INGRESAR').onPressed, isNull);
      notifier.gate.complete();
      await tester.pump();
    });

    testWidgets('el aviso de términos está ANTES de los botones sociales',
        (tester) async {
      await _pumpLoginSocial(tester, _FakePopupNotifier());

      final aviso = tester.getTopLeft(find.byType(TermsNoticeText)).dy;
      final google = tester.getTopLeft(_boton('GOOGLE')).dy;
      final apple = tester.getTopLeft(_boton('APPLE')).dy;
      expect(aviso, lessThan(google));
      expect(aviso, lessThan(apple));
    });

    testWidgets('cancelar: sin SnackBar, sin texto de error, sin spinner',
        (tester) async {
      final notifier = _FakePopupNotifier();
      await _pumpLoginSocial(tester, notifier);

      await tester.tap(_boton('GOOGLE'));
      await tester.pump();
      // El notifier real restaura el estado previo ante un cancel: AsyncData.
      notifier.resultado = const AsyncData<User?>(null);
      notifier.gate.complete();
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(const AuthFailure.signInCancelled().userMessage),
          findsNothing);
      expect(_botonWidget(tester, 'GOOGLE').loading, isFalse);
      expect(_botonWidget(tester, 'GOOGLE').onPressed, isNotNull);
    });

    testWidgets('popupBlocked muestra el copy de ventanas emergentes',
        (tester) async {
      final notifier = _FakePopupNotifier();
      await _pumpLoginSocial(tester, notifier);

      await tester.tap(_boton('APPLE'));
      await tester.pump();
      notifier.resultado = const AsyncError<User?>(
        AuthFailure.popupBlocked(),
        StackTrace.empty,
      );
      notifier.gate.complete();
      await tester.pump();

      expect(find.text(const AuthFailure.popupBlocked().userMessage),
          findsOneWidget);
      expect(
          find.text(const AuthFailure.unknown('x').userMessage), findsNothing);
      expect(_botonWidget(tester, 'APPLE').loading, isFalse);
    });

    for (final entry in {
      'oscuro': AppTheme.dark(),
      'claro': AppTheme.light(),
    }.entries) {
      testWidgets(
          'tema ${entry.key}: providerUnavailable muestra la dirección de '
          'contacto seleccionable', (tester) async {
        final notifier = _FakePopupNotifier();
        await _pumpLoginSocial(tester, notifier, theme: entry.value);

        await tester.tap(_boton('GOOGLE'));
        await tester.pump();
        notifier.resultado = const AsyncError<User?>(
          AuthFailure.providerUnavailable(),
          StackTrace.empty,
        );
        notifier.gate.complete();
        await tester.pump();

        expect(find.text(const AuthFailure.providerUnavailable().userMessage),
            findsOneWidget);
        expect(find.widgetWithText(SelectableText, kLegalContactEmail),
            findsOneWidget);
      });

      testWidgets(
          'tema ${entry.key}: popupBlocked NO muestra la dirección de contacto',
          (tester) async {
        final notifier = _FakePopupNotifier();
        await _pumpLoginSocial(tester, notifier, theme: entry.value);

        await tester.tap(_boton('APPLE'));
        await tester.pump();
        notifier.resultado = const AsyncError<User?>(
          AuthFailure.popupBlocked(),
          StackTrace.empty,
        );
        notifier.gate.complete();
        await tester.pump();

        expect(find.text(const AuthFailure.popupBlocked().userMessage),
            findsOneWidget);
        expect(find.text(kLegalContactEmail), findsNothing);
        expect(find.byType(SelectableText), findsNothing);
      });
    }

    testWidgets('el éxito no navega desde la pantalla: sigue montada sin error',
        (tester) async {
      final notifier = _FakePopupNotifier();
      final observer = _CuentaPushes();
      await _pumpLoginSocial(tester, notifier, observer: observer);

      await tester.tap(_boton('GOOGLE'));
      await tester.pump();
      notifier.gate.complete();
      await tester.pump();

      // Navegar es del router (redirect por authStateChanges); la pantalla no
      // empuja ninguna ruta ni muestra nada nuevo.
      expect(observer.pushes, 1, reason: 'solo la ruta inicial');
      expect(find.byType(CoachHubLoginScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    // INVARIANTE DE POPUP: entre el tap y `signInWithPopup` no puede haber
    // ningún `await`, o el navegador pierde la activación del usuario y
    // bloquea la ventana. Lo que SÍ se puede probar acá: invocar el onPressed
    // y mirar el fake SIN ceder al event loop. Un `await` previo a la llamada
    // al notifier hace que `llamadas` siga vacío en este punto. Lo que NO se
    // puede probar en unit test: que el navegador conceda el popup (activación
    // transitoria del usuario) ni la cadena notifier → servicio real; eso es
    // verificación MANUAL (paso 3 del checklist de usuario en tasks.md).
    testWidgets('el notifier se invoca de forma síncrona dentro del onPressed',
        (tester) async {
      final notifier = _FakePopupNotifier();
      await _pumpLoginSocial(tester, notifier);

      _botonWidget(tester, 'GOOGLE').onPressed!();
      expect(notifier.llamadas, ['google'],
          reason: 'hubo un await entre onPressed y el notifier');
      notifier.gate.complete();
      await tester.pump();

      notifier.gate = Completer<void>();
      _botonWidget(tester, 'APPLE').onPressed!();
      expect(notifier.llamadas, ['google', 'apple'],
          reason: 'hubo un await entre onPressed y el notifier');
      notifier.gate.complete();
      await tester.pump();
    });
  });
}

class _CuentaPushes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

Finder _boton(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TreinoButton),
    );

TreinoButton _botonWidget(WidgetTester tester, String label) =>
    tester.widget<TreinoButton>(_boton(label));

/// Notifier de prueba: registra qué método popup se llamó y resuelve cuando el
/// test completa [gate]. La llamada es síncrona hasta el primer await, igual
/// que el real.
class _FakePopupNotifier extends AuthNotifier {
  final List<String> llamadas = [];
  Completer<void> gate = Completer<void>();
  AsyncValue<User?> resultado = const AsyncData<User?>(null);

  @override
  Future<User?> build() async => null;

  @override
  Future<void> signInWithGooglePopup() => _hacer('google');

  @override
  Future<void> signInWithApplePopup() => _hacer('apple');

  Future<void> _hacer(String quien) async {
    llamadas.add(quien);
    state = const AsyncLoading();
    await gate.future;
    state = resultado;
  }
}

Future<void> _pumpLoginSocial(
  WidgetTester tester,
  _FakePopupNotifier notifier, {
  ThemeData? theme,
  NavigatorObserver? observer,
}) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authNotifierProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        theme: theme ?? AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        navigatorObservers: [if (observer != null) observer],
        home: const CoachHubLoginScreen(),
      ),
    ),
  );
  await tester.pump();
}
