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

  testWidgets('el documento muestra la fecha que RECIBE, no una global',
      (tester) async {
    // Antes las dos fechas salían de una constante COMPARTIDA, así que
    // reescribir la política dejaba la fecha de junio o le inventaba una
    // revisión a los Términos. Lo trajo el review del #941.
    //
    // Este test comparaba `kPrivacyLastUpdated` contra `kTermsLastUpdated` y
    // exigía que la segunda NO apareciera en pantalla. Eso funcionaba sólo
    // mientras las dos fechas fueran DISTINTAS — y el día que los dos
    // documentos se revisan juntos, que es un caso perfectamente normal y pasó
    // el 2026-09-17 con el gate de edad mínima, se ponía rojo sin que nada
    // estuviera mal. Peor todavía: confundía "mismo valor" con "constante
    // compartida", que es exactamente el bug que existe para atrapar.
    //
    // Lo que sí prueba la independencia es que la pantalla renderice la fecha
    // que le PASAN, usando un valor que no es ninguna de las dos globales: si
    // alguna vez volviera a hardcodear una, este centinela no aparecería.
    const centinela = '31 de diciembre de 1999';
    await tester.pumpWidget(wrap(
      const LegalDocumentScreen(
        title: 'Política de Privacidad',
        sections: kPrivacySections,
        lastUpdated: centinela,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Última actualización'),
      300,
    );

    expect(find.textContaining(centinela), findsOneWidget);
    expect(find.textContaining(kPrivacyLastUpdated), findsNothing);
    expect(find.textContaining(kTermsLastUpdated), findsNothing);
  });
}
