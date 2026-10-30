import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/treino_toast.dart';
import '../../../../l10n/app_l10n.dart';
import '../../application/hub_pdf_import_job_provider.dart';

/// Ruta de «Importar plan»: ahí la pantalla misma muestra el resultado.
const _uploadRoute = '/upload-plan';

/// Aviso del shell cuando la lectura de un PDF termina mientras el PF está en
/// otra sección del Hub ([hubPdfImportJobProvider]). Usa el toast del kit, el
/// mismo de todo el Hub. No dibuja nada: [SizedBox.shrink], como
/// `CoachHubTourGate`, así no mueve el layout del shell.
///
/// En `/upload-plan` no avisa: la pantalla abre la vista previa o muestra el
/// error ella misma.
class HubPdfImportNotice extends ConsumerWidget {
  const HubPdfImportNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<HubPdfImportJob>(hubPdfImportJobProvider, (prev, next) {
      if (prev is! HubPdfImportReading) return;
      if (next is! HubPdfImportReady && next is! HubPdfImportFailed) return;
      final router = GoRouter.of(context);
      if (router.routerDelegate.currentConfiguration.uri.path == _uploadRoute) {
        return;
      }
      final l10n = AppL10n.of(context);
      if (next is HubPdfImportReady) {
        showTreinoToast(
          context,
          l10n.coachHubPdfReadyToast,
          type: TreinoToastType.success,
          // Hay algo que decidir: más que el default.
          duration: const Duration(seconds: 10),
          action: TreinoToastAction(
            label: l10n.coachHubPdfReadyAction,
            onPressed: () {
              ref.read(hubPdfImportJobProvider.notifier).acknowledge();
              router.go('$_uploadRoute/preview');
            },
          ),
        );
      } else {
        // El error queda en el job: la pantalla de subida lo muestra con su
        // acción, igual que si el PF no se hubiera ido.
        showTreinoToast(
          context,
          l10n.coachHubPdfFailedToast,
          type: TreinoToastType.error,
          duration: const Duration(seconds: 10),
          action: TreinoToastAction(
            label: l10n.coachHubPdfFailedAction,
            onPressed: () => router.go(_uploadRoute),
          ),
        );
      }
    });
    return const SizedBox.shrink();
  }
}
