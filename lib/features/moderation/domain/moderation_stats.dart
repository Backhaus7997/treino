import 'package:flutter/foundation.dart';

/// Cuantos reportes esperan y cuanto hace que espera el mas viejo.
///
/// Existe para poder PROBAR que se cumple la promesa de
/// `docs/legal/normas-de-comunidad.md:123` en vez de afirmarla. Una promesa
/// publica sin forma de medirla es una afirmacion sin verificar.
@immutable
class ModerationStats {
  const ModerationStats({
    required this.pending,
    required this.oldestPendingHours,
    required this.breachingSla,
  });

  factory ModerationStats.fromMap(Map<Object?, Object?> raw) => ModerationStats(
        pending: raw['pending'] is int ? raw['pending']! as int : 0,
        oldestPendingHours: raw['oldestPendingHours'] is int
            ? raw['oldestPendingHours']! as int
            : null,
        breachingSla:
            raw['breachingSla'] is int ? raw['breachingSla']! as int : 0,
      );

  final int pending;
  final int? oldestPendingHours;

  /// Cuantos pendientes ya rompieron las 24 horas. Si esto no es cero, la
  /// promesa publicada esta incumplida AHORA.
  final int breachingSla;
}
