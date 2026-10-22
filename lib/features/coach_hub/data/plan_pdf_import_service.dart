import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../domain/periodized_plan.dart';
import '../domain/periodized_plan_json.dart';
import 'periodized_import_draft.dart';
import 'plan_draft_matcher.dart';

/// Tope del archivo, igual que `PDF_MAX_BYTES` del servidor
/// (`functions/src/pdf-import/pdf-check.ts`). El cliente lo chequea antes de
/// subir para no mandar 5 MB en base64 que el servidor va a rechazar.
const int kPdfImportMaxBytes = 5 * 1024 * 1024;

/// Timeout del lado Dart. Acompaña al `timeoutSeconds: 300` del callable: con
/// el default de 60 s del SDK, la app cortaría una extracción que el servidor
/// todavía está haciendo (y que ya descontó cupo).
const Duration kPdfImportCallTimeout = Duration(seconds: 300);

/// Llamada cruda a `parsePlanPdf`: recibe el request y devuelve `data` tal
/// cual llega. Es el punto de inyección de los tests; en producción es
/// [parsePlanPdfCallable].
typedef ParsePlanPdfCall = Future<Object?> Function(
  Map<String, Object?> request,
);

/// El callable real, en la región de las funciones y con el timeout largo.
ParsePlanPdfCall parsePlanPdfCallable(FirebaseFunctions functions) {
  final callable = functions.httpsCallable(
    'parsePlanPdf',
    options: HttpsCallableOptions(timeout: kPdfImportCallTimeout),
  );
  return (request) async => (await callable.call<Object?>(request)).data;
}

/// Cupo de imports devuelto por el servidor después de descontar este.
class PdfImportQuota {
  const PdfImportQuota({
    required this.usedThisWeek,
    required this.limitWeekly,
    required this.usedToday,
    required this.limitDaily,
  });

  final int usedThisWeek;
  final int limitWeekly;
  final int usedToday;
  final int limitDaily;

  /// Lo que queda: el tope que se agote primero manda.
  int get remaining {
    final week = limitWeekly - usedThisWeek;
    final day = limitDaily - usedToday;
    final left = week < day ? week : day;
    return left < 0 ? 0 : left;
  }

  /// Null si no tiene la forma del contrato: el cupo es informativo y no
  /// tumba un plan que ya se extrajo (y se pagó).
  static PdfImportQuota? tryParse(Object? raw) {
    if (raw is! Map) return null;
    int? n(Object? v) => v is int ? v : (v is double ? v.toInt() : null);
    final usedThisWeek = n(raw['usedThisWeek']);
    final limitWeekly = n(raw['limitWeekly']);
    final usedToday = n(raw['usedToday']);
    final limitDaily = n(raw['limitDaily']);
    if (usedThisWeek == null ||
        limitWeekly == null ||
        usedToday == null ||
        limitDaily == null) {
      return null;
    }
    return PdfImportQuota(
      usedThisWeek: usedThisWeek,
      limitWeekly: limitWeekly,
      usedToday: usedToday,
      limitDaily: limitDaily,
    );
  }
}

/// `details.reason` de un `invalid-argument`.
enum PdfRejectReason { notPdf, tooBig, tooManyPages, encrypted, unknown }

/// `details.scope` de un `resource-exhausted`.
enum PdfQuotaScope { week, day, unknown }

/// Resultado tipado de [PlanPdfImportService.importPdf]: una variante por
/// caso del contrato (docs/plan-import-pdf.md, «Contrato del callable»). La
/// UI hace `switch` exhaustivo; ninguna variante se traga como otra.
sealed class PdfImportResult {
  const PdfImportResult();
}

/// Plan extraído, validado por el cliente y matcheado. [draft] trae lo exacto
/// asignado y lo demás como sugerencia o en rojo: nunca se autoasigna lo que
/// propuso el modelo.
final class PdfImportSuccess extends PdfImportResult {
  const PdfImportSuccess({
    required this.draft,
    required this.quota,
    required this.model,
  });

  final PeriodizedImportDraft draft;

  /// Null si el servidor no lo mandó con la forma del contrato.
  final PdfImportQuota? quota;
  final String model;
}

