import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/tokens.dart';
import '../../../core/utils/argentina_time.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_confirm_dialog.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../coach_hub/application/pdf_import_quota_provider.dart';
import '../../coach_hub/application/plan_import_providers.dart';
import '../../coach_hub/application/plan_pdf_import_providers.dart';
import '../../coach_hub/data/periodized_import_draft.dart';
import '../../coach_hub/data/plan_pdf_import_service.dart';

/// Ruta de la pantalla de subida para [athleteId].
String planPdfImportPath(String athleteId) => '/workout/import-pdf/$athleteId';

/// Subida del PDF de un plan (docs/plan-import-pdf.md, «Flujo del PF en
/// mobile», pasos 2 y 3): aviso de privacidad, cupo, selector y espera.
///
/// Cada error tipado del servicio se muestra EN la pantalla, con su acción.
/// Mientras procesa no se puede reenviar, y salir pide confirmación: el
/// servidor ya descontó el cupo.
class PlanPdfImportUploadScreen extends ConsumerStatefulWidget {
  const PlanPdfImportUploadScreen({super.key, required this.athleteId});

  final String athleteId;

  @override
  ConsumerState<PlanPdfImportUploadScreen> createState() =>
      _PlanPdfImportUploadScreenState();
}

class _PlanPdfImportUploadScreenState
    extends ConsumerState<PlanPdfImportUploadScreen> {
  PlatformFile? _file;
  bool _processing = false;

  /// Lo que se muestra en lugar del botón: un error del archivo elegido
  /// (chequeo local) o el resultado no exitoso del servicio.
  PdfImportResult? _failure;

  /// El plan leído en ESTA visita. No se lee de [periodizedImportProvider]:
  /// ese guarda el último borrador de cualquier import.
  PeriodizedImportDraft? _read;

  Future<void> _pick() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (!mounted || picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    setState(() {
      // El tope se chequea acá, antes de mandar 5 MB en base64 que el
      // servidor va a rechazar.
      final tooBig = file.size > kPdfImportMaxBytes;
      _file = tooBig ? null : file;
      _read = null;
      _failure =
          tooBig ? const PdfImportInvalidFile(PdfRejectReason.tooBig) : null;
    });
  }

  Future<void> _process() async {
    final file = _file;
    final bytes = file?.bytes;
    if (_processing || file == null) return;
    if (bytes == null) {
      setState(() => _failure = const PdfImportInternal(code: 'no-bytes'));
      return;
    }
    setState(() {
      _processing = true;
      _failure = null;
    });
    final result = await ref.read(planPdfImportServiceProvider).importPdf(
          bytes: Uint8List.fromList(bytes),
          fileName: file.name,
          athleteId: widget.athleteId,
        );
    if (!mounted) return;
    final draft = result is PdfImportSuccess ? result.draft : null;
    if (draft != null) {
      ref.read(periodizedImportProvider.notifier).state = draft;
    }
    setState(() {
      _processing = false;
      _read = draft;
      _failure = draft == null ? result : null;
    });
  }

  Future<void> _confirmLeave() async {
    final l10n = AppL10n.of(context);
    final leave = await showTreinoConfirmDialog(
      context,
      title: l10n.pdfImportLeaveTitle,
      body: l10n.pdfImportLeaveBody,
      confirmLabel: l10n.pdfImportLeaveConfirm,
    );
    if (leave && mounted) _leave();
  }

  void _leave() => context.canPop()
      ? context.pop()
      : context.go('/coach/athlete/${widget.athleteId}');

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final read = _read;

    final Widget state;
    final Key stateKey;
    if (_processing) {
      stateKey = const ValueKey('processing');
      state = const _Processing();
    } else if (_failure != null) {
      stateKey = ValueKey('failure-${_failure.runtimeType}');
      state = _FailurePanel(
        failure: _failure!,
        onPickAnother: _pick,
        onRetry: _file == null ? null : _process,
      );
    } else {
      stateKey = ValueKey('idle-${_file?.name}-${read != null}');
      state = _Idle(
        file: _file,
        summary: read == null
            ? null
            : l10n.pdfImportReadSummary(
                read.plan.days.length, read.plan.numWeeks),
        onPick: _pick,
        onProcess: _file == null ? null : _process,
      );
    }

    return PopScope(
      canPop: !_processing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: palette.bg,
        body: AppBackground(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s8, AppSpacing.s8, AppSpacing.s20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(TreinoIcon.back, color: palette.textPrimary),
                        tooltip: l10n.commonBack,
                        onPressed: _processing ? _confirmLeave : _leave,
                      ),
                      Expanded(
                        child: Text(
                          l10n.pdfImportUploadTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: AppFonts.w700,
                            fontSize: AppTextSize.title,
                            letterSpacing: AppFonts.headingTracking,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.s20,
                        AppSpacing.s12, AppSpacing.s20, AppSpacing.s20),
                    children: [
                      _Notice(text: l10n.pdfImportPrivacyNotice),
                      const _QuotaLine(),
                      const SizedBox(height: AppSpacing.s18),
                      TreinoStateSwitcher(childKey: stateKey, child: state),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _body(Color color, {FontWeight weight = AppFonts.w400}) =>
    GoogleFonts.barlow(
      fontSize: AppTextSize.body,
      fontWeight: weight,
      color: color,
      height: 1.4,
    );

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(TreinoIcon.shieldCheck, color: palette.accent),
          const SizedBox(width: AppSpacing.s12),
          Expanded(child: Text(text, style: _body(palette.textPrimary))),
        ],
      ),
    );
  }
}

