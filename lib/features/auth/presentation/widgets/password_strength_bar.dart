import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// 3-segment password strength bar computed locally, no async.
class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({super.key, required this.password});

  final String password;

  /// Returns strength [0, 3]:
  /// 0 — < 8 chars
  /// 1 — 8+ chars, letters only
  /// 2 — 8+ chars, letter + number
  /// 3 — 8+ chars, letter + number + symbol
  static int _strength(String pw) {
    if (pw.length < 8) return 0;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(pw);
    final hasDigit = RegExp(r'[0-9]').hasMatch(pw);
    final hasSymbol = RegExp(r'[^A-Za-z0-9]').hasMatch(pw);
    if (hasLetter && hasDigit && hasSymbol) return 3;
    if (hasLetter && hasDigit) return 2;
    if (hasLetter || hasDigit) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final strength = _strength(password);

    String hint;
    Color hintColor;
    switch (strength) {
      case 0:
        hint = '';
        hintColor = palette.textMuted;
      case 1:
        hint = 'Débil. Sumá una mayúscula y un número.';
        hintColor = palette.textMuted;
      case 2:
        hint = 'Buena. Sumá un símbolo para hacerla fuerte.';
        hintColor = palette.textMuted;
      case _:
        hint = 'Fuerte.';
        hintColor = palette.accent;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: List.generate(3, (i) {
            final lit = i < strength;
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                decoration: BoxDecoration(
                  color: lit ? palette.accent : palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            hint,
            style: GoogleFonts.barlow(
              fontSize: 12,
              color: hintColor,
            ),
          ),
        ],
      ],
    );
  }
}
