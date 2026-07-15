/// The thin, Redux-friendly descriptor of "there is currently a call" -
/// deliberately kept minimal (no transports/consumers/roster - that's all
/// CallController's job, see the mobile calling plan's state-split
/// rationale). Just enough for cross-screen UI gating: is a call active,
/// which conversation, what kind.
class CallSession {
  final String conversationID;

  /// "single" | "group"
  final String conversationType;

  /// "audio" | "video"
  final String callType;

  /// True if this device placed the call rather than answered it - drives
  /// which screen shows first (active-call vs incoming-call already having
  /// been dismissed).
  final bool isOutgoing;

  /// Every other participant's entityID, captured at initiation time -
  /// only meaningful when isOutgoing is true. webapp's CallWindow.tsx only
  /// ever sends EndCallRequest from the caller's side (isCaller gate) - a
  /// callee hanging up just leaves the mediasoup room, with no explicit
  /// signal to the caller beyond the ordinary participant-left event - so
  /// this is only needed/populated for the outgoing case. Kept here rather
  /// than derived from CallController's mediasoup roster at hangup time
  /// because the roster is empty until the other side actually joins - if
  /// the caller cancels before that happens, the roster alone can't tell
  /// the hangup handler who to notify.
  final List<String> recepients;

  bool get isGroup => conversationType != "single";

  const CallSession({
    required this.conversationID,
    required this.conversationType,
    required this.callType,
    required this.isOutgoing,
    this.recepients = const [],
  });
}
