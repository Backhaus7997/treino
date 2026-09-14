import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/athlete_file_providers.dart';
import 'package:treino/features/coach/domain/athlete_file.dart';
import 'package:treino/features/coach/presentation/athlete_files_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

const _athleteId = 'athlete-1';

AthleteFile _file({
  required String id,
  required String fileName,
  required AthleteFileKind kind,
  required int sizeBytes,
}) =>
    AthleteFile(
      id: id,
      trainerId: 'trainer-1',
      athleteId: _athleteId,
      fileName: fileName,
      kind: kind,
      contentType:
          kind == AthleteFileKind.pdf ? 'application/pdf' : 'image/jpeg',
      sizeBytes: sizeBytes,
      storagePath: 'athleteFiles/$id',
      downloadUrl: 'https://example.com/$id',
      uploadedAt: DateTime.utc(2026, 9, 1),
      sharedWithAthlete: true,
    );

Widget _wrap(List<AthleteFile> files) => ProviderScope(
      overrides: [
        sharedAthleteFilesProvider(_athleteId)
            .overrideWith((ref) => Stream.value(files)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(
          body: AthleteFilesScreen(athleteId: _athleteId),
        ),
      ),
    );

void main() {
  _guardaDeHost();

  testWidgets('renderiza los archivos compartidos con tamaño y fecha',
      (tester) async {
    await tester.pumpWidget(_wrap([
      _file(
        id: 'analysis',
        fileName: 'análisis.pdf',
        kind: AthleteFileKind.pdf,
        sizeBytes: 512 * 1024,
      ),
      _file(
        id: 'posture',
        fileName: 'postura.jpg',
        kind: AthleteFileKind.image,
        sizeBytes: 2 * 1024 * 1024,
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('análisis.pdf'), findsOneWidget);
    expect(find.text('postura.jpg'), findsOneWidget);
    expect(find.textContaining('512 KB'), findsOneWidget);
    expect(find.textContaining('2.0 MB'), findsOneWidget);
    expect(find.textContaining('1/9/2026'), findsNWidgets(2));
  });

  testWidgets('lista vacía muestra el estado propio', (tester) async {
    await tester.pumpWidget(_wrap(const []));
    await tester.pumpAndSettle();

    expect(
      find.text('Tu PF todavía no compartió archivos con vos.'),
      findsOneWidget,
    );
  });
}

// ── esDescargaDeStorage ───────────────────────────────────────────────────────
//
// `downloadUrl` lo escribe el PF y la regla de Firestore sólo valida que sea un
// string, así que un cliente modificado puede poner ahí cualquier destino. Esta
// guarda es lo único que separa «el alumno abre el PDF que le compartieron» de
// «el alumno abre lo que el PF quiera», y en iOS además sostiene la entrada de
// esta pantalla en la allowlist de `superficie_de_cobro_alumno_test.dart`
// (Guideline 3.1.3(f)).

void _guardaDeHost() {
  group('esDescargaDeStorage', () {
    test('acepta los tres hosts que Firebase Storage usa en la práctica', () {
      for (final url in [
        'https://firebasestorage.googleapis.com/v0/b/treino-dev.appspot.com/o/f.pdf?alt=media&token=abc',
        'https://treino-dev.firebasestorage.app/o/f.pdf?alt=media&token=abc',
        'https://treino-dev.appspot.com/o/f.pdf?alt=media&token=abc',
      ]) {
        expect(esDescargaDeStorage(Uri.parse(url)), isTrue, reason: url);
      }
    });

    test('rechaza cualquier otro destino, que es el vector real', () {
      for (final url in [
        // Una pasarela de pago: el caso que cruza la Guideline 3.1.3(f).
        'https://checkout.mercadopago.com.ar/pagar',
        // Un host que sólo TERMINA parecido al bueno.
        'https://firebasestorage.googleapis.com.attacker.test/f.pdf',
        // El host correcto pero sin TLS.
        'http://firebasestorage.googleapis.com/v0/b/x/o/f.pdf',
        // Otros esquemas.
        'javascript:alert(1)',
        'file:///etc/passwd',
      ]) {
        expect(esDescargaDeStorage(Uri.parse(url)), isFalse, reason: url);
      }
    });
  });
}
