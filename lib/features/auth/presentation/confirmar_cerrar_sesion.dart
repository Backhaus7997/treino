import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/treino_confirm_dialog.dart';
import '../../../l10n/app_l10n.dart';
import '../application/auth_providers.dart';

/// «Cerrar sesión» del usuario: pregunta antes de salir (#1504).
///
/// Lo usan el perfil del atleta y el del PF. NO es para las salidas de
/// emergencia de las pantallas de error (verificar mail, perfil no
/// disponible, edad): ahí salir ES la acción esperada y una pregunta de más
/// sólo estorba.
///
/// No destructiva: cerrar sesión no pierde nada, así que la acción va en el
/// color de texto de acento, no en rojo.
Future<void> confirmarCerrarSesion(BuildContext context, WidgetRef ref) async {
  final l10n = AppL10n.of(context);
  final confirmed = await showTreinoConfirmDialog(
    context,
    title: l10n.authSignOutConfirmTitle,
    confirmLabel: l10n.authSignOutConfirmAction,
    destructive: false,
  );
  if (!confirmed) return;
  await ref.read(authNotifierProvider.notifier).signOut();
}