/// El servidor devolvió un plan, pero la validación del cliente
/// (`periodized_plan_json.dart`) lo rechaza. El cupo YA se descontó: el
/// servidor no sabe que el cliente lo rechazó.
final class PdfImportInvalidPlan extends PdfImportResult {
  const PdfImportInvalidPlan({
    required this.diagnostics,
    required this.quota,
    required this.model,
  });

  final List<ImportDiagnostic> diagnostics;
  final PdfImportQuota? quota;
  final String? model;

  List<ImportDiagnostic> get errors =>
      diagnostics.where((d) => d.isError).toList(growable: false);
}

/// `unauthenticated`: sin sesión.
final class PdfImportUnauthenticated extends PdfImportResult {
  const PdfImportUnauthenticated();
}

/// `permission-denied`: la cuenta no es de PF.
final class PdfImportNotTrainer extends PdfImportResult {
  const PdfImportNotTrainer();
}

/// `failed-precondition` sin `reason`: kill switch apagado para este uid.
final class PdfImportDisabled extends PdfImportResult {
  const PdfImportDisabled();
}

/// `failed-precondition` con `reason: structured_outputs_disabled`: falta un
/// paso de rollout en Vertex (no es culpa del PF). El cupo se devolvió.
final class PdfImportStructuredOutputsDisabled extends PdfImportResult {
  const PdfImportStructuredOutputsDisabled();
}

/// `invalid-argument`, o el chequeo previo del cliente. No toca el cupo.
final class PdfImportInvalidFile extends PdfImportResult {
  const PdfImportInvalidFile(this.reason);
  final PdfRejectReason reason;
}

/// `resource-exhausted`. [resetsAt] es null si no vino o no se pudo leer.
final class PdfImportQuotaExhausted extends PdfImportResult {
  const PdfImportQuotaExhausted({required this.scope, this.resetsAt});
  final PdfQuotaScope scope;
  final DateTime? resetsAt;
}

/// `deadline-exceeded` (del servidor o del timeout del cliente). El servidor
/// devuelve el cupo cuando el que cortó fue él.
final class PdfImportTimeout extends PdfImportResult {
  const PdfImportTimeout();
}

/// `internal` y todo lo que no es del contrato (red caída, código
/// desconocido, respuesta sin `plan`). [code] queda para el log.
final class PdfImportInternal extends PdfImportResult {
  const PdfImportInternal({this.code});
  final String? code;
}

/// Habla con `parsePlanPdf` y deja el resultado listo para la vista previa.
///
/// Sólo UX: la barrera real (rol, kill switch, cupo, validación) está en el
/// servidor. Este servicio NO crea nada: ni rutina, ni propios, ni aliases.
class PlanPdfImportService {
  PlanPdfImportService({
    required ParsePlanPdfCall call,
    required PlanDraftMatcher matcher,
  })  : _call = call,
        _matcher = matcher;

  final ParsePlanPdfCall _call;
  final PlanDraftMatcher _matcher;

  Future<PdfImportResult> importPdf({
    required Uint8List bytes,
    required String fileName,
    String? athleteId,
  }) async {
    if (!fileName.toLowerCase().endsWith('.pdf')) {
      return const PdfImportInvalidFile(PdfRejectReason.notPdf);
    }
    if (bytes.length > kPdfImportMaxBytes) {
      return const PdfImportInvalidFile(PdfRejectReason.tooBig);
    }

    final Object? data;
    try {
      data = await _call({
        'pdfBase64': base64Encode(bytes),
        'fileName': fileName,
        if (athleteId != null) 'athleteId': athleteId,
      });
    } on FirebaseFunctionsException catch (e) {
      return mapParsePlanPdfError(e);
    } on TimeoutException {
      return const PdfImportTimeout();
    } catch (_) {
      return const PdfImportInternal();
    }

    if (data is! Map || data['plan'] is! Map) {
      return const PdfImportInternal(code: 'malformed-response');
    }
    final quota = PdfImportQuota.tryParse(data['quota']);
    final rawModel = data['model'];
    final model = rawModel is String ? rawModel : null;

    final parsed = periodizedPlanFromJson(_stringKeys(data['plan'] as Map));
    if (!parsed.canImport) {
      return PdfImportInvalidPlan(
        diagnostics: parsed.diagnostics,
        quota: quota,
        model: model,
      );
    }
    final PeriodizedImportDraft draft;
    try {
      draft = await _matcher.matchDraft(
        plan: parsed.plan!,
        warnings: parsed.warnings,
        name: planNameFromFileName(fileName),
      );
    } catch (_) {
      // Sin catálogo no hay vista previa. El cupo ya se descontó.
      return const PdfImportInternal(code: 'catalog-unavailable');
    }
    return PdfImportSuccess(draft: draft, quota: quota, model: model ?? '');
  }
}

