// Full-screen "in a call" UI, audio-only (video tiles are M7's concern -
// this screen only ever shows a roster list + mic/speaker/end-call
// controls). Rebuilds off CallController.instance directly via
// ListenableBuilder rather than owning any call-engine state itself,
// matching the mobile calling plan's CallController design.

import 'package:chatterloop_app/core/calls/call_controller.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/call_api.dart';
import 'package:chatterloop_app/models/call_models/call_signed_payloads_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ActiveCallView extends StatefulWidget {
  const ActiveCallView({super.key});

  @override
  State<ActiveCallView> createState() => _ActiveCallViewState();
}

class _ActiveCallViewState extends State<ActiveCallView> {
  bool _endingOrGone = false;

  Future<void> _endCall() async {
    if (_endingOrGone) return;
    setState(() => _endingOrGone = true);

    final current = appStore.state.currentCall;
    // Only the caller ever notifies the other side explicitly (matches
    // webapp's CallWindow.tsx isCaller gate) - a callee hanging up just
    // leaves the mediasoup room below, surfacing to the caller as an
    // ordinary participant-left roster event, nothing more.
    if (current != null && current.isOutgoing && current.recepients.isNotEmpty) {
      CallApi().endCallRequest(IEndCallRequest(
        conversationID: current.conversationID,
        conversationType: current.conversationType,
        recepients: current.recepients,
      ));
    }

    await CallController.instance.leaveCall();
    appStore.dispatch(DispatchModel(clearCurrentCallT, null));
    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/messages');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Hanging up is an explicit button, not a back-swipe - mirrors
      // IncomingCallView's same guard.
      canPop: false,
      child: ListenableBuilder(
        listenable: CallController.instance,
        builder: (context, _) {
          final controller = CallController.instance;

          // The call ended out from under this screen - either the other
          // side's decline/hangup arrived via sse_events.dart's
          // "callreject" case (which calls leaveCall() directly), or the
          // other side just silently left the mediasoup room with no
          // explicit signal at all (webapp only sends an end signal from
          // whichever side placed the call - see CallController's
          // _maybeEndOnEmptyRoster). Either way status ends up idle here
          // and this screen needs to both pop AND clear the cross-screen
          // Redux signal - _endCall() below does the latter for an
          // explicit hangup, but this branch is the only place that does
          // it for the other two paths, which don't go through _endCall().
          if (controller.status == CallEngineStatus.idle && !_endingOrGone) {
            _endingOrGone = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              appStore.dispatch(DispatchModel(clearCurrentCallT, null));
              if (!mounted) return;
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/messages');
              }
            });
          }

          final connecting = controller.status == CallEngineStatus.joining;
          final statusText = connecting
              ? "Connecting…"
              : controller.participants.isEmpty
                  ? "Ringing…"
                  : "Connected";

          return Scaffold(
            backgroundColor: const Color(0xFF14161A),
            body: SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  const CircleAvatar(
                    radius: 56,
                    backgroundColor: CLColors.brand300,
                    child: Icon(Icons.person, color: Colors.white, size: 48),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    controller.isGroup ? "Group call" : "Call",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(statusText,
                      style: const TextStyle(color: Colors.white70, fontSize: 15)),
                  if (controller.participants.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    ...controller.participants.map((p) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            p.username ?? p.clientId,
                            style:
                                const TextStyle(color: Colors.white60, fontSize: 14),
                          ),
                        )),
                  ],
                  const Spacer(flex: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CallControlButton(
                          icon: controller.muted ? Icons.mic_off : Icons.mic,
                          active: controller.muted,
                          onPressed: controller.isActive
                              ? () => controller.toggleMic()
                              : null,
                        ),
                        _CallControlButton(
                          icon: controller.speakerOn
                              ? Icons.volume_up
                              : Icons.hearing,
                          active: controller.speakerOn,
                          onPressed: controller.isActive
                              ? () => controller.toggleSpeaker()
                              : null,
                        ),
                        Material(
                          color: CLColors.pink,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _endingOrGone ? null : _endCall,
                            child: const Padding(
                              padding: EdgeInsets.all(18),
                              child: Icon(Icons.call_end,
                                  color: Colors.white, size: 30),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;

  const _CallControlButton(
      {required this.icon, required this.active, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Colors.white : Colors.white24,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(icon,
              color: active ? const Color(0xFF14161A) : Colors.white, size: 24),
        ),
      ),
    );
  }
}
