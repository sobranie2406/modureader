import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';

/// Shared local-only visibility control. Showing a value never saves it.
class SyncSecretField extends StatefulWidget {
  const SyncSecretField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.autofocus = false,
    this.helperText,
    this.errorText,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled, autofocus;
  final String? helperText, errorText;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<SyncSecretField> createState() => _SyncSecretFieldState();
}

class _SyncSecretFieldState extends State<SyncSecretField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        obscureText: !_visible,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        validator: widget.validator,
        onFieldSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
          helperMaxLines: 3,
          errorText: widget.errorText,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: _visible
                ? ModuStrings.text(context, '隐藏敏感信息', 'Hide sensitive value')
                : ModuStrings.text(context, '显示敏感信息', 'Show sensitive value'),
            onPressed: widget.enabled
                ? () => setState(() => _visible = !_visible)
                : null,
            icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
          ),
        ),
      );
}
