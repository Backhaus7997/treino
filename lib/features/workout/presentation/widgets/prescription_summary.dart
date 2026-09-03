/// El resumen de una prescripción: `3 × 10 · 60 kg`, `4 × 1:30`, `3 × —`.
///
/// Es lo que [PrescriptionChips] muestra **con la tabla de series colapsada**,
/// y por lo tanto lo único que dice qué está prescripto cuando el detalle no
/// está en pantalla.
///
/// ## Por qué vive acá
///
/// Nació privado dentro de `routine_editor_screen.dart` y ahí quedó invisible
/// para el editor web del Coach Hub, que dibuja la misma card sobre el mismo
/// modelo. Dos pantallas formateando la misma prescripción por su cuenta
/// divergen — y en este repo eso ya pasó con la regla de agrupar superseries,
/// que vivía en la pantalla del teléfono y el companion de Wear no vio nunca
/// (ver el dartdoc de `superset_blocks.dart`).
///
/// **Pero esto NO es dominio.** Aquella regla define qué es un bloque de
/// entrenamiento; ésta arma un string para mostrar. Vive en `widgets/`, al lado
/// de [PrescriptionChips] que la consume, y no en `domain/` — donde además
/// habría invertido la dependencia, porque `secondsToMmss` es de presentación.
///
/// Opera sobre PRIMITIVOS y no sobre el modelo de ninguna de las dos pantallas
/// a propósito: el editor mobile tiene `_EditableSlot` y el web tiene
/// `_EditorSlot`, los dos privados.
library;

import '../../../../core/utils/kg_format.dart';
import '../../domain/set_enums.dart';
import 'duration_text_field.dart' show secondsToMmss;


/// Un set, reducido a lo que el resumen necesita.
typedef SetDeResumen = ({int? reps, int? durationSeconds, double? weightKg});

/// [unidadDePeso] entra por parámetro: este archivo no resuelve traducciones.
String resumenDePrescripcion({
  required ExerciseMode modo,
  required List<SetDeResumen> sets,
  required String unidadDePeso,
}) {
  final esDuracion = modo == ExerciseMode.duration;

  final medidas = esDuracion
      ? sets.map((s) => s.durationSeconds).toList()
      : sets.map((s) => s.reps).toList();
  final medida = _uniforme(medidas);
  final textoMedida = medida == null
      ? '—'
      : esDuracion
          ? _mmss(medida)
          : '$medida';

  final partes = <String>['${sets.length} × $textoMedida'];
  if (!esDuracion) {
    final peso = _uniforme(sets.map((s) => s.weightKg).toList());
    if (peso != null) {
      partes.add('${formatWeightKg(peso)} $unidadDePeso');
    } else if (sets.any((s) => s.weightKg != null)) {
      // Algunos sets tienen peso y otros no: el guión dice "no es uniforme",
      // que es distinto de "no hay peso" (peso corporal, sin unidad).
      partes.add('— $unidadDePeso');
    }
  }
  return partes.join(' · ');
}

/// El valor si TODOS son iguales, o null. Un `null` en la lista lo descarta
/// entero: con un set sin completar, el resumen no puede afirmar un número.
T? _uniforme<T>(List<T?> valores) {
  if (valores.isEmpty || valores.first == null) return null;
  final primero = valores.first;
  return valores.every((v) => v == primero) ? primero : null;
}

String _mmss(int segundos) {
  final texto = secondsToMmss(segundos);
  return texto.startsWith('0') ? texto.substring(1) : texto;
}
