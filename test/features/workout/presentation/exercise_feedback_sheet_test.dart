import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/workout/application/exercise_feedback_submitter.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_feedback_sheet.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockSubmitter extends Mock implements ExerciseFeedbackSubmitter {}

void main() {
  late _MockSubmitter submitter;

  const uid = 'athlete-ui';
  const sessionId = 'session-ui';

  ExerciseFeedback anyFeedback() => ExerciseFeedback(
        id: 'fb-1',
        exerciseId: 'bench-press',
        exerciseName: 'Press de banca',
        setNumber: 3,
        kind: ExerciseFeedbackKind.comment,
        text: 'x',
        createdAt: DateTime.utc(2026, 8, 24),
      );

  setUpAll(() {
    // mocktail necesita un valor concreto para `any(named: 'kind')`.
    registerFallbackValue(ExerciseFeedbackKind.comment);
  });

  setUp(() {
    submitter = _MockSubmitter();
    when(() => submitter.submit(
          uid: any(named: 'uid'),
          sessionId: any(named: 'sessionId'),
          exerciseId: any(named: 'exerciseId'),
          exerciseName: any(named: 'exerciseName'),
          kind: any(named: 'kind'),
          setNumber: any(named: 'setNumber'),
          text: any(named: 'text'),
          localPhotoPath: any(named: 'localPhotoPath'),
          now: any(named: 'now'),
        )).thenAnswer((_) async => anyFeedback());
  });

  Future<void> pump(WidgetTester tester, {int? setNumber = 3}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseFeedbackSubmitterProvider.overrideWithValue(submitter),
        ],
        child: MaterialApp(
          // Fijo: sin esto el host de tests resuelve en_US y los `find.text`
          // de abajo (es-AR) no encontrarian nada.
          locale: const Locale('es', 'AR'),
          localizationsDelegates: const [
            AppL10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppL10n.supportedLocales,
          home: Scaffold(
            body: ExerciseFeedbackSheet(
              uid: uid,
              sessionId: sessionId,
              exerciseId: 'bench-press',
              exerciseName: 'Press de banca',
              setNumber: setNumber,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ElevatedButton submitButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(
        find.byKey(const Key('exercise_feedback_submit')),
      );

  testWidgets('ENVIAR arranca deshabilitado — nada de reportes vacíos',
      (tester) async {
    await pump(tester);
    expect(submitButton(tester).onPressed, isNull);
  });

  testWidgets('ENVIAR se habilita en cuanto hay texto, y se apaga si se borra',
      (tester) async {
    await pump(tester);

    await tester.enterText(
      find.byKey(const Key('exercise_feedback_text')),
      'Me tira el hombro',
    );
    await tester.pump();
    expect(submitButton(tester).onPressed, isNotNull);

    // Sólo espacios NO cuenta como contenido.
    await tester.enterText(
      find.byKey(const Key('exercise_feedback_text')),
      '   ',
    );
    await tester.pump();
    expect(submitButton(tester).onPressed, isNull);
  });

  testWidgets('el aviso de notificación aparece SÓLO con molestia elegida',
      (tester) async {
    await pump(tester);
    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));

    expect(find.text(l10n.exerciseFeedbackDiscomfortNotice), findsNothing);

    await tester.tap(find.text(l10n.exerciseFeedbackKindDiscomfort));
    await tester.pump();

    // El usuario tiene que saber que ESTE chip le avisa al PF y el otro no.
    expect(find.text(l10n.exerciseFeedbackDiscomfortNotice), findsOneWidget);
  });

  testWidgets('enviar manda el kind elegido y la serie anclada',
      (tester) async {
    await pump(tester);
    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));

    await tester.tap(find.text(l10n.exerciseFeedbackKindDiscomfort));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('exercise_feedback_text')),
      'Me tira el hombro derecho',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('exercise_feedback_submit')));
    await tester.pumpAndSettle();

    verify(() => submitter.submit(
          uid: uid,
          sessionId: sessionId,
          exerciseId: 'bench-press',
          exerciseName: 'Press de banca',
          kind: ExerciseFeedbackKind.discomfort,
          setNumber: 3,
          text: 'Me tira el hombro derecho',
          localPhotoPath: null,
        )).called(1);
  });

  testWidgets('sin serie en curso el reporte va a nivel ejercicio',
      (tester) async {
    await pump(tester, setNumber: null);
    await tester.enterText(
      find.byKey(const Key('exercise_feedback_text')),
      'La máquina está rota',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('exercise_feedback_submit')));
    await tester.pumpAndSettle();

    verify(() => submitter.submit(
          uid: uid,
          sessionId: sessionId,
          exerciseId: 'bench-press',
          exerciseName: 'Press de banca',
          kind: ExerciseFeedbackKind.comment,
          setNumber: null,
          text: 'La máquina está rota',
          localPhotoPath: null,
        )).called(1);
  });

  testWidgets('un fallo al guardar avisa y NO cierra el sheet', (tester) async {
    // Cerrar el sheet ante un error perdería lo que el usuario escribió, que
    // es exactamente lo que no puede pasar con un reporte de dolor.
    when(() => submitter.submit(
          uid: any(named: 'uid'),
          sessionId: any(named: 'sessionId'),
          exerciseId: any(named: 'exerciseId'),
          exerciseName: any(named: 'exerciseName'),
          kind: any(named: 'kind'),
          setNumber: any(named: 'setNumber'),
          text: any(named: 'text'),
          localPhotoPath: any(named: 'localPhotoPath'),
          now: any(named: 'now'),
        )).thenThrow(StateError('sin red'));

    await pump(tester);
    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));

    await tester.enterText(
      find.byKey(const Key('exercise_feedback_text')),
      'Me duele',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('exercise_feedback_submit')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.exerciseFeedbackError), findsOneWidget);
    expect(find.byType(ExerciseFeedbackSheet), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('exercise_feedback_text')))
          .controller
          ?.text,
      equals('Me duele'),
    );
  });
}
