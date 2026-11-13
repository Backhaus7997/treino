/// Pure validators — no Flutter binding.
class EmailPasswordValidator {
  EmailPasswordValidator._();

  static const _emailRegex = r'^[^\s@]+@[^\s@]+\.[^\s@]+$';

  /// Returns null if valid, error message if invalid.
  ///
  /// Valida el email YA recortado: los espacios de los bordes no son parte de la
  /// dirección. El autocompletado del teclado suele dejar uno al final, y las
  /// pantallas igual mandan `.trim()` a Firebase, así que rechazarlo acá
  /// bloqueaba un mail que después se iba a enviar bien (#1698). Los espacios
  /// de ADENTRO siguen siendo inválidos.
  static String? validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'El email no es válido';
    if (!RegExp(_emailRegex).hasMatch(email)) return 'El email no es válido';
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
