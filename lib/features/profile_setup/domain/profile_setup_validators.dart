/// Validadores puros para los inputs del flow ProfileSetup. Devuelven `null`
/// cuando el valor es válido, o un mensaje de error en es-AR que la UI muestra
/// debajo del input.
///
/// Tono: imperativo rioplatense ("Ingresá", "Mínimo", "Máximo"), sin signos de
/// apertura, sin copy corporativo. Ver `docs/product.md` §Tono y voz.
class ProfileSetupValidators {
  ProfileSetupValidators._();

  /// Username permitido: 3-20 chars, letras / números / `_` / `.`. Sin espacios.
  static final RegExp _usernameRegex = RegExp(r'^[a-zA-Z0-9_.]+$');

  static String? validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) return 'Ingresá un username';
    final trimmed = value.trim();
    if (trimmed.length < 3) return 'Mínimo 3 caracteres';
    if (trimmed.length > 20) return 'Máximo 20 caracteres';
    if (!_usernameRegex.hasMatch(trimmed)) {
      return 'Solo letras, números, "_" y "."';
    }
    return null;
  }

  /// Peso corporal en kg. Acepta coma o punto decimal.
  static String? validateBodyWeightKg(String? value) {
    if (value == null || value.trim().isEmpty) return 'Ingresá tu peso';
    final n = double.tryParse(value.replaceAll(',', '.'));
    if (n == null) return 'Número inválido';
    if (n <= 20) return 'Mínimo 20 kg';
    if (n >= 300) return 'Máximo 300 kg';
    return null;
  }

  /// Altura en cm — entero. `UserProfile.heightCm` es `int?`.
  static String? validateHeightCm(String? value) {
    if (value == null || value.trim().isEmpty) return 'Ingresá tu altura';
    final n = int.tryParse(value.trim());
    if (n == null) return 'Número entero inválido';
    if (n <= 100) return 'Mínimo 100 cm';
    if (n >= 250) return 'Máximo 250 cm';
    return null;
  }
}
