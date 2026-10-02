// Las claves `privacyPromoEmails*` y `privacyEntryTitle` — el texto del
// interruptor «Correos promocionales» de Perfil › Privacidad y del rótulo de
// la fila que lleva hasta ahí.
//
// Dos cosas se fijan acá:
//
//  1. El copy EXACTO en las tres lenguas. Es la promesa que se le hace al
//     usuario («los avisos de tu cuenta te siguen llegando» es cierto sólo
//     porque únicamente los mails con `prefKey` se frenan), así que una
//     reescritura «de estilo» no puede pasar sin que alguien lo decida.
//  2. Que ninguna de las cuatro cadenas hable de comprar. Es el binario móvil
//     y la Guideline 3.1.3 de Apple no deja que la app invite a pagar por otro
//     lado; el scan de `test/features/paywall/` busca frases enteras y no ve
//     palabras sueltas, así que éste mira las palabras.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/l10n/app_l10n.dart';

typedef _Textos = ({
  String entrada,
  String titulo,
  String subtitulo,
  String error,
});

Future<_Textos> _cargar(Locale locale) async {
  final l = await AppL10n.delegate.load(locale);
  return (
    entrada: l.privacyEntryTitle,
    titulo: l.privacyPromoEmailsTitle,
    subtitulo: l.privacyPromoEmailsSubtitle,
    error: l.privacyPromoEmailsSaveError,
  );
}

/// Palabras que le hablan al usuario de comprar, en las tres lenguas. `\b` a
/// los dos lados: «Pro» no puede dispararse con «Probá» ni con «promocionales».
final _prohibidas = RegExp(
  r'\b(plan(es)?|pagos?|pagar|pagá|suscripci[oó]n(es)?|suscrib\w*|precios?|'
  r'ofertas?|web|pro|payments?|pay|subscriptions?|subscribe|prices?|'
  r'offers?|upgrade)\b',
  caseSensitive: false,
);

void main() {
  test('es_AR: el copy exacto', () async {
    final t = await _cargar(const Locale('es', 'AR'));
    expect(t.entrada, 'Analítica y correos');
    expect(t.titulo, 'Correos promocionales');
    expect(
      t.subtitulo,
      'Si lo apagás, no te mandamos más. Los avisos de tu cuenta te siguen '
      'llegando.',
    );
    expect(t.error, 'No pudimos guardar el cambio. Intentá de nuevo.');
  });

  test('es: el copy exacto, en tuteo y no en voseo', () async {
    final t = await _cargar(const Locale('es'));
    expect(t.entrada, 'Analítica y correos');
    expect(t.titulo, 'Correos promocionales');
    expect(
      t.subtitulo,
      'Si lo desactivas, dejamos de enviártelos. Los avisos de tu cuenta te '
      'seguirán llegando.',
    );
    expect(t.error, 'No pudimos guardar el cambio. Inténtalo de nuevo.');
  });

  test('en: el copy exacto', () async {
    final t = await _cargar(const Locale('en'));
    expect(t.entrada, 'Analytics and emails');
    expect(t.titulo, 'Promotional emails');
    expect(
      t.subtitulo,
      "Turn it off and we'll stop sending them. Account notices still reach "
      'you.',
    );
    expect(t.error, "We couldn't save the change. Try again.");
  });

  for (final locale in const [Locale('es', 'AR'), Locale('es'), Locale('en')]) {
    test('$locale: ni el título ni el subtítulo ni el rótulo hablan de comprar',
        () async {
      final t = await _cargar(locale);
      for (final texto in [t.entrada, t.titulo, t.subtitulo, t.error]) {
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

  test('el guard de palabras prohibidas muerde (control)', () {
    // Sin esto, un regex que no matchea nada dejaría el test de arriba
    // verde para siempre.
    for (final mala in [
      'Mirá los planes',
      'Pagá en la web',
      'Tu suscripción',
      'El precio',
      'Una oferta',
      'Hazte Pro',
      'Choose a plan',
    ]) {
      expect(_prohibidas.hasMatch(mala), isTrue, reason: mala);
    }
    // Y no da falsos positivos con las palabras vecinas del copy real.
    for (final buena in ['Correos promocionales', 'Probá', 'Promotional']) {
      expect(_prohibidas.hasMatch(buena), isFalse, reason: buena);
    }
  });
}