/// El cupo, sólo si se sabe: mientras carga, o si el tier no se puede
/// afirmar, no hay línea (ni un «0» inventado).
class _QuotaLine extends ConsumerWidget {
  const _QuotaLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = ref.watch(pdfImportRemainingProvider);
    if (remaining == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s12),
      child: Text(
        AppL10n.of(context)
            .pdfImportQuotaRemaining(remaining.week, remaining.day),
        key: const Key('pdf_import_quota'),
        style: _body(AppPalette.of(context).textMuted),
      ),
    );
  }
}

class _Cta extends StatelessWidget {
  const _Cta({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: TreinoButtonTokens.foreground(context),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontWeight: AppFonts.w700,
          fontSize: AppTextSize.body,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _Secondary extends StatelessWidget {
  const _Secondary({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: palette.accent),
        foregroundColor: palette.accentText,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
      ),
      icon: Icon(TreinoIcon.filePdf, color: palette.accent),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _body(palette.accentText, weight: AppFonts.w600),
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({
    required this.file,
    required this.summary,
    required this.onPick,
    required this.onProcess,
  });

  final PlatformFile? file;
  final String? summary;
  final VoidCallback onPick;
  final VoidCallback? onProcess;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final file = this.file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (file != null) ...[
          Row(
            children: [
              Icon(TreinoIcon.filePdf, color: palette.textMuted),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _body(palette.textPrimary, weight: AppFonts.w600),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(
                '${(file.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                style: _body(palette.textMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s14),
        ],
        if (summary != null) ...[
          Text(summary!, style: _body(palette.accentText)),
          const SizedBox(height: AppSpacing.s14),
        ],
        _Secondary(
          label:
              file == null ? l10n.pdfImportPickFile : l10n.pdfImportPickAnother,
          onPressed: onPick,
        ),
        const SizedBox(height: AppSpacing.s12),
        _Cta(label: l10n.pdfImportProcess, onPressed: onProcess),
      ],
    );
  }
}

class _Processing extends StatelessWidget {
  const _Processing();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.pdfImportProcessingTitle,
          style: _body(palette.textPrimary, weight: AppFonts.w700),
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
        Text(l10n.pdfImportProcessingHint, style: _body(palette.textMuted)),
      ],
    );
  }
}

