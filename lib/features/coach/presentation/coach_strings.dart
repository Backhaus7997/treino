/// Static string shims for test finders — maps to ARB keys in AppL10n.
///
/// These constants exist so widget tests can find UI text without depending
/// on a localizations context. Values must stay in sync with intl_es_AR.arb.
abstract final class CoachStrings {
  /// AppL10n: coachEditorAddSlot
  static const editorAddSlot = 'Agregar ejercicio';

  /// AppL10n: coachEditorSubmit
  static const editorSubmit = 'ASIGNAR PLAN';
}
