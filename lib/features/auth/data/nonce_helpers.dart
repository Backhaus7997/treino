import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Nonce utility functions for Apple Sign-In (REQ-NONCE-001, REQ-NONCE-002).
///
/// These functions are intentionally package-public — extracted from
/// `auth_service.dart` into this file so that tests can import them via
/// `import 'package:treino/features/auth/data/nonce_helpers.dart' as nonce_helpers`
/// and verify nonce direction semantics without calling through the full service.
///
/// They are NOT annotated with `@visibleForTesting` because `auth_service.dart`
/// calls them legitimately from production code. The design constraint is:
/// **only `auth_service.dart` (within the `auth` feature) should call these.**
/// Do not call them from outside `lib/features/auth/`.

/// Generates a cryptographically random nonce string of [length] characters.
///
/// Uses [Random.secure] — NOT [Random] — to satisfy REQ-NONCE-001.
String generateNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(length, (_) => charset[random.nextInt(charset.length)])
      .join();
}

/// Returns the lowercase hex SHA-256 digest of [input].
String sha256OfString(String input) {
  final bytes = utf8.encode(input);
  return sha256.convert(bytes).toString();
}
