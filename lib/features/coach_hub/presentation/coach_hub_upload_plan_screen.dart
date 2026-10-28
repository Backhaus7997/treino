import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../application/hub_pdf_import_job_provider.dart';
import '../application/pdf_import_quota_provider.dart';
import '../application/plan_import_providers.dart';
import '../application/plan_pdf_import_providers.dart';
import '../data/periodized_template_builder.dart';
import '../data/plan_pdf_import_service.dart';
import '../domain/periodized_plan.dart';
import '../infrastructure/browser_download.dart';
import 'widgets/import_plan_widgets.dart';
import 'widgets/pdf_import_failure_copy.dart';

/// Upload screen del Coach Hub — paso 1 del flujo de import.
///
/// 1. Botón "Descargar plantilla" → genera el xlsx periodizado en memoria +
///    browser download
/// 2. File picker para que el PF elija un xlsx (o un PDF, si el kill switch
///    `app_config/pdf_import` se lo habilita: [pdfImportGateProvider])
/// 3. Botón "Procesar" → parseo + match (client-side) → vista previa. Si el
///    parser encuentra errores se muestran TODOS con su celda y no se avanza.
///    Un PDF va por `parsePlanPdf` (docs/plan-import-pdf.md) y llega a la
///    MISMA vista previa, sin alumno: se eligen al asignar, como en el Excel.
///    La lectura vive en [hubPdfImportJobProvider], no en esta pantalla: el
///    PF puede irse a otra sección y el shell le avisa al terminar.
///
/// Con el gate apagado (o cargando) la pantalla es la del Excel solo: ni el
/// picker acepta PDF ni hay texto del PDF.
class CoachHubUploadPlanScreen extends ConsumerStatefulWidget {
  const CoachHubUploadPlanScreen({super.key});

  @override
  ConsumerState<CoachHubUploadPlanScreen> createState() =>
      _CoachHubUploadPlanScreenState();
}

