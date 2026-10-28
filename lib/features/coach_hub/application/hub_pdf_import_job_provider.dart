import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/periodized_import_draft.dart';
import '../data/plan_pdf_import_service.dart';
import 'plan_import_providers.dart';
import 'plan_pdf_import_providers.dart';

/// En qué está la lectura de PDF del Coach Hub. Una sola a la vez.
sealed class HubPdfImportJob {
  const HubPdfImportJob();
}

/// Nada en curso ni resultado por mostrar.
final class HubPdfImportIdle extends HubPdfImportJob {
  const HubPdfImportIdle();
}

/// `parsePlanPdf` está leyendo [fileName].
final class HubPdfImportReading extends HubPdfImportJob {
  const HubPdfImportReading(this.fileName);
  final String fileName;
}

/// Leído: el borrador ya está en [periodizedImportProvider], esperando que el
/// PF abra la vista previa.
final class HubPdfImportReady extends HubPdfImportJob {
  const HubPdfImportReady(this.fileName);
  final String fileName;
}

/// La lectura terminó mal. [failure] es el resultado tipado del servicio, que
/// la pantalla de subida muestra con su acción.
final class HubPdfImportFailed extends HubPdfImportJob {
  const HubPdfImportFailed({required this.fileName, required this.failure});
  final String fileName;
  final PdfImportResult failure;
}

/// La lectura de PDF del Coach Hub, FUERA del widget de subida.
///
/// Leer un PDF tarda hasta un par de minutos y el servidor descuenta el cupo
/// al empezar. Mientras la lectura vivía en el `State` de la pantalla, irse
/// por el sidebar, la top bar o el «atrás» del navegador (nada de eso pasa
/// por un `PopScope`) desmontaba la pantalla y el resultado, ya pagado, se
/// tiraba. Acá sobrevive a la pantalla: si el PF vuelve, ve la espera o el
/// resultado; si está en otra sección, el shell le avisa
/// (`HubPdfImportNotice`).
///
/// No es autoDispose: vive lo que vive el Hub. Se reinicia al cambiar de
/// cuenta (logout, otra sesión en la misma pestaña): un resultado que llega
/// después no se guarda, y un borrador listo que la lectura dejó se borra.
///
/// Sólo el Coach Hub lo usa; mobile sigue con su pantalla por alumno.
class HubPdfImportJobNotifier extends Notifier<HubPdfImportJob> {
  /// Sube con cada lectura y con cada reinicio: un resultado cuyo número ya
  /// no es el vigente se descarta.
  int _run = 0;

  /// Los bytes de la última lectura fallida, para «Reintentar» aunque el PF
  /// se haya ido y la pantalla ya no tenga el archivo.
  ({Uint8List bytes, String fileName})? _retry;

  /// El borrador que dejó la última lectura exitosa: al cambiar de cuenta se
  /// borra sólo si sigue siendo ESE (no pisa un Excel posterior).
  PeriodizedImportDraft? _draft;

  @override
  HubPdfImportJob build() {
    ref.listen<String?>(currentUidProvider, (previous, next) {
      if (previous != next) _resetForAccountChange();
    });
    return const HubPdfImportIdle();
  }

  bool get isReading => state is HubPdfImportReading;

  /// Hay con qué reintentar la última lectura fallida.
  bool get canRetry => state is HubPdfImportFailed && _retry != null;

  /// Empieza a leer. Con una lectura en curso no hace nada: una a la vez,
  /// aunque el PF salga y vuelva a la pantalla.
  Future<void> start({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (isReading) return;
    final run = ++_run;
    _retry = null;
    state = HubPdfImportReading(fileName);
    PdfImportResult result;
    try {
      // Sin alumno: el Hub los elige al asignar (el servidor no lo usa).
      result = await ref
          .read(planPdfImportServiceProvider)
          .importPdf(bytes: bytes, fileName: fileName);
    } catch (_) {
      // El servicio ya traduce sus errores; esto es para no quedar
      // «leyendo» para siempre si algo se escapa.
      result = const PdfImportInternal(code: 'unexpected');
    }
    // Cambió la cuenta mientras leía: el resultado no es de esta sesión.
    if (run != _run) return;
    if (result is PdfImportSuccess) {
      // Sin `forAthlete`, igual que el borrador del Excel: la vista previa
      // del Hub no mira el dueño y asigna a los alumnos que elija el PF.
      _draft = result.draft;
      ref.read(periodizedImportProvider.notifier).state = result.draft;
      state = HubPdfImportReady(fileName);
    } else {
      _retry = (bytes: bytes, fileName: fileName);
      state = HubPdfImportFailed(fileName: fileName, failure: result);
    }
  }

  /// «Reintentar» con los bytes de la última lectura fallida.
  Future<void> retry() async {
    final last = _retry;
    if (!canRetry || last == null) return;
    await start(bytes: last.bytes, fileName: last.fileName);
  }

  /// La pantalla (o el aviso) ya usó el resultado: vuelve a reposo. Con una
  /// lectura en curso no hace nada. El borrador queda en
  /// [periodizedImportProvider] hasta que se asigne o se descarte.
  void acknowledge() {
    if (isReading) return;
    _retry = null;
    state = const HubPdfImportIdle();
  }

  void _resetForAccountChange() {
    _run++;
    _retry = null;
    final draft = _draft;
    _draft = null;
    final store = ref.read(periodizedImportProvider.notifier);
    if (draft != null && identical(store.state, draft)) store.state = null;
    state = const HubPdfImportIdle();
  }
}

final hubPdfImportJobProvider =
    NotifierProvider<HubPdfImportJobNotifier, HubPdfImportJob>(
  HubPdfImportJobNotifier.new,
);
