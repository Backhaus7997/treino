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
  ///
  /// El número no es sólo política de producto. Con 16 la app queda FUERA del
  /// alcance de COPPA (16 CFR 312, que aplica bajo 13) y parada en el piso
  /// máximo del art. 8 del RGPD (16, que ningún estado miembro puede subir),
  /// así que no hay que construir verificación de consentimiento parental para
  /// ninguna jurisdicción. Ese es el ahorro real de elegir 16 y no 13.
  ///
  /// Lo que NO elimina: los de 16 y 17 siguen siendo menores para el CCyC
  /// argentino y los textos legales les siguen exigiendo consentimiento del
  /// representante legal. Lo que 16 saca de encima es la obligación de
  /// VERIFICARLO con un mecanismo técnico.
  ///
  /// Ver `docs/legal/terminos-y-condiciones.md`.
  static const int kMinAgeYears = 16;

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
  /// por qué para que nadie agregue una: el 16º cumpleaños de alguien nacido un
  /// 29/2 cae SIEMPRE en año bisiesto (16 es múltiplo de 4), así que la fecha
  /// existe. Para cualquier día posterior el `day >=` ya resuelve solo el 28/2
  /// de un año no bisiesto.
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
