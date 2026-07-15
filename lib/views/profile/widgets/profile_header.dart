// Shared profile hero section - cover photo, overlapping avatar, name/badge,
// email, username, an actions slot (screen-specific buttons), and an info
// card (gender/joined/birthdate). Mirrors webapp's Profile.tsx hero
// (ProfileCoverContainer + ProfilePicContainer + the name/info block) minus
// the Diary card and Posts/Saves/Archives feed tabs - this app doesn't have
// those features yet, so this widget is display-only by design, not a
// trimmed-down version of something that's supposed to do more.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:flutter/material.dart';

const double _coverHeight = 170;
const double _avatarSize = 108;

IconData _genderIcon(String gender) => switch (gender) {
      "Male" => Icons.male,
      "Female" => Icons.female,
      _ => Icons.transgender,
    };

/// Same shape as ProfileHeader (cover + overlapping avatar + name/username
/// lines), shown while the profile request is still in flight - instead of
/// a bare spinner over an otherwise blank page.
class ProfileHeaderSkeleton extends StatelessWidget {
  const ProfileHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            const CLSkeleton(
              width: double.infinity,
              height: _coverHeight,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            Positioned(
              bottom: -(_avatarSize / 2),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: cl(context).bg),
                child: CLSkeleton(
                  width: _avatarSize,
                  height: _avatarSize,
                  borderRadius: BorderRadius.circular(_avatarSize / 2),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: _avatarSize / 2 + 14),
        const CLSkeleton(width: 160, height: 18),
        const SizedBox(height: 10),
        const CLSkeleton(width: 110, height: 13),
        const SizedBox(height: 24),
      ],
    );
  }
}

class ProfileHeader extends StatelessWidget {
  final String id;
  final String displayName;
  final String username;
  final String? email;
  final String? avatarSrc;
  final String? coverSrc;
  final bool isBadged;
  final String? gender;
  final String? joinedLabel;
  final String? birthdateLabel;
  final Widget? actions;
  final bool online;

  const ProfileHeader({
    super.key,
    required this.id,
    required this.displayName,
    required this.username,
    this.email,
    this.avatarSrc,
    this.coverSrc,
    this.isBadged = false,
    this.gender,
    this.joinedLabel,
    this.birthdateLabel,
    this.actions,
    this.online = false,
  });

  Widget _coverPlaceholder(CLPalette p) => Container(
        width: double.infinity,
        height: _coverHeight,
        color: p.surface2,
      );

  Widget _infoRow(CLPalette p, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 19, color: p.text2),
          const SizedBox(width: 8),
          if (label.isNotEmpty)
            Text("$label ", style: TextStyle(color: p.text, fontSize: 14)),
          Flexible(
            child: Text(value,
                style: TextStyle(
                    color: p.text, fontSize: 14, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final hasInfoCard = (gender != null && gender!.isNotEmpty) ||
        joinedLabel != null ||
        birthdateLabel != null;

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(20)),
              child: (coverSrc != null &&
                      coverSrc!.isNotEmpty &&
                      coverSrc != "none")
                  ? CLNetworkImage(
                      src: coverSrc!,
                      width: double.infinity,
                      height: _coverHeight,
                      errorBuilder: (_) => _coverPlaceholder(p),
                    )
                  : _coverPlaceholder(p),
            ),
            Positioned(
              bottom: -(_avatarSize / 2),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(shape: BoxShape.circle, color: p.bg),
                child: CLAvatar(
                    id: id,
                    name: displayName,
                    src: avatarSrc,
                    size: _avatarSize,
                    online: online),
              ),
            ),
          ],
        ),
        SizedBox(height: _avatarSize / 2 + 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  displayName.isEmpty ? username : displayName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: p.text, fontSize: 20, fontWeight: FontWeight.w800),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isBadged) ...[
                const SizedBox(width: 5),
                Icon(Icons.verified, size: 18, color: p.brand),
              ],
            ],
          ),
        ),
        if (email != null && email!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(email!, style: TextStyle(color: p.text2, fontSize: 13)),
        ],
        const SizedBox(height: 2),
        Text("@$username", style: TextStyle(color: p.text2, fontSize: 13)),
        if (actions != null) ...[
          const SizedBox(height: 16),
          actions!,
        ],
        if (hasInfoCard) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: CLCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (gender != null && gender!.isNotEmpty)
                    _infoRow(p, _genderIcon(gender!), "", gender!),
                  if (joinedLabel != null)
                    _infoRow(p, Icons.access_time, "Joined", joinedLabel!),
                  if (birthdateLabel != null)
                    _infoRow(
                        p, Icons.cake_outlined, "Born in", birthdateLabel!),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
