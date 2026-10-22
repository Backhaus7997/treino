import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Los textos de la notificación de fin de descanso (#1617) se piden SIN
/// `BuildContext` —`lookupAppL10n` con el locale resuelto— porque se arman
/// cuando la app pasa a segundo plano. Tienen que existir y no estar vacíos en
/// los tres idiomas: una notificación sin texto es peor que ninguna.
void main() {
  for (final locale in const [
    Locale('es', 'AR'),
    Locale('es'),
    Locale('en'),
  ]) {
    test('$locale tiene título y cuerpo', () {
      final l10n = lookupAppL10n(locale);
      expect(l10n.sessionRestEndedTitle.trim(), isNotEmpty);
      expect(l10n.sessionRestEndedBody.trim(), isNotEmpty);
    });
  }

  test('es-AR: corto y directo, con voseo', () {
    final l10n = lookupAppL10n(const Locale('es', 'AR'));
    expect(l10n.sessionRestEndedTitle, 'Terminó el descanso');
    expect(l10n.sessionRestEndedBody, 'Volvé a la serie');
  });
}
