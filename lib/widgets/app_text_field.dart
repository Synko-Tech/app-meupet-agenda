import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Labeled text field with themed decoration, optional helper/error text and
/// a built-in visibility toggle for password fields.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.helperText,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.showObscureToggle = true,
    this.maxLines = 1,
    this.validator,
    this.prefixIcon,
    this.suffixIcon,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.autovalidateMode,
    this.focusNode,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final String? helperText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool showObscureToggle;
  final int maxLines;
  final String? Function(String?)? validator;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final AutovalidateMode? autovalidateMode;
  final FocusNode? focusNode;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscureText != widget.obscureText) {
      _obscured = widget.obscureText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showToggle = widget.obscureText && widget.showObscureToggle;
    return TextFormField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      obscureText: widget.obscureText ? _obscured : false,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      validator: widget.validator,
      autofillHints: widget.autofillHints,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      enabled: widget.enabled,
      inputFormatters: widget.inputFormatters,
      textCapitalization: widget.textCapitalization,
      autovalidateMode: widget.autovalidateMode,
      focusNode: widget.focusNode,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        helperText: widget.helperText,
        prefixIcon: widget.prefixIcon,
        suffixIcon: showToggle
            ? IconButton(
                tooltip: _obscured ? 'Mostrar senha' : 'Ocultar senha',
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(
                  _obscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              )
            : widget.suffixIcon,
      ),
    );
  }
}
