import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:flutter/material.dart';

/// Shared, compact identity control for community posts and interactions.
class CommunityIdentityToggle extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const CommunityIdentityToggle(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return ListTile(
      dense: true,
      minTileHeight: 48,
      contentPadding: const EdgeInsets.only(left: 12, right: 8),
      title:
          Text(title, style: TextStyle(fontSize: CLType.label, color: p.text)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: CLType.caption, color: p.text2)),
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: SizedBox(
          width: 40,
          height: 30,
          child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Switch(
                  value: value,
                  onChanged: onChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap))),
    );
  }
}
