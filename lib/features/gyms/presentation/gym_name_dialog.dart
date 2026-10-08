import 'package:flutter/material.dart';

import '../../../l10n/app_l10n.dart';

/// Pide el nombre de un gimnasio. Devuelve el texto tipeado (sin espacios en
/// los bordes) o `null` si el usuario cancela.
///
/// Política de Places (#1338): el nombre NO se pre-llena con el de Google. Lo
/// escribe el primer usuario que vincula el gym y lo ven todos.
Future<String?> showGymNameDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _GymNameDialog(),
  );
}

class _GymNameDialog extends StatefulWidget {
  const _GymNameDialog();

  @override
  State<_GymNameDialog> createState() => _GymNameDialogState();
}

class _GymNameDialogState extends State<_GymNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return AlertDialog(
      title: Text(l10n.gymNameDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.gymNameDialogBody),
          const SizedBox(height: 12),
          TextField(
            key: const Key('gym-name-field'),
            controller: _controller,
            autofocus: true,
            maxLength: 100,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: l10n.gymNameDialogHint),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('gym-name-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const Key('gym-name-confirm'),
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.gymNameDialogConfirm),
        ),
      ],
    );
  }
}
