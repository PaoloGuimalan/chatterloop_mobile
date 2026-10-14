import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:chatterloop_app/core/notifications/notification_renderer.dart';
import 'package:chatterloop_app/core/notifications/conversation_shortcuts.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

Future<void> logoutUser(BuildContext context) async {
  final store = StoreProvider.of<AppState>(context);
  // Explicit server logout FIRST, while still authenticated (before the
  // local token is cleared): the /u/logout endpoint nulls THIS device's FCM
  // push token on its session row, so it stops being a push target. The
  // separate status=false half is handled by the SSE close below. Best-
  // effort in a try/catch - a failed logout call must never block sign-out.
  try {
    await ApiClient.instance.dio.post(Endpoints().logout);
  } catch (_) {}
  store.dispatch(
      DispatchModel(resetAppStateT, UserAuth(false, UserAccount.empty)));
  SseConnection().closeConnection();
  await ApiClient.instance.clearToken();
  // Clear the tray and every stored push thread - notifications outlive the
  // session, so without this the next account to log in on this device would
  // see the previous one's messages sitting in the notification shade.
  await NotificationRenderer.dismissAll();
  // Shortcuts outlive the session too - without this the next account would
  // see the previous one's contacts in the launcher and the shade.
  await ConversationShortcuts.clearAll();
  if (context.mounted) context.go('/login');
}
