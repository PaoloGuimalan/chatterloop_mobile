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

  /// Camera buttons on the avatar and the cover. Null hides both.
  ///
  /// The OWNER's own profile only - web gates the same affordance on
  /// `authentication.user.userID === userID`. Passing a handler is the whole
  /// permission check as far as this widget is concerned; deciding it is the
  /// screen's job, since only it knows whose profile this is.
  final VoidCallback? onChangeAvatar;
  final VoidCallback? onChangeCover;
  final bool isBadged;

  /// Private profile - shows a lock beside the name, mirroring the webapp.
  /// Purely an indicator; whether content is actually withheld is `canView`,
  /// which the screen handles.
  final bool isPrivate;
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
    this.onChangeAvatar,
    this.onChangeCover,
    this.isBadged = false,
    this.isPrivate = false,
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
            Text("$label ",
                style: TextStyle(color: p.text, fontSize: CLType.title)),
          Flexible(
            child: Text(value,
                style: TextStyle(
                    color: p.text,
                    fontSize: CLType.title,
                    fontWeight: FontWeight.w700),
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
        // Tall enough to CONTAIN the avatar's overhang.
        //
        // The avatar used to be positioned at bottom:-(size/2), hanging outside
        // the Stack - and Flutter does not hit-test anything drawn outside its
        // parent's bounds, so the whole lower half of the avatar (including the
        // camera badge on its corner) was visible but untappable. clipBehavior
        // .none makes it VISIBLE, not interactive; that distinction is the bug.
        SizedBox(
          height: _coverHeight + _avatarSize / 2 + 4,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
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
              ),
              if (onChangeCover != null)
                Positioned(
                  right: 12,
                  top: MediaQuery.of(context).padding.top + 8,
                  child: _MediaEditButton(
                    onTap: onChangeCover!,
                    tooltip: "Change cover photo",
                  ),
                ),
              Positioned(
                top: _coverHeight - _avatarSize / 2,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: p.bg),
                    child: Stack(
                      children: [
                        CLAvatar(
                            id: id,
                            name: displayName,
                            src: avatarSrc,
                            size: _avatarSize,
                            online: online),
                        if (onChangeAvatar != null)
                          // INSIDE the avatar's own box, not hanging off its
                          // corner - same hit-testing rule as above.
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: _MediaEditButton(
                              onTap: onChangeAvatar!,
                              tooltip: "Change profile picture",
                              compact: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Just breathing room now - the overhang is inside the SizedBox above
        // rather than hanging past it, so this no longer reserves space for it.
        const SizedBox(height: 14),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: CLSpacing.contentGutter),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  displayName.isEmpty ? username : displayName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: p.text,
                      fontSize: CLType.screenTitle,
                      fontWeight: FontWeight.w800),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isBadged) ...[
                const SizedBox(width: 5),
                Icon(Icons.verified, size: 18, color: p.brand),
              ],
              if (isPrivate) ...[
                const SizedBox(width: 5),
                Icon(Icons.lock, size: 16, color: p.text2),
              ],
            ],
          ),
        ),
        if (email != null && email!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(email!,
              style: TextStyle(color: p.text2, fontSize: CLType.bodySm)),
        ],
        const SizedBox(height: 2),
        Text("@$username",
            style: TextStyle(color: p.text2, fontSize: CLType.bodySm)),
        if (actions != null) ...[
          const SizedBox(height: 16),
          actions!,
        ],
        if (hasInfoCard) ...[
          const SizedBox(height: 16),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: CLSpacing.contentGutter),
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

/// The camera affordance on a profile's avatar and cover.
///
/// Its own scrim, because it sits on whatever photo the user chose - a bare
/// icon disappears against a light one.
class _MediaEditButton extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;
  final bool compact;

  const _MediaEditButton({
    required this.onTap,
    required this.tooltip,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: p.surface,
        shape: CircleBorder(side: BorderSide(color: p.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? 6 : 8),
            child: Icon(Icons.photo_camera_outlined,
                size: compact ? 16 : 18, color: p.text2),
          ),
        ),
      ),
    );
  }
}
