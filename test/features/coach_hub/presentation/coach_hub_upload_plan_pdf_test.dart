// «Importar plan» del Coach Hub con PDF (docs/plan-import-pdf.md): el mismo
// selector acepta la plantilla o un PDF sólo si el kill switch lo habilita
// para el PF; el PDF pasa por `parsePlanPdf` con el aviso, el cupo, el tope
// de 5 MB y la espera de mobile, y llega a la MISMA vista previa del Hub, sin
// alumno. Con el gate apagado la pantalla es la del Excel solo.

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/application/pdf_import_quota_provider.dart';
import 'package:treino/features/coach_hub/application/plan_import_providers.dart';
import 'package:treino/features/coach_hub/application/plan_pdf_import_providers.dart';
import 'package:treino/features/coach_hub/data/periodized_import_draft.dart';
import 'package:treino/features/coach_hub/data/plan_pdf_import_service.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_upload_plan_screen.dart';
import 'package:treino/features/workout/domain/exercise.dart';

import '../data/periodized_test_helpers.dart';
import 'periodized_draft_fixtures.dart';

const _aviso = 'Usamos IA para leer tu PDF y armar el plan. No guardamos el '
    'archivo. Subí solo los datos de tu alumno que sean necesarios.';
const _hintPdf =
    'Plantilla .xlsx (hasta 10 MB) o el PDF de tu plan (hasta 5 MB).';
const _hintExcel = 'Archivo .xlsx, hasta 10 MB.';

/// Servicio de test: cada llamada queda pendiente hasta [complete].
class _FakeService implements PlanPdfImportService {
  final calls = <String>[];
  Completer<PdfImportResult>? _pending;

  void complete(PdfImportResult r) => _pending!.complete(r);

  @override
  Future<PdfImportResult> importPdf({
    required Uint8List bytes,
    required String fileName,
    String? athleteId,
  }) {
    calls.add('$fileName:$athleteId');
    _pending = Completer<PdfImportResult>();
    return _pending!.future;
  }
}

/// Picker que anota con qué extensiones y `withData` lo abrieron.
class _RecordingPicker extends FakeFilePicker {
  _RecordingPicker(super.file);
  List<String>? allowed;
  bool? withData;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) {
    allowed = allowedExtensions;
    this.withData = withData;
    return super.pickFiles(allowedExtensions: allowedExtensions);
  }
}

Exercise _ex(String id, String name) =>
    Exercise(id: id, name: name, muscleGroup: 'legs', category: 'compound');

/// La pantalla de subir con un PDF de [size] bytes ya «elegido».
Future<void> _pumpPdf(
  WidgetTester tester,
  _FakeService service, {
  PdfImportGate gate = PdfImportGate.enabled,
  PdfImportRemaining? remaining,
  String fileName = 'plan_fuerza-FINAL.pdf',
  int size = 1024,
}) async {
  await pumpUploadFlow(
    tester,
    bytes: Uint8List(8),
    fileSize: size,
    fileName: fileName,
    catalog: const [],
    routineRepo: MockRoutineRepo(),
    pdfGate: gate,
    extra: [
      planPdfImportServiceProvider.overrideWithValue(service),
      pdfImportRemainingProvider.overrideWithValue(remaining),
    ],
  );
}

Future<_RecordingPicker> _recordPicker(String name, int size) async {
  final picker = _RecordingPicker(
    PlatformFile(name: name, size: size, bytes: Uint8List(8)),
  );
  FilePicker.platform = picker;
  return picker;
}

