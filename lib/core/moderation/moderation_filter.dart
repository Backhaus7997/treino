import 'vetted_terms.g.dart';

/// Que hacer con un texto que el usuario esta por publicar.
enum ModerationVerdict {
  /// Pasa.
  ok,

  /// Pasa, pero genera un reporte automatico para la cola de moderacion.
  review,

  /// No se puede enviar.
  block,
}

/// Filtrado de terminos vetados.
///
/// Cuarto requisito de la App Store Review Guideline 1.2: *"a method for
/// filtering objectionable material from being posted to the app"*. Los otros
/// tres —reportar, bloquear y contacto publicado— ya estaban.
///
/// ## Dos capas, y las dos hacen falta
///
/// Esta es la del cliente, y es la que tecnicamente satisface la guideline:
/// el contenido no llega a postearse, y el usuario se entera al instante sin
/// esperar al servidor. Pero el cliente se saltea con el SDK directo, asi que
/// hay un espejo en `functions/src/moderation/` que pone en cuarentena lo que
/// paso igual.
///
/// Las reglas de Firestore NO participan: no tienen bucles, no pueden leer
/// una lista externa, y el archivo tiene tope de 256 KiB — que este repo ya
/// cruzo una vez, por cinco bytes.
///
/// ## El espejo no se escribe dos veces
///
/// Las listas, los mapas de plegado y de leet, y el corpus de conformidad
/// salen los dos de `assets/moderation/terminos-vetados.json` en la misma
/// corrida de `scripts/build_moderation_list.py`. Lo unico escrito dos veces
/// es este algoritmo, y es lo que el corpus de `kVettedCases` vigila: las dos
/// suites corren los mismos casos y comparan contra las mismas expectativas.
abstract final class ModerationFilter {
  const ModerationFilter._();

  /// El veredicto para [text].
  ///
  /// NO dice que termino lo disparo, a proposito. Devolverlo convierte al
  /// filtro en un oraculo: quien quiera evadirlo prueba variantes hasta que
  /// deja de saltar, y el mensaje le dice exactamente cuando lo logro.
  static ModerationVerdict check(String text) {
    final tokens = _tokens(normalize(text));
    if (tokens.isEmpty) return ModerationVerdict.ok;

    // --- Pasada A: palabra completa -------------------------------------
    //
    // Por palabra y no por subcadena porque `musculo` contiene `culo` y
    // `computadora` contiene `puta`. Con `contains()` se bloquean las dos, y
    // en una app de entrenamiento `musculo` aparece en cada rutina.
    for (final t in tokens) {
      if (kVettedBlockWords.contains(t)) return ModerationVerdict.block;
    }
    if (_hasPhrase(tokens, kVettedBlockPhrases)) return ModerationVerdict.block;

    // --- Pasada B: antievasion ------------------------------------------
    if (_evades(tokens)) return ModerationVerdict.block;

    // --- Pasada C: letras sueltas ---------------------------------------
    final deletreado = _spelledOut(tokens);
    if (deletreado == ModerationVerdict.block) return ModerationVerdict.block;

    // --- Pasada A, severidad `review` ------------------------------------
    for (final t in tokens) {
      if (kVettedReviewWords.contains(t)) return ModerationVerdict.review;
    }
    if (_hasPhrase(tokens, kVettedReviewPhrases)) {
      return ModerationVerdict.review;
    }

    return deletreado ?? ModerationVerdict.ok;
  }

  /// Minuscula, sin diacriticos, sin leet y sin repeticiones.
  ///
  /// Publico porque los tests lo miden aparte del veredicto: cuando un caso
  /// del corpus falla, saber en que quedo el texto es la diferencia entre
  /// arreglarlo y adivinar.
  static String normalize(String text) =>
      _collapse(_leet(_fold(text.toLowerCase())));

  // -- pasos de la normalizacion ------------------------------------------

