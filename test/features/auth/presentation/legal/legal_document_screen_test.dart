import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';
import 'package:treino/features/auth/presentation/legal/legal_document_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.dark(),
        home: child,
      );

  testWidgets('renders the title, first section and a back affordance',
      (tester) async {
    await tester.pumpWidget(wrap(
      const LegalDocumentScreen(
        title: 'Términos y Condiciones',
        sections: kTermsSections,
        lastUpdated: kTermsLastUpdated,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Términos y Condiciones'), findsOneWidget);
    // First section heading is visible at the top of the scroll view.
    expect(find.text(kTermsSections.first.heading), findsOneWidget);
    expect(find.byTooltip('Volver'), findsOneWidget);
  });

  testWidgets('renders the privacy document with its sections', (tester) async {
    await tester.pumpWidget(wrap(
      const LegalDocumentScreen(
        title: 'Política de Privacidad',
        sections: kPrivacySections,
        lastUpdated: kPrivacyLastUpdated,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Política de Privacidad'), findsOneWidget);
    expect(find.text(kPrivacySections.first.heading), findsOneWidget);
  });

  testWidgets('cada documento muestra SU propia fecha de revisión',
      (tester) async {
    // Antes las dos salían de una constante compartida, así que reescribir
    // la política dejaba la fecha de junio o le inventaba una revisión a los
    // Términos. Lo trajo el review del #941.
    await tester.pumpWidget(wrap(
      const LegalDocumentScreen(
        title: 'Política de Privacidad',
        sections: kPrivacySections,
        lastUpdated: kPrivacyLastUpdated,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Última actualización'),
      300,
    );

    expect(find.textContaining(kPrivacyLastUpdated), findsOneWidget);
    expect(find.textContaining(kTermsLastUpdated), findsNothing);
  });
}
