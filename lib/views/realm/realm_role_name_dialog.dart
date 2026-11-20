import 'package:chatterloop_app/core/design/app_dialog.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:flutter/material.dart';

/// The route owns the controller through its closing animation.
class RealmRoleNameDialog extends StatefulWidget {
  const RealmRoleNameDialog(
      {super.key, required this.title, this.initialValue = ''});
  final String title, initialValue;
  @override
  State<RealmRoleNameDialog> createState() => _RealmRoleNameDialogState();
}

class _RealmRoleNameDialogState extends State<RealmRoleNameDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final name = _controller.text.trim();
    final canSave = name.isNotEmpty && name.length <= 150;
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.border));
    return AppDialog(
        title: widget.title,
        description: 'Choose a display name for this role.',
        icon: Icons.badge_outlined,
        iconBesideTitle: true,
        actions: [
          AppDialogAction(
              label: 'Cancel', onPressed: () => Navigator.pop(context)),
          AppDialogAction(
              label: 'Save role',
              primary: true,
              onPressed: canSave ? () => Navigator.pop(context, name) : null),
        ],
        children: [
          const SizedBox(height: 18),
          TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 150,
              style: TextStyle(fontSize: CLType.body, color: p.text),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: 'Role name',
                  filled: true,
                  fillColor: p.surface2,
                  border: border,
                  enabledBorder: border,
                  focusedBorder: border.copyWith(
                      borderSide: BorderSide(color: p.brand, width: 1.5)),
                  contentPadding: const EdgeInsets.all(14))),
        ]);
  }
}
