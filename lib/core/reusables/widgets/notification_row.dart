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

    final radius = BorderRadius.circular(detail ? CLRadii.md : CLRadii.sm);
    final background = n.isRead ? p.surface : p.brandSoft;
    // Only the detail rows carry a border; BorderSide.none keeps ONE shape
    // description for both cases, which Material needs (it accepts `shape` or
    // `borderRadius`, never both).
    final borderSide = detail
        ? BorderSide(color: n.isRead ? p.border : Colors.transparent)
        : BorderSide.none;

    // The background is NOT painted here any more when the row is tappable -
    // the Material below paints it instead. It used to be a Container colour
    // sitting inside the Material, which meant the ink splash rendered
    // underneath an opaque box and was never visible: the row responded to
    // taps and looked completely dead doing it.
    final content = Padding(
      padding: EdgeInsets.all(detail ? 10 : 9),
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

    if (!isTappable) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: radius,
          border: Border.fromBorderSide(borderSide),
        ),
        child: content,
      );
    }

    return _PressableRow(
      background: background,
      pressedOverlay: p.brand,
      radius: radius,
      borderSide: borderSide,
      onTap: () => onOpen!(n),
      child: content,
    );
  }
}

/// A row that visibly changes colour while it is being pressed.
///
/// An InkWell alone was not enough. Its splash is an ANIMATION, and the tap
/// here navigates immediately - so the ripple is torn down with the screen
/// about a frame after it starts and a click reads as no feedback at all. The
/// highlight it draws on press-down has the same problem in reverse: on a quick
/// tap it fades in and out too fast to see.
///
/// So the press state is held explicitly and the background is blended, which
/// is instant, does not depend on any animation completing, and survives right
/// up to the moment the route changes. The InkWell stays for the ripple on top
/// of it - together they cover a tap, a hold, and a drag-off cancel.
class _PressableRow extends StatefulWidget {
  final Color background;

  /// Blended OVER [background] while pressed, rather than replacing it, so the
  /// unread rows keep reading as unread while they are held.
  final Color pressedOverlay;
  final BorderRadius radius;
  final BorderSide borderSide;
  final VoidCallback onTap;
  final Widget child;

  const _PressableRow({
    required this.background,
    required this.pressedOverlay,
    required this.radius,
    required this.borderSide,
    required this.onTap,
    required this.child,
  });

  @override
  State<_PressableRow> createState() => _PressableRowState();
}

class _PressableRowState extends State<_PressableRow> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colour = _pressed
        ? Color.alphaBlend(
            widget.pressedOverlay.withValues(alpha: 0.16), widget.background)
        : widget.background;

    return Material(
      // Animated so releasing fades back rather than snapping - fast enough
      // that the press itself still reads as immediate.
      animationDuration: const Duration(milliseconds: 120),
      color: colour,
      shape:
          RoundedRectangleBorder(borderRadius: widget.radius, side: widget.borderSide),
      // Without this the splash paints past the rounded corners into the square
      // bounds of the box.
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        // Long-press is not an action here, but declaring it is what keeps the
        // pressed state up for the whole hold instead of the gesture arena
        // cancelling the tap partway through.
        onLongPress: widget.onTap,
        highlightColor: Colors.transparent, // the blended colour above IS this
        splashColor: widget.pressedOverlay.withValues(alpha: 0.14),
        child: widget.child,
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
