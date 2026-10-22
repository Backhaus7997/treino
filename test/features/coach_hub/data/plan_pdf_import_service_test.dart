// PlanPdfImportService: el contrato de `parsePlanPdf` (docs/plan-import-pdf.md)
// con un doble del callable. Un caso por error, el éxito, y el control de que
// el candidato del LLM nunca se autoasigna. El veto y la política de
// sugerencia/alternativa están en plan_draft_matcher_test.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach_hub/data/plan_draft_matcher.dart';
import 'package:treino/features/coach_hub/data/plan_pdf_import_service.dart';
import 'package:treino/features/workout/data/exercise_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';

class _MockExerciseRepo extends Mock implements ExerciseRepository {}

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockCallable extends Mock implements HttpsCallable {}

class _MockResult extends Mock implements HttpsCallableResult<Object?> {}

const _catalog = [
  Exercise(
      id: 'press',
      name: 'Press de banca',
      muscleGroup: 'chest',
      category: 'compound'),
  Exercise(
      id: 'remo',
      name: 'Remo con barra',
      muscleGroup: 'back',
      category: 'compound'),
  Exercise(
      id: 'bulgara',
      name: 'Estocada búlgara',
      muscleGroup: 'legs',
      category: 'compound'),
];

Map<String, Object?> _exercise(
  String rawName, {
  String? candidate,
  double? confidence,
}) =>
    {
      'component': 1,
      'rawName': rawName,
      'note': null,
      'weeks': [
        [
          {'type': 'normal', 'weightKg': 60, 'repsMin': 8, 'repsMax': 10},
        ],
      ],
      'candidateExerciseId': candidate,
      'candidateConfidence': confidence,
      'sourceText': '$rawName 4x8-10 @60kg',
    };

Map<String, Object?> _plan(List<Map<String, Object?>> exercises) => {
      'numWeeks': 1,
      'days': [
        {
          'dayNumber': 1,
          'title': 'Torso A',
          'rows': [
            for (var i = 0; i < exercises.length; i++)
              {
                'number': i + 1,
                'restSeconds': 90,
                'exercises': [exercises[i]],
              },
          ],
        },
      ],
      'warnings': [
        {'code': 'ambiguous_reps', 'message': 'Reps dudosas', 'page': 2},
      ],
    };

const _quota = {
  'usedThisWeek': 3,
  'limitWeekly': 7,
  'usedToday': 1,
  'limitDaily': 7,
};

/// Clave del renglón [row] (base 1) del día 1, primer componente.
({int dayNumber, int row, int component}) _key(int row) =>
    (dayNumber: 1, row: row, component: 0);

