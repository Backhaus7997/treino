import 'package:flutter/material.dart';

/// Valida [formKey] y, si hay errores, lleva la pantalla hasta el PRIMERO.
///
/// `FormState.validate()` pinta el error pero no se mueve: en un formulario
/// largo el campo inválido queda fuera de pantalla y tocar GUARDAR parece no
/// hacer nada (#1499). Esto agrega las dos mitades que faltan: scrollea hasta
/// el primer `FormField` con error (en orden de árbol, o sea de arriba abajo)
/// y, si es un campo de texto, le pide el foco.
///
/// Devuelve `true` si el formulario es válido, igual que `validate()`. Un
/// [formKey] sin montar cuenta como válido: el caller decide qué hacer.
bool validateAndRevealFirstError(GlobalKey<FormState> formKey) {
  final form = formKey.currentState;
  if (form == null) return true;
  if (form.validate()) return true;

  final first = _firstFieldWithError(formKey.currentContext);
  if (first != null && first.context.mounted) {
    Scrollable.ensureVisible(
      first.context,
      alignment: 0.1,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    _requestTextFocus(first.context);
  }
  return false;
}

FormFieldState<dynamic>? _firstFieldWithError(BuildContext? root) {
  if (root == null) return null;
  FormFieldState<dynamic>? found;
  void visit(Element element) {
    if (found != null) return;
    if (element is StatefulElement) {
      final state = element.state;
      if (state is FormFieldState<dynamic> && state.hasError) {
        found = state;
        return;
      }
    }
    element.visitChildren(visit);
  }

  (root as Element).visitChildren(visit);
  return found;
}

void _requestTextFocus(BuildContext fieldContext) {
  var done = false;
  void visit(Element element) {
    if (done) return;
    if (element is StatefulElement) {
      final state = element.state;
      if (state is EditableTextState) {
        state.requestKeyboard();
        done = true;
        return;
      }
    }
    element.visitChildren(visit);
  }

  (fieldContext as Element).visitChildren(visit);
}
