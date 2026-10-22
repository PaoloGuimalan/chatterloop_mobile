import 'package:flutter/material.dart';
import 'tokens.dart';
import 'app_dialog.dart';

class PassphraseDialog extends AppDialog {
  const PassphraseDialog(
      {super.key,
      required super.title,
      required super.description,
      super.children,
      super.iconBesideTitle = true,
      required super.actions})
      : super(icon: Icons.lock_outline);
}

class PassphraseField extends StatelessWidget {
  const PassphraseField(
      {super.key,
      required this.label,
      this.labelSpan,
      required this.controller,
      this.secret = false,
      this.enabled = true,
      this.autofocus = false,
      this.maxLength,
      this.errorText,
      this.onSubmitted});
  final String label;
  final InlineSpan? labelSpan;
  final TextEditingController controller;
  final bool secret, enabled, autofocus;
  final int? maxLength;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: p.border));
    return Padding(
      padding: const EdgeInsets.only(top: 15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (labelSpan == null)
          Text(label, style: TextStyle(fontSize: CLType.caption, color: p.text))
        else
          Text.rich(labelSpan!,
              style: TextStyle(fontSize: CLType.caption, color: p.text)),
        const SizedBox(height: 7),
        Semantics(
            label: label,
            child: TextField(
              controller: controller,
              obscureText: secret,
              enabled: enabled,
              autofocus: autofocus,
              maxLength: maxLength,
              autocorrect: !secret,
              enableSuggestions: !secret,
              enableIMEPersonalizedLearning: !secret,
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: CLType.title, color: p.text),
              decoration: InputDecoration(
                filled: true,
                fillColor: p.surface2,
                contentPadding: const EdgeInsets.all(11),
                border: border,
                enabledBorder: border,
                disabledBorder: border,
                focusedBorder:
                    border.copyWith(borderSide: BorderSide(color: p.brand)),
                counterText: '',
                errorText: errorText,
                errorMaxLines: 3,
              ),
              onSubmitted: onSubmitted,
            )),
      ]),
    );
  }
}

class PassphraseAction extends AppDialogAction {
  const PassphraseAction(
      {super.key,
      required super.label,
      required super.onPressed,
      super.primary});
}
