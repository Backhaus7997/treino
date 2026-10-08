import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/widgets/photo_viewer_screen.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_feedback_note.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Ampliar la foto del reporte (plan del PF §2).
///
/// Hasta este cambio el adjunto era un `ClipRRect` de 140 px sin un solo
/// gesto: el PF veía la miniatura y se acababa ahí. Una foto de una molestia
/// mirada en 140 px no sirve para lo único que el PF necesita, que es ver QUÉ
/// le pasa al alumno.
///
/// Los tres tests van por la SEMÁNTICA y no por `find.byType(GestureDetector)`
/// —como hace el test gemelo del chat— por dos motivos. Uno: un finder atado al
/// tipo de widget se rompe cuando la implementación cambia aunque la pantalla
/// siga andando igual, y al revés, pasa en verde con el bug puesto. Dos: acá la
/// etiqueta ES parte del feature. `TreinoTappable` es un `GestureDetector` con
/// escala y no aporta rol ni nombre, así que sin el `Semantics` de afuera el
/// lector de pantalla anuncia una imagen sin nombre y sin forma de saber que se
/// abre — que para un lector de pantalla es lo mismo que no tener el feature.
void main() {
  ExerciseFeedback feedback({String? photoUrl}) => ExerciseFeedback(
        id: 'fb-1',
        exerciseId: 'bench-press',
        exerciseName: 'Press de banca',
        kind: ExerciseFeedbackKind.discomfort,
        text: 'me tiró el hombro en la última',
        photoUrl: photoUrl,
        createdAt: DateTime.utc(2026, 9, 16, 18, 30),
      );

  Future<void> pump(WidgetTester tester, ExerciseFeedback fb) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(body: ExerciseFeedbackNote(feedback: fb)),
      ),
    );
    await tester.pump();
  }

  group('foto del reporte', () {
    // Control negativo del test de abajo: si este pasara con foto Y sin foto,
    // el finder no estaría probando nada.
    testWidgets('un reporte sin foto no expone ningún botón de ver foto',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, feedback());

      expect(find.bySemanticsLabel('Ver foto'), findsNothing);
      handle.dispose();
    });

    testWidgets('la foto se anuncia como botón y abre el visor',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        feedback(photoUrl: 'https://firebasestorage.googleapis.com/hombro.jpg'),
      );

      final boton = find.bySemanticsLabel('Ver foto');
      expect(boton, findsOneWidget);
      // El rol importa tanto como la etiqueta: sin `button: true` el lector
      // anuncia el nombre pero no que sea accionable. Y `hasTapAction` no es
      // redundante con `isButton` — el flag es lo que el lector ANUNCIA y la
      // acción es lo que puede EJECUTAR: un nodo puede tener el rol sin exponer
      // la acción, y ahí el usuario de VoiceOver oye "botón" y no puede
      // activarlo. `matchesSemantics` pide declarar las dos.
      expect(
        tester.getSemantics(boton),
        matchesSemantics(
          label: 'Ver foto',
          isButton: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(boton);
      // `pump` con duración en vez de `pumpAndSettle`: la animación de carga de
      // CachedNetworkImage nunca termina y el settle se iría a timeout.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(PhotoViewerScreen), findsOneWidget);
      handle.dispose();
    });

    testWidgets('el visor recibe la URL del reporte, no otra', (tester) async {
      const url =
          'https://firebasestorage.googleapis.com/rodilla.jpg?token=abc';
      final handle = tester.ensureSemantics();
      await pump(tester, feedback(photoUrl: url));

      await tester.tap(find.bySemanticsLabel('Ver foto'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final visor = tester.widget<PhotoViewerScreen>(
        find.byType(PhotoViewerScreen),
      );
      expect(visor.imageUrl, url);
      handle.dispose();
    });
  });
}
