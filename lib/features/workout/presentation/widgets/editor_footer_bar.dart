import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';

/// Pie fijo del editor de rutina: qué falta, y el botón de guardar.
///
/// Hasta #868 la validación corría al tocar guardar y salía por `SnackBar`: el
/// usuario cargaba todo el plan, apretaba el CTA, y recién ahí se enteraba de
/// que el día 2 había quedado vacío — en un mensaje efímero que además tapaba
/// la pantalla. Ahora corre en vivo y se ve mientras se edita.
///
/// El pie es presentación pura: recibe el estado ya calculado. Quién decide
/// qué es un problema sigue siendo la pantalla, con la misma lógica que usa
/// para habilitar el guardado.
class EditorFooterBar extends StatelessWidget {
  const EditorFooterBar({
    required this.summary,
    required this.problems,
    required this.submitLabel,
    required this.onSubmit,
    this.onGoToProblem,
    this.submitting = false,
    super.key,
  });

  /// El resumen de "está todo bien": `2 días · 41 sets · todo listo`. Se
  /// muestra sólo cuando [problems] está vacío.
  final String summary;

  /// Los problemas a mostrar, ya recortados y en orden de aparición. La barra
  /// los une con " · " y no los prioriza: eso lo hace quien los arma.
  final List<String> problems;

  final String submitLabel;

  /// Guardar. **Se llama también cuando el plan es inválido**: el CTA
  /// deshabilitado sigue siendo tocable, y ese tap es lo que muestra el primer
  /// error y salta a su día. Un botón que no responde no explica nada.
  final VoidCallback onSubmit;

  /// Salta al primer día con problema. Null cuando el problema no vive en un
  /// día concreto —falta el nombre del plan, por ejemplo— y no hay a dónde ir.
  final VoidCallback? onGoToProblem;

  final bool submitting;

  /// Alto del CTA. Del handoff.
  static const double _kAltoCta = 52;

  /// Opacidad del fondo. El pie flota sobre el scroll y sin sombras (regla del
  /// kit) el velo es lo único que separa una cosa de la otra.
  static const int _kVelo = 245;

  bool get _hayProblemas => problems.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.bg.withAlpha(_kVelo),
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s18,
            AppSpacing.s8,
            AppSpacing.s18,
            AppSpacing.s12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LineaDeEstado(
                texto: _hayProblemas ? problems.join(' · ') : summary,
                hayProblemas: _hayProblemas,
                onIr: _hayProblemas ? onGoToProblem : null,
              ),
              const SizedBox(height: AppSpacing.s8),
              _Cta(
                label: submitLabel,
                habilitado: !_hayProblemas,
                enviando: submitting,
                onTap: onSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La línea que dice si falta algo, y lleva al primer lugar donde falta.
class _LineaDeEstado extends StatelessWidget {
  const _LineaDeEstado({
    required this.texto,
    required this.hayProblemas,
    required this.onIr,
  });

  final String texto;
  final bool hayProblemas;
  final VoidCallback? onIr;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final color = hayProblemas ? palette.warning : palette.accentText;

    return Row(
      children: [
        Icon(
          hayProblemas ? TreinoIcon.errorState : TreinoIcon.check,
          size: 15,
          color: color,
        ),
        const SizedBox(width: AppSpacing.hairline),
        Expanded(
          child: Text(
            texto,
            key: const Key('footer_status_line'),
            style: GoogleFonts.barlow(
              fontSize: 11.5,
              height: 1.2,
              fontWeight: FontWeight.w400,
              color: hayProblemas ? palette.textPrimary : palette.textMuted,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onIr != null) ...[
          const SizedBox(width: AppSpacing.s8),
          Semantics(
            button: true,
            label: l10n.routineEditorGoToProblemA11y,
            excludeSemantics: true,
            child: GestureDetector(
              key: const Key('footer_go_to_problem'),
              behavior: HitTestBehavior.opaque,
              onTap: onIr,
              // Alto EXPLÍCITO y no padding + texto: el label mide dos
              // caracteres, y dejar que el alto salga de la tipografía daba 41
              // dp — por debajo del mínimo de 48 que fija la épica. El ancho
              // sale del padding porque ahí sobra de todas formas.
              child: SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                  ),
                  child: Center(
                    child: Text(
                      l10n.routineEditorGoToProblem,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: palette.accentText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// El botón de guardar. Deshabilitado se ve apagado pero **sigue respondiendo**.
///
/// Sigue siendo un `ElevatedButton` y no un `InkWell` con el estilo copiado:
/// el handoff especifica cómo se ve, no de qué está hecho, y veinticinco tests
/// del editor lo buscan por tipo. Cambiar el widget por gusto habría costado
/// adaptarlos a todos sin ganar un píxel.
class _Cta extends StatelessWidget {
  const _Cta({
    required this.label,
    required this.habilitado,
    required this.enviando,
    required this.onTap,
  });

  final String label;
  final bool habilitado;
  final bool enviando;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tinta = TreinoButtonTokens.foreground(context);

    return ElevatedButton(
      key: const Key('footer_submit_button'),
      // `onPressed` NUNCA es null por estar incompleto: el botón apagado
      // sigue siendo tocable, y ese tap es lo que muestra el primer problema y
      // salta a su día. Un botón muerto no explica nada. Sólo se apaga de
      // verdad mientras el guardado está en vuelo.
      onPressed: enviando ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            habilitado ? palette.accent : palette.accent.withAlpha(_kApagado),
        foregroundColor: habilitado ? tinta : tinta.withAlpha(_kTintaApagada),
        disabledBackgroundColor: palette.accent.withAlpha(_kApagado),
        minimumSize: const Size.fromHeight(EditorFooterBar._kAltoCta),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
      ),
      child: enviando
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: tinta),
            )
          : Text(
              label,
              style: GoogleFonts.barlowCondensed(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
    );
  }
}

/// Relleno del CTA cuando falta algo, sobre 255. Se lee como apagado sin
/// desaparecer: el botón sigue siendo el destino de la pantalla.
const int _kApagado = 64;

/// Tinta del CTA apagado, sobre 255.
const int _kTintaApagada = 140;