/// Elige y aprieta PROCESAR PLAN, sin esperar a que termine.
Future<void> _pickAndStart(WidgetTester tester) async {
  await tester.tap(find.text('Elegir archivo'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('PROCESAR PLAN'));
  await tester.pump();
}

void main() {
  useTallSurface();

  group('gate apagado: la pantalla del Excel solo', () {
    for (final gate in [PdfImportGate.disabled, PdfImportGate.loading]) {
      testWidgets('${gate.name}: sin aviso, sin cupo, sin PDF en el picker',
          (tester) async {
        final service = _FakeService();
        await _pumpPdf(tester, service,
            gate: gate,
            remaining: (week: 5, day: 2, limitWeekly: 7, limitDaily: 7));
        final picker = await _recordPicker('plan.xlsx', 10);

        expect(find.text(_hintExcel), findsOneWidget);
        expect(find.text(_hintPdf), findsNothing);
        expect(find.text(_aviso), findsNothing);
        expect(find.textContaining('Te quedan'), findsNothing);
        expect(find.textContaining('PDF'), findsNothing);
        expect(
            find.textContaining('Es la única que aceptamos.'), findsOneWidget);

        await tester.tap(find.text('Elegir archivo'));
        await tester.pumpAndSettle();
        expect(picker.allowed, ['xlsx']);
        expect(picker.withData, isTrue);
      });
    }

    testWidgets('un .pdf igual va por el Excel: el servicio no se llama',
        (tester) async {
      // El navegador deja elegir «todos los archivos»: con el gate apagado
      // nada cambia respecto de hoy (el parser del Excel lo rechaza).
      final service = _FakeService();
      await _pumpPdf(tester, service, gate: PdfImportGate.disabled);
      await _pickAndStart(tester);
      await tester.pumpAndSettle();

      expect(service.calls, isEmpty);
      expect(find.byKey(const Key('pdf_import_progress')), findsNothing);
      expect(find.byType(CoachHubPlanPreviewScreen), findsNothing);
    });
  });

  group('gate prendido', () {
    testWidgets('aviso exacto, cupo y un selector para xlsx y pdf con bytes',
        (tester) async {
      final service = _FakeService();
      await _pumpPdf(tester, service,
          remaining: (week: 5, day: 2, limitWeekly: 7, limitDaily: 7));
      final picker = await _recordPicker('plan.pdf', 10);

      expect(find.text(_hintPdf), findsOneWidget);
      expect(find.text(_hintExcel), findsNothing);
      expect(find.text(_aviso), findsOneWidget);
      expect(find.text('Te quedan 5 esta semana y 2 hoy.'), findsOneWidget);
      // La plantilla sigue ahí: el Excel no se fue a ningún lado.
      expect(find.text('Descargar plantilla'), findsOneWidget);
      // Con un PDF al lado, la plantilla ya no es «la única que aceptamos».
      expect(find.textContaining('Es la única planilla que aceptamos'),
          findsOneWidget);
      expect(find.textContaining('Es la única que aceptamos.'), findsNothing);

      await tester.tap(find.text('Elegir archivo'));
      await tester.pumpAndSettle();
      expect(picker.allowed, unorderedEquals(['xlsx', 'pdf']));
      expect(picker.withData, isTrue);
    });

    testWidgets('sin cupo conocido no hay ningún número', (tester) async {
      await _pumpPdf(tester, _FakeService());
      expect(find.text(_aviso), findsOneWidget);
      expect(find.byKey(const Key('pdf_import_quota')), findsNothing);
    });

    testWidgets('un PDF de más de 5 MB se rechaza sin llamar al servidor',
        (tester) async {
      final service = _FakeService();
      await _pumpPdf(tester, service, size: kPdfImportMaxBytes + 1);

      await tester.tap(find.text('Elegir archivo'));
      await tester.pumpAndSettle();

      expect(find.text('El archivo pesa más de 5 MB. Elegí uno más liviano.'),
          findsOneWidget);
      expect(find.text('Elegir otro archivo'), findsOneWidget);
      expect(find.text('PROCESAR PLAN'), findsNothing);
      expect(service.calls, isEmpty);
    });

    testWidgets(
        'leyendo: espera visible, sin reenvío; al terminar llega a la vista '
        'previa del Hub con el borrador SIN alumno y sus sugerencias',
        (tester) async {
      final service = _FakeService();
      await _pumpPdf(tester, service);
      await _pickAndStart(tester);

      expect(service.calls, ['plan_fuerza-FINAL.pdf:null']);
      expect(find.text('Leyendo tu plan…'), findsOneWidget);
      expect(
          find.text('Puede tardar hasta un par de minutos. No cierres esta '
              'pantalla.'),
          findsOneWidget);
      expect(find.byKey(const Key('pdf_import_progress')), findsOneWidget);
      expect(find.text('PROCESAR PLAN'), findsNothing);

      service.complete(PdfImportSuccess(
        draft: pdfDraft(),
        quota: null,
        model: 'm',
      ));
      await tester.pumpAndSettle();

      expect(find.byType(CoachHubPlanPreviewScreen), findsOneWidget);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(CoachHubPlanPreviewScreen)));
      final PeriodizedImportDraft? draft =
          container.read(periodizedImportProvider);
      expect(draft, isNotNull);
      expect(draft!.athleteId, isNull);
      expect(draft.suggestions, {kPdfRemoKey: kPdfRemoBarra});
      expect(find.text('Sugerencia: Remo con barra'), findsOneWidget);
      expect(find.text('Confirmar la sugerencia'), findsOneWidget);
      expect(find.text('Alternativa: Remo con mancuerna'), findsOneWidget);
      // Una sola llamada: ni el éxito ni el rebuild reenvían.
      expect(service.calls, hasLength(1));
    });

    testWidgets('al volver de la vista previa el PDF ya no queda listo',
        (tester) async {
      final service = _FakeService();
      await _pumpPdf(tester, service);
      await _pickAndStart(tester);
      service.complete(
          PdfImportSuccess(draft: pdfDraft(), quota: null, model: 'm'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      expect(find.byType(CoachHubUploadPlanScreen), findsOneWidget);
      expect(find.text('plan_fuerza-FINAL.pdf'), findsNothing);
      expect(find.text('Elegir archivo'), findsOneWidget);
    });

    testWidgets('salir mientras lee pide confirmación', (tester) async {
      final service = _FakeService();
      await _pumpPdf(tester, service);
      await _pickAndStart(tester);

      // La barra de progreso es indeterminada: pumpAndSettle no termina.
      await tester.tap(find.byTooltip('Volver'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('¿Salir mientras se lee el plan?'), findsOneWidget);
      expect(find.text('Este intento ya cuenta en tu cupo aunque salgas.'),
          findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('¿Salir mientras se lee el plan?'), findsNothing);
      expect(find.text('Leyendo tu plan…'), findsOneWidget);

      // Confirmar sí sale, al dashboard.
      await tester.tap(find.byTooltip('Volver'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Salir'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CoachHubUploadPlanScreen), findsNothing);
      expect(find.text('DASHBOARD'), findsOneWidget);
    });

    group('errores tipados del servicio, con su acción', () {
      testWidgets('timeout: mensaje, «Reintentar» y «Elegir otro archivo»',
          (tester) async {
        final service = _FakeService();
        await _pumpPdf(tester, service);
        await _pickAndStart(tester);
        service.complete(const PdfImportTimeout());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('pdf_import_error')), findsOneWidget);
        expect(find.textContaining('tardó demasiado'), findsOneWidget);
        expect(find.text('Elegir otro archivo'), findsOneWidget);
        expect(find.text('PROCESAR PLAN'), findsNothing);

        await tester.tap(find.text('Reintentar'));
        await tester.pump();
        expect(service.calls, hasLength(2));
        expect(find.text('Leyendo tu plan…'), findsOneWidget);
      });

      testWidgets('cupo agotado sin fecha: sólo el mensaje', (tester) async {
        final service = _FakeService();
        await _pumpPdf(tester, service);
        await _pickAndStart(tester);
        service.complete(
            const PdfImportQuotaExhausted(scope: PdfQuotaScope.unknown));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('pdf_import_error')), findsOneWidget);
        expect(find.text('Reintentar'), findsNothing);
        expect(find.text('Elegir otro archivo'), findsNothing);
      });

      testWidgets('kill switch apagado en el servidor', (tester) async {
        final service = _FakeService();
        await _pumpPdf(tester, service);
        await _pickAndStart(tester);
        service.complete(const PdfImportDisabled());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('pdf_import_error')), findsOneWidget);
        expect(find.text('Reintentar'), findsNothing);
      });

      testWidgets('PDF con contraseña: «Elegir otro archivo», sin reintento',
          (tester) async {
        final service = _FakeService();
        await _pumpPdf(tester, service);
        await _pickAndStart(tester);
        service.complete(const PdfImportInvalidFile(PdfRejectReason.encrypted));
        await tester.pumpAndSettle();

        expect(find.text('Elegir otro archivo'), findsOneWidget);
        expect(find.text('Reintentar'), findsNothing);
      });
    });

    testWidgets('con el gate prendido, un .xlsx sigue yendo por el Excel',
        (tester) async {
      final service = _FakeService();
      final bytes = programa([
        header1(weeks: 2),
        [1, 'Ejercicio A', 60, '3x8', '3x9'],
      ]);
      await pumpUploadFlow(
        tester,
        bytes: bytes,
        catalog: [_ex('a', 'Ejercicio A')],
        routineRepo: MockRoutineRepo(),
        fileName: 'Plan de fuerza.xlsx',
        pdfGate: PdfImportGate.enabled,
        extra: [
          planPdfImportServiceProvider.overrideWithValue(service),
          pdfImportRemainingProvider.overrideWithValue(null),
        ],
      );
      await pickAndProcess(tester);

      expect(service.calls, isEmpty);
      expect(find.byType(CoachHubPlanPreviewScreen), findsOneWidget);
      expect(find.text('Plan de fuerza'), findsWidgets);
    });
  });
}
