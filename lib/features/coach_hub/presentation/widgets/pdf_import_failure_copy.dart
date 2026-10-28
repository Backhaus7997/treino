import '../../../../core/utils/argentina_time.dart';
import '../../../../l10n/app_l10n.dart';
import '../../data/plan_pdf_import_service.dart';

/// Lo que comparten las dos pantallas de subida del PDF (la de la ficha del
/// alumno en mobile y «Importar plan» del Coach Hub): qué se le dice al PF
/// con cada resultado no exitoso del servicio. Los contenedores son de cada
/// app; el texto y las acciones, uno solo.

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
