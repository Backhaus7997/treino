/// Validadores puros para los inputs del flow ProfileSetup. Devuelven `null`
/// cuando el valor es válido, o un mensaje de error en es-AR que la UI muestra
/// debajo del input.
///
/// Tono: imperativo rioplatense ("Ingresá", "Mínimo", "Máximo"), sin signos de
/// apertura, sin copy corporativo. Ver `docs/product.md` §Tono y voz.
class ProfileSetupValidators {
  ProfileSetupValidators._();

  /// Username permitido: 3-20 chars, letras / números / `_` / `.`. Sin espacios.
  static final RegExp _usernameRegex = RegExp(r'^[a-zA-Z0-9_.]+$');

  static String? validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) return 'Ingresá un username';
    final trimmed = value.trim();
    if (trimmed.length < 3) return 'Mínimo 3 caracteres';
    if (trimmed.length > 20) return 'Máximo 20 caracteres';
    if (!_usernameRegex.hasMatch(trimmed)) {
      return 'Solo letras, números, "_" y "."';
    }
    return null;
  }

  /// Peso corporal en kg. Acepta coma o punto decimal.
  static String? validateBodyWeightKg(String? value) {
    if (value == null || value.trim().isEmpty) return 'Ingresá tu peso';
    final n = double.tryParse(value.replaceAll(',', '.'));
    if (n == null) return 'Número inválido';
    if (n <= 20) return 'Mínimo 20 kg';
    if (n >= 300) return 'Máximo 300 kg';
    return null;
  }

  /// Altura en cm — entero. `UserProfile.heightCm` es `int?`.
  static String? validateHeightCm(String? value) {
    if (value == null || value.trim().isEmpty) return 'Ingresá tu altura';
    final n = int.tryParse(value.trim());
    if (n == null) return 'Número entero inválido';
    if (n <= 100) return 'Mínimo 100 cm';
    if (n >= 250) return 'Máximo 250 cm';
    return null;
  }

  /// Edad mínima de cuenta, en años cumplidos.
  /// Ver `docs/legal/terminos-y-condiciones.md` §3.
  ///
  /// **13 y no menos**: COPPA, en los Estados Unidos, alcanza a los menores de
  /// 13 y les exige un consentimiento parental VERIFICABLE que TREINO no
  /// implementa. Con este piso, ningún usuario queda dentro de ese régimen.
  ///
  /// **13 y no más**: el caso del club. Un entrenador con alumnos de 13 a 15 no
  /// tenía forma legítima de llevarlos, y esa banda está enteramente fuera de
  /// COPPA.
  ///
  /// Este número lo leen el texto legal in-app y las reglas de Firestore. Si lo
  /// cambiás, `legal_content_test` te va a decir qué más hay que tocar.
  static const int kMinAgeYears = 13;

  /// Edad máxima plausible. Por encima de esto es un dedazo en el año, no una
  /// persona — el date picker ofrece 1920 como `firstDate`.
  static const int _maxPlausibleAgeYears = 120;

  /// Fecha de nacimiento. `null` es INVÁLIDO: a diferencia del resto de los
  /// campos del perfil, éste es obligatorio en el alta — es el gate de edad.
  ///
  /// [now] es inyectable a propósito, no por prolijidad: sin él el test del
  /// borde ("cumple 16 hoy" contra "los cumple mañana") depende del día en que
  /// corra CI y se vuelve flaky.
  static String? validateBornAt(DateTime? value, {DateTime? now}) {
    if (value == null) return 'Ingresá tu fecha de nacimiento';
    final today = now ?? DateTime.now();
    if (_compareCalendarDates(value, today) > 0) {
      return 'La fecha no puede ser futura';
    }
    final years = _yearsBetween(value, today);
    if (years > _maxPlausibleAgeYears) return 'Fecha inválida';
    if (years < kMinAgeYears) {
      return 'Tenés que tener $kMinAgeYears años para usar TREINO';
    }
    return null;
  }

  /// Años cumplidos entre [born] y [now], POR COMPONENTES DE FECHA.
  ///
  /// No se calcula dividiendo días por 365: esa cuenta acumula un día de error
  /// cada cuatro años, y a los 16 ya son cuatro días — de sobra para rechazar a
  /// alguien el día de su propio cumpleaños.
  ///
  /// El 29 de febrero sale bien de acá SIN ninguna excepción, y conviene decir
  /// por qué para que nadie agregue una.
  ///
  /// Cuando la edad mínima era 16 el argumento era que el 16º cumpleaños de un
  /// nacido el 29/2 cae siempre en año bisiesto, porque 16 es múltiplo de 4.
  /// **Con 13 ese argumento ya no vale**: 2008 + 13 = 2021, que no es bisiesto,
  /// así que ese cumpleaños no existe como fecha. El código igual funciona, pero
  /// por otro motivo, y el motivo importa porque es una decisión:
  ///
  /// el `day >=` hace que en un año no bisiesto la persona cumpla el **1 de
  /// marzo**, no el 28 de febrero. Es la convención más conservadora de las dos
  /// que se usan, y es la correcta para un gate de edad: entre adelantar o
  /// atrasar un día el cumplimiento de la edad mínima, atrasar nunca deja pasar
  /// a alguien que todavía no la tiene.
  static int _yearsBetween(DateTime born, DateTime now) {
    var years = now.year - born.year;
    final hadBirthday = now.month > born.month ||
        (now.month == born.month && now.day >= born.day);
    if (!hadBirthday) years--;
    return years;
  }

  /// Compara SÓLO el día calendario de [a] y [b]. Negativo si [a] es anterior.
  ///
  /// Por componentes y no con `isAfter` porque los dos lados viven en zonas
  /// horarias distintas: `bornAt` se persiste como fecha-only UTC
  /// (`DateTime.utc(y, m, d)` — ver `_pickBornAt` en
  /// `profile_edit_personal_screen.dart`) mientras que `now` es local. En un
  /// dispositivo al este de Greenwich, la fecha de HOY guardada como medianoche
  /// UTC es un instante POSTERIOR al ahora local, y un `value.isAfter(today)`
  /// la rechazaría como futura a alguien que eligió hoy.
  static int _compareCalendarDates(DateTime a, DateTime b) {
    if (a.year != b.year) return a.year - b.year;
    if (a.month != b.month) return a.month - b.month;
    return a.day - b.day;
  }
}
