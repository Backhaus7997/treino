import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';
import 'package:treino/features/auth/presentation/legal/legal_document_screen.dart';
import 'package:treino/features/profile/presentation/legal_index_screen.dart';

/// La pantalla se alimenta de [kLegalDocuments], que se GENERA junto con el
/// resto de `legal_content.dart` desde `docs/legal/*.md`. Por eso los tests se
/// escriben contra la lista, no contra títulos hardcodeados: cuando se
/// resuelvan los pendientes y el generador emita los nueve documentos, esto
/// tiene que seguir pasando sin tocarse.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: child),
      );

  testWidgets('lista un ítem por cada documento de kLegalDocuments',
      (tester) async {
    await tester.pumpWidget(wrap(const LegalIndexScreen()));
    await tester.pumpAndSettle();

    expect(kLegalDocuments, isNotEmpty);
    for (final doc in kLegalDocuments) {
      expect(
        find.text(doc.title),
        findsOneWidget,
        reason: 'falta la fila de "${doc.title}"',
      );
    }
  });

  testWidgets('tocar un documento abre LegalDocumentScreen con ese contenido',
      (tester) async {
    await tester.pumpWidget(wrap(const LegalIndexScreen()));
    await tester.pumpAndSettle();

    final first = kLegalDocuments.first;
    await tester.tap(find.text(first.title));
    await tester.pumpAndSettle();

    final screen = tester.widget<LegalDocumentScreen>(
      find.byType(LegalDocumentScreen),
    );
    expect(screen.title, first.title);
    expect(screen.sections, same(first.sections));
    expect(screen.lastUpdated, first.lastUpdated);
    // El encabezado de la primera sección confirma que se renderizó el
    // documento correcto, no sólo que se montó la pantalla.
    expect(find.text(first.sections.first.heading), findsOneWidget);
  });

  testWidgets('cada documento muestra su propia fecha de actualización',
      (tester) async {
    await tester.pumpWidget(wrap(const LegalIndexScreen()));
    await tester.pumpAndSettle();

    // Las fechas son POR DOCUMENTO (los Términos y la Política se revisan por
    // separado), así que se verifica que la de cada uno esté en su fila y no
    // una sola al pie.
    for (final doc in kLegalDocuments) {
      expect(
        find.textContaining(doc.lastUpdated),
        findsWidgets,
        reason: 'falta la fecha de "${doc.title}"',
      );
    }
  });

  testWidgets('muestra el contacto al pie', (tester) async {
    await tester.pumpWidget(wrap(const LegalIndexScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining(kLegalContactEmail), findsOneWidget);
  });
}
