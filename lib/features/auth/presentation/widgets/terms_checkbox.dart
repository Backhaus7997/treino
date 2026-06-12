import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_palette.dart';

/// T&C checkbox with tappable "Términos" and "Política de Privacidad" links.
///
/// Rendered as a single [Text.rich] so the links stay tappable even when the
/// line wraps — the old `Wrap` of sibling `GestureDetector`s left the second
/// wrapped line completely dead (audit F5). Tapping each opens the matching
/// Notion page in an external browser, so the user can actually READ what they
/// are accepting (GDPR / Ley 25.326).
class TermsCheckbox extends StatefulWidget {
  const TermsCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<TermsCheckbox> createState() => _TermsCheckboxState();
}

class _TermsCheckboxState extends State<TermsCheckbox> {
  // TODO(onboarding): reemplazar por las URLs públicas REALES de Notion antes
  // de mergear (audit Q2). Los placeholders apuntan a notion.so pero todavía
  // no abren páginas reales.
  static const _termsUrl = 'https://www.notion.so/treino-terminos';
  static const _privacyUrl = 'https://www.notion.so/treino-privacidad';

  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = () => _open(_termsUrl);
    _privacyTap = TapGestureRecognizer()..onTap = () => _open(_privacyUrl);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
          value: widget.value,
          onChanged: (v) => widget.onChanged(v ?? false),
          activeColor: palette.accent,
          checkColor: palette.bg,
          side: BorderSide(color: palette.border),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: baseStyle,
              children: [
                const TextSpan(text: 'Acepto los '),
                TextSpan(
                  text: 'Términos',
                  style: linkStyle,
                  recognizer: _termsTap,
                ),
                const TextSpan(text: ' y la '),
                TextSpan(
                  text: 'Política de Privacidad',
                  style: linkStyle,
                  recognizer: _privacyTap,
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
