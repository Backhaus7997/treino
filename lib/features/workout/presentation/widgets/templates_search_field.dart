import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../application/unified_templates_providers.dart';

/// Cuadro de búsqueda de EXPLORAR (#1412).
///
/// Escribe en [templatesSearchQueryProvider] con debounce: la grilla (50
/// plantillas, cada filtrado recorre todos sus ejercicios) no se recalcula
/// con cada letra sino cuando el atleta hace una pausa. El botón de borrar,
/// en cambio, actúa al instante — vaciar la búsqueda no es algo que haya que
/// esperar.
class TemplatesSearchField extends ConsumerStatefulWidget {
  const TemplatesSearchField({
    super.key,
    this.debounce = const Duration(milliseconds: 300),
  });

  /// Pausa de tipeo antes de filtrar. Parametrizable sólo para los tests.
  final Duration debounce;

  @override
  ConsumerState<TemplatesSearchField> createState() =>
      _TemplatesSearchFieldState();
}

class _TemplatesSearchFieldState extends ConsumerState<TemplatesSearchField> {
  late final TextEditingController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(templatesSearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // El botón de borrar depende del texto crudo, no del que ya se aplicó.
    setState(() {});
    _timer?.cancel();
    _timer = Timer(widget.debounce, () {
      if (!mounted) return;
      ref.read(templatesSearchQueryProvider.notifier).state = value.trim();
    });
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    ref.read(templatesSearchQueryProvider.notifier).state = '';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color),
        );

    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      style: GoogleFonts.barlow(color: palette.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        prefixIcon: Icon(TreinoIcon.search, color: palette.textMuted),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  TreinoIcon.close,
                  color: palette.textMuted,
                  size: 18,
                ),
                tooltip: l10n.workoutExploreSearchClear,
                splashRadius: 18,
                onPressed: _clear,
              ),
        hintText: l10n.workoutExploreSearchHint,
        hintStyle: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
        filled: true,
        fillColor: palette.bgCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        border: border(palette.border),
        enabledBorder: border(palette.border),
        focusedBorder: border(palette.accent),
      ),
      onChanged: _onChanged,
    );
  }
}
