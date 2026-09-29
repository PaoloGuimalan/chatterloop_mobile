// One place that decides how an incoming direct or group call reaches the
// user, whichever way it arrived, and how its ring ends.
//
// A call can announce itself three ways: the `incomingcall` SSE (a live
// connection), a `call` push landing while the app is open, and a `call` push
// drawn by the background isolate while it isn't. Before this, only the first
// existed, and it pushed the full-screen ringing route even with the app in
// the background - where nobody could see it. Now:
//
//   app in front   -> the in-app ringing screen (IncomingCallView)
//   app behind     -> the ringing notification, the same one a push draws
//
// and every way a ring can end - answered or declined elsewhere, cancelled,
// the call ending - goes through [dismiss] or [missed], so the screen, the
// pending state and the tray entry can't disagree.

import 'package:chatterloop_app/core/calls/call_controller.dart';
import 'package:chatterloop_app/core/notifications/notification_renderer.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/routes/app_router.dart';
import 'package:chatterloop_app/models/call_models/call_session_model.dart';
import 'package:chatterloop_app/models/call_models/incoming_call_alert_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class IncomingCallAlerts {
  IncomingCallAlerts._();

  /// The conversation whose ringing screen this class last pushed. Stops the
  /// SAME ring being shown twice when two paths deliver it at once - a tap on
  /// the notification also resumes the app, and both want the screen.
  static String? _screenShownFor;

  static bool get _inForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// A call is ringing for this user.
  static void present(IncomingCallAlert alert) {
    // Busy on THIS device - dropped before anything is pushed or dispatched,
    // so no frame of a ringing screen ever paints over the live call.
    //
    // SILENT, never a decline: declining tells the caller they were refused,
    // and this same person may be free on another device that is ringing
    // right now. Every device answers for itself.
    //
    // CallController.isBusy, not appStore.state.currentCall: a voice channel
    // never sets currentCall. See its doc comment.
    if (CallController.instance.isBusy) {
      if (kDebugMode) {
        print("[calls] incoming call suppressed - already in a call "
            "(engine=${CallController.instance.status}, "
            "conversation=${CallController.instance.conversationID})");
      }
      return;
    }

    // The same ring from a second path (SSE and a push, say).
    final pending = appStore.state.pendingIncomingCall;
    if (pending?.conversationID == alert.conversationID) return;

    appStore.dispatch(DispatchModel(setPendingIncomingCallT, alert));
    if (_inForeground) {
      _pushScreen(alert);
    } else {
      NotificationRenderer.showCallRing(alert.toPushData());
    }
  }

  /// The ringing notification's body was tapped: open the in-app ringing
  /// screen, which offers everything the notification does plus "audio only".
  static Future<void> openRinging(IncomingCallAlert alert) async {
    await NotificationRenderer.cancelCallRing(alert.conversationID);
    if (CallController.instance.isBusy) return;
    if (appStore.state.pendingIncomingCall?.conversationID !=
        alert.conversationID) {
      appStore.dispatch(DispatchModel(setPendingIncomingCallT, alert));
    }
    _pushScreen(alert);
  }

  /// The notification's Join: straight into the call, no ringing screen.
  static Future<void> answerFromNotification(IncomingCallAlert alert) async {
    final joined = await answer(alert);
    if (joined) {
      appRouter.push('/call/active');
    } else if (!CallController.instance.isBusy) {
      // The call could not be joined - most often it ended in the moment
      // between the tap and the app opening. The conversation is where it
      // was, and where its missed call will point.
      appRouter.push('/conversation/${alert.conversationID}');
    }
  }

  /// Answers [alert] - IncomingCallView's Accept and the notification's Join
  /// both come here. True once the call is joined; navigation is the
  /// caller's, since only a screen with a BuildContext can replace itself.
  static Future<bool> answer(IncomingCallAlert alert,
      {bool cameraOff = false}) async {
    appStore.dispatch(DispatchModel(clearPendingIncomingCallT, null));
    _screenShownFor = null;
    await NotificationRenderer.cancelCallRing(alert.conversationID);

    // The callee's recipients (who to notify when WE leave) = the caller
    // plus every other participant the alert carries, minus ourselves.
    // Without this the callee had no recipients, so its leave-room couldn't
    // tell the caller it left. entityID throughout (matches webapp).
    final myEntityId = appStore.state.userAuth.user.entityId;
    final recepients = <String>{
      alert.caller.entityId,
      ...alert.recepients,
    }.where((e) => e.isNotEmpty && e != myEntityId).toList();

    final joined = await CallController.instance.joinCall(
      conversationID: alert.conversationID,
      conversationType: alert.conversationType,
      callType: alert.callType,
      isOutgoing: false,
      recepients: recepients,
      startCameraOff: cameraOff || alert.callType != "video",
    );
    if (!joined) return false;

    appStore.dispatch(DispatchModel(
        setCurrentCallT,
        CallSession(
            conversationID: alert.conversationID,
            conversationType: alert.conversationType,
            callType: alert.callType,
            isOutgoing: false,
            recepients: recepients)));
    return true;
  }

  /// This device's ring for [conversationId] is over, without a missed call:
  /// answered or declined on another device, or taken back. Clears the
  /// pending alert - which is what makes an open IncomingCallView dismiss
  /// itself - and the tray ring.
  static Future<void> dismiss(String conversationId) async {
    if (conversationId.isEmpty) return;
    if (appStore.state.pendingIncomingCall?.conversationID == conversationId) {
      appStore.dispatch(DispatchModel(clearPendingIncomingCallT, null));
      _screenShownFor = null;
    }
    await NotificationRenderer.cancelCallRing(conversationId);
  }

  /// The call ended without this user joining - the `callmissed` SSE, or a
  /// `call_missed` push landing while the app is open. [data] is the same
  /// notice either way, so both go through the renderer that draws it from a
  /// push (which also honours a Decline made on this device).
  static Future<void> missed(Map<String, dynamic> data) async {
    await dismiss((data['conversationID'] ?? '').toString());
    await NotificationRenderer.render(data);
  }

  /// The app came to the front. A call that started ringing while it was in
  /// the background is ringing in the tray; hand it over to the in-app
  /// screen. If the tray ring is gone, it was declined there or rang out, and
  /// the pending alert is stale.
  static Future<void> onResumed() async {
    final pending = appStore.state.pendingIncomingCall;
    if (pending == null || _screenShownFor == pending.conversationID) return;
    if (await NotificationRenderer.isCallRinging(pending.conversationID)) {
      await openRinging(pending);
    } else {
      appStore.dispatch(DispatchModel(clearPendingIncomingCallT, null));
    }
  }

  static void _pushScreen(IncomingCallAlert alert) {
    if (_screenShownFor == alert.conversationID) return;
    _screenShownFor = alert.conversationID;
    // appRouter (not a BuildContext) since this fires outside any widget's
    // tree.
    appRouter.push('/call/incoming', extra: alert);
  }

  /// IncomingCallView is gone - accepted, declined, dismissed - so the next
  /// ring for the same conversation may show the screen again.
  static void screenClosed(String conversationId) {
    if (_screenShownFor == conversationId) _screenShownFor = null;
  }
}