  static String _fold(String s) {
    final out = StringBuffer();
    for (final rune in s.runes) {
      // Las marcas combinantes se DESCARTAN, no se traducen. El mapa de
      // plegado solo cubre caracteres precompuestos, asi que el mismo texto
      // llegado descompuesto —`u` seguido de U+0301 en vez de `ú`— conservaba
      // la marca, que no es `[0-9a-z]` y por lo tanto partia el token en dos:
      // `púto` escrito descompuesto daba `['pu','to']` y pasaba, mientras que
      // el precompuesto se bloqueaba. Los dos se ven IDENTICOS en pantalla.
      if (_isCombining(rune)) continue;
      final ch = String.fromCharCode(rune);
      out.write(kVettedFold[ch] ?? ch);
    }
    return out.toString();
  }

  static bool _isCombining(int rune) {
    for (var i = 0; i < kVettedCombiningRanges.length; i += 2) {
      if (rune < kVettedCombiningRanges[i]) return false;
      if (rune <= kVettedCombiningRanges[i + 1]) return true;
    }
    return false;
  }

  static String _leet(String s) {
    final chars = [for (final r in s.runes) String.fromCharCode(r)];
    final out = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      final ch = chars[i];
      final rep = kVettedLeet[ch];
      if (rep == null) {
        out.write(ch);
        continue;
      }
      // `!` solo se traduce con letra a los DOS lados. Sin esa regla `puta!`
      // normaliza a `putai`, que no matchea `puta` por palabra completa: el
      // leet a lo bruto produce falsos NEGATIVOS sobre el texto mas comun que
      // existe, un insulto con signo de exclamacion. `@` y `$` se traducen
      // siempre — ver `LEET_SOLO_ENTRE_LETRAS` en el generador.
      if (kVettedLeetOnlyBetweenLetters.contains(ch)) {
        final antes = i > 0 && _isAlnum(chars[i - 1]);
        final despues = i + 1 < chars.length && _isAlnum(chars[i + 1]);
        out.write(antes && despues ? rep : ch);
      } else {
        out.write(rep);
      }
    }
    return out.toString();
  }

  static String _collapse(String s) {
    final chars = [for (final r in s.runes) String.fromCharCode(r)];
    final out = StringBuffer();
    var i = 0;
    while (i < chars.length) {
      var j = i;
      while (j < chars.length && chars[j] == chars[i]) {
        j++;
      }
      final largo = j - i;
      out.write(largo >= kVettedCollapseMin ? chars[i] : chars[i] * largo);
      i = j;
    }
    return out.toString();
  }

  static bool _isAlnum(String ch) {
    if (ch.length != 1) return false;
    final c = ch.codeUnitAt(0);
    return (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x7a);
  }

  static final RegExp _separadores = RegExp(r'[^0-9a-z]+');

  static List<String> _tokens(String normalized) =>
      normalized.split(_separadores).where((t) => t.isNotEmpty).toList();

  // -- las dos pasadas -----------------------------------------------------

  static bool _hasPhrase(List<String> tokens, List<List<String>> phrases) {
    for (final phrase in phrases) {
      if (phrase.length > tokens.length) continue;
      for (var i = 0; i + phrase.length <= tokens.length; i++) {
        var match = true;
        for (var j = 0; j < phrase.length; j++) {
          if (tokens[i + j] != phrase[j]) {
            match = false;
            break;
          }
        }
        if (match) return true;
      }
    }
    return false;
  }

  /// La pasada antievasion.
  ///
  /// Hace dos cosas, y es importante lo que NO hace:
  ///
  /// 1. Junta las corridas de tokens de UN caracter. `p u t o` y `p-u-t-o`
  ///    dan cuatro tokens de un caracter, y pegados dan `puto`.
  /// 2. Busca cada termino de `kVettedAntiEvasion` como subcadena de cada
  ///    token, salteando los que estan en `kVettedAllowlist`.
  ///
  /// Lo que no hace es pegar el texto entero. Esa version —la obvia— bloquea
  /// `otro loco`, porque `otroloco` contiene `trolo`. Tambien `otro lote`.
  /// Los dos son castellano rioplatense corriente y los dos estan en el
  /// corpus.
  static bool _evades(List<String> tokens) {
    final candidatos = <String>[];
    final corrida = <String>[];

    void cerrarCorrida() {
      if (corrida.length > 1) candidatos.add(corrida.join());
      corrida.clear();
    }

    for (final t in tokens) {
      // Se pega con el anterior solo si LOS DOS son cortos.
      //
      // Antes se pegaban unicamente las corridas de UN caracter, y `pu-to` o
      // `p-uto` se escapaban: dos fragmentos de dos y tres letras, ninguno de
      // largo 1, asi que no se juntaban y ninguno contenia el termino. Un
      // separador salteaba la capa entera.
      final corto = t.length <= kVettedJoinMaxFragment;
      final anteriorCorto =
          corrida.isNotEmpty && corrida.last.length <= kVettedJoinMaxFragment;

      if (corto && (corrida.isEmpty || anteriorCorto)) {
        corrida.add(t);
        continue;
      }
      cerrarCorrida();
      // La allowlist no puede aportar letras a un match: `computo` contiene
      // `puto` y `controlo` contiene `trolo`, y las dos son palabras normales.
      if (!kVettedAllowlist.contains(t)) candidatos.add(t);
      if (corto) corrida.add(t);
    }
    cerrarCorrida();

    for (final c in candidatos) {
      for (final termino in kVettedAntiEvasion) {
        if (c.contains(termino)) return true;
      }
    }
    return false;
  }

  /// Las frases vetadas sin espacios: `hijo de puta` -> `hijodeputa`. Es la
  /// forma en que quedan cuando se escriben con todas las letras separadas.
  static final List<String> _compactBlockPhrases = [
    for (final p in kVettedBlockPhrases) p.join(),
  ];
  static final List<String> _compactReviewPhrases = [
    for (final p in kVettedReviewPhrases) p.join(),
  ];

  /// La pasada de las letras sueltas.
  ///
  /// `p i j a`, `p-i-j-a` y `h.i.j.o d.e p.u.t.a` dan puros tokens de UNA
  /// letra. La pasada B ya los pega, pero solo los compara contra
  /// `kVettedAntiEvasion`, que es chico a proposito —`pija`, `culo` y `puta`
  /// no estan, porque por subcadena bloquearian `pijama`, `musculo` y
  /// `computadora`—. Asi que cualquier termino fuera de ese subconjunto
  /// pasaba entero escrito letra por letra.
  ///
  /// Aca se compara contra la lista COMPLETA, y por subcadena, pero solo
  /// sobre corridas de tokens de UN caracter. Esa restriccion es la que hace
  /// seguro lo que en la pasada B no lo es: el castellano no produce corridas
  /// de letras sueltas —`musculo` es un token de siete, no siete de uno—, asi
  /// que la subcadena no tiene palabras legitimas contra las que chocar. Por
  /// subcadena y no exacto para que una letra legitima pegada adelante —`y p
  /// u t a`— no alcance para salvarla.
  ///
  /// NO se extiende a fragmentos de dos o tres letras, como la pasada B: `por
  /// no` pegado da `porno`. Ese es el precio de no bloquear castellano
  /// corriente.
  ///
  /// Devuelve la severidad del peor termino encontrado, o `null` si no hay
  /// ninguno.
  static ModerationVerdict? _spelledOut(List<String> tokens) {
    final corridas = <String>[];
    final actual = StringBuffer();
    var largo = 0;

    void cerrar() {
      if (largo > 1) corridas.add(actual.toString());
      actual.clear();
      largo = 0;
    }

    for (final t in tokens) {
      if (t.length == 1) {
        actual.write(t);
        largo++;
      } else {
        cerrar();
      }
    }
    cerrar();
    if (corridas.isEmpty) return null;

    bool contiene(Iterable<String> terminos) =>
        corridas.any((c) => terminos.any(c.contains));

    if (contiene(kVettedBlockWords) || contiene(_compactBlockPhrases)) {
      return ModerationVerdict.block;
    }
    if (contiene(kVettedReviewWords) || contiene(_compactReviewPhrases)) {
      return ModerationVerdict.review;
    }
    return null;
  }
}
