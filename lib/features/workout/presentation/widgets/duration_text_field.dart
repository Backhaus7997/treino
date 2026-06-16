import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

// ── Formatter ─────────────────────────────────────────────────────────────────

/// Converts a raw digit string (no separators) to a total-seconds int.
///
/// The user types digits from the right:
///   "1"    → 00:01  →  1 s
///   "10"   → 00:10  → 10 s
///   "130"  → 01:30  → 90 s
///   "0140" → 01:40  → 100 s
///   "9959" → 99:59  → 5999 s   (max representable)
///
/// Minutes are capped at 99; seconds are always 0–59.
int digitStringToSeconds(String digits) {
  if (digits.isEmpty) return 0;
  // Keep only up to 4 digits (MMSS).
  final d = digits.length > 4 ? digits.substring(digits.length - 4) : digits;
  final padded = d.padLeft(4, '0');
  final mm = int.parse(padded.substring(0, 2));
  final ss = int.parse(padded.substring(2, 4));
  final minutes = mm.clamp(0, 99);
  final seconds = ss.clamp(0, 59);
  return minutes * 60 + seconds;
}

/// Converts total seconds to the "MM:SS" display string used by the formatter.
String secondsToMmss(int totalSeconds) {
  final s = totalSeconds.clamp(0, 99 * 60 + 59);
  final mm = (s ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

/// Right-to-left digit-fill formatter.
///
/// The backing text is always the raw digit string (up to 4 chars).
/// On every keystroke the display value is re-derived and shown with the
/// cursor pinned to the end.
class _DurationInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Strip every non-digit.
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    // Cap at 4 digits (MMSS).
    final capped =
        digits.length > 4 ? digits.substring(digits.length - 4) : digits;

    // Build the MM:SS display string.
    final display =
        capped.isEmpty ? '00:00' : secondsToMmss(digitStringToSeconds(capped));

    return TextEditingValue(
      text: display,
      selection: TextSelection.collapsed(offset: display.length),
    );
  }
}

// ── Widget ────────────────────────────────────────────────────────────────────

/// A compact duration field that accepts user input as digits (right-to-left
/// fill) and exposes the result in seconds via [onChanged].
///
/// The keyboard is numeric; the display is always "MM:SS". Typing "130"
/// produces "01:30" (90 s). Minutes are capped at 99.
class DurationTextField extends StatefulWidget {
  const DurationTextField({
    super.key,
    required this.valueSeconds,
    required this.onChanged,
    this.label,
    this.hasError = false,
  });

  final int valueSeconds;
  final ValueChanged<int> onChanged;
  final String? label;

  /// When true the underline turns danger-red to signal the duration is
  /// missing or zero (the set is incomplete).
  final bool hasError;

  @override
  State<DurationTextField> createState() => _DurationTextFieldState();
}

class _DurationTextFieldState extends State<DurationTextField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: secondsToMmss(widget.valueSeconds));
  }

  @override
  void didUpdateWidget(DurationTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync the display when the parent updates the value externally,
    // but only when the field is not focused (avoid fighting user input).
    if (oldWidget.valueSeconds != widget.valueSeconds) {
      final display = secondsToMmss(widget.valueSeconds);
      if (_ctrl.text != display) {
        _ctrl.text = display;
        _ctrl.selection = TextSelection.collapsed(offset: display.length);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // NOTE: does NOT wrap itself in Expanded — callers that need flex
    // expansion (e.g. inside a Row) must provide their own Expanded wrapper.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
          ),
          const SizedBox(height: 2),
        ],
        TextField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            _DurationInputFormatter(),
          ],
          style: GoogleFonts.barlow(
            fontSize: 16,
            color: palette.textPrimary,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            filled: false,
            border: UnderlineInputBorder(
              borderSide: BorderSide(
                color:
                    widget.hasError ? palette.danger : palette.border,
                width: widget.hasError ? 1.5 : 1.0,
              ),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color:
                    widget.hasError ? palette.danger : palette.border,
                width: widget.hasError ? 1.5 : 1.0,
              ),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: widget.hasError ? palette.danger : palette.accent,
                width: 2,
              ),
            ),
          ),
          onChanged: (raw) {
            // The formatter has already transformed raw into "MM:SS".
            // Re-parse seconds from the display string.
            final parts = _ctrl.text.split(':');
            if (parts.length == 2) {
              final mm = int.tryParse(parts[0]) ?? 0;
              final ss = int.tryParse(parts[1]) ?? 0;
              widget.onChanged(mm * 60 + ss);
            }
          },
        ),
      ],
    );
  }
}
