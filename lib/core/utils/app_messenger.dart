// One ScaffoldMessenger for the whole app, reachable without a BuildContext.
//
// Exists for work that OUTLIVES the widget that started it. A media download
// keeps running after you leave the conversation - that is the whole point of
// it being a background download - so by the time it finishes, the State that
// kicked it off may be disposed and its context dead. ScaffoldMessenger.of
// (context) needs a mounted element; this key does not.
//
// Wired once, on MaterialApp.router in main.dart.

import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> clMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Shows [message] on whatever screen is up, or does nothing if the app has
/// no messenger yet (before the first frame, or after teardown). Silently
/// dropping the message is right here - a download's outcome is never worth
/// throwing over.
void clSnack(String message, {SnackBarAction? action}) {
  final messenger = clMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}
