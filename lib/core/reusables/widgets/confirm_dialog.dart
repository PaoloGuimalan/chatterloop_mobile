// The one confirm dialog for destructive-but-quiet actions.
//
// Unfollowing, unfriending, leaving and removing all share a shape: nothing on
// screen says they happened, the other side is never told, and the only way
// back is an action the OTHER person controls. That is what earns a prompt -
// not how many taps it takes.
//
// Extracted once the roster screen, both profiles and every follow surface
// each wanted the same AlertDialog; the copy for each case lives at its call
// site, since only the caller knows the noun.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:flutter/material.dart';

/// Returns true only when the destructive action was chosen.
///
/// A null [confirmLabel] makes this INFORMATIONAL: one dismiss button and no
/// destructive action, for the cases where the thing was refused outright and
/// there is nothing to confirm (a sole owner trying to leave). It still
/// returns false, so callers need no special case.
Future<bool> showCLConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
}) async {
  final p = cl(context);
  final answer = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.surface,
      title: Text(title,
          style: TextStyle(color: p.text, fontSize: CLType.screenTitle)),
      content: Text(message,
          style: TextStyle(color: p.text2, fontSize: CLType.body)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(confirmLabel == null ? 'Got it' : 'Cancel',
              style: TextStyle(color: p.text2)),
        ),
        if (confirmLabel != null)
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: p.pink),
            child: Text(confirmLabel),
          ),
      ],
    ),
  );
  return answer == true;
}

/// Shared copy so all six follow surfaces say the same thing.
///
/// [name] is display-ready: "@handle" for a person, the page's own name.
/// A pending request is withdrawn through the same call an established follow
/// is dropped with, but "Unfollow" would misdescribe it.
Future<bool> confirmUnfollow(
  BuildContext context, {
  required String name,
  required bool isRealm,
  bool isPending = false,
  String realmNoun = 'page',
}) {
  if (isPending) {
    return showCLConfirm(
      context,
      title: 'Withdraw follow request to $name?',
      message: "They won't see the request any more. You can send a new one "
          "later.",
      confirmLabel: 'Withdraw',
    );
  }
  return showCLConfirm(
    context,
    title: 'Unfollow $name?',
    message: isRealm
        ? "You'll stop seeing this $realmNoun's posts in your feed. You can "
            "follow again anytime."
        : "You'll stop seeing their posts in your feed. You can follow again "
            "anytime.",
    confirmLabel: 'Unfollow',
  );
}
