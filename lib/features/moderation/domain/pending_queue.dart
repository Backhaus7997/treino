import 'package:flutter/foundation.dart';

import 'pending_report.dart';

/// Lo que devuelve la cola: los reportes Y si la lista esta completa.
@immutable
class PendingQueue {
  const PendingQueue({required this.reportes, required this.incompleta});

  final List<PendingReport> reportes;

  /// `true` cuando el servidor dejo de escanear antes de juntar los pedidos.
  ///
  /// Sin esto, una cola que se corto por el tope se ve EXACTAMENTE igual que
  /// una vacia — y "no hay reportes esperando" sobre reportes que si existen
  /// es la clase de mensaje tranquilizador que AGENTS.md 11.1 trata.
  final bool incompleta;
}
