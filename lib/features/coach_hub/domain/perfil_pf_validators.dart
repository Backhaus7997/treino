// Validadores del perfil profesional del PF. Fuente única para las tarjetas
// del Hub (`IdentidadCard`, `EspecialidadPrecioCard`) y el onboarding: mismos
// rangos y mismos mensajes que `profile_edit_trainer_screen.dart`.

const int kBioMinLength = 20;
const int kBioMaxLength = 280;
const int kPrecioMinimo = 500;
const int kPrecioMaximo = 999999;

/// Bio no vacía, de [kBioMinLength] a [kBioMaxLength] caracteres (recortada).
/// Devuelve el mensaje de error, o null si es válida.
String? validarBio(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return 'Escribí una bio.'; // i18n: Fase 11
  if (value.length < kBioMinLength) {
    return 'Al menos $kBioMinLength caracteres.'; // i18n: Fase 11
  }
  if (value.length > kBioMaxLength) {
    return 'Máximo $kBioMaxLength caracteres.'; // i18n: Fase 11
  }
  return null;
}

/// Tarifa mensual entera entre [kPrecioMinimo] y [kPrecioMaximo].
/// Devuelve el mensaje de error, o null si es válida.
String? validarPrecio(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return 'Ingresá un precio.'; // i18n: Fase 11
  final n = int.tryParse(value);
  if (n == null) return 'Ingresá un número entero.'; // i18n: Fase 11
  if (n < kPrecioMinimo) return 'Mínimo \$$kPrecioMinimo.'; // i18n: Fase 11
  if (n > kPrecioMaximo) return 'Máximo \$$kPrecioMaximo.'; // i18n: Fase 11
  return null;
}
