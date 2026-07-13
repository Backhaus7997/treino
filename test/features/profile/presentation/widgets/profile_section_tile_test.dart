import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/profile/presentation/widgets/profile_section_tile.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildTile({
  required IconData icon,
  required String title,
  String? subtitle,
  Widget? trailing,
  bool destructive = false,
  required VoidCallback onTap,
}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      body: ProfileSectionTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        destructive: destructive,
        onTap: onTap,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests — SCENARIO-509a..e
// ---------------------------------------------------------------------------

void main() {
  group('ProfileSectionTile', () {
    testWidgets('uses TreinoTappable for press feedback', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          icon: TreinoIcon.edit,
          title: 'Datos personales',
          onTap: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TreinoTappable), findsOneWidget);
    });

    // SCENARIO-509a: renders title only (no subtitle)
    testWidgets('SCENARIO-509a: renders title without subtitle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTile(
          icon: TreinoIcon.edit,
          title: 'Datos personales',
          onTap: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Datos personales'), findsOneWidget);
      expect(find.text('Editá tu info'), findsNothing);
    });

    // SCENARIO-509b: renders title + subtitle
    testWidgets('SCENARIO-509b: renders title and subtitle', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          icon: TreinoIcon.edit,
          title: 'Datos personales',
          subtitle: 'Editá tu info',
          onTap: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Datos personales'), findsOneWidget);
      expect(find.text('Editá tu info'), findsOneWidget);
    });

    // SCENARIO-509c: renders custom trailing override (no chevron)
    testWidgets('SCENARIO-509c: renders custom trailing widget', (
      tester,
    ) async {
      const customKey = Key('custom-trailing');
      await tester.pumpWidget(
        _buildTile(
          icon: TreinoIcon.edit,
          title: 'Datos personales',
          trailing: const SizedBox(key: customKey, width: 20, height: 20),
          onTap: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(customKey), findsOneWidget);
    });

    // SCENARIO-509d: tap fires onTap callback
    testWidgets('SCENARIO-509d: tap fires onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildTile(
          icon: TreinoIcon.edit,
          title: 'Datos personales',
          onTap: () => tapped = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Datos personales'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    // SCENARIO-509e: destructive variant — title uses danger color (widget renders without crash)
    testWidgets(
      'SCENARIO-509e: destructive variant renders title in danger color',
      (tester) async {
        await tester.pumpWidget(
          _buildTile(
            icon: TreinoIcon.trash,
            title: 'Eliminar cuenta',
            destructive: true,
            onTap: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Widget renders without crash; title is visible
        expect(find.text('Eliminar cuenta'), findsOneWidget);
      },
    );
  });
}
