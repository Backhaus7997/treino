/// Static string shims for test finders — maps to ARB keys in AppL10n.
///
/// These constants exist so widget tests can find UI text without depending
/// on a localizations context. Values must stay in sync with intl_es_AR.arb.
abstract final class WorkoutStrings {
  /// AppL10n: workoutPickerAddButton ICU plural
  /// "Agregar {count} {count, plural, =1{ejercicio} other{ejercicios}}"
  static String pickerAddButton(int count) {
    final noun = count == 1 ? 'ejercicio' : 'ejercicios';
    return 'Agregar $count $noun';
  }
}
