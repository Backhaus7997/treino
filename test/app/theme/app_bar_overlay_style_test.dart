import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/theme_watcher.dart';

/// #1463: un `AppBar` con `backgroundColor: Colors.transparent` y sin
/// `systemOverlayStyle` estimaba «fondo oscuro» y pintaba los íconos de la
/// barra de estado en BLANCO, también sobre el fondo claro del tema claro.
///
/// Se mira el `AnnotatedRegion` que el propio `AppBar` dibuja: es el que gana
/// sobre el de `ThemeWatcher` (está más abajo en el árbol), así que es el valor
/// que llega a la barra de estado.
void main() {
  Future<SystemUiOverlayStyle> estiloDelAppBar(
    WidgetTester tester,
    ThemeData theme,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(backgroundColor: Colors.transparent),
        ),
      ),
    );
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
    );
    return region.value;
  }

  group('AppBar transparente resuelve la barra de estado por el tema', () {
    testWidgets('tema claro → íconos OSCUROS', (tester) async {
      final estilo = await estiloDelAppBar(tester, AppTheme.light());

      expect(estilo.statusBarIconBrightness, Brightness.dark);
      expect(estilo.statusBarBrightness, Brightness.light);
    });

    testWidgets('tema oscuro → íconos CLAROS', (tester) async {
      final estilo = await estiloDelAppBar(tester, AppTheme.dark());

      expect(estilo.statusBarIconBrightness, Brightness.light);
      expect(estilo.statusBarBrightness, Brightness.dark);
    });

    testWidgets('un AppBar con systemOverlayStyle propio lo sigue pisando',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              systemOverlayStyle: SystemUiOverlayStyle.light,
            ),
          ),
        ),
      );
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
      );

      expect(region.value.statusBarIconBrightness, Brightness.light);
    });
  });

  group('ThemeWatcher y el AppBar no se pelean', () {
    for (final (nombre, theme) in [
      ('claro', AppTheme.light()),
      ('oscuro', AppTheme.dark()),
    ]) {
      testWidgets('tema $nombre: la región del Watcher es la misma del AppBar',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: ThemeWatcher(
              child: Scaffold(
                appBar: AppBar(backgroundColor: Colors.transparent),
              ),
            ),
          ),
        );
        final delWatcher = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find
              .descendant(
                of: find.byType(ThemeWatcher),
                matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
              )
              .first,
        );
        final delAppBar = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          ),
        );

        expect(delAppBar.value, delWatcher.value);
      });
    }
  });
}
