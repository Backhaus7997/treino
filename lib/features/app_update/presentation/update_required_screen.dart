import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/presentation/widgets/auth_pill_button.dart';

/// Pantalla bloqueante «Actualizá la app». Sin salida: no hay botón de cerrar
/// ni ruta debajo (el gate reemplaza al router mientras esté activa).
///
/// [abrirUrl] es un seam para probarla sin plataforma.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.storeUrl,
    this.abrirUrl = _abrirExterno,
  });

  final String storeUrl;
  final Future<bool> Function(Uri url) abrirUrl;

  static Future<bool> _abrirExterno(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _fallo = false;

  Future<void> _abrirTienda() async {
    var ok = false;
    try {
      final uri = Uri.tryParse(widget.storeUrl);
      ok = uri != null && await widget.abrirUrl(uri);
    } catch (_) {
      ok = false;
    }
    if (mounted) setState(() => _fallo = !ok);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return AppBackground(
      child: Scaffold(
        key: const Key('update_required_screen'),
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(TreinoIcon.download, size: 48, color: palette.accent),
                  const SizedBox(height: AppSpacing.s20),
                  Text(
                    l10n.appUpdateTitle.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.barlowCondensed(
                      fontSize: AppTextSize.display,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Text(
                    l10n.appUpdateBody,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.barlow(
                      fontSize: AppTextSize.body,
                      height: 1.4,
                      color: palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s20),
                  AuthPillButton(
                    key: const Key('update_required_cta'),
                    label: l10n.appUpdateCta,
                    showArrow: false,
                    onPressed: _abrirTienda,
                  ),
                  if (_fallo) ...[
                    const SizedBox(height: AppSpacing.s12),
                    Text(
                      l10n.appUpdateOpenError,
                      key: const Key('update_required_error'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.barlow(
                        fontSize: AppTextSize.bodyDense,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
