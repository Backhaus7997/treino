import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';

import 'section_header.dart';

/// Placeholder único reutilizable para las secciones aún no shipeadas
/// (ADR-CHW-009). Cada `sections/<section>/routes.dart` lo construye con su
/// `label`. Sin `Scaffold` — el shell lo provee.
class ProximamenteScreen extends StatelessWidget {
  const ProximamenteScreen({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Spacing en escala oficial {8·12·14·18·20} (docs/design-system.md). El ADR
    // proponía 24/32 pero la escala del proyecto no los permite.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: label),
          const SizedBox(height: 18),
          Text(
            'Próximamente.', // i18n: Fase W1
            style: TextStyle(color: palette.textMuted, fontSize: 16),
          ),
          // TODO(W2+): wire real screen
        ],
      ),
    );
  }
}
