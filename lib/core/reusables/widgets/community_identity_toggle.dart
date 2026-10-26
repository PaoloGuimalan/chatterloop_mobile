import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:flutter/material.dart';

/// Shared, compact identity control for community posts and interactions.
class CommunityIdentityToggle extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool compact;

  const CommunityIdentityToggle(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.value,
      required this.onChanged,
      this.compact = false});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return ListTile(
      dense: true,
      minTileHeight: compact ? 40 : 48,
      contentPadding: EdgeInsets.only(left: compact ? 0 : 12, right: 8),
      title:
          Text(title, style: TextStyle(fontSize: CLType.label, color: p.text)),
      subtitle: compact
          ? null
          : Text(subtitle,
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
