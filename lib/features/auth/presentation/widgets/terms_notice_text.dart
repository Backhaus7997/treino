import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../legal/legal_content.dart';
import '../legal/legal_document_screen.dart';

/// Leyenda de consentimiento legal para Welcome/Login (QA-AUTH-001, issue
/// #434): Google/Apple Sign-In crea una cuenta TREINO igual que Register, así
/// que el usuario tiene que saberlo ANTES de tocar el botón social.
///
/// A diferencia de [TermsCheckbox] (Register), acá no hay checkbox — el gate
/// real y la persistencia de `termsAcceptedAt` para cuentas OAuth nuevas
/// viven en el submit de ProfileSetup. Esta leyenda es sólo informativa, con
/// los mismos links tappables que abren los documentos legales in-app.
class TermsNoticeText extends StatefulWidget {
  const TermsNoticeText({super.key});

  @override
  State<TermsNoticeText> createState() => _TermsNoticeTextState();
}

class _TermsNoticeTextState extends State<TermsNoticeText> {
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
      fontSize: 12,
      color: palette.textMuted,
      height: 1.4,
    );
    final linkStyle = baseStyle.copyWith(
      color: palette.accent,
      decoration: TextDecoration.underline,
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(
            text: 'Al continuar con Google o Apple, aceptás los ',
          ),
          TextSpan(
            text: 'Términos y Condiciones',
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
      textAlign: TextAlign.center,
    );
  }
}