/// Traduce un error del callable a su variante. Pública para poder probar el
/// mapeo sin armar el resto.
PdfImportResult mapParsePlanPdfError(FirebaseFunctionsException e) {
  final details = e.details is Map ? e.details as Map : const {};
  switch (e.code) {
    case 'unauthenticated':
      return const PdfImportUnauthenticated();
    case 'permission-denied':
      return const PdfImportNotTrainer();
    case 'failed-precondition':
      // Sin reason (o con una que no conocemos) es el kill switch: falla
      // cerrado, igual que el servidor.
      return details['reason'] == 'structured_outputs_disabled'
          ? const PdfImportStructuredOutputsDisabled()
          : const PdfImportDisabled();
    case 'invalid-argument':
      return PdfImportInvalidFile(switch (details['reason']) {
        'not_pdf' => PdfRejectReason.notPdf,
        'too_big' => PdfRejectReason.tooBig,
        'too_many_pages' => PdfRejectReason.tooManyPages,
        'encrypted' => PdfRejectReason.encrypted,
        _ => PdfRejectReason.unknown,
      });
    case 'resource-exhausted':
      final resetsAt = details['resetsAt'];
      return PdfImportQuotaExhausted(
        scope: switch (details['scope']) {
          'week' => PdfQuotaScope.week,
          'day' => PdfQuotaScope.day,
          _ => PdfQuotaScope.unknown,
        },
        resetsAt: resetsAt is String ? DateTime.tryParse(resetsAt) : null,
      );
    case 'deadline-exceeded':
      return const PdfImportTimeout();
    default:
      return PdfImportInternal(code: e.code);
  }
}

/// El canal de plataforma entrega `Map<Object?, Object?>`; el lector del JSON
/// pide claves `String` en el primer nivel (los niveles de abajo los lee como
/// `Map` genérico).
Map<String, Object?> _stringKeys(Map raw) => {
      for (final e in raw.entries) e.key.toString(): e.value,
    };

/// Tope del nombre de la rutina importada: el default y lo que el PF escriba
/// en la vista previa. Las reglas no limitan `routines.name`; esto es para
/// que entre en una tarjeta.
const kPdfPlanNameMaxLength = 60;

final _pdfExtension = RegExp(r'\.pdf$', caseSensitive: false);
final _separators = RegExp(r'[_\-]+');
final _spaces = RegExp(r'\s+');

/// Lo que el sistema o el PF le cuelga al archivo y no es parte del nombre:
/// «(2)» de las copias del navegador y «final»/«FINAL», al final.
final _trailingNoise =
    RegExp(r'\s*(\(\d+\)|\bfinal)\s*$', caseSensitive: false);

/// Nombre inicial de la rutina a partir del archivo: sin la extensión, con
/// `_` y `-` como espacios, sin «(2)» ni «final» al final y con el largo
/// acotado. «plan_fuerza-FINAL (2).pdf» queda «plan fuerza».
@visibleForTesting
String planNameFromFileName(String fileName) {
  var name = fileName.trim().replaceFirst(_pdfExtension, '');
  name = name.replaceAll(_separators, ' ').replaceAll(_spaces, ' ').trim();
  while (true) {
    final next = name.replaceFirst(_trailingNoise, '').trim();
    if (next == name) break;
    name = next;
  }
  // En graphemes, como cuenta `TextField.maxLength`: cortar por unidades
  // UTF-16 parte un emoji a la mitad y deja un surrogate suelto en el nombre.
  if (name.characters.length > kPdfPlanNameMaxLength) {
    final cut = name.characters.take(kPdfPlanNameMaxLength).toString();
    final lastSpace = cut.lastIndexOf(' ');
    // Corta en la última palabra entera si no se pierde demasiado.
    name = (lastSpace > kPdfPlanNameMaxLength ~/ 2
            ? cut.substring(0, lastSpace)
            : cut)
        .trim();
  }
  return name.isEmpty ? 'Plan importado' : name;
}
