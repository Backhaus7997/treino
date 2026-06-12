import 'package:flutter/widgets.dart';

/// Stub del breadcrumb del top bar. La implementación real (deriva el trail
/// desde `GoRouterState.uri` contra `sidebarRegistry`) llega en W1.3.2.
class CoachHubBreadcrumb extends StatelessWidget {
  const CoachHubBreadcrumb({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
