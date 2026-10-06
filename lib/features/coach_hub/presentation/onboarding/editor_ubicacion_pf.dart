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
/// el botón o con Enter), ELIGE uno de los resultados y le pone un NOMBRE.
/// Solo un lugar elegido y nombrado llega a [onElegir]: un texto libre sin
/// coordenadas no es una ubicación y no se puede guardar.
///
/// Políticas de Places: el nombre y la dirección de Google se MUESTRAN en la
/// lista (con la atribución «Google Maps»), pero NO se guardan ni se prefillan.
/// El nombre lo escribe SIEMPRE el PF y es lo único que se persiste como
/// etiqueta.
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
  LugarCandidato? _elegido;
  int _busquedaActual = 0;

  bool get _puedeAgregar =>
      _elegido != null && _etiqueta.text.trim().isNotEmpty;

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
    setState(() {
      _estado = _Estado.cargando;
      _elegido = null;
    });

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
    // Volver a tocar el mismo resultado no borra lo que el PF ya tipeó.
    if (_elegido?.placeId != lugar.placeId) _etiqueta.clear();
    setState(() => _elegido = lugar);
  }

  void _agregar() {
    final lugar = _elegido;
    if (lugar == null || !_puedeAgregar) return;
    final etiqueta = _etiqueta.text.trim();
    _busquedaActual++;
    _consulta.clear();
    _etiqueta.clear();
    setState(() {
      _estado = _Estado.inicial;
      _resultados = const [];
      _elegido = null;
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
          _Estado.resultados => _Resultados(
              resultados: _resultados,
              elegido: _elegido,
              onElegir: _elegir,
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

/// Los candidatos de Places (nombre y dirección solo para mostrar) y, una vez
/// elegido uno, el campo donde el PF escribe el nombre que se guarda.
class _Resultados extends StatelessWidget {
  const _Resultados({
    required this.resultados,
    required this.elegido,
    required this.onElegir,
    required this.etiqueta,
    required this.onAgregar,
  });

  final List<LugarCandidato> resultados;
  final LugarCandidato? elegido;
  final ValueChanged<LugarCandidato> onElegir;
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
          for (var i = 0; i < resultados.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.s8),
            _Candidato(
              key: Key('onboarding-pf-lugar-resultado-$i'),
              lugar: resultados[i],
              seleccionado: identical(resultados[i], elegido),
              onTap: () => onElegir(resultados[i]),
            ),
          ],
          if (elegido != null) ...[
            const SizedBox(height: AppSpacing.s12),
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

class _Candidato extends StatelessWidget {
  const _Candidato({
    super.key,
    required this.lugar,
    required this.seleccionado,
    required this.onTap,
  });

  final LugarCandidato lugar;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final direccion = lugar.formattedAddress;
    return Material(
      color: palette.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(
          color: seleccionado ? palette.accent : palette.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (lugar.displayName.isNotEmpty)
                Text(
                  lugar.displayName,
                  style: GoogleFonts.barlow(
                    color: palette.textPrimary,
                    fontSize: AppTextSize.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (direccion.isNotEmpty && direccion != lugar.displayName) ...[
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  direccion,
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
    );
  }
}

/// Atribución textual exigida por la política de Google Places.
const _atribucionGoogleMaps = 'Google Maps';
