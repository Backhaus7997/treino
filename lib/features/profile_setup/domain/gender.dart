/// Género que elige el atleta en el step 3 del ProfileSetup.
///
/// El mockup (`profile-setup-3.png`) muestra tres chips: FEMENINO · MASCULINO ·
/// OTRO. Mantener el orden y el casing UPPERCASE para que la UI lo consuma
/// directo del enum.
enum Gender {
  female('FEMENINO'),
  male('MASCULINO'),
  other('OTRO');

  const Gender(this.label);

  final String label;
}
