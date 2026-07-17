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
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:flutter/material.dart';
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
          const _SettingsItem(Icons.privacy_tip_outlined, "Data & Privacy",
              "Export a copy of your data or delete your account", null),
          _SettingsItem(
              Icons.devices_outlined,
              "Device Sessions",
              "See where you're logged in and sign out of other devices",
              () => context.push('/settings/device-sessions')),
          const _SettingsItem(Icons.block_outlined, "Blocked Accounts",
              "Manage accounts you've blocked", null),
        ],
      ),
      const _SettingsCategory(
        "Messages",
        "Access your archived or restricted messages",
        [
          _SettingsItem(Icons.archive_outlined, "Archives",
              "Check archived messages, revisit conversations", null),
          _SettingsItem(Icons.lock_outline, "Restricted",
              "Access restricted conversations", null),
        ],
      ),
      const _SettingsCategory(
        "Location",
        "View and/or modify how the app displays your location",
        [
          _SettingsItem(Icons.map_outlined, "Map Feed Access",
              "Change how Map Feed uses your location", null),
        ],
      ),
    ];

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text("Settings")),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.title,
                    style: TextStyle(
                        fontSize: 13,
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
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: p.text)),
                    const SizedBox(height: 2),
                    Text(item.description,
                        style: TextStyle(fontSize: 12, color: p.text2)),
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
