import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/design/tokens.dart';

/// The route owns its controller until its closing animation has completed.
class RealmTextDialog extends StatefulWidget {
  final String title, label, confirmLabel, initialValue;
  final int maxLength;
  const RealmTextDialog(
      {super.key,
      required this.title,
      required this.label,
      this.confirmLabel = 'Save',
      this.initialValue = '',
      this.maxLength = 5000});
  @override
  State<RealmTextDialog> createState() => _RealmTextDialogState();
}

class _RealmTextDialogState extends State<RealmTextDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          scrollable: true,
          backgroundColor: cl(context).surface,
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          title: Text(widget.title),
          content: TextField(
              controller: _controller,
              autofocus: true,
              minLines: widget.maxLength > 100 ? 2 : 1,
              maxLines: widget.maxLength > 100 ? 5 : 1,
              maxLength: widget.maxLength,
              decoration: InputDecoration(labelText: widget.label),
              onChanged: (_) => setState(() {})),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            TextButton(
                onPressed: _controller.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(context, _controller.text.trim()),
                child: Text(widget.confirmLabel))
          ]);
}
