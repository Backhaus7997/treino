import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/app/theme/tokens/components/treino_button_tokens.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/auth/presentation/widgets/auth_input.dart';
import 'package:treino/features/coach_hub/application/lugar_search_providers.dart';
import 'package:treino/features/coach_hub/data/lugar_search_service.dart';
import 'package:treino/features/coach_hub/presentation/onboarding/onboarding_widgets.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Estado de la búsqueda. Cada caso se pinta distinto a propósito: sobre todo
/// [_Estado.errorConfig] y [_Estado.vacio], que NUNCA deben confundirse (una
/// key mal armada que dice «no encontramos ese lugar» manda al PF a buscar una
/// dirección que sí existe
/// dirección que sí existe). [_Estado.errorConfig] además NO ofrece reintentar:
/// con la key ausente nunca puede funcionar.
enum _Estado { inicial, cargando, resultados, vacio, errorConfig, errorRed }

/// Buscador de un lugar de entrenamiento POR DIRECCIÓN (design D9/D10).
///
/// La web no usa la geolocalización del dispositivo: el PF escribe, busca (con
/// el botón o con Enter) y ELIGE un resultado. Solo un resultado elegido llega a
/// [onElegir]: un texto libre sin coordenadas no es una ubicación y no se puede
/// guardar.
///
/// La búsqueda es explícita (botón/Enter, desde [LugarSearchService.minCaracteres]
/// caracteres), no por tecla: cada request de Text Search se factura, y así no
/// hace falta debounce. Una respuesta tardía de una búsqueda vieja se descarta.
class EditorUbicacionPf extends ConsumerStatefulWidget {
  const EditorUbicacionPf({super.key, required this.onElegir});

  /// Se llama con el resultado que el PF eligió. El editor se limpia después.
  final ValueChanged<LugarCandidato> onElegir;

  @override
  ConsumerState<EditorUbicacionPf> createState() => _EditorUbicacionPfState();
}

class _EditorUbicacionPfState extends ConsumerState<EditorUbicacionPf> {
  final _consulta = TextEditingController();
  _Estado _estado = _Estado.inicial;
  List<LugarCandidato> _resultados = const [];
  int _busquedaActual = 0;

  bool get _puedeBuscar =>
      _consulta.text.trim().length >= LugarSearchService.minCaracteres &&
      _estado != _Estado.cargando;

  @override
  void initState() {
    super.initState();
    // Habilita/deshabilita «Buscar» según el largo del texto.
    _consulta.addListener(_alCambiarTexto);
  }

  void _alCambiarTexto() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _consulta.removeListener(_alCambiarTexto);
    _consulta.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final texto = _consulta.text.trim();
    if (texto.length < LugarSearchService.minCaracteres) return;
    final esta = ++_busquedaActual;
    setState(() => _estado = _Estado.cargando);

    _Estado siguiente;
    var encontrados = const <LugarCandidato>[];
    try {
      encontrados = await ref.read(lugarSearchServiceProvider).buscar(texto);
      siguiente = encontrados.isEmpty ? _Estado.vacio : _Estado.resultados;
    } on LugarSearchConfigError {
      siguiente = _Estado.errorConfig;
    } catch (_) {
      // `LugarSearchError` y todo lo que salga de la red: se puede reintentar.
      // Nunca se muestra el texto de la excepción.
      siguiente = _Estado.errorRed;
    }
    if (!mounted || esta != _busquedaActual) return;
    setState(() {
      _estado = siguiente;
      _resultados = encontrados;
    });
  }

  void _elegir(LugarCandidato lugar) {
    _busquedaActual++;
    _consulta.clear();
    setState(() {
      _estado = _Estado.inicial;
      _resultados = const [];
    });
    widget.onElegir(lugar);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AuthInput(
                key: const Key('onboarding-pf-lugar-busqueda'),
                controller: _consulta,
                label: l10n.coachHubOnboardingPfLocationSearchLabel,
                hint: l10n.coachHubOnboardingPfLocationSearchHint,
                leadingIcon: TreinoIcon.mapPin,
                textInputAction: TextInputAction.search,
                onFieldSubmitted: (_) {
                  if (_puedeBuscar) _buscar();
                },
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            TreinoButton(
              key: const Key('onboarding-pf-lugar-buscar'),
              label: l10n.coachHubOnboardingPfLocationSearchButton,
              variant: TreinoButtonVariant.secondary,
              loading: _estado == _Estado.cargando,
              onPressed: _puedeBuscar ? _buscar : null,
            ),
          ],
        ),
        switch (_estado) {
          _Estado.inicial || _Estado.cargando => const SizedBox.shrink(),
          _Estado.resultados => _Resultados(
              resultados: _resultados,
              onElegir: _elegir,
            ),
          _Estado.vacio => _Aviso(
              mensaje: l10n.coachHubOnboardingPfLocationEmpty,
              esError: false,
            ),
          _Estado.errorConfig => _Aviso(
              mensaje: l10n.coachHubOnboardingPfLocationConfigError,
              esError: true,
            ),
          _Estado.errorRed => _Aviso(
              mensaje: l10n.coachHubOnboardingPfLocationNetworkError,
              esError: true,
              onReintentar: _buscar,
            ),
        },
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.mensaje,
    required this.esError,
    this.onReintentar,
  });

  final String mensaje;
  final bool esError;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          esError
              ? OnboardingError(mensaje)
              : Text(
                  mensaje,
                  style: GoogleFonts.barlow(
                    color: AppPalette.of(context).textMuted,
                    fontSize: AppTextSize.bodyDense,
                  ),
                ),
          if (onReintentar != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Align(
              alignment: Alignment.centerLeft,
              child: TreinoButton(
                key: const Key('onboarding-pf-lugar-reintentar'),
                label: l10n.coachHubOnboardingPfLocationRetry,
                variant: TreinoButtonVariant.secondary,
                onPressed: onReintentar,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Resultados extends StatelessWidget {
  const _Resultados({required this.resultados, required this.onElegir});

  final List<LugarCandidato> resultados;
  final ValueChanged<LugarCandidato> onElegir;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      key: const Key('onboarding-pf-lugar-resultados'),
      padding: const EdgeInsets.only(top: AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < resultados.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.s8),
            Material(
              color: palette.bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                side: BorderSide(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: Key('onboarding-pf-lugar-resultado-$i'),
                onTap: () => onElegir(resultados[i]),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resultados[i].label,
                        style: GoogleFonts.barlow(
                          color: palette.textPrimary,
                          fontSize: AppTextSize.body,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (resultados[i].direccion.isNotEmpty &&
                          resultados[i].direccion != resultados[i].label) ...[
                        const SizedBox(height: AppSpacing.hairline),
                        Text(
                          resultados[i].direccion,
                          style: GoogleFonts.barlow(
                            color: palette.textMuted,
                            fontSize: AppTextSize.bodyDense,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
          // Política de Places: el contenido de Places mostrado fuera de un mapa
          // de Google exige la atribución textual visible. Es el nombre de marca:
          // no se traduce, por eso es una constante y no una clave ARB.
          const SizedBox(height: AppSpacing.s8),
          Text(
            _atribucionGoogleMaps,
            textAlign: TextAlign.end,
            style: GoogleFonts.barlow(
              color: palette.textMuted,
              fontSize: AppTextSize.bodyDense,
            ),
          ),
        ],
      ),
    );
  }
}

/// Atribución textual exigida por la política de Google Places.
const _atribucionGoogleMaps = 'Google Maps';
