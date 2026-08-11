// One notification row - Flutter counterpart of webapp's NotificationRow.
//
// Two sizes, both from the mockup: `preview` is the compact row inside a
// section card on the Notifications screen; `detail` is the larger bordered
// row in a section's "See all" list, which also carries the type badge on the
// avatar. Unread rows sit on a brand tint in both.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/core/utils/notification_actions.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_v2_model.dart';
import 'package:flutter/material.dart';

/// type -> the small badge glyph on the avatar (detail rows only).
({IconData icon, Color Function(CLPalette) color}) _typeBadge(String type) {
  return switch (type) {
    "post_reaction" => (icon: Icons.favorite, color: (p) => p.pink),
    "post_comment" => (icon: Icons.mode_comment, color: (p) => p.green),
    "tag_notification" => (icon: Icons.alternate_email, color: (p) => p.gold),
    "shared_post_notification" => (icon: Icons.cached, color: (p) => p.brand),
    "contact_request" => (icon: Icons.person_add, color: (p) => p.brand),
    "follow" => (icon: Icons.person_add, color: (p) => p.green),
    // A follow of a private profile, awaiting approval - distinct glyph from
    // a plain "follow", which is already established.
    "follow_request" => (icon: Icons.lock_person, color: (p) => p.brand),
    "info_contact_accept" => (icon: Icons.how_to_reg, color: (p) => p.green),
    "info_contact_decline" => (icon: Icons.close, color: (p) => p.text3),
    "poke" => (icon: Icons.touch_app, color: (p) => p.gold),
    _ => (icon: Icons.notifications, color: (p) => p.text3),
  };
}