class _CoachHubUploadPlanScreenState
    extends ConsumerState<CoachHubUploadPlanScreen> {
  PlatformFile? _pickedFile;
  bool _submitting = false;
  bool _downloadingTemplate = false;
  String? _error;
  List<ImportDiagnostic> _diagnostics = const [];

  /// El tope local de 5 MB, chequeado al elegir. Los resultados del servidor
  /// no viven acá sino en [hubPdfImportJobProvider], que sobrevive a esta
  /// pantalla: el PF puede irse mientras se lee el PDF sin perder lo que ya
  /// pagó con su cupo.
  PdfImportResult? _pickFailure;

  bool get _pdfEnabled =>
      ref.read(pdfImportGateProvider) == PdfImportGate.enabled;

  HubPdfImportJobNotifier get _job =>
      ref.read(hubPdfImportJobProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Lo que la lectura terminó mientras el PF estaba acá: listo → a la
    // vista previa, como siempre. Si estaba en otra sección, avisa el shell.
    ref.listenManual<HubPdfImportJob>(hubPdfImportJobProvider, (prev, next) {
      if (prev is! HubPdfImportReading || next is! HubPdfImportReady) return;
      // Sólo si esta pantalla es la de arriba: debajo de la vista previa no
      // se empuja otra.
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      _openPreview();
    });
  }

  void _openPreview() {
    _job.acknowledge();
    // Ese PDF ya gastó cupo: al volver de la vista previa no queda listo
    // para procesarse de nuevo por un clic de más.
    setState(() => _pickedFile = null);
    // push, como el Excel: «atrás» desde la vista previa vuelve acá.
    context.push('/upload-plan/preview');
  }

  /// El archivo va por el import de PDF: es un `.pdf` y el gate lo permite.
  /// Con el gate apagado todo va por el Excel, como antes.
  static bool _isPdf(PlatformFile? file, {required bool pdfEnabled}) =>
      pdfEnabled && file != null && file.name.toLowerCase().endsWith('.pdf');

  Future<void> _pickFile() async {
    final pdfEnabled = _pdfEnabled;
    setState(() {
      _error = null;
      _diagnostics = const [];
      _pickFailure = null;
    });
    // Elegir otro archivo deja atrás el error (o el «listo») de la lectura
    // anterior.
    _job.acknowledge();
    // Web: no hay rutas, sólo bytes (`withData`). Un solo selector para los
    // dos formatos: el tipo del archivo decide el camino.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: pdfEnabled ? const ['xlsx', 'pdf'] : const ['xlsx'],
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final file = result.files.first;
    setState(() {
      // El tope del PDF se chequea acá, antes de mandar 5 MB en base64 que el
      // servidor va a rechazar.
      final tooBig = _isPdf(file, pdfEnabled: pdfEnabled) &&
          file.size > kPdfImportMaxBytes;
      _pickedFile = tooBig ? null : file;
      _pickFailure =
          tooBig ? const PdfImportInvalidFile(PdfRejectReason.tooBig) : null;
    });
  }

  Future<void> _process() => _isPdf(_pickedFile, pdfEnabled: _pdfEnabled)
      ? _processPdf()
      : _processFile();

  Future<void> _processPdf() async {
    final file = _pickedFile;
    final bytes = file?.bytes;
    // Una lectura a la vez, aunque el PF haya salido y vuelto.
    if (_job.isReading || file == null) return;
    if (bytes == null) {
      setState(() => _pickFailure = const PdfImportInternal(code: 'no-bytes'));
      return;
    }
    setState(() {
      _pickFailure = null;
      _error = null;
    });
    // Sin await: la lectura sigue aunque esta pantalla se desmonte. El
    // resultado llega por [hubPdfImportJobProvider].
    unawaited(
        _job.start(bytes: Uint8List.fromList(bytes), fileName: file.name));
  }

  // pop back to the dashboard (the push origin); fall back to go() when
  // there's no stack to pop (e.g. deep-linked directly here).
  void _leave() => context.canPop() ? context.pop() : context.go('/dashboard');

  Future<void> _downloadTemplate() async {
    if (_downloadingTemplate) return;
    setState(() {
      _downloadingTemplate = true;
      _error = null;
    });

    try {
      final bytes = buildPeriodizedTemplateBytes();
      triggerBrowserDownload(
        bytes: bytes,
        filename: 'treino-plantilla-plan.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos generar la plantilla.');
    } finally {
      if (mounted) setState(() => _downloadingTemplate = false);
    }
  }

  /// Nombre inicial de la rutina: el del archivo sin la extensión.
  static String _routineNameOf(String fileName) {
    final base =
        fileName.replaceFirst(RegExp(r'\.xlsx$', caseSensitive: false), '');
    final clean = base.trim();
    return clean.isEmpty ? 'Plan importado' : clean;
  }

  Future<void> _processFile() async {
    if (_submitting) return;
    final file = _pickedFile;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'No pudimos leer el archivo. Volvé a elegirlo.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _diagnostics = const [];
    });

    try {
      final outcome =
          await ref.read(planImportRepositoryProvider).parseAndMatch(
                bytes: Uint8List.fromList(bytes),
                defaultName: _routineNameOf(file.name),
              );
      final draft = outcome.draft;
      if (draft == null) {
        if (!mounted) return;
        setState(() {
          _diagnostics = outcome.diagnostics;
          _submitting = false;
        });
        return;
      }
      ref.read(periodizedImportProvider.notifier).state = draft;
      if (!mounted) return;
      setState(() => _submitting = false);
      // push (not go): preview is a sub-step, so pop() from it returns here
      // with the picked file still in state and the browser Back works.
      context.push('/upload-plan/preview');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos procesar el archivo. Probá de nuevo.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final file = _pickedFile;
    final errors = _diagnostics.where((d) => d.isError).toList();
    final pdfEnabled =
        ref.watch(pdfImportGateProvider) == PdfImportGate.enabled;
    // La lectura vive en el job, no acá: al volver a la pantalla se ve en
    // qué quedó. Salir mientras lee ya no pregunta nada: no se pierde.
    final job = ref.watch(hubPdfImportJobProvider);
    final readingPdf = job is HubPdfImportReading;
    final pdfReady =
        job is HubPdfImportReady && ref.watch(periodizedImportProvider) != null;
    final pdfFailure =
        _pickFailure ?? (job is HubPdfImportFailed ? job.failure : null);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20,
                vertical: AppSpacing.s18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(palette: palette, onBack: _leave),
                  const SizedBox(height: AppSpacing.s20),
                  _TemplateCard(
                    palette: palette,
                    onDownload: _downloadTemplate,
                    loading: _downloadingTemplate,
                    pdfEnabled: pdfEnabled,
                  ),
                  const SizedBox(height: AppSpacing.s18),
                  _UploadCard(
                    palette: palette,
                    file: file,
                    pdfEnabled: pdfEnabled,
                    isPdf: _isPdf(file, pdfEnabled: pdfEnabled),
                    onPick: readingPdf ? null : _pickFile,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.s14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: importText(palette.dangerText,
                          size: AppTextSize.bodyDense),
                    ),
                  ],
                  if (errors.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s14),
                    _ErrorsCard(palette: palette, errors: errors),
                  ],
                  if (pdfFailure != null && !readingPdf) ...[
                    const SizedBox(height: AppSpacing.s14),
                    _PdfFailureCard(
                      palette: palette,
                      failure: pdfFailure,
                      onPickAnother: _pickFile,
                      // Con los bytes que guardó el job: sirve aunque el
                      // PF se haya ido y vuelto sin el archivo.
                      onRetry: _pickFailure == null && _job.canRetry
                          ? _job.retry
                          : null,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.s18),
                  // Leyendo, la espera ocupa el lugar del botón; con un
                  // error del PDF, sus acciones (como en mobile); con el
                  // plan ya leído (terminó mientras el PF estaba en otra
                  // sección), el paso a la vista previa.
                  if (readingPdf)
                    _ReadingPdfCard(palette: palette, fileName: job.fileName)
                  else if (pdfReady)
                    _PdfReadyCard(palette: palette, onOpen: _openPreview)
                  else if (pdfFailure == null)
                    TreinoButton(
                      label: 'PROCESAR PLAN',
                      expand: true,
                      loading: _submitting,
                      onPressed: _pickedFile == null ? null : _process,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Aviso de privacidad y cupo del import de PDF, dentro de la tarjeta de
/// subida: la spec pide el aviso al momento de subir, antes de elegir.
class _PdfNotice extends StatelessWidget {
  const _PdfNotice({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return ImportCard(
      padding: AppSpacing.s12,
      background: palette.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(TreinoIcon.shieldCheck, color: palette.accent),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  AppL10n.of(context).pdfImportPrivacyNotice,
                  style: importText(
                    palette.textPrimary,
                    size: AppTextSize.bodyDense,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          _PdfQuotaLine(palette: palette),
        ],
      ),
    );
  }
}

/// El cupo, sólo si se sabe: mientras carga, o si el tier no se puede
/// afirmar, no hay línea (ni un «0» inventado).
class _PdfQuotaLine extends ConsumerWidget {
  const _PdfQuotaLine({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = ref.watch(pdfImportRemainingProvider);
    if (remaining == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: Text(
        AppL10n.of(context)
            .pdfImportQuotaRemaining(remaining.week, remaining.day),
        key: const Key('pdf_import_quota'),
        style: importText(palette.textMuted, size: AppTextSize.bodyDense),
      ),
    );
  }
}

/// La espera mientras `parsePlanPdf` lee el PDF. Dice que se puede seguir
/// usando el Hub: la lectura no depende de esta pantalla.
class _ReadingPdfCard extends StatelessWidget {
  const _ReadingPdfCard({required this.palette, required this.fileName});
  final AppPalette palette;

  /// El PDF que se está leyendo: al volver a la pantalla, el archivo elegido
  /// ya no está en la tarjeta de subida.
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return ImportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.pdfImportProcessingTitle,
            style: importText(
              palette.textPrimary,
              size: AppTextSize.bodyLarge,
              weight: AppFonts.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.hairline),
          Text(
            fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: importText(palette.textMuted, size: AppTextSize.caption),
          ),
          const SizedBox(height: AppSpacing.s12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              key: const Key('pdf_import_progress'),
              color: palette.accent,
              backgroundColor: palette.border,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            l10n.coachHubPdfProcessingHint,
            style: importText(
              palette.textMuted,
              size: AppTextSize.bodyDense,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// El plan se leyó mientras el PF estaba en otra sección y volvió acá sin
/// pasar por el aviso: el borrador lo espera en la vista previa.
class _PdfReadyCard extends StatelessWidget {
  const _PdfReadyCard({required this.palette, required this.onOpen});
  final AppPalette palette;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return ImportCard(
      key: const Key('pdf_import_ready'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(TreinoIcon.checkCircleFill, color: palette.accent),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  l10n.coachHubPdfReadyToast,
                  style: importText(
                    palette.textPrimary,
                    size: AppTextSize.bodyLarge,
                    weight: AppFonts.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s14),
          TreinoButton(
            label: l10n.coachHubPdfReadyAction,
            expand: true,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

/// Un resultado no exitoso del PDF, con el mismo texto y las mismas acciones
/// que en mobile ([pdfImportFailureCopy]).
class _PdfFailureCard extends StatelessWidget {
  const _PdfFailureCard({
    required this.palette,
    required this.failure,
    required this.onPickAnother,
    required this.onRetry,
  });
  final AppPalette palette;
  final PdfImportResult failure;
  final VoidCallback onPickAnother;

  /// Null si no hay archivo con el que reintentar.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final copy = pdfImportFailureCopy(l10n, failure);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ImportCard(
          key: const Key('pdf_import_error'),
          borderColor: palette.danger,
          background: palette.danger.withValues(alpha: 0.08),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(TreinoIcon.warning, color: palette.dangerText),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  copy.message,
                  style: importText(palette.textPrimary, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        if (copy.retry && onRetry != null) ...[
          const SizedBox(height: AppSpacing.s14),
          TreinoButton(
            label: l10n.pdfImportRetry,
            expand: true,
            onPressed: onRetry,
          ),
        ],
        if (copy.pickAnother) ...[
          const SizedBox(height: AppSpacing.s12),
          TreinoButton(
            label: l10n.pdfImportPickAnother,
            icon: TreinoIcon.upload,
            variant: TreinoButtonVariant.secondaryAccent,
            expand: true,
            onPressed: onPickAnother,
          ),
        ],
      ],
    );
  }
}

class _ErrorsCard extends StatelessWidget {
  const _ErrorsCard({required this.palette, required this.errors});
  final AppPalette palette;
  final List<ImportDiagnostic> errors;

  @override
  Widget build(BuildContext context) {
    return ImportCard(
      borderColor: palette.danger,
      background: palette.danger.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            errors.length == 1
                ? 'Hay 1 error en el archivo. Corregilo y volvé a subirlo.'
                : 'Hay ${errors.length} errores en el archivo. Corregilos y '
                    'volvé a subirlo.',
            style: importText(
              palette.textPrimary,
              size: AppTextSize.body,
              weight: AppFonts.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          ImportDiagnosticsList(diagnostics: errors),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.palette, required this.onBack});
  final AppPalette palette;

  /// Volver al dashboard; mientras se lee un PDF, pide confirmación.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TreinoIconButton(
          icon: TreinoIcon.arrowLeft,
          tooltip: 'Volver',
          color: palette.textPrimary,
          onPressed: onBack,
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TREINO COACH HUB',
                style: TextStyle(
                  fontFamily: AppFonts.barlowCondensed,
                  color: palette.highlight,
                  fontSize: AppTextSize.caption,
                  fontWeight: AppFonts.w700,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: AppSpacing.hairline),
              Text(
                'IMPORTAR PLAN',
                style: TextStyle(
                  fontFamily: AppFonts.barlowCondensed,
                  color: palette.textPrimary,
                  fontSize: AppTextSize.heading,
                  fontWeight: AppFonts.w700,
                  letterSpacing: 1.2,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.palette,
    required this.onDownload,
    required this.loading,
    required this.pdfEnabled,
  });
  final AppPalette palette;
  final VoidCallback onDownload;
  final bool loading;

  /// Con el PDF habilitado, «es la única que aceptamos» sería falso: la
  /// plantilla es la única PLANILLA, y al lado se acepta un PDF.
  final bool pdfEnabled;

  @override
  Widget build(BuildContext context) {
    return ImportCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(TreinoIcon.download, color: palette.accent),
          const SizedBox(width: AppSpacing.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿No tenés la plantilla?',
                  style: importText(
                    palette.textPrimary,
                    size: AppTextSize.bodyLarge,
                    weight: AppFonts.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  pdfEnabled
                      ? AppL10n.of(context).coachHubImportTemplateBodyPdf
                      : 'Descargá la plantilla: una hoja "Programa" con un '
                          'bloque por día y una columna por semana, y una hoja '
                          '"Instrucciones" con la notación. Es la única que '
                          'aceptamos.',
                  style: importText(
                    palette.textMuted,
                    size: AppTextSize.bodyDense,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.s12),
                TreinoButton(
                  label: 'Descargar plantilla',
                  variant: TreinoButtonVariant.secondaryAccent,
                  loading: loading,
                  onPressed: onDownload,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  const _UploadCard({
    required this.palette,
    required this.file,
    required this.pdfEnabled,
    required this.isPdf,
    required this.onPick,
  });
  final AppPalette palette;
  final PlatformFile? file;

  /// El gate del import de PDF está prendido para este PF.
  final bool pdfEnabled;

  /// [file] va por el import de PDF.
  final bool isPdf;

  /// Null mientras se lee un PDF: no se cambia el archivo a mitad.
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final picked = file;
    return ImportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Subí tu plan',
            style: importText(
              palette.textPrimary,
              size: AppTextSize.bodyLarge,
              weight: AppFonts.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.hairline),
          Text(
            pdfEnabled
                ? AppL10n.of(context).coachHubImportUploadHintPdf
                : 'Archivo .xlsx, hasta 10 MB.',
            style: importText(palette.textMuted, size: AppTextSize.bodyDense),
          ),
          if (pdfEnabled) ...[
            const SizedBox(height: AppSpacing.s14),
            _PdfNotice(palette: palette),
          ],
          const SizedBox(height: AppSpacing.s14),
          if (picked == null)
            TreinoButton(
              label: 'Elegir archivo',
              icon: TreinoIcon.upload,
              variant: TreinoButtonVariant.secondaryAccent,
              expand: true,
              onPressed: onPick,
            )
          else
            ImportCard(
              padding: AppSpacing.s12,
              background: palette.bg,
              child: Row(
                children: [
                  Icon(isPdf ? TreinoIcon.filePdf : TreinoIcon.fileXls,
                      color: palette.accent),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          picked.name,
                          style: importText(
                            palette.textPrimary,
                            weight: AppFonts.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _formatBytes(picked.size),
                          style: importText(
                            palette.textMuted,
                            size: AppTextSize.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TreinoButton(
                    label: 'Cambiar',
                    variant: TreinoButtonVariant.ghostAccent,
                    size: TreinoButtonSize.sm,
                    onPressed: onPick,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
