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
/// el botón o con Enter) y, si Places encuentra el lugar, le pone un NOMBRE.
/// Solo un lugar encontrado y nombrado llega a [onElegir]: un texto libre sin
/// coordenadas no es una ubicación y no se puede guardar.
///
/// Políticas de Places: la búsqueda pide solo `id` y `location`, así que no hay
/// texto de Google que mostrar ni guardar. El nombre lo escribe SIEMPRE el PF
/// (sin prefill) y es lo único que se persiste como etiqueta. Se usa el primer
/// resultado (el mejor match de Google).
///
/// La búsqueda es explícita (botón/Enter, desde [LugarSearchService.minCaracteres]
/// caracteres), no por tecla: cada request de Text Search se factura, y así no
/// hace falta debounce. Una respuesta tardía de una búsqueda vieja se descarta.
class EditorUbicacionPf extends ConsumerStatefulWidget {
  const EditorUbicacionPf({super.key, required this.onElegir});

  /// Se llama con el lugar encontrado y el nombre que el PF le puso (ya
  /// recortado, nunca vacío). El editor se limpia después.
  final void Function(LugarCandidato lugar, String etiqueta) onElegir;

  @override
  ConsumerState<EditorUbicacionPf> createState() => _EditorUbicacionPfState();
}

class _EditorUbicacionPfState extends ConsumerState<EditorUbicacionPf> {
  final _consulta = TextEditingController();
  final _etiqueta = TextEditingController();
  _Estado _estado = _Estado.inicial;
  List<LugarCandidato> _resultados = const [];
  int _busquedaActual = 0;

  bool get _puedeAgregar => _etiqueta.text.trim().isNotEmpty;

  bool get _puedeBuscar =>
      _consulta.text.trim().length >= LugarSearchService.minCaracteres &&
      _estado != _Estado.cargando;

  @override
  void initState() {
    super.initState();
    // Habilita/deshabilita «Buscar» según el largo del texto.
    _consulta.addListener(_alCambiarTexto);
    _etiqueta.addListener(_alCambiarTexto);
  }

  void _alCambiarTexto() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _consulta.removeListener(_alCambiarTexto);
    _etiqueta.removeListener(_alCambiarTexto);
    _consulta.dispose();
    _etiqueta.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final texto = _consulta.text.trim();
    if (texto.length < LugarSearchService.minCaracteres) return;
    final esta = ++_busquedaActual;
    _etiqueta.clear();
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

  void _agregar() {
    if (_resultados.isEmpty || !_puedeAgregar) return;
    final lugar = _resultados.first;
    final etiqueta = _etiqueta.text.trim();
    _busquedaActual++;
    _consulta.clear();
    _etiqueta.clear();
    setState(() {
      _estado = _Estado.inicial;
      _resultados = const [];
    });
    widget.onElegir(lugar, etiqueta);
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
          _Estado.resultados => _LugarEncontrado(
              etiqueta: _etiqueta,
              onAgregar: _puedeAgregar ? _agregar : null,
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

/// El lugar que Places encontró, sin texto de Google: solo pide el nombre.
class _LugarEncontrado extends StatelessWidget {
  const _LugarEncontrado({required this.etiqueta, required this.onAgregar});

  final TextEditingController etiqueta;
  final VoidCallback? onAgregar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final palette = AppPalette.of(context);
    return Padding(
      key: const Key('onboarding-pf-lugar-resultados'),
      padding: const EdgeInsets.only(top: AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.coachHubOnboardingPfLocationFound,
            style: GoogleFonts.barlow(
              color: palette.textPrimary,
              fontSize: AppTextSize.body,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AuthInput(
                  key: const Key('onboarding-pf-lugar-etiqueta'),
                  controller: etiqueta,
                  label: l10n.coachHubOnboardingPfLocationLabelLabel,
                  hint: l10n.coachHubOnboardingPfLocationLabelHint,
                  leadingIcon: TreinoIcon.mapPin,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => onAgregar?.call(),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              TreinoButton(
                key: const Key('onboarding-pf-lugar-agregar'),
                label: l10n.coachHubOnboardingPfLocationAddButton,
                variant: TreinoButtonVariant.secondary,
                onPressed: onAgregar,
              ),
            ],
          ),
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
