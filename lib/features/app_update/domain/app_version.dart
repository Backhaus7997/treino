/// Comparación de versiones para el gate de versión mínima.
///
/// Acepta `MAJOR`, `MAJOR.MINOR` o `MAJOR.MINOR.PATCH`, con sufijo de build
/// (`1.4.0+12`) y/o de pre-release (`1.4.0-beta.1`). Ambos sufijos se IGNORAN:
/// se compara solo el núcleo numérico. Es a propósito —
/// - el build number (`+57`) no es parte de lo que el equipo escribe como
///   mínimo («1.4.0»), y `PackageInfo.version` ni siquiera lo trae;
/// - un pre-release no se ordena contra su release en este gate: `1.4.0-beta`
///   se trata como `1.4.0`.
///
/// Todo lo que no sea parseable devuelve `null`, y el llamador lo trata como
/// «no sé» ⇒ NO bloquea (ver `UpdateRequirement`): una cadena rota en el
/// documento no puede dejar a nadie afuera de la app.
typedef AppVersion = ({int major, int minor, int patch});

final RegExp _formaDeVersion = RegExp(
  r'^(\d{1,9})(?:\.(\d{1,9}))?(?:\.(\d{1,9}))?(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
);

/// `null` si [raw] no es una versión válida.
AppVersion? parseAppVersion(String? raw) {
  if (raw == null) return null;
  final m = _formaDeVersion.firstMatch(raw.trim());
  if (m == null) return null;
  return (
    major: int.parse(m.group(1)!),
    minor: int.parse(m.group(2) ?? '0'),
    patch: int.parse(m.group(3) ?? '0'),
  );
}

/// Negativo si `a < b`, 0 si iguales, positivo si `a > b`. `null` si alguna
/// de las dos no se puede parsear.
int? compareAppVersions(String? a, String? b) {
  final va = parseAppVersion(a);
  final vb = parseAppVersion(b);
  if (va == null || vb == null) return null;
  if (va.major != vb.major) return va.major.compareTo(vb.major);
  if (va.minor != vb.minor) return va.minor.compareTo(vb.minor);
  return va.patch.compareTo(vb.patch);
}

/// `true` SOLO si ambas versiones son válidas y [installed] es estrictamente
/// menor que [minimum]. Cualquier duda ⇒ `false` (falla abierto).
bool isOlderThan(String? installed, String? minimum) {
  final c = compareAppVersions(installed, minimum);
  return c != null && c < 0;
}
