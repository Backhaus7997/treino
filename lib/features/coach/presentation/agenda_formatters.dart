/// Date and time formatting utilities for the Coach Agenda feature.
///
/// Extracted from [AgendaStrings] (ADR-I18N-003). These are pure utility
/// functions, NOT user-facing strings — they do not belong in ARB.
///
/// All DateTimes follow the Argentina single-TZ convention (ADR-7): stored
/// UTC values that REPRESENT Argentina wall-clock time directly. Fields are
/// read without `.toLocal()` to avoid the 3h offset.
abstract final class AgendaFormatters {
  /// Formats a [DateTime] as `dd/MM/yyyy`.
  static String formatDate(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year}';
  }

  /// Formats a [DateTime] as `HH:mm`.
  static String formatTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hh:$min';
  }

  /// ISO weekday → display label (1=Monday … 7=Sunday).
  static const Map<int, String> dayOfWeekLabels = {
    1: 'Lunes',
    2: 'Martes',
    3: 'Miércoles',
    4: 'Jueves',
    5: 'Viernes',
    6: 'Sábado',
    7: 'Domingo',
  };
}
