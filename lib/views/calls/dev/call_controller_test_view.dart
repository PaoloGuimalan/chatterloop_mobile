// M3 verification screen: exercises the real CallController.instance
// (WebrtcApi-driven, not the hand-rolled REST calls in call_spike_view.dart)
// end to end on a real device. Same purpose as the M1 spike had for the raw
// sequence - prove the wrapped version behaves identically before any
// screen in the real UI (M5/M6) depends on it. Kept alongside
// call_spike_view.dart as a permanent debugging tool for the same reason:
// if a future milestone misbehaves, this exercises CallController alone,
// without Redux/incoming-call-screen/active-call-screen layers in the way.
//
// Not wired into app_router.dart - push it manually while debugging, e.g.
// `Navigator.push(context, MaterialPageRoute(builder: (_) =>
// const CallControllerTestView()))`.

import 'package:chatterloop_app/core/calls/call_controller.dart';
import 'package:flutter/material.dart';

const String _testConversationID = "84186354038942661132";

class CallControllerTestView extends StatelessWidget {
  const CallControllerTestView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = CallController.instance;
    return Scaffold(
      appBar: AppBar(title: const Text("CallController test (M3)")),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: controller.status == CallEngineStatus.idle
                            ? () => controller.joinCall(
                                  conversationID: _testConversationID,
                                  conversationType: "single",
                                  callType: "audio",
                                  isOutgoing: true,
                                  startMuted: false,
                                )
                            : null,
                        child: Text(controller.status == CallEngineStatus.joining
                            ? "Joining…"
                            : "Join call"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: controller.isActive
                            ? () => controller.toggleMic()
                            : null,
                        child: Text(controller.muted ? "Unmute" : "Mute"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: controller.status == CallEngineStatus.idle
                            ? null
                            : () => controller.leaveCall(),
                        child: const Text("Leave"),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  "status: ${controller.status}\n"
                  "clientId: ${controller.clientId}\n"
                  "conversationID: ${controller.conversationID}\n"
                  "muted: ${controller.muted}\n"
                  "participants: ${controller.joinedParticipants.length}\n"
                  "remote consumers: ${controller.consumers.length}\n"
                  "lastError: ${controller.lastError ?? '-'}",
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: controller.joinedParticipants
                      .map((p) => Text(
                            "${p.username.isNotEmpty ? p.username : p.clientId} "
                            "muted=${controller.participantStatuses[p.clientId]?.muted ?? false} "
                            "cameraOff=${controller.participantStatuses[p.clientId]?.cameraOff ?? false}",
                            style: const TextStyle(
                                fontSize: 12, fontFamily: 'monospace'),
                          ))
                      .toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
