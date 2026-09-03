import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/primitives.dart';
import '../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/presentation/legal/legal_content.dart';
import '../../auth/presentation/legal/legal_document_screen.dart';
import 'widgets/profile_section_tile.dart';

/// Índice de los documentos legales, accesible desde Perfil.
///
/// Antes de esta pantalla los legales sólo se alcanzaban desde el registro y
/// el login (`TermsCheckbox` / `TermsNoticeText`): con la cuenta ya creada
/// nadie podía volver a leer lo que había aceptado. Eso además de ser un
/// derecho del usuario es algo que las dos tiendas esperan encontrar.
///
/// La lista sale de [kLegalDocuments], que **se genera** junto con el resto de
/// `legal_content.dart` a partir de `docs/legal/*.md`
/// (`scripts/build_legal_content.py`). Agregar un documento nuevo no requiere
/// tocar esta pantalla: aparece solo.
class LegalIndexScreen extends StatelessWidget {
  const LegalIndexScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header — mismo patrón que las pantallas hermanas de Perfil ──────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: TreinoTappable(
            onTap: () => context.pop(),
            child: Row(
              children: [
                Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    l10n.legalDocumentsTitle.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Lista de documentos ─────────────────────────────────────────────
        Expanded(
          child: TreinoFadeSlideIn(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.bgCard,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: palette.textMuted.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < kLegalDocuments.length; i++) ...[
                        if (i > 0) _Divider(palette: palette),
                        Semantics(
                          button: true,
                          label: kLegalDocuments[i].title,
                          excludeSemantics: true,
                          child: ProfileSectionTile(
                            icon: TreinoIcon.file,
                            title: kLegalDocuments[i].title,
                            subtitle: 'Actualizado el '
                                '${kLegalDocuments[i].lastUpdated}',
                            inGroup: true,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => LegalDocumentScreen(
                                  title: kLegalDocuments[i].title,
                                  sections: kLegalDocuments[i].sections,
                                  lastUpdated: kLegalDocuments[i].lastUpdated,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Consultas sobre estos documentos: $kLegalContactEmail',
                  style: GoogleFonts.barlow(
                    fontSize: 12,
                    height: 1.5,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        indent: 20,
        endIndent: 20,
        color: palette.textMuted.withValues(alpha: 0.12),
      );
}
