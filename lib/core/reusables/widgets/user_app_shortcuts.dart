import 'package:chatterloop_app/core/design/rails.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class UserAppShortcuts extends StatelessWidget {
  final VoidCallback onSettings;
  final bool isActingAsPage;
  const UserAppShortcuts(
      {super.key, required this.onSettings, this.isActingAsPage = false});

  Future<void> _openPages() async {
    try {
      if (await launchUrl(Uri.parse('${Endpoints.origin}/pages'),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
    CLAlerts.show("Couldn't open Pages. Please try again.",
        type: CLAlertType.error);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return CLRailSection(title: 'Apps', gap: 10, children: [
      _tile(
          context,
          isActingAsPage ? 'Manage realm' : 'Settings',
          isActingAsPage ? Icons.tune : Icons.settings_outlined,
          p.brand,
          onSettings),
      _tile(context, 'Servers', Icons.dns_outlined, p.gold,
          () => context.go('/servers')),
      _tile(context, 'Pages', Icons.description_outlined, p.brand, _openPages),
      _tile(context, 'Chatterloop Extension', Icons.extension_outlined, p.text3,
          null),
    ]);
  }

  Widget _tile(BuildContext context, String label, IconData icon, Color color,
      VoidCallback? onTap) {
    final p = cl(context);
    return SizedBox(
        width: 100,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(CLRadii.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(CLRadii.md),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
              child: Column(children: [
                Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16)),
                    child: Icon(icon, color: color, size: 28)),
                const SizedBox(height: 8),
                Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: CLType.caption,
                        fontWeight: FontWeight.w600,
                        color: onTap == null ? p.text3 : p.text)),
                if (onTap == null)
                  Text('Coming soon',
                      style: TextStyle(fontSize: CLType.meta, color: p.text3)),
              ]),
            ),
          ),
        ));
  }
}
