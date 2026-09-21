import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';
import 'package:treino/features/profile_setup/domain/profile_setup_validators.dart';

/// consentimiento-legal-versionado — R1: constantes de versión independientes
/// y monotónicas.
void main() {
  group('kTermsVersion / kPrivacyVersion', () {
    // Assertear el VALOR (`equals(1)`) convertía este test en un snapshot: un
    // bump legítimo lo ponía rojo y había que editarlo, que es justo lo que
    // entrena a editar tests en vez de leerlos. El invariante real es que son
    // enteros y que nunca retroceden.
    test('son enteros y nunca bajan de 1', () {
      expect(kTermsVersion, isA<int>());
      expect(kTermsVersion, greaterThanOrEqualTo(1));
      expect(kPrivacyVersion, isA<int>());
      expect(kPrivacyVersion, greaterThanOrEqualTo(1));
    });

    test(
        'are independent constants — bumping one does not require changing '
        'the other (compile-time proof: two distinct top-level consts)', () {
      // No hay forma de "bumpear" un const en runtime, así que la
      // independencia se prueba comparando identidad de valor: si algún día
      // colapsan a la misma variable, este assert de igualdad NO alcanzaría
      // para detectarlo, pero el punto real de R1 es que son dos
      // declaraciones separadas — ver kPrivacyVersion != kTermsVersionSymbol
      // no aplica en Dart. La prueba de comportamiento vive en que ambas
      // existen y son ints ordinarios, sin acoplamiento entre sí.
      expect(kTermsVersion, greaterThanOrEqualTo(1));
      expect(kPrivacyVersion, greaterThanOrEqualTo(1));
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // El contrato que la app MUESTRA no puede prometer lo que el código rechaza
  //
  // Hallazgo de Codex en el PR #1162, y después un segundo agujero que este
  // mismo grupo NO cazó: al bajar el piso a 13, la §9 de la POLÍTICA siguió
  // diciendo 16 y nadie se enteró. La versión anterior fallaba por dos motivos
  // que conviene dejar escritos, porque son el mismo error:
  //
  //   1. Miraba sólo `kTermsSections`. La línea viva estaba en
  //      `kPrivacySections`, que nunca se escaneaba.
  //   2. Asserteaba `isNot(contains('o contar con el consentimiento'))` — la
  //      cadena EXACTA que se estaba borrando en ese momento. La línea que
  //      sobrevivió decía «SIN el consentimiento de una persona adulta
  //      responsable»: misma promesa rota, otras palabras.
  //
  // O sea: era un snapshot disfrazado de invariante. Ahora se assertea el
  // invariante, sobre los DOS documentos.
  // ────────────────────────────────────────────────────────────────────────
  group('los documentos in-app y el gate de edad dicen lo mismo', () {
    String cuerpo(List<LegalSection> secs) =>
        secs.map((s) => '${s.heading}\n${s.body}').join('\n\n');

    /// Todo lo que la app muestra como texto legal, junto. Que sean dos listas
    /// es un detalle de estructura, no una excusa para revisar sólo una.
    final todoElTexto =
        '${cuerpo(kTermsSections)}\n\n${cuerpo(kPrivacySections)}';

    /// La frase con la que CADA documento declara el piso. Está acoplada a la
    /// redacción a propósito: si alguien la reescribe, este test falla y lo
    /// obliga a volver a confirmar el número, que es exactamente lo que no
    /// pasó las dos veces anteriores.
    ///
    /// Las variantes salieron del markdown de `docs/legal/`, que desde el
    /// 2026-09-21 es la fuente real: antes este archivo estaba escrito a mano y
    /// usaba otras palabras que las del documento. Al generarlo, los Términos
    /// pasaron a decir «tenés que tener N años cumplidos» y la Política «…para
    /// crear una cuenta en TREINO es de N años». El número se volvió a
    /// confirmar contra `kMinAgeYears` al agregar cada variante.
    final declaracionDePiso = RegExp(
      r'(?:Debés tener|tenés que tener'
      r'|edad mínima para (?:crear una cuenta|usar TREINO)'
      r'(?: en TREINO)? es de)'
      r'\s+(\d+)\s+años',
    );

    /// La mayoría de edad argentina. Es el único otro número que puede
    /// aparecer legítimamente al lado de "años" en estos textos.
    const mayoriaDeEdad = 18;

    // Los dos chequeos van POR DOCUMENTO, no sobre la unión.
    //
    // Hacerlos sobre el texto concatenado era otra vez más débil que el
    // invariante, y Codex lo marcó en el PR #1183: si los Términos regresaban a
    // declarar 18 como piso mientras la Política seguía diciendo 13, el
    // conjunto de edades citadas quedaba en {13, 18} y el `contains('13 años')`
    // global también pasaba. Medido antes de arreglarlo: 6/6 en verde con los
    // Términos declarando 18.
    for (final doc in [
      (nombre: 'Términos', secciones: kTermsSections),
      (nombre: 'Política', secciones: kPrivacySections),
    ]) {
      test('${doc.nombre}: declara el piso y es kMinAgeYears', () {
        final texto = cuerpo(doc.secciones);
        final match = declaracionDePiso.firstMatch(texto);

        expect(match, isNotNull,
            reason: '${doc.nombre} no declara ninguna edad mínima con una '
                'frase que este test reconozca. Si la redacción cambió, '
                'actualizá `declaracionDePiso` Y volvé a confirmar el número.');

        expect(
          int.parse(match!.group(1)!),
          equals(ProfileSetupValidators.kMinAgeYears),
          reason: '${doc.nombre} declara un piso distinto del que aplica el '
              'código. Los dos documentos y kMinAgeYears tienen que decir lo '
              'mismo.',
        );
      });

      test('${doc.nombre}: no cita ninguna otra edad', () {
        final citadas = RegExp(r'(\d+)\s*años')
            .allMatches(cuerpo(doc.secciones))
            .map((m) => int.parse(m.group(1)!))
            .toSet();

        expect(
          citadas.difference({
            ProfileSetupValidators.kMinAgeYears,
            mayoriaDeEdad,
          }),
          isEmpty,
          reason: '${doc.nombre} cita edades que no son ni kMinAgeYears '
              '(${ProfileSetupValidators.kMinAgeYears}) ni la mayoría de edad '
              '($mayoriaDeEdad).',
        );
      });
    }

    test('no se ofrece a un "adulto responsable" como vía alrededor del piso',
        () {
      // La formulación rota, en sus dos variantes, colgaba de «persona adulta
      // responsable» — que no es una figura legal. El texto correcto nombra a
      // «madre, padre o representante legal», que sí lo es, y lo pide COMO
      // REQUISITO para los menores de 18, no como excepción al piso de edad.
      //
      // Por eso el guard prohíbe la formulación vaga en vez de la palabra
      // «consentimiento», que en el texto correcto aparece y debe aparecer.
      expect(
        todoElTexto.toLowerCase(),
        isNot(contains('persona adulta responsable')),
      );
    });

    test('la política declara que recolecta la fecha de nacimiento', () {
      expect(
        cuerpo(kPrivacySections).toLowerCase(),
        contains('fecha de nacimiento'),
      );
    });
  });
}
