import 'package:flutter/foundation.dart';

/// Clave de familia para `sessionNotifierProvider`.
///
/// Sealed para garantizar un `switch` exhaustivo en `SessionNotifier.build()`.
/// Diseño §3.1 — ADR-SP-11.
@immutable
sealed class SessionInit {
  const SessionInit();
}

/// Inicia una sesión nueva para la rutina y día dados.
final class FreshSession extends SessionInit {
  const FreshSession({
    required this.routineId,
    required this.dayNumber,
    this.weekNumber = 0,
  });

  final String routineId;
  final int dayNumber;

  /// 0-based week of the plan this session belongs to.
  /// Default 0 keeps single-week backward-compat (REQ-PERIOD-038).
  final int weekNumber;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreshSession &&
          other.routineId == routineId &&
          other.dayNumber == dayNumber &&
          other.weekNumber == weekNumber;

  @override
  int get hashCode => Object.hash(routineId, dayNumber, weekNumber);
}

/// Retoma una sesión activa existente por su id.
final class ResumeSession extends SessionInit {
  const ResumeSession({required this.sessionId});

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResumeSession && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}