void main() {
  setUpAll(() => registerFallbackValue(<String, Object?>{}));

  late List<Map<String, Object?>> requests;
  late _MockExerciseRepo repo;

  setUp(() {
    requests = [];
    repo = _MockExerciseRepo();
    when(() => repo.listAll()).thenAnswer((_) async => _catalog);
  });

  PlanPdfImportService service(FutureOr<Object?> Function() respond) =>
      PlanPdfImportService(
        call: (request) async {
          requests.add(request);
          return respond();
        },
        matcher: PlanDraftMatcher(exerciseRepository: repo),
      );

  PlanPdfImportService failing(String code, [Object? details]) => service(
        () => throw FirebaseFunctionsException(
            code: code, message: 'x', details: details),
      );

  final pdf = Uint8List.fromList(utf8.encode('%PDF-1.7 plan'));

  Future<PdfImportResult> run(PlanPdfImportService s,
          {String fileName = 'Plan Juan.pdf'}) =>
      s.importPdf(bytes: pdf, fileName: fileName, athleteId: 'alumno-1');

  test('el callable real va a parsePlanPdf con timeout de 300 s', () async {
    final functions = _MockFunctions();
    final callable = _MockCallable();
    final result = _MockResult();
    when(() => result.data).thenReturn({'ok': true});
    when(() => callable.call<Object?>(any())).thenAnswer((_) async => result);
    when(() => functions.httpsCallable('parsePlanPdf',
        options: any(named: 'options'))).thenReturn(callable);

    final data = await parsePlanPdfCallable(functions)({'pdfBase64': 'x'});

    final options = verify(() => functions.httpsCallable('parsePlanPdf',
        options: captureAny(named: 'options'))).captured.single;
    expect((options as HttpsCallableOptions).timeout,
        const Duration(seconds: 300));
    expect(data, {'ok': true});
  });

  group('éxito', () {
    test('valida, matchea y expone cupo y modelo', () async {
      final s = service(() => {
            'plan': _plan([
              _exercise('Press de banca'),
              _exercise('Remo pendlay con barra'),
            ]),
            'quota': _quota,
            'model': 'claude-opus-5-5',
          });

      final result = await run(s);

      expect(requests.single['pdfBase64'], base64Encode(pdf));
      expect(requests.single['fileName'], 'Plan Juan.pdf');
      expect(requests.single['athleteId'], 'alumno-1');
      final ok = result as PdfImportSuccess;
      expect(ok.model, 'claude-opus-5-5');
      expect(ok.quota!.usedThisWeek, 3);
      expect(ok.quota!.limitWeekly, 7);
      expect(ok.quota!.usedToday, 1);
      expect(ok.quota!.limitDaily, 7);
      expect(ok.draft.name, 'Plan Juan');
      expect(ok.draft.assignments[_key(1)]!.id, 'press');
      expect(ok.draft.suggestions[_key(2)]!.id, 'remo');
      expect(ok.draft.warnings.single.page, 2);
      // El peso y el rango llegan al plan.
      final set = ok.draft.plan.days.single.rows.first.exercises.single.weeks
          .single.single;
      expect(set.weightKg, 60);
      expect((set.repsMin, set.repsMax), (8, 10));
    });

    test('candidato del LLM que pasa el veto entra como SUGERENCIA', () async {
      final s = service(() => {
            'plan': _plan([
              _exercise('Split squat búlgaro', candidate: 'bulgara'),
            ]),
            'quota': _quota,
            'model': 'm',
          });

      final ok = await run(s) as PdfImportSuccess;

      expect(ok.draft.suggestions[_key(1)]!.id, 'bulgara');
      expect(ok.draft.isResolved(_key(1)), isFalse);
    });

    test('CONTROL NEGATIVO: confianza 1.0 tampoco autoasigna', () async {
      final s = service(() => {
            'plan': _plan([
              _exercise('Split squat búlgaro',
                  candidate: 'bulgara', confidence: 1.0),
            ]),
            'quota': _quota,
            'model': 'm',
          });

      final ok = await run(s) as PdfImportSuccess;

      expect(ok.draft.assignments, isEmpty);
      expect(ok.draft.unresolved, [_key(1)]);
    });

    test('cupo con otra forma: el plan llega igual, cupo «no sé»', () async {
      final s = service(() => {
            'plan': _plan([_exercise('Press de banca')]),
            'quota': {'usedThisWeek': 'tres'},
            'model': 'm',
          });

      final ok = await run(s) as PdfImportSuccess;

      expect(ok.quota, isNull);
      expect(ok.draft.assignments, hasLength(1));
    });
  });

  group('validación del cliente', () {
    test('plan que el cliente rechaza: InvalidPlan con cupo', () async {
      final s = service(() => {
            'plan': {'numWeeks': 0, 'days': []},
            'quota': _quota,
            'model': 'm',
          });

      final result = await run(s) as PdfImportInvalidPlan;

      expect(result.errors, isNotEmpty);
      expect(result.quota!.usedThisWeek, 3);
    });

    test('respuesta sin plan: internal', () async {
      final s = service(() => {'quota': _quota});

      expect(await run(s), isA<PdfImportInternal>());
    });

    test('archivo > 5 MB no llama al servidor', () async {
      final s = service(() => fail('no debía llamar'));

      final result = await s.importPdf(
        bytes: Uint8List(kPdfImportMaxBytes + 1),
        fileName: 'grande.pdf',
      );

      expect((result as PdfImportInvalidFile).reason, PdfRejectReason.tooBig);
      expect(requests, isEmpty);
    });

    test('extensión que no es .pdf no llama al servidor', () async {
      final s = service(() => fail('no debía llamar'));

      final result = await run(s, fileName: 'plan.xlsx');

      expect((result as PdfImportInvalidFile).reason, PdfRejectReason.notPdf);
      expect(requests, isEmpty);
    });
  });

  group('errores del callable', () {
    for (final (code, type) in [
      ('unauthenticated', PdfImportUnauthenticated),
      ('permission-denied', PdfImportNotTrainer),
      ('failed-precondition', PdfImportDisabled), // kill switch, sin details
      ('deadline-exceeded', PdfImportTimeout),
    ]) {
      test(code, () async {
        expect((await run(failing(code))).runtimeType, type);
      });
    }

    test('failed-precondition structured_outputs_disabled', () async {
      final result = await run(failing(
          'failed-precondition', {'reason': 'structured_outputs_disabled'}));

      expect(result, isA<PdfImportStructuredOutputsDisabled>());
      expect(result, isNot(isA<PdfImportDisabled>()));
    });

    for (final (reason, expected) in [
      ('not_pdf', PdfRejectReason.notPdf),
      ('too_big', PdfRejectReason.tooBig),
      ('too_many_pages', PdfRejectReason.tooManyPages),
      ('encrypted', PdfRejectReason.encrypted),
    ]) {
      test('invalid-argument $reason', () async {
        final result =
            await run(failing('invalid-argument', {'reason': reason}));

        expect((result as PdfImportInvalidFile).reason, expected);
      });
    }

    test('resource-exhausted semanal con resetsAt', () async {
      final result = await run(failing('resource-exhausted', {
        'scope': 'week',
        'resetsAt': '2026-10-26T03:00:00.000Z',
      })) as PdfImportQuotaExhausted;

      expect(result.scope, PdfQuotaScope.week);
      expect(result.resetsAt, DateTime.utc(2026, 10, 26, 3));
    });

    test('resource-exhausted diario con resetsAt', () async {
      final result = await run(failing('resource-exhausted', {
        'scope': 'day',
        'resetsAt': '2026-10-23T03:00:00.000Z',
      })) as PdfImportQuotaExhausted;

      expect(result.scope, PdfQuotaScope.day);
      expect(result.resetsAt, DateTime.utc(2026, 10, 23, 3));
    });

    test('TimeoutException del cliente también es timeout', () async {
      expect(await run(service(() => throw TimeoutException('x'))),
          isA<PdfImportTimeout>());
    });

    test('internal', () async {
      final result = await run(failing('internal')) as PdfImportInternal;

      expect(result.code, 'internal');
    });

    test('código fuera del contrato cae en internal con el código', () async {
      final result = await run(failing('unavailable')) as PdfImportInternal;

      expect(result.code, 'unavailable');
    });
  });

  group('nombre inicial a partir del archivo', () {
    final casos = <String, String>{
      'Plan Juan.pdf': 'Plan Juan',
      'plan_fuerza-hipertrofia.PDF': 'plan fuerza hipertrofia',
      'Plan Ana FINAL (2).pdf': 'Plan Ana',
      'rutina_final_FINAL.pdf': 'rutina',
      'Bloque 1 (3) final.pdf': 'Bloque 1',
      '  __ - .pdf': 'Plan importado',
      'FINAL.pdf': 'Plan importado',
      // «final» en el medio es parte del nombre.
      'final de temporada.pdf': 'final de temporada',
    };
    for (final MapEntry(key: archivo, value: nombre) in casos.entries) {
      test('"$archivo" → "$nombre"', () {
        expect(planNameFromFileName(archivo), nombre);
      });
    }

    test('se acota al tope, cortando en una palabra entera', () {
      final largo = List.filled(20, 'semana').join('_');
      final nombre = planNameFromFileName('$largo.pdf');
      expect(nombre.length, lessThanOrEqualTo(kPdfPlanNameMaxLength));
      expect(nombre, startsWith('semana semana'));
      expect(nombre.endsWith('semana'), isTrue);
    });

    test('no parte un emoji que cruza el tope', () {
      // 59 letras y un emoji fuera del BMP (dos unidades UTF-16) en la
      // posición 60: cortar por code units deja medio surrogate.
      final nombre = planNameFromFileName('${'a' * 59}😀b.pdf');
      expect(nombre, '${'a' * 59}😀');
      expect(nombre.runes.any((r) => r >= 0xD800 && r <= 0xDFFF), isFalse);
    });

    test('cuenta graphemes, no code units: un emoji ocupa uno', () {
      final nombre = planNameFromFileName('${'👨‍👩‍👧' * 70}.pdf');
      expect(nombre, '👨‍👩‍👧' * kPdfPlanNameMaxLength);
    });
  });
}
