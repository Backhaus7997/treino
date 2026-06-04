import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:go_router/go_router.dart';

/// Navigates to [deepLink] using the current [context]'s GoRouter.
///
/// Fallback rules (ADR-PN-009):
/// - null or empty → `context.go('/coach')`.
/// - no leading `/` → log warning + `context.go('/coach')`.
/// - valid path → `context.go(deepLink)`.
///
/// Callers MUST check `context.mounted` before calling this function.
///
/// REQ-PN-HANDLER-001, REQ-PN-HANDLER-002, REQ-PN-HANDLER-003, ADR-PN-009.
void goDeepLink(BuildContext context, String? deepLink) {
  const fallback = '/coach';

  if (deepLink == null || deepLink.isEmpty) {
    context.go(fallback);
    return;
  }

  if (!deepLink.startsWith('/')) {
    debugPrint('[fcm] invalid deepLink (no leading slash): $deepLink');
    context.go(fallback);
    return;
  }

  context.go(deepLink);
}
