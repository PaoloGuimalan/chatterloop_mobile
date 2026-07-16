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
    // Already on a call somewhere else in the app (e.g. we're the caller
    // of a different conversation) - decline immediately rather than show
    // an alert the user can't actually act on without first ending their
    // current call. Real group-call "second incoming call" UX (hold/
    // switch) is out of scope for this pass.
    if (appStore.state.currentCall != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _decline());
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

  Future<void> _accept() async {
    if (_resolving) return;
    setState(() => _resolving = true);
    _autoDeclineTimer?.cancel();
    CallRingManager.stop();
    appStore.dispatch(DispatchModel(clearPendingIncomingCallT, null));

    final joined = await CallController.instance.joinCall(
      conversationID: widget.alert.conversationID,
      conversationType: widget.alert.conversationType,
      callType: widget.alert.callType,
      isOutgoing: false,
      startCameraOff: widget.alert.callType != "video",
    );
    if (!mounted) return;
    if (!joined) {
      Navigator.of(context).pop();
      return;
    }
    appStore.dispatch(DispatchModel(
        setCurrentCallT,
        CallSession(
            conversationID: widget.alert.conversationID,
            conversationType: widget.alert.conversationType,
            callType: widget.alert.callType,
            isOutgoing: false)));
    context.go('/call/active');
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
        backgroundColor: const Color(0xFF14161A),
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              CircleAvatar(
                radius: 56,
                backgroundColor: CLColors.brand300,
                backgroundImage: hasImage ? NetworkImage(alert.displayImage!) : null,
                child: hasImage
                    ? null
                    : Text(
                        alert.caller.name.isNotEmpty
                            ? alert.caller.name[0].toUpperCase()
                            : "?",
                        style: const TextStyle(
                            fontSize: 40,
                            color: Colors.white,
                            fontWeight: FontWeight.w600),
                      ),
              ),
              const SizedBox(height: 20),
              Text(
                alert.callDisplayName.isNotEmpty
                    ? alert.callDisplayName
                    : alert.caller.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                alert.callType == "video"
                    ? "Incoming video call"
                    : "Incoming voice call",
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CallActionButton(
                      icon: Icons.call_end,
                      color: CLColors.pink,
                      label: "Decline",
                      onPressed: _resolving ? null : _decline,
                    ),
                    _CallActionButton(
                      icon: Icons.call,
                      color: CLColors.green,
                      label: "Accept",
                      onPressed: _resolving ? null : _accept,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}
