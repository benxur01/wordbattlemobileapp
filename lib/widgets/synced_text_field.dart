import 'package:flutter/material.dart';

/// A [TextField] whose controller persists across rebuilds but stays in
/// sync with an externally-owned `value` (e.g. lifted state in AppRoot).
/// Plain `TextEditingController.fromValue(...)` in build() would create a
/// new controller every rebuild and drop focus/cursor position on every
/// keystroke — this widget avoids that by only overwriting the controller
/// text when it actually diverges from `value` (external resets/suggestion
/// picks), not on every parent rebuild caused by the field's own input.
class SyncedTextField extends StatefulWidget {
  const SyncedTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.onSubmitted,
    this.style,
    this.decoration,
    this.textAlign = TextAlign.start,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.textInputAction,
    this.maxLength,
    this.focusNode,
    this.autofocus = false,
    this.obscureText = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;
  final InputDecoration? decoration;
  final TextAlign textAlign;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextInputAction? textInputAction;
  final int? maxLength;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool obscureText;

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: widget.style,
      decoration: widget.decoration ?? const InputDecoration(border: InputBorder.none, isDense: true),
      textAlign: widget.textAlign,
      textCapitalization: widget.textCapitalization,
      // An empty hint list opts the field out of the platform autofill service,
      // which otherwise offers the device owner's name for anything that looks
      // like a username.
      autofillHints: const [],
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.enableSuggestions,
      textInputAction: widget.textInputAction,
      maxLength: widget.maxLength,
      obscureText: widget.obscureText,
    );
  }
}
