import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// T&C checkbox with tappable "Términos" and "Política de Privacidad" spans.
/// Tapping each shows a SnackBar("Próximamente").
// TODO: Etapa 6+/localization will replace SnackBars with real screens or URLs.
class TermsCheckbox extends StatelessWidget {
  const TermsCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  void _showSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Próximamente')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final baseStyle = GoogleFonts.barlow(
      fontSize: 14,
      color: palette.textPrimary,
    );
    final linkStyle = baseStyle.copyWith(
      color: palette.accent,
      decoration: TextDecoration.underline,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          activeColor: palette.accent,
          checkColor: palette.bg,
          side: BorderSide(color: palette.border),
        ),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Acepto los ', style: baseStyle),
              GestureDetector(
                onTap: () => _showSnackBar(context),
                child: Text('Términos', style: linkStyle),
              ),
              Text(' y la ', style: baseStyle),
              GestureDetector(
                onTap: () => _showSnackBar(context),
                child: Text('Política de Privacidad', style: linkStyle),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
