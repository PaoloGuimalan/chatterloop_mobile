// Full-screen ringing alert, native-phone-call style (user-confirmed
// preference over webapp's slide-in banner - see the mobile calling plan's
// Context section). Reads the alert passed via GoRouter's `extra` (pushed
// from sse_events.dart's "incomingcall" case using the global `appRouter`
// getter, since that fires outside any widget's BuildContext).

import 'dart:async';

import 'package:chatterloop_app/core/calls/call_controller.dart';
import 'package:chatterloop_app/core/calls/call_ring_manager.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/call_api.dart';
import 'package:chatterloop_app/models/call_models/call_session_model.dart';
import 'package:chatterloop_app/models/call_models/incoming_call_alert_model.dart';
import 'package:chatterloop_app/models/call_models/call_signed_payloads_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

class IncomingCallView extends StatefulWidget {
  final IncomingCallAlert alert;

  const IncomingCallView({super.key, required this.alert});

  @override
  State<IncomingCallView> createState() => _IncomingCallViewState();
}

class _IncomingCallViewState extends State<IncomingCallView> {
  Timer? _autoDeclineTimer;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    // Busy on this device. sse_events.dart's "incomingcall" case now drops
    // these before the route is ever pushed, so this is a backstop for the
    // race where the engine goes busy between that check and this frame -
    // it should not normally be reached.
    //
    // Two changes from what used to live here. It reads the ENGINE rather
    // than appStore.state.currentCall, which a voice channel never sets (see
    // CallController.isBusy); and it dismisses SILENTLY rather than calling
    // _decline(), because declining tells the caller they were refused and
    // ends their call - taking it away from this user's other devices, any
    // of which may be free and ringing. Real "second incoming call" UX
    // (hold/switch) is still out of scope.
    if (CallController.instance.isBusy) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _dismissBusy());
      return;
    }
    CallRingManager.start();
    _autoDeclineTimer = Timer(const Duration(seconds: 60), _decline);
  }

  @override
  void dispose() {
    _autoDeclineTimer?.cancel();
    CallRingManager.stop();
    super.dispose();
  }

  /// [cameraOff] answers a VIDEO call without sending video - the design's
  /// "Audio only" button. It is only an option on a video call; on a voice
  /// call the camera is already off and the button is not rendered.
  Future<void> _accept({bool cameraOff = false}) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    _autoDeclineTimer?.cancel();
    CallRingManager.stop();
    appStore.dispatch(DispatchModel(clearPendingIncomingCallT, null));

    // The callee's recipients (who to notify when WE leave) = the caller
    // plus every other participant the alert carries, minus ourselves.
    // Without this the callee had no recipients, so its leave-room couldn't
    // tell the caller it left. entityID throughout (matches webapp).
    final myEntityId = appStore.state.userAuth.user.entityId;
    final recepients = <String>{
      widget.alert.caller.entityId,
      ...widget.alert.recepients,
    }.where((e) => e.isNotEmpty && e != myEntityId).toList();

    final joined = await CallController.instance.joinCall(
      conversationID: widget.alert.conversationID,
      conversationType: widget.alert.conversationType,
      callType: widget.alert.callType,
      isOutgoing: false,
      recepients: recepients,
      startCameraOff: cameraOff || widget.alert.callType != "video",
    );
    if (!mounted) return;
    if (!joined) {
      // joinCall refuses anything but an idle engine, so the usual reason to
      // land here is that this device is already occupied - most often a
      // voice channel, which does not set currentCall and so does not read as
      // busy to the guards above. It used to pop in silence: the alert simply
      // vanished on Accept, with no call and no explanation.
      //
      // Says so, and still declines nothing - the caller keeps ringing, and
      // this user's other devices keep their chance to answer.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(CallController.instance.isBusy
            ? "Leave your current call before answering."
            : (CallController.instance.lastError ??
                "Could not join the call.")),
      ));
      Navigator.of(context).pop();
      return;
    }
    appStore.dispatch(DispatchModel(
        setCurrentCallT,
        CallSession(
            conversationID: widget.alert.conversationID,
            conversationType: widget.alert.conversationType,
            callType: widget.alert.callType,
            isOutgoing: false,
            recepients: recepients)));
    // pushReplacement (not go) so THIS incoming-call route is REPLACED by
    // the active-call route rather than left underneath it. With go,
    // go_router can keep this imperatively-pushed page in the stack, so
    // when the call later ends and the active screen pops, this incoming
    // screen briefly reappears before dismissing itself - the flash the
    // caller/callee sees on hang-up.
    context.pushReplacement('/call/active');
  }

  Future<void> _decline() async {
    if (_resolving) return;
    setState(() => _resolving = true);
    _autoDeclineTimer?.cancel();
    CallRingManager.stop();
    appStore.dispatch(DispatchModel(clearPendingIncomingCallT, null));
    // Fire-and-forget - the caller's own screen tears down via the
    // `callreject` SSE event this triggers, no response payload to wait on.
    CallApi().rejectCallRequest(IRejectCallRequest(
      conversationType: widget.alert.conversationType,
      conversationID: widget.alert.conversationID,
      caller: widget.alert.caller,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  /// Busy on this device: take the alert away without telling anybody.
  ///
  /// Clears the pending state the SSE handler may already have dispatched
  /// (the race this guards), stops any ringtone, and pops. Notifies nothing -
  /// see initState for why a busy device must not decline on the user's
  /// behalf.
  void _dismissBusy() {
    if (_resolving) return;
    setState(() => _resolving = true);
    _autoDeclineTimer?.cancel();
    CallRingManager.stop();
    appStore.dispatch(DispatchModel(clearPendingIncomingCallT, null));
    if (mounted) Navigator.of(context).pop();
  }

  /// The caller cancelled/ended this call while it was still ringing -
  /// sse_events.dart's "callreject" case already dispatched
  /// clearPendingIncomingCallT for us (webapp's CallWindow.tsx sends
  /// EndCallRequest from the caller's side regardless of whether the
  /// callee has answered yet), so unlike _decline() above there's nothing
  /// left to notify - just tear down locally.
  void _dismissRemotely() {
    if (_resolving) return;
    setState(() => _resolving = true);
    _autoDeclineTimer?.cancel();
    CallRingManager.stop();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    final hasImage = alert.displayImage != null && alert.displayImage != "none";
    return StoreConnector<AppState, bool>(
      distinct: true,
      converter: (store) =>
          store.state.pendingIncomingCall?.conversationID == alert.conversationID,
      builder: (context, isStillPending) {
        if (!isStillPending && !_resolving) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _dismissRemotely());
        }
        return _buildScaffold(alert, hasImage);
      },
    );
  }

  Widget _buildScaffold(IncomingCallAlert alert, bool hasImage) {
    return PopScope(
      // Back press declines, same as ActiveCallView's back-press-hangs-up -
      // never a silent dismiss (canPop: true would leave the call ringing
      // in the background with no visible alert) and never a dead end if
      // the automatic dismiss-on-remote-cancel logic above ever has a gap.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!_resolving) _decline();
      },
      child: Scaffold(
        backgroundColor: CLColors.callBg,
        body: SafeArea(
          // 6/10/10 and a 10 gap between panels, from the design. The three
          // panels are the whole screen: a banner, the caller, the answers.
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Column(
              children: [
                _banner(),
                const SizedBox(height: 10),
                Expanded(child: _callerPanel(alert, hasImage)),
                const SizedBox(height: 10),
                _answers(alert),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The "Incoming call" strip. Says what the screen IS, which matters when it
  /// appears over whatever the user was doing.
  Widget _banner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CLColors.callPanel,
        borderRadius: BorderRadius.circular(CLColors.callRadius),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: CLColors.callBrandSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.call, size: 18, color: CLColors.callBrand),
          ),
          const SizedBox(width: 10),
          const Text(
            "Incoming call",
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: CLColors.callText2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _callerPanel(IncomingCallAlert alert, bool hasImage) {
    final name = alert.callDisplayName.isNotEmpty
        ? alert.callDisplayName
        : alert.caller.name;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: CLColors.callPanel,
        borderRadius: BorderRadius.circular(CLColors.callRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 56, // 112 across, per the design
            backgroundColor: CLColors.brand300,
            backgroundImage:
                hasImage ? NetworkImage(alert.displayImage!) : null,
            child: hasImage
                ? null
                : Text(
                    name.isNotEmpty ? name[0].toUpperCase() : "?",
                    style: const TextStyle(
                        fontSize: 38,
                        color: Colors.white,
                        fontWeight: FontWeight.w700),
                  ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: CLColors.callText,
                fontSize: 18,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            alert.callType == "video"
                ? "Video call · ringing…"
                : "Voice call · ringing…",
            style: const TextStyle(color: CLColors.callText2, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _answers(IncomingCallAlert alert) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: CLColors.callPanel,
        borderRadius: BorderRadius.circular(CLColors.callRadius),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CallActionButton(
            icon: Icons.call_end,
            color: CLColors.callEnd,
            label: "Decline",
            onPressed: _resolving ? null : _decline,
          ),
          // Only on a VIDEO call - answering a voice call "audio only" is
          // answering it normally, so the button would be a third way to do
          // what Accept already does.
          if (alert.callType == "video")
            _CallActionButton(
              icon: Icons.videocam_off,
              color: CLColors.callControl,
              label: "Audio only",
              onPressed: _resolving ? null : () => _accept(cameraOff: true),
            ),
          _CallActionButton(
            icon: Icons.call,
            color: CLColors.callAccept,
            label: "Accept",
            onPressed: _resolving ? null : _accept,
          ),
        ],
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onPressed;

  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 62 across with a 24 glyph, per the design. Sized rather than padded
        // so all three answers are the same circle regardless of their icon.
        Material(
          color: color,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 62,
              height: 62,
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(color: CLColors.callText2, fontSize: 12)),
      ],
    );
  }
}
