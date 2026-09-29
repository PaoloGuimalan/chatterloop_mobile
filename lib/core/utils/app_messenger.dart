// A notice reachable without a BuildContext.
//
// Exists for work that OUTLIVES the widget that started it. A media download
// keeps running after you leave the conversation - that is the whole point of
// it being a background download - so by the time it finishes, the State that
// kicked it off may be disposed and its context dead.
//
// Now a thin shim over CLAlerts, which needs no context at all and draws above
// every screen. The ScaffoldMessenger key stays wired on MaterialApp.router in
// main.dart for anything Material still routes through it.

import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> clMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Shows [message] as a notice over whatever screen is up. [type] defaults to
/// info - a download's outcome is news, not a problem.
void clSnack(
  String message, {
  SnackBarAction? action,
  CLAlertType type = CLAlertType.info,
}) {
  CLAlerts.show(
    message,
    type: type,
    action: action == null
        ? null
        : CLAlertAction(label: action.label, onPressed: action.onPressed),
  );
}
