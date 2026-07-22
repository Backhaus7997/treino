/// Diálogo de alta de un pago ad-hoc (monto + concepto) para la sección Pagos.
///
/// Extraído de `alumno_detail_screen.dart` (PR1 — refactor puro). Devuelve
/// `({int amount, String concept})?` o `null` si se cancela.
///
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX, es-AR + // i18n.
library;

import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';

import 'thousands_input_formatter.dart';

/// Diálogo de alta de un pago ad-hoc (monto + concepto). Devuelve el record o
/// `null` si se cancela. Copy hardcodeada (CoachHubApp no tiene l10n delegates).
class RegistrarPagoDialog extends StatefulWidget {
  const RegistrarPagoDialog({super.key});

  @override
  State<RegistrarPagoDialog> createState() => _RegistrarPagoDialogState();
}

class _RegistrarPagoDialogState extends State<RegistrarPagoDialog> {
  final _monto = TextEditingController();
  final _concepto = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _monto.dispose();
    _concepto.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = parseGroupedInt(_monto.text);
    final concept = _concepto.text.trim();
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Ingresá un monto válido.'); // i18n
      return;
    }
    if (concept.isEmpty) {
      setState(() => _error = 'Completá todos los campos.'); // i18n
      return;
    }
    Navigator.of(context).pop((amount: amount, concept: concept));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    InputDecoration deco(String label, String hint) => InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: palette.textMuted),
          hintStyle: TextStyle(color: palette.textMuted),
          enabledBorder:
              OutlineInputBorder(borderSide: BorderSide(color: palette.border)),
          focusedBorder:
              OutlineInputBorder(borderSide: BorderSide(color: palette.accent)),
        );
    return AlertDialog(
      backgroundColor: palette.bgCard,
      title: Text('Registrar pago', // i18n
          style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _monto,
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsSeparatorInputFormatter()],
            style: TextStyle(color: palette.textPrimary),
            decoration: deco('Monto (ARS)', 'Ej: 5000'), // i18n
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _concepto,
            style: TextStyle(color: palette.textPrimary),
            decoration: deco('Concepto', 'Ej: Clase suelta'), // i18n
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: TextStyle(color: palette.danger, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancelar', // i18n
                style: TextStyle(color: palette.textMuted))),
        TextButton(
            onPressed: _submit,
            child: Text('Registrar', // i18n
                style: TextStyle(
                    color: palette.accent, fontWeight: FontWeight.w700))),
      ],
    );
  }
}
