import 'package:flutter/material.dart';

import '../../../../core/widgets/treino_icon.dart';

class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.isPassword = false,
    this.keyboardType,
    this.textInputAction,
    this.focusNode,
    this.nextFocusNode,
    this.onFieldSubmitted,
    this.validator,
    this.autofillHints,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final bool isPassword;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  final Iterable<String>? autofillHints;
  final bool enabled;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    Widget? suffixIcon;
    if (widget.isPassword) {
      suffixIcon = Tooltip(
        message: _obscured ? 'Mostrar contraseña' : 'Ocultar contraseña',
        child: IconButton(
          icon: Icon(
            _obscured ? TreinoIcon.eye : TreinoIcon.eyeOff,
          ),
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      );
    }

    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: widget.isPassword && _obscured,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      enabled: widget.enabled,
      validator: widget.validator,
      onFieldSubmitted: (v) {
        if (widget.nextFocusNode != null) {
          FocusScope.of(context).requestFocus(widget.nextFocusNode);
        }
        widget.onFieldSubmitted?.call(v);
      },
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: suffixIcon,
      ),
    );
  }
}
