/// Nivel de experiencia que elige el atleta en el step 3 del ProfileSetup.
///
/// Las descripciones se muestran como subtítulo en las cards del mockup
/// (`docs/app-alumno/screens/profile-setup/profile-setup-3.png`).
enum ExperienceLevel {
  beginner('PRINCIPIANTE', 'Recién empiezo o vuelvo después de mucho.'),
  intermediate(
    'INTERMEDIO',
    'Entreno hace 6+ meses, conozco la mayoría de ejercicios.',
  ),
  advanced('AVANZADO', '2+ años entrenando con periodización.');

  const ExperienceLevel(this.label, this.description);

  final String label;
  final String description;
}
