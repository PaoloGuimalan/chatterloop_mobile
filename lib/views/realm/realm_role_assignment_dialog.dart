import 'package:chatterloop_app/core/design/app_dialog.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/models/user_models/role_model.dart';
import 'package:flutter/material.dart';

/// Select a role first, then confirm through the shared dialog actions.
class RealmRoleAssignmentDialog extends StatefulWidget {
  const RealmRoleAssignmentDialog(
      {super.key,
      required this.roles,
      required this.currentRoleId,
      required this.memberName});
  final List<RoleDefinition> roles;
  final int? currentRoleId;
  final String memberName;

  @override
  State<RealmRoleAssignmentDialog> createState() =>
      _RealmRoleAssignmentDialogState();
}

class _RealmRoleAssignmentDialogState extends State<RealmRoleAssignmentDialog> {
  late int? _selectedId =
      widget.roles.any((role) => role.id == widget.currentRoleId)
          ? widget.currentRoleId
          : null;

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final canSave = _selectedId != widget.currentRoleId &&
        widget.roles.any((role) => role.id == _selectedId && role.assignable);
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.border));
    return AppDialog(
      title: 'Assign different role',
      description: 'Choose a role for ${widget.memberName}.',
      icon: Icons.manage_accounts_outlined,
      iconBesideTitle: true,
      actions: [
        AppDialogAction(
            label: 'Cancel', onPressed: () => Navigator.pop(context)),
        AppDialogAction(
            label: 'Save role',
            primary: true,
            onPressed:
                canSave ? () => Navigator.pop(context, _selectedId) : null),
      ],
      children: [
        const SizedBox(height: 18),
        if (widget.roles.isEmpty)
          const Text('No assignable roles are available.')
        else
          DropdownButtonFormField<int>(
            initialValue: _selectedId,
            isExpanded: true,
            menuMaxHeight: 280,
            dropdownColor: p.surface,
            borderRadius: BorderRadius.circular(10),
            style: TextStyle(
                fontFamily: 'Inter', fontSize: CLType.body, color: p.text),
            decoration: InputDecoration(
                labelText: 'Role',
                filled: true,
                fillColor: p.surface2,
                border: border,
                enabledBorder: border,
                focusedBorder: border.copyWith(
                    borderSide: BorderSide(color: p.brand, width: 1.5)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
            items: widget.roles
                .map((role) => DropdownMenuItem<int>(
                      value: role.id,
                      enabled: role.assignable,
                      child: Text(role.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: role.assignable ? p.text : p.text3)),
                    ))
                .toList(),
            onChanged: (value) {
              if (widget.roles
                  .any((role) => role.id == value && role.assignable)) {
                setState(() => _selectedId = value);
              }
            },
          ),
      ],
    );
  }
}
