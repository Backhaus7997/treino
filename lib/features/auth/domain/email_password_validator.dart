/// Pure validators — no Flutter binding.
class EmailPasswordValidator {
  EmailPasswordValidator._();

  static const _emailRegex = r'^[^\s@]+@[^\s@]+\.[^\s@]+$';

  /// Returns null if valid, error message if invalid.
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'El email no es válido';
    if (!RegExp(_emailRegex).hasMatch(value)) return 'El email no es válido';
    return null;
  }

  /// Returns null if valid, error message if invalid.
  /// Rules: ≥8 chars, ≥1 letter [A-Za-z], ≥1 digit [0-9].
  static String? validatePassword(String? value) {
    const msg =
        'La contraseña debe tener al menos 8 caracteres, una letra y un número';
    if (value == null || value.isEmpty) return msg;
    if (value.length < 8) return msg;
    if (!value.contains(RegExp(r'[A-Za-z]'))) return msg;
    if (!value.contains(RegExp(r'[0-9]'))) return msg;
    return null;
  }

  /// Returns null if equal, error message otherwise.
  static String? validatePasswordMatch(String? password, String? confirm) {
    if (password != confirm) return 'Las contraseñas no coinciden';
    return null;
  }
}
