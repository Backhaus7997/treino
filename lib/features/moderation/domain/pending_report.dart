import 'package:flutter/foundation.dart';

/// Un reporte sin resolver, tal como lo devuelve `listPendingReports`.
///
/// DTO plano y no freezed a proposito: nace de un `Map` que devuelve una Cloud
/// Function, no se persiste, no se compara por valor en ningun lado, y sumar
/// una clase generada obliga a correr `build_runner` a quien toque esto.
@immutable
class PendingReport {
  const PendingReport({
    required this.id,
    required this.targetKind,
    required this.targetId,
    required this.targetOwnerUid,
    required this.reason,
    required this.reporterUid,
    required this.detail,
    required this.createdAt,
    required this.firstViewedAt,
    required this.contentPath,
  });

  /// Lee un item de la respuesta del callable.
  ///
  /// Tolerante por diseño: si el servidor agrega un campo, esto sigue
  /// funcionando; si saca uno, cae a un valor vacio en vez de explotar. Una
  /// cola de moderacion que no abre porque el servidor cambio una clave deja
  /// al equipo sin la herramienta justo cuando corre el reloj de las 24 horas.
  factory PendingReport.fromMap(Map<Object?, Object?> raw) {
    String texto(String clave) =>
        raw[clave] is String ? raw[clave]! as String : '';
    DateTime? fecha(String clave) {
      final v = raw[clave];
      return v is String ? DateTime.tryParse(v) : null;
    }

    return PendingReport(
      id: texto('id'),
      targetKind: texto('targetKind'),
      targetId: texto('targetId'),
      targetOwnerUid: texto('targetOwnerUid'),
      reason: texto('reason'),
      reporterUid: texto('reporterUid'),
      detail: raw['detail'] is String ? raw['detail']! as String : null,
      createdAt: fecha('createdAt'),
      firstViewedAt: fecha('firstViewedAt'),
      contentPath:
          raw['contentPath'] is String ? raw['contentPath']! as String : null,
    );
  }

  final String id;
  final String targetKind;
  final String targetId;
  final String targetOwnerUid;
  final String reason;
  final String reporterUid;

  /// Lo que escribio quien denuncio. Texto libre, puede citar lo que le
  /// dijeron — o sea datos de un tercero. No se loguea ni se manda por mail.
  final String? detail;

  final DateTime? createdAt;

  /// Cuando se MIRO por primera vez. Es la medida de la promesa publicada:
  /// las 24 horas son para revisar, no para resolver.
  final DateTime? firstViewedAt;

  /// Ruta del documento reportado, o `null` si no se pudo derivar.
  final String? contentPath;

  /// Horas desde que entro el reporte. `null` si no tiene fecha.
  int? get horasDesdeQueEntro {
    final creado = createdAt;
    if (creado == null) return null;
    return DateTime.now().toUtc().difference(creado.toUtc()).inHours;
  }

  /// `true` si ya paso el plazo prometido sin que nadie lo mirara.
  ///
  /// Mismo criterio que `moderationStats` del servidor: lo que se promete es
  /// REVISAR dentro de las 24 horas. Un reporte mirado en tiempo y todavia
  /// abierto no incumple nada — resolverlo puede requerir una decision.
  bool get rompioElPlazo {
    final creado = createdAt;
    if (creado == null) return false;
    final vencimiento = creado.toUtc().add(const Duration(hours: 24));
    final visto = firstViewedAt;
    if (visto == null) return DateTime.now().toUtc().isAfter(vencimiento);
    return visto.toUtc().isAfter(vencimiento);
  }
}
