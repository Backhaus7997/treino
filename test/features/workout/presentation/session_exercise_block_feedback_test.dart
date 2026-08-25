import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_feedback_note.dart';
import 'package:treino/features/workout/presentation/widgets/session_exercise_block.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Lo que ve el PF (#628). `SessionExerciseBlock` es el widget COMPARTIDO por
/// las tres superficies que muestran una sesión — el detalle del alumno, el
/// athlete-detail mobile del PF y el Coach Hub web — así que testearlo acá
/// cubre a las tres. Si el render viviera duplicado por pantalla, este archivo
/// tendría que existir por triplicado y alguna se quedaría atrás.
void main() {
  SetLog setLog(int n) => SetLog(
        id: 'set-$n',
        exerciseId: 'bench-press',
        exerciseName: 'Press de banca',
        setNumber: n,
        reps: 10,
        weightKg: 80,
        completedAt: DateTime.utc(2026, 8, 24, 18, n),
      );

  ExerciseFeedback feedback({
    required String id,
    int? setNumber,
    ExerciseFeedbackKind kind = ExerciseFeedbackKind.comment,
    String? text = 'algo',
  }) =>
      ExerciseFeedback(
        id: id,
        exerciseId: 'bench-press',
        exerciseName: 'Press de banca',
        setNumber: setNumber,
        kind: kind,
        text: text,
        createdAt: DateTime.utc(2026, 8, 24, 18, 30),
      );

  Future<void> pump(
    WidgetTester tester, {
    required List<SetLog> sets,
    required List<ExerciseFeedback> reports,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'AR'),
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SessionExerciseBlock(
              exerciseName: 'Press de banca',
              sets: sets,
              feedback: reports,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('sin reportes se ve exactamente igual que antes', (tester) async {
    // El parámetro es opcional con default vacío para que ningún call site
    // existente cambie de aspecto.
    await pump(tester, sets: [setLog(1), setLog(2)], reports: const []);
    expect(find.byType(ExerciseFeedbackNote), findsNothing);
    expect(find.text('10 reps'), findsNWidgets(2));
  });

  testWidgets('el reporte se renderiza y muestra su serie', (tester) async {
    await pump(
      tester,
      sets: [setLog(1), setLog(2), setLog(3)],
      reports: [feedback(id: 'f1', setNumber: 3, text: 'Me tira el hombro')],
    );
    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));

    expect(find.byType(ExerciseFeedbackNote), findsOneWidget);
    expect(find.text('Me tira el hombro'), findsOneWidget);
    expect(find.text(l10n.exerciseFeedbackNoteSetTag(3)), findsOneWidget);
  });

  testWidgets('una molestia se marca distinto de un comentario',
      (tester) async {
    // Es el punto entero del chip de tipo: si las dos se vieran igual, el PF
    // tendría que leer cada reporte para encontrar el que importa.
    await pump(
      tester,
      sets: [setLog(1)],
      reports: [
        feedback(id: 'f1', setNumber: 1, text: 'buena sensación'),
        feedback(
          id: 'f2',
          setNumber: 1,
          kind: ExerciseFeedbackKind.discomfort,
          text: 'me duele',
        ),
      ],
    );
    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));

    expect(find.text(l10n.exerciseFeedbackNoteTagComment), findsOneWidget);
    expect(find.text(l10n.exerciseFeedbackNoteTagDiscomfort), findsOneWidget);
  });

  testWidgets('el reporte SIN serie no muestra tag de serie', (tester) async {
    await pump(
      tester,
      sets: [setLog(1)],
      reports: [feedback(id: 'f1', text: 'La máquina está rota')],
    );

    expect(find.byType(ExerciseFeedbackNote), findsOneWidget);
    expect(find.text('La máquina está rota'), findsOneWidget);
    expect(find.textContaining('SERIE'), findsNothing);
  });

  testWidgets('un reporte de una serie BORRADA no se pierde', (tester) async {
    // El alumno reportó en la serie 3 y después la borró. Lo que dijo que le
    // pasó sigue valiendo: cae al pie del ejercicio en vez de desaparecer.
    await pump(
      tester,
      sets: [setLog(1), setLog(2)],
      reports: [
        feedback(
          id: 'f1',
          setNumber: 3,
          kind: ExerciseFeedbackKind.discomfort,
          text: 'me tiró en la última',
        ),
      ],
    );

    expect(find.byType(ExerciseFeedbackNote), findsOneWidget);
    expect(find.text('me tiró en la última'), findsOneWidget);
  });

  testWidgets('cada reporte cae bajo SU serie, no bajo todas', (tester) async {
    await pump(
      tester,
      sets: [setLog(1), setLog(2)],
      reports: [
        feedback(id: 'f1', setNumber: 1, text: 'reporte de la uno'),
        feedback(id: 'f2', setNumber: 2, text: 'reporte de la dos'),
      ],
    );

    expect(find.byType(ExerciseFeedbackNote), findsNWidgets(2));
    // Si el filtro por setNumber estuviera roto, cada fila mostraría los dos
    // y estos finders devolverían 2 en vez de 1.
    expect(find.text('reporte de la uno'), findsOneWidget);
    expect(find.text('reporte de la dos'), findsOneWidget);
  });

  testWidgets('un ejercicio SIN ninguna serie igual muestra su reporte',
      (tester) async {
    // El bloque tiene que aguantar `sets: const []`: es el render del
    // ejercicio que existe SÓLO porque el alumno reportó sobre él (#628).
    await pump(
      tester,
      sets: const [],
      reports: [feedback(id: 'f1', text: 'No pude ni empezar, me tira')],
    );

    expect(find.text('Press de banca'), findsOneWidget);
    expect(find.byType(ExerciseFeedbackNote), findsOneWidget);
    expect(find.text('No pude ni empezar, me tira'), findsOneWidget);
    // Sin filas de serie: no hay ninguna que registrar.
    expect(find.textContaining('reps'), findsNothing);
  });

  testWidgets('sin series, el reporte anclado a una serie tampoco se pierde',
      (tester) async {
    // El alumno reportó sobre la serie 2 (que estaba PENDIENTE) y nunca la
    // registró. No hay fila bajo la cual colgarlo → cae al pie del ejercicio
    // en vez de desaparecer.
    await pump(
      tester,
      sets: const [],
      reports: [feedback(id: 'f1', setNumber: 2, text: 'me tiró en la dos')],
    );

    expect(find.byType(ExerciseFeedbackNote), findsOneWidget);
    expect(find.text('me tiró en la dos'), findsOneWidget);
  });

  // ── buildSessionExerciseGroups ─────────────────────────────────────────────

  group('buildSessionExerciseGroups (#628)', () {
    ExerciseFeedback report(String exerciseId, String name, {String? id}) =>
        ExerciseFeedback(
          id: id ?? 'f-$exerciseId',
          exerciseId: exerciseId,
          exerciseName: name,
          kind: ExerciseFeedbackKind.discomfort,
          text: 'me molesta',
          createdAt: DateTime.utc(2026, 8, 24, 18, 30),
        );

    test('sin reportes: un grupo por ejercicio, con sus series', () {
      final groups = buildSessionExerciseGroups(
        sets: [setLog(1), setLog(2)],
        feedback: const [],
      );

      expect(groups, hasLength(1));
      expect(groups.single.exerciseId, 'bench-press');
      expect(groups.single.sets, hasLength(2));
      expect(groups.single.feedback, isEmpty);
    });

    test('un ejercicio reportado SIN series entra igual, al final', () {
      // El miembro de superset que no es la celda activa: cero logs de ese
      // `exerciseId`, así que derivar los bloques sólo de los SetLog lo
      // perdía y el PF nunca veía el reporte.
      final groups = buildSessionExerciseGroups(
        sets: [setLog(1)],
        feedback: [report('remo-polea', 'Remo en polea')],
      );

      expect(groups.map((g) => g.exerciseId), ['bench-press', 'remo-polea']);
      // El nombre sale del reporte denormalizado, sin tocar el catálogo.
      expect(groups.last.exerciseName, 'Remo en polea');
      expect(groups.last.sets, isEmpty);
      expect(groups.last.feedback, hasLength(1));
    });

    test('sesión con reportes y CERO series NO queda vacía', () {
      // El caso más ruidoso del bug: las tres superficies cortaban por
      // `logs.isEmpty` y mostraban el placeholder de "sin series", tragándose
      // todo lo que el alumno había dicho.
      final groups = buildSessionExerciseGroups(
        sets: const [],
        feedback: [report('remo-polea', 'Remo en polea')],
      );

      expect(groups, hasLength(1));
      expect(groups.single.exerciseName, 'Remo en polea');
      expect(groups.single.sets, isEmpty);
    });

    test('varios reportes del mismo ejercicio huérfano dan UN solo bloque', () {
      final groups = buildSessionExerciseGroups(
        sets: const [],
        feedback: [
          report('remo-polea', 'Remo en polea', id: 'f1'),
          report('remo-polea', 'Remo en polea', id: 'f2'),
        ],
      );

      expect(groups, hasLength(1));
      expect(groups.single.feedback, hasLength(2));
    });

    test('sin series y sin reportes no hay nada que renderizar', () {
      // Es lo que preserva el placeholder de "sin series" para la sesión
      // genuinamente vacía.
      expect(
        buildSessionExerciseGroups(sets: const [], feedback: const []),
        isEmpty,
      );
    });
  });
}
