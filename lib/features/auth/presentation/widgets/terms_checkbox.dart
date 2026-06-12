import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../legal/legal_content.dart';
import '../legal/legal_document_screen.dart';

/// T&C checkbox with tappable "Términos" and "Política de Privacidad" links.
///
/// Rendered as a single [Text.rich] so the links stay tappable even when the
/// line wraps. Tapping each opens the matching in-app document
/// ([LegalDocumentScreen]) so the user can actually READ what they accept
/// (Ley 25.326) — without depending on external URLs.
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
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = _openTerms;
    _privacyTap = TapGestureRecognizer()..onTap = _openPrivacy;
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  void _openTerms() => _openDoc('Términos y Condiciones', kTermsSections);

  void _openPrivacy() => _openDoc('Política de Privacidad', kPrivacySections);

  void _openDoc(String title, List<LegalSection> sections) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen(title: title, sections: sections),
      ),
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