DateTime? _parseNotificationAt(NotificationV2 n) {
  // 1) Direct ISO support (if backend ever sends it)
  final iso = DateTime.tryParse(n.date);
  if (iso != null) return iso;

  // 2) Parse MM/DD/YYYY + optional h:mm AM/PM
  final dateParts = n.date.split('/');
  if (dateParts.length != 3) return null;

  final month = int.tryParse(dateParts[0]);
  final day = int.tryParse(dateParts[1]);
  final year = int.tryParse(dateParts[2]);
  if (month == null || day == null || year == null) return null;

  var hour = 0;
  var minute = 0;

  final rawTime = n.time?.trim();
  if (rawTime != null && rawTime.isNotEmpty) {
    final m =
        RegExp(r'^(\d{1,2}):(\d{2})(?:\s*([AaPp][Mm]))?$').firstMatch(rawTime);
    if (m != null) {
      hour = int.tryParse(m.group(1)!) ?? 0;
      minute = int.tryParse(m.group(2)!) ?? 0;
      final ampm = m.group(3)?.toLowerCase();

      if (ampm == 'pm' && hour < 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;
    }
  }

  return DateTime(year, month, day, hour, minute);
}

class CLNotificationRow extends StatelessWidget {
  final NotificationV2 notification;

  /// Larger row with the type badge and a border, for the See-all list.
  final bool detail;

  /// An accept/decline for THIS row is in flight.
  final bool busy;
  final ValueChanged<NotificationV2> onAccept;
  final ValueChanged<NotificationV2> onDecline;

  /// Runs a server-driven action. Absent = fall back to onAccept/onDecline.
  final void Function(NotificationV2, NotificationAction)? onAction;

  /// Row tap - only called when the server gave this platform a destination.
  final ValueChanged<NotificationV2>? onOpen;

  const CLNotificationRow({
    super.key,
    required this.notification,
    this.detail = false,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    this.onAction,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final n = notification;
    final badge = _typeBadge(n.type);

    // Bold sender name + the stored sentence. The details text starts with the
    // sender's @handle ("@maria reacted ..."), so strip it when there's a real
    // display name to show instead - graceful fallback otherwise.
    final senderName = (n.fromUser?.displayName.isNotEmpty == true)
        ? n.fromUser!.displayName
        : n.headline;
    var details = n.details;
    final handle = n.fromUser?.handle;
    if (handle != null && handle.isNotEmpty) {
      details = details.replaceFirst(
          RegExp('^@$handle\\s+', caseSensitive: false), "");
    }
    // Narrowed to what this build can actually carry out - see
    // isRunnableAction. Platform filtering already happened at parse time.
    final serverActions = onAction == null
        ? const <NotificationAction>[]
        : n.actions.where(isRunnableAction).toList();

    final parsedAt = _parseNotificationAt(n);
    final timeLabel = parsedAt != null
        ? timeSince(
            parsedAt) // or timeSinceShort(parsedAt) if you want shorter labels
        : ((n.time != null && n.time!.isNotEmpty)
            ? "${n.date} · ${n.time}"
            : n.date);

    final avatarSize = detail ? 44.0 : 38.0;

    // Tappable ONLY when the server gave this platform a destination. A row
    // that lights up and then goes nowhere is worse than one that never
    // responded.
    final destination = n.redirect;
    final isTappable = destination != null && onOpen != null;

    final row = Container(
      padding: EdgeInsets.all(detail ? 10 : 9),
      decoration: BoxDecoration(
        color: n.isRead ? p.surface : p.brandSoft,
        borderRadius: BorderRadius.circular(detail ? CLRadii.md : CLRadii.sm),
        border: detail
            ? Border.all(color: n.isRead ? p.border : Colors.transparent)
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: avatarSize,
            height: avatarSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CLAvatar(
                  id: n.fromUser?.entityId ?? n.fromUserID,
                  name: senderName,
                  src: n.fromUser?.profile,
                  size: avatarSize,
                ),
                if (detail)
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Icon(badge.icon, size: 13, color: badge.color(p)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: senderName,
                      style:
                          TextStyle(fontWeight: FontWeight.w700, color: p.text),
                    ),
                    // Verified check beside the NAME, matching the webapp.
                    // `is_verified` on a notification sender means "show a
                    // check" - the server maps it from is_badged for a user
                    // and is_verified for a realm. An Account's own
                    // is_verified is the email-confirmation gate, unrelated.
                    if (n.fromUser?.isVerified == true)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 3, right: 1),
                          child: Icon(Icons.verified, size: 13, color: p.brand),
                        ),
                      ),
                    if (details.isNotEmpty)
                      TextSpan(
                        text: " $details",
                        style: TextStyle(color: p.text2),
                      ),
                  ]),
                  style: TextStyle(fontSize: detail ? 13.5 : 13, height: 1.35),
                ),
                const SizedBox(height: 2),
                Text(
                  timeLabel,
                  style: TextStyle(fontSize: CLType.meta, color: p.text3),
                ),
              ],
            ),
          ),
          // Server-driven buttons, already filtered to this platform at parse
          // time and narrowed here to the kinds this build can carry out. An
          // unrunnable entry renders nothing rather than a button that does
          // nothing - which is what keeps a shipped app safe when the server
          // starts sending a kind it has never heard of.
          if (serverActions.isNotEmpty) ...[
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < serverActions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  CLMiniBtn(
                    label: serverActions[i].name,
                    // `style` is a hint; anything unrecognised takes the
                    // neutral outline rather than guessing at emphasis.
                    variant: serverActions[i].style == 'primary'
                        ? CLBtnVariant.primary
                        : CLBtnVariant.outline,
                    onPressed:
                        busy ? null : () => onAction!(n, serverActions[i]),
                  ),
                ],
              ],
            ),
          ]
          // LEGACY fallback: an older server sends no `actions`, so the
          // hardcoded pair stays until that server is everywhere. Delete this
          // branch once it is.
          else if (n.isActionable) ...[
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CLMiniBtn(
                  label: "Confirm",
                  onPressed: busy ? null : () => onAccept(n),
                ),
                const SizedBox(height: 6),
                CLMiniBtn(
                  label: "Decline",
                  variant: CLBtnVariant.outline,
                  onPressed: busy ? null : () => onDecline(n),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (!isTappable) return row;

    // Material+InkWell rather than GestureDetector so the tap gets the ripple
    // every other list row in the app has. The buttons inside sit ABOVE this in
    // the tree, so a press on one is consumed there and never reaches the row.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onOpen!(n),
        borderRadius: BorderRadius.circular(detail ? CLRadii.md : CLRadii.sm),
        child: row,
      ),
    );
  }
}

class CLNotificationRowSkeleton extends StatelessWidget {
  final bool detail;

  const CLNotificationRowSkeleton({super.key, this.detail = false});

  @override
  Widget build(BuildContext context) {
    final size = detail ? 44.0 : 38.0;
    return Padding(
      padding: EdgeInsets.all(detail ? 10 : 9),
      child: Row(
        children: [
          CLSkeleton(
              width: size,
              height: size,
              borderRadius: BorderRadius.circular(size / 2)),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                CLSkeleton(width: double.infinity, height: 11),
                SizedBox(height: 7),
                CLSkeleton(width: 90, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
