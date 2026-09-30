import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
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
}
