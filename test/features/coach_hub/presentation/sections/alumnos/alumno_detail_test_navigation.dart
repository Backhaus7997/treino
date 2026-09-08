import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Navega la ficha del alumno por grupo y, si corresponde, por sub-vista.
///
/// Centraliza el conocimiento de los dos [TabBar] anidados para que un futuro
/// reagrupamiento no obligue a reescribir cada test de la pantalla.
Future<void> navigateAlumnoDetail(
  WidgetTester tester, {
  required String group,
  String? subview,
}) async {
  await _settle(tester);

  final primary = find.byType(TabBar).first;
  await tester.tap(
    find.descendant(of: primary, matching: find.text(group)),
  );
  await _settle(tester);

  if (subview == null) return;

  final secondary = find.byType(TabBar).last;
  await tester.tap(
    find.descendant(of: secondary, matching: find.text(subview)),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  } catch (_) {
    // Algunos providers de loading intencional no completan. Los frames ya
    // bombeados alcanzan para que la navegación y sus aserciones sean estables.
  }
}
