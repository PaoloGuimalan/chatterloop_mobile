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
    final textScaler = MediaQuery.textScalerOf(context);
    final tileHeight = 62 + textScaler.scale(CLType.caption) * 2.5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CLSectionHeader(title: 'Apps'),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: tileHeight,
          ),
          children: [
            _tile(context, isActingAsPage ? 'Manage realm' : 'Settings',
                'settings', onSettings),
            _tile(context, 'Servers', 'servers',
                () => context.push('/server-browser')),
            _tile(context, 'Pages', 'pages', _openPages),
            _tile(context, 'Diary', 'diary', () => context.push('/diary')),
            _tile(context, 'Notes', 'notes', null),
            _tile(context, 'Chatterloop Extension', 'extension', null),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _tile(BuildContext context, String label, String iconName,
      VoidCallback? onTap) {
    final p = cl(context);
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: p.surface2,
        borderRadius: BorderRadius.circular(CLRadii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CLRadii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: Image.asset('assets/images/app-icon-$iconName.png',
                        width: 28, height: 28, excludeFromSemantics: true),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: CLType.caption,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: onTap == null ? p.text3 : p.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
