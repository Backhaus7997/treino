import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/widgets/empty_state/empty_state.dart';

/// Envuelve en MaterialApp con el tema dado.
Widget _wrap(Widget widget, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(body: widget),
    );

void main() {
  group('TreinoEmptyState —', () {
    // -------------------------------------------------------------------------
    // Normal: ícono + título + descripción
    // -------------------------------------------------------------------------
    testWidgets(
        'normal → ícono, título y descripción visibles '
        '[SCENARIO-CK-ES-01]', (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoEmptyState(
          icon: TreinoIcon.emptyState,
          title: 'Sin alumnos todavía',
          description: 'Invitá a tu primer alumno para empezar.',
        ),
      ));
      await tester.pump();
      expect(find.text('Sin alumnos todavía'), findsOneWidget);
      expect(
        find.text('Invitá a tu primer alumno para empezar.'),
        findsOneWidget,
      );
      expect(find.byIcon(TreinoIcon.emptyState), findsOneWidget);
      // Spacing en escala 8/12/14/18/20 — Finding W4 (no padding 32 crudo).
      final padding = tester.widget<Padding>(
        find.byKey(const Key('empty_state_content')),
      );
      expect(padding.padding, const EdgeInsets.all(AppSpacing.s20));
    });

    // -------------------------------------------------------------------------
    // Sin descripción: solo ícono + título
    // -------------------------------------------------------------------------
    testWidgets(
        'sin descripción → renderiza solo ícono y título '
        '[SCENARIO-CK-ES-02]', (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoEmptyState(
          icon: TreinoIcon.emptyState,
          title: 'Sin datos',
        ),
      ));
      await tester.pump();
      expect(find.text('Sin datos'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Con CTA: botón visible y callback
    // -------------------------------------------------------------------------
    testWidgets(
        'con CTA → botón visible y llama callback '
        '[SCENARIO-CK-ES-03]', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_wrap(
        TreinoEmptyState(
          icon: TreinoIcon.emptyState,
          title: 'Sin alumnos',
          ctaLabel: 'Invitar alumno',
          onCtaTap: () => pressed++,
        ),
      ));
      await tester.pump();
      expect(find.text('Invitar alumno'), findsOneWidget);
      await tester.tap(find.text('Invitar alumno'));
      await tester.pump();
      expect(pressed, 1);
    });

    // -------------------------------------------------------------------------
    // Sin CTA: botón no se renderiza
    // -------------------------------------------------------------------------
    testWidgets(
        'sin ctaLabel → botón no se renderiza '
        '[SCENARIO-CK-ES-04]', (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoEmptyState(
          icon: TreinoIcon.emptyState,
          title: 'Sin alumnos',
        ),
      ));
      await tester.pump();
      expect(find.byType(TextButton), findsNothing);
    });

    // -------------------------------------------------------------------------
    // Loading: skeleton shimmer visible, contenido oculto
    // -------------------------------------------------------------------------
    testWidgets(
        'loading=true → skeleton visible, contenido oculto '
        '[SCENARIO-CK-ES-05]', (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoEmptyState(
          icon: TreinoIcon.emptyState,
          title: 'Sin alumnos',
          loading: true,
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('empty_state_skeleton')), findsOneWidget);
      expect(find.text('Sin alumnos'), findsNothing);
    });

    // -------------------------------------------------------------------------
    // Entrance motion: TreinoFadeSlideIn no crashea
    // -------------------------------------------------------------------------
    testWidgets('entrada animada → no crashea [SCENARIO-CK-ES-06]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoEmptyState(
          icon: TreinoIcon.emptyState,
          title: 'Sin alumnos',
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Sin alumnos'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Smoke dark + light
    // -------------------------------------------------------------------------
    testWidgets('smoke dark+light sin crash [SCENARIO-CK-ES-07]',
        (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await tester.pumpWidget(_wrap(
          const TreinoEmptyState(
            icon: TreinoIcon.emptyState,
            title: 'Sin alumnos',
            description: 'Descripción de prueba',
          ),
          theme: theme,
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Sin alumnos'), findsOneWidget);
      }
    });
  });
}
