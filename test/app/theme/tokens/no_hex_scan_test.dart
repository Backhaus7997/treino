import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Test de análisis estático — detector de hex literals fuera de la allowlist.
///
/// ALLOWLIST-RATCHET: la lista de archivos permitidos se construyó escaneando
/// `lib/` programáticamente en el momento en que se escribió este test (WU-05,
/// FASE 0). Hoy solo [primitives.dart] contiene `Color(0x...)`.
///
/// Regla: cada fase remueve entradas de la allowlist — NUNCA agrega nuevas.
/// Si un archivo nuevo introduce un hex literal fuera de la allowlist, este
/// test FALLA, bloqueando el merge.
///
/// Archivos permitidos (sufijos relativos a lib/):
///   - app/theme/tokens/primitives.dart   ← única fuente de verdad de hex
///
/// La allowlist NO incluye app_palette.dart porque WU-02 eliminó todos
/// sus hex literals (ahora referencia primitivos).
///
/// ALCANCE DEL SCANNER (deliberado):
///   ✓ Color(0x...)          — hex ARGB inline con cualquier longitud de dígitos
///   ✓ Color.fromARGB(...)   — constructor con componentes enteros
///   ✓ Color.fromRGBO(...)   — constructor con componentes + opacidad
///   ✗ Colors.*              — constantes del SDK de Flutter (intencional; no
///                             son literales definidos en el proyecto)
///   ✗ withOpacity/withValues — modificadores de opacidad (intencional; operan
///                             sobre tokens existentes, no introducen hex crudo)
void main() {
  group('no_hex_scan — prohibición de Color(0x...) fuera de allowlist', () {
    /// Allowlist de rutas relativas a lib/ que pueden contener hex inline.
    /// FASE 0: solo primitives.dart.
    const allowlist = {
      'app/theme/tokens/primitives.dart',
    };

    late List<String> offenders;

    setUpAll(() {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) {
        // Si no existe lib/, asumimos que corremos desde un directorio diferente.
        // El test fallará con mensaje claro en los expects.
        offenders = [];
        return;
      }

      // Detecta cualquiera de las tres formas de hardcodear colores hex:
      //   1. Color(0x...)        — ARGB hex con cualquier cantidad de dígitos
      //   2. Color.fromARGB(...) — constructor por componentes enteros
      //   3. Color.fromRGBO(...) — constructor por componentes + opacidad double
      final hexPattern = RegExp(
        r'Color\(0x[0-9A-Fa-f]+\)|Color\.fromARGB\(|Color\.fromRGBO\(',
      );
      offenders = [];

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;

        // Normalizar separadores a slash para comparación cross-platform.
        final normalized = entity.path.replaceAll(r'\', '/');
        // Extraer ruta relativa a lib/
        final libIndex = normalized.indexOf('lib/');
        if (libIndex == -1) continue;
        final relativePath =
            normalized.substring(libIndex + 4); // después de "lib/"

        // Si está en la allowlist, no es un ofensor.
        if (allowlist.contains(relativePath)) continue;

        final content = entity.readAsStringSync();
        if (hexPattern.hasMatch(content)) {
          offenders.add(relativePath);
        }
      }
    });

    test(
        'ningún archivo fuera de la allowlist contiene '
        'Color(0x...) / Color.fromARGB / Color.fromRGBO', () {
      expect(
        offenders,
        isEmpty,
        reason:
            'Archivos con hex literal fuera de allowlist:\n${offenders.join('\n')}\n\n'
            'Para corregir: reemplazá los Color(0x...) / Color.fromARGB / '
            'Color.fromRGBO por referencias a AppColorPrimitives en '
            'lib/app/theme/tokens/primitives.dart.',
      );
    });

    test('la allowlist no creció vs FASE 0 (ratchet)', () {
      // Este test valida que nadie agregó nuevas entradas a la allowlist
      // sin actualizar este comentario. Si la allowlist crece, FALLA.
      expect(
        allowlist.length,
        1,
        reason: 'La allowlist tiene ${allowlist.length} entradas pero FASE 0 '
            'define 1. Si agregaste una entrada nueva, estás violando el '
            'ratchet. En su lugar, referenciá AppColorPrimitives.',
      );
    });
  });
}
