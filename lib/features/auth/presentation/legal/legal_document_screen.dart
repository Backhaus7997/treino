import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_background.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import 'legal_content.dart';

/// Visor a pantalla completa de un documento legal (Términos / Política de
/// Privacidad).
///
/// Se monta con `Navigator.push` desde [TermsCheckbox] — no necesita una ruta
/// de go_router, así que funciona durante el registro sin importar el estado de
/// autenticación (no lo intercepta `authRedirect`).
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.sections,
  });

  final String title;
  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      body: AppBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: back + title.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(TreinoIcon.back, color: palette.textPrimary),
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Volver',
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: sections.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 18),
                  itemBuilder: (context, i) {
                    // Footer: última actualización + contacto.
                    if (i == sections.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Última actualización: $kLegalLastUpdated.\n'
                          'Consultas: $kLegalContactEmail',
                          style: GoogleFonts.barlow(
                            fontSize: 12,
                            height: 1.5,
                            color: palette.textMuted,
                          ),
                        ),
                      );
                    }

                    final section = sections[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            section.heading,
                            style: GoogleFonts.barlowCondensed(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: palette.accent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          section.body,
                          style: GoogleFonts.barlow(
                            fontSize: 14,
                            height: 1.55,
                            color: palette.textPrimary,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
