// Shared top-level helpers for the Agenda web feature.
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).

/// Devuelve true si [day] es estrictamente antes de hoy (nivel de fecha, TZ local).
bool isDayPast(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DateTime(day.year, day.month, day.day).isBefore(today);
}

/// True si [name] parece un UID raw (≥20 chars, sin espacios, alfanumérico).
/// Mirror de la lógica en day_timeline.dart:323-327.
bool isRawUid(String name) =>
    name.length >= 20 &&
    !name.contains(' ') &&
    RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name);

/// Iniciales de [name] (máx 2 chars).
String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}

// Fechas en español sin depender de initializeDateFormatting. // i18n
const spanishWeekdays = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];
const spanishMonths = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// "Martes 30 de junio". // i18n
String spanishDayLabel(DateTime d) =>
    '${spanishWeekdays[d.weekday - 1]} ${d.day} de ${spanishMonths[d.month - 1]}';