typedef PdfImportFailureCopy = ({String message, bool pickAnother, bool retry});

/// El texto de cada resultado no exitoso, y si se arregla eligiendo otro
/// archivo o reintentando. Exhaustivo: una variante nueva del servicio no
/// compila hasta tener su texto.
PdfImportFailureCopy pdfImportFailureCopy(
  AppL10n l10n,
  PdfImportResult failure,
) {
  PdfImportFailureCopy copy(String m,
          {bool pick = false, bool retry = false}) =>
      (message: m, pickAnother: pick, retry: retry);
  return switch (failure) {
    PdfImportInvalidFile(:final reason) => copy(
        switch (reason) {
          PdfRejectReason.tooBig => l10n.pdfImportErrorTooBig,
          PdfRejectReason.notPdf => l10n.pdfImportErrorNotPdf,
          PdfRejectReason.tooManyPages => l10n.pdfImportErrorTooManyPages,
          PdfRejectReason.encrypted => l10n.pdfImportErrorEncrypted,
          PdfRejectReason.unknown => l10n.pdfImportErrorFileUnknown,
        },
        pick: true,
      ),
    PdfImportQuotaExhausted(:final scope, :final resetsAt) =>
      copy(_quotaMessage(l10n, scope, resetsAt)),
    PdfImportTimeout() =>
      copy(l10n.pdfImportErrorTimeout, pick: true, retry: true),
    PdfImportInternal() => copy(l10n.pdfImportErrorInternal, retry: true),
    PdfImportInvalidPlan() => copy(l10n.pdfImportErrorInvalidPlan, pick: true),
    PdfImportDisabled() => copy(l10n.pdfImportErrorDisabled),
    PdfImportStructuredOutputsDisabled() =>
      copy(l10n.pdfImportErrorUnavailable),
    PdfImportNotTrainer() => copy(l10n.pdfImportErrorNotTrainer),
    PdfImportUnauthenticated() => copy(l10n.pdfImportErrorSignedOut),
    PdfImportSuccess() => copy(''),
  };
}

/// Cupo agotado: cuándo vuelve, sólo si el servidor lo dijo. Sin fecha, no
/// se inventa una.
String _quotaMessage(AppL10n l10n, PdfQuotaScope scope, DateTime? resetsAt) {
  if (resetsAt == null || scope == PdfQuotaScope.unknown) {
    return l10n.pdfImportErrorQuotaUnknown;
  }
  String two(int n) => n.toString().padLeft(2, '0');
  // El cupo se resetea en hora argentina (spec), no en la del teléfono.
  final at = toArgentina(resetsAt.toUtc());
  final date = '${two(at.day)}/${two(at.month)}';
  final time = '${two(at.hour)}:${two(at.minute)}';
  return scope == PdfQuotaScope.week
      ? l10n.pdfImportErrorQuotaWeek(date, time)
      : l10n.pdfImportErrorQuotaDay(date, time);
}

class _FailurePanel extends StatelessWidget {
  const _FailurePanel({
    required this.failure,
    required this.onPickAnother,
    required this.onRetry,
  });

  final PdfImportResult failure;
  final VoidCallback onPickAnother;

  /// Null si no hay archivo con el que reintentar.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final copy = pdfImportFailureCopy(l10n, failure);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const Key('pdf_import_error'),
          padding: const EdgeInsets.all(AppSpacing.s14),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: palette.dangerText),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(TreinoIcon.warning, color: palette.dangerText),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(copy.message, style: _body(palette.textPrimary)),
              ),
            ],
          ),
        ),
        if (copy.retry && onRetry != null) ...[
          const SizedBox(height: AppSpacing.s14),
          _Cta(label: l10n.pdfImportRetry, onPressed: onRetry),
        ],
        if (copy.pickAnother) ...[
          const SizedBox(height: AppSpacing.s12),
          _Secondary(
              label: l10n.pdfImportPickAnother, onPressed: onPickAnother),
        ],
      ],
    );
  }
}
