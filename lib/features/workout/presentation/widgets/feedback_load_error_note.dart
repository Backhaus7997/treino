import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Aviso de que los reportes del alumno NO se pudieron leer (#628).
///
/// Existe porque degradar el fallo a lista vacía deja "falló la lectura"
/// indistinguible de "no reportó nada": el PF abre el historial, ve las series
/// de siempre y concluye que no hubo ninguna molestia. En un canal cuyo único
/// valor es enterarse a tiempo, ese silencio es el peor modo de falla posible.
///
/// Es un estado INDEPENDIENTE, no un reemplazo: la sesión y sus series se
/// siguen renderizando abajo. Un problema leyendo los reportes no puede
/// esconder el entrenamiento.
///
/// Va en `textMuted` y no en `warning`: el ámbar sobre `bgCard` claro no llega
/// al 4.5:1 que pide un cuerpo de 12 px, y este widget ya lo dice con palabras.
/// El ícono carga el énfasis y es redundante con el texto.
class FeedbackLoadErrorNote extends StatelessWidget {
  const FeedbackLoadErrorNote({required this.message, super.key});

  /// El texto ya resuelto por locale. Lo elige el llamador porque la superficie
  /// del PF y la del propio alumno no dicen lo mismo: para uno son "los
  /// reportes del alumno", para el otro son "tus reportes".
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(TreinoIcon.warning, size: 12, color: palette.textMuted),
        const SizedBox(width: AppSpacing.hairline),
        Expanded(
          child: Text(
            message,
            style: GoogleFonts.barlow(fontSize: 12, color: palette.textMuted),
          ),
        ),
      ],
    );
  }
}
