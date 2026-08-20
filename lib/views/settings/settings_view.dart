// Mirrors webapp's Settings.tsx category list (src/app/tabs/settings/
// Settings.tsx:50-144) - webapp uses a master/detail desktop layout with
// inline section components; mobile instead pushes a full screen per item,
// matching how every other list->detail flow in this app already works
// (Contacts -> UserProfileScreen, Messages -> ConversationView, etc).
//
// Personal Information and Credentials both route to the existing
// /profile/edit screen, which already covers name + username in one form -
// webapp splits them into two sections (Credentials also disables the email
// field), but there's no separate mobile screen to port that split onto yet.
// Data & Privacy / Device Sessions / Blocked Accounts / Archives / Map Feed
// Access don't have a mobile screen built yet either - shown disabled, same
// treatment webapp itself already gives its own unimplemented "Restricted"
// item (Settings.tsx:122's isDisabled), rather than a dead-end tap.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/utils/app_version.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class _SettingsItem {
  final IconData icon;
  final String name;
  final String description;
  final VoidCallback? onTap;

  const _SettingsItem(this.icon, this.name, this.description, this.onTap);

  bool get isDisabled => onTap == null;
}

class _SettingsCategory {
  final String title;
  final String description;
  final List<_SettingsItem> items;

  const _SettingsCategory(this.title, this.description, this.items);
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final categories = [
      _SettingsCategory(
        "Account",
        "Review, update, and manage your account information",
        [
          _SettingsItem(
              Icons.account_circle_outlined,
              "Personal Information",
              "Change your name, birthdate, and other public information",
              () => context.push('/settings/personal-information')),
          _SettingsItem(
              Icons.key_outlined,
              "Credentials",
              "Set up or update your necessary account credentials",
              () => context.push('/settings/credentials')),
          _SettingsItem(
              Icons.shield_outlined,
              "Data & Privacy",
              "Export a copy of your data or permanently delete your account",
              () => context.push('/settings/data-privacy')),
          _SettingsItem(
              Icons.devices_outlined,
              "Device Sessions",
              "See where you're logged in and sign out of other devices",
              () => context.push('/settings/device-sessions')),
          _SettingsItem(
              Icons.block_outlined,
              "Blocked Accounts",
              "Manage accounts you've blocked",
              () => context.push('/settings/blocked-accounts')),
        ],
      ),
      _SettingsCategory(
        "Messages",
        "Access your archived or restricted messages",
        [
          _SettingsItem(
              Icons.inventory_2_outlined,
              "Archives",
              "Check your archived messages and revisit conversations",
              () => context.push('/settings/archives')),
          _SettingsItem(Icons.lock_outline, "Restricted",
              "Access restricted conversations", null),
        ],
      ),
      _SettingsCategory(
        "Location",
        "View and/or modify how the app displays your location",
        [
          _SettingsItem(
              Icons.map_outlined,
              "Map Feed Access",
              "Change how Map Feed uses or displays your location",
              () => context.push('/settings/map')),
        ],
      ),
    ];

    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text("Settings")),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        // +1 for the version footer, which scrolls with the list rather than
        // pinning to the bottom - it is a fact about the install, not an
        // action, so it belongs after the content and not over it.
        itemCount: categories.length + 1,
        itemBuilder: (context, index) {
          if (index == categories.length) return const _VersionFooter();
          final category = categories[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.title,
                    style: TextStyle(
                        fontSize: CLType.bodySm,
                        fontWeight: FontWeight.w700,
                        color: p.text2)),
                const SizedBox(height: 8),
                CLCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (var i = 0; i < category.items.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: p.border),
                        _SettingsRow(item: category.items[i]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final _SettingsItem item;
  const _SettingsRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Opacity(
      opacity: item.isDisabled ? 0.5 : 1,
      child: InkWell(
        onTap: item.isDisabled
            ? null
            : () {
                item.onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Icon(item.icon, size: 20, color: p.text2),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: TextStyle(
                            fontSize: CLType.title,
                            fontWeight: FontWeight.w600,
                            color: p.text)),
                    const SizedBox(height: 2),
                    Text(item.description,
                        style: TextStyle(fontSize: CLType.caption, color: p.text2)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              item.isDisabled
                  ? CLBadge(label: "Soon", tone: CLBadgeTone.grey)
                  : Icon(Icons.chevron_right, size: 20, color: p.text3),
            ],
          ),
        ),
      ),
    );
  }
}

/// The running build, spelled out where a user can read it back to support.
///
/// Deliberately shows the build number alongside the marketing version: two
/// builds can share a version name (a rebuild, a hotfix that was never
/// renamed), and the build number is the half that actually identifies which
/// artifact is installed - the same value the server sees in X-App-Version.
///
/// Tapping copies it, since transcribing a version by hand into a support
/// message is exactly where it gets mistyped.
class _VersionFooter extends StatefulWidget {
  const _VersionFooter();

  @override
  State<_VersionFooter> createState() => _VersionFooterState();
}

class _VersionFooterState extends State<_VersionFooter> {
  /// Held in state rather than created in build(): AppVersion caches after a
  /// successful read, so this is all but resolved by the time Settings opens,
  /// but a rebuild must not kick off a fresh platform call to find that out.
  late final Future<void> _loaded = AppVersion.ensureLoaded();

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return FutureBuilder<void>(
      future: _loaded,
      builder: (context, snapshot) {
        // Nothing at all rather than "Version unknown" - on the one path where
        // the manifest read fails there is no useful thing to say, and an
        // error string in a settings list reads as something being broken.
        if (!AppVersion.isReady) return const SizedBox.shrink();
        final label = "Version ${AppVersion.name} (build ${AppVersion.build})";
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          child: Center(
            // Sized to the text rather than filling the row: a full-width tap
            // target under a settings list invites taps from people who were
            // aiming at the last item and did not mean to hit anything.
            child: InkWell(
              onTap: () => _copy(label),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  label,
                  style: TextStyle(fontSize: CLType.caption, color: p.text3),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Copies the version, plus the platform the server keys off in X-Platform -
  /// a pasted "android" saves support a round trip asking which phone.
  ///
  /// The messenger is captured BEFORE the await: Clipboard.setData is async,
  /// and reaching back through `context` after it resolves is the standard way
  /// this crashes when the user leaves Settings in the meantime.
  Future<void> _copy(String label) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
        ClipboardData(text: "$label - ${AppVersion.platform}"));
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(
      content: Text("Version copied."),
      duration: Duration(seconds: 2),
    ));
  }
}
