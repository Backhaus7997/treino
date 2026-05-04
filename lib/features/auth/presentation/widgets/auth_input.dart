import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Mockup-aligned input field: small condensed UC label above, filled field
/// with leading icon inside, optional eye toggle for passwords.
class AuthInput extends StatefulWidget {
  const AuthInput({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    required this.leadingIcon,
    this.obscureText = false,
    this.suffixToggle = false,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofillHints,
    this.enabled = true,
    this.focusNode,
    this.nextFocusNode,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData leadingIcon;
  final bool obscureText;
  final bool suffixToggle;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;

  @override
  State<AuthInput> createState() => _AuthInputState();
}

class _AuthInputState extends State<AuthInput> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    Widget? suffixIcon;
    if (widget.suffixToggle) {
      suffixIcon = Tooltip(
        message: _obscured ? 'Mostrar contraseña' : 'Ocultar contraseña',
        child: IconButton(
          icon: Icon(
            _obscured ? TreinoIcon.eye : TreinoIcon.eyeOff,
            color: palette.textMuted,
            size: 20,
          ),
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label above field — condensed UC, small
        Text(
          widget.label,
          style: GoogleFonts.barlowCondensed(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: _obscured,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          enabled: widget.enabled,
          validator: widget.validator,
          style: GoogleFonts.barlow(
            color: palette.textPrimary,
            fontSize: 16,
          ),
          onFieldSubmitted: (v) {
            if (widget.nextFocusNode != null) {
              FocusScope.of(context).requestFocus(widget.nextFocusNode);
            }
            widget.onFieldSubmitted?.call(v);
          },
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: Icon(
              widget.leadingIcon,
              color: palette.textMuted,
              size: 20,
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 48, minHeight: 48),
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}
