// Las claves `privacyTrainingReminders*` — el texto del interruptor
// «Recordatorios de entrenamiento» de Perfil › Privacidad (sólo atleta).
//
// Hermano de `privacy_promo_emails_l10n_test.dart`, por los mismos dos motivos:
//
//  1. El copy EXACTO en las tres lenguas. Es la promesa que se le hace al
//     atleta sobre qué avisos le llegan (racha en riesgo, volvé a entrenar); si
//     el backend suma un tercer aviso, el subtítulo tiene que cubrirlo y eso lo
//     decide una persona, no un retoque «de estilo».
//  2. Que ninguna cadena hable de comprar. Es el binario móvil y la Guideline
//     3.1.3 de Apple no deja que la app invite a pagar por otro lado.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/l10n/app_l10n.dart';

typedef _Textos = ({String titulo, String subtitulo, String error});

Future<_Textos> _cargar(Locale locale) async {
  final l = await AppL10n.delegate.load(locale);
  return (
    titulo: l.privacyTrainingRemindersTitle,
    subtitulo: l.privacyTrainingRemindersSubtitle,
    error: l.privacyTrainingRemindersSaveError,
  );
}

/// Mismas palabras que el test de correos promocionales: las que le hablan al
/// usuario de comprar, en las tres lenguas.
final _prohibidas = RegExp(
  r'\b(plan(es)?|pagos?|pagar|pagá|suscripci[oó]n(es)?|suscrib\w*|precios?|'
  r'ofertas?|web|pro|payments?|pay|subscriptions?|subscribe|prices?|'
  r'offers?|upgrade)\b',
  caseSensitive: false,
);

void main() {
  test('es_AR: el copy exacto, en voseo', () async {
    final t = await _cargar(const Locale('es', 'AR'));
    expect(t.titulo, 'Recordatorios de entrenamiento');
    expect(
      t.subtitulo,
      'Te avisamos si tu racha está en riesgo o si hace días que no entrenás.',
    );
    expect(t.error, 'No pudimos guardar el cambio. Intentá de nuevo.');
  });

  test('es: el copy exacto, en tuteo y no en voseo', () async {
    final t = await _cargar(const Locale('es'));
    expect(t.titulo, 'Recordatorios de entrenamiento');
    expect(
      t.subtitulo,
      'Te avisamos si tu racha está en riesgo o si llevas días sin entrenar.',
    );
    expect(t.error, 'No pudimos guardar el cambio. Inténtalo de nuevo.');
  });

  test('en: el copy exacto', () async {
    final t = await _cargar(const Locale('en'));
    expect(t.titulo, 'Training reminders');
    expect(
      t.subtitulo,
      "We'll let you know if your streak is at risk or you haven't trained in "
      'a few days.',
    );
    expect(t.error, "We couldn't save the change. Try again.");
  });

  for (final locale in const [Locale('es', 'AR'), Locale('es'), Locale('en')]) {
    test('$locale: ninguna cadena habla de comprar', () async {
      final t = await _cargar(locale);
      for (final texto in [t.titulo, t.subtitulo, t.error]) {
        expect(
          _prohibidas.hasMatch(texto),
          isFalse,
          reason: '«$texto» nombra algo de la lista anti-steering '
              '(${_prohibidas.firstMatch(texto)?.group(0)}): la app no puede '
              'mencionar planes, pagos ni precios (Guideline 3.1.3)',
        );
      }
    });
  }
}
