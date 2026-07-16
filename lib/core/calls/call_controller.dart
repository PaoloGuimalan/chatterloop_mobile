// A deliberately close, near line-by-line Dart port of webapp's
// calls_v2/CallWindow.tsx (React), which is the proven-stable reference
// implementation for this whole feature. Every state var, ref, callback,
// and effect below is named and structured to mirror its counterpart
// there directly (comments cite the original's line numbers) rather than
// being independently redesigned - several rounds of independent
// "reasonable-looking" Dart implementations turned out subtly wrong in
// ways only real-device testing surfaced, so this pass prioritizes
// fidelity to the known-working structure over idiomatic-Dart cleanliness.
//
// React's useEffect has no direct Dart equivalent, so each one becomes a
// private `_maybeXxx()` method with the SAME guard condition as the
// original's dependency-array + internal check, called explicitly from
// every place that mutates any of its "dependencies" - the closest
// faithful translation of "re-run whenever these values change" into an
// imperative language. useState becomes plain fields + notifyListeners();
// useRef becomes plain fields with no notifyListeners (mutating them alone
// never triggers a UI rebuild, same as in React). useCallback/useMemo
// become plain methods/getters - Dart doesn't memoize allocations the way
// React does, but nothing here depends on referential equality the way
// React's dependency arrays sometimes implicitly do.
//
// Two structural adaptations from the original, both because this is a
// singleton reused across many calls rather than a component that mounts
// fresh per call and fully unmounts after:
//   - cleanupLocalCallResources here ALSO nulls out mediaStream/
//     sendTransport/recvTransport/device (the original doesn't need to,
//     since its whole component instance is destroyed right after).
//   - The caller/recepients data webapp reads from its `data` prop is
//     passed into joinCall() as explicit parameters instead (isOutgoing,
//     recepients) - this app already resolves those via Redux's
//     CallSession at the UI layer (M5/M6), so there's no separate `data`
//     object to carry them.

// ignore_for_file: library_private_types_in_public_api, unused_element, duplicate_ignore, unused_field

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:chatterloop_app/core/requests/webrtc_api.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:mediasoup_client_flutter/mediasoup_client_flutter.dart';

/// {clientId, username} only - matches webapp's joinedParticipants exactly
/// (CallWindow.tsx line 78-80). Mute/camera-off status is tracked
/// SEPARATELY in participantStatuses, same split as webapp - deliberately
/// not bundled into one model the way call_models/CallParticipant is.
class JoinedParticipant {
  final String clientId;
  final String username;
  const JoinedParticipant({required this.clientId, required this.username});
}

class ParticipantStatusEntry {
  final bool muted;
  final bool cameraOff;
  const ParticipantStatusEntry({this.muted = false, this.cameraOff = false});
}

/// Matches webapp's consumers map value shape exactly (CallWindow.tsx line
/// 730: `{id, kind, consumer, ownerClientId, source}`).
class ConsumerEntry {
  final String id;
  final String kind;
  final Consumer consumer;
  final String? ownerClientId;
  final String? source;
  const ConsumerEntry({
    required this.id,
    required this.kind,
    required this.consumer,
    this.ownerClientId,
    this.source,
  });
}

class _PendingConsumeResponse {
  final String id;
  final String producerId;
  final String kind;
  final Map<String, dynamic> rtpParameters;
  final String? ownerClientId;
  final String? source;
  const _PendingConsumeResponse({
    required this.id,
    required this.producerId,
    required this.kind,
    required this.rtpParameters,
    this.ownerClientId,
    this.source,
  });
}

class _PendingProduceTrack {
  final String kind;
  final MediaStreamTrack track;
  final String? source;
  _PendingProduceTrack({required this.kind, required this.track, this.source});
}

/// One in-flight transport.produce() call awaiting its resulting
/// producerId - resolved by EITHER "produce-response" or our own
/// "new_producer" echo, whichever arrives first (see the long comment at
/// the 'produce' transport listener for why both are needed).
class _PendingProduce {
  final String kind;
  final Completer<String> completer;
  _PendingProduce(this.kind, this.completer);
}

/// Matches webapp's connectTransportState/connectRecvTransportState shape
/// exactly (CallWindow.tsx lines 60-70): `{params, instance, triggered}`.
class _TransportConnectState {
  Map<String, dynamic>? params;
  String? instance;
  bool triggered = false;
}

enum CallEngineStatus { idle, joining, active, leaving }

class CallController extends ChangeNotifier {
  CallController._();
  static final CallController instance = CallController._();

  final _dio = ApiClient.instance.dio;
  final _webrtcApi = WebrtcApi();
  final _endpoints = Endpoints();

  // ── Cross-cutting fields not present in webapp - needed for this app's
  // own Redux/routing/UI integration, no equivalent in CallWindow.tsx ────
  CallEngineStatus status = CallEngineStatus.idle;
  String? conversationID;
  String? conversationType; // "single" | "group"
  String? callType; // "audio" | "video"
  String? lastError;
  bool speakerOn = false; // mobile-only - webapp has no speakerphone concept
  bool isOutgoing = false;
  List<String> endCallRecepients = const [];

  // ── State (mirrors webapp's useState, CallWindow.tsx lines 43-86) ─────
  MediaStream? mediaStream;
  Device? device;
  bool enableMic = true;
  bool enableCamera = false;
  final _TransportConnectState connectTransportState = _TransportConnectState();
  final _TransportConnectState connectRecvTransportState =
      _TransportConnectState();
  Transport? sendTransport;
  Transport? recvTransport;
  final List<_PendingConsumeResponse> pendingConsumeResponses = [];
  final Map<String, ConsumerEntry> consumers = {}; // keyed by producerId
  final List<JoinedParticipant> joinedParticipants = [];
  final List<String> pendingProducerIds = [];
  final Map<String, ParticipantStatusEntry> participantStatuses = {};
  MediaStream? screenStream;
  bool isScreenSharing = false;

  // ── Refs (mirrors webapp's useRef, CallWindow.tsx lines 87-119) - plain
  // mutable fields, never trigger notifyListeners on their own ───────────
  bool _hasLeft = false;
  bool _hasJoined = false;
  bool _isConsuming = false;
  final Map<String, String> _producerOwner = {}; // producerId -> clientId
  final Map<String, String> _producerSource = {}; // producerId -> source
  final List<_PendingProduceTrack> _pendingProduceTracks = [];
  String? _clientId;
  Producer? _audioProducer;
  Producer? _videoProducer;
  Producer? _screenProducer;
  Producer? _screenAudioProducer;
  Map<String, dynamic>? _encodings; // {camera: [...], screenshare: [...]}
  // ignore: unused_field
  bool _isReconnecting = false; // M9's concern - not wired to anything yet

  StreamSubscription? _sseSub;

  // ── Derived (mirrors webapp's useMemo `members`, CallWindow.tsx
  // lines 129-145) - this app resolves it once at joinCall() time instead
  // of recomputing per-render, since there's no render loop here.
  List<String> members = const [];

  String get clientId => _clientId ?? '';
  bool get isGroup => conversationType != null && conversationType != "single";
  bool get isActive => status == CallEngineStatus.active;

  /// Kept for the UI - the local track actually being produced for camera,
  /// distinct from mediaStream's raw video track list (mirrors how webapp
  /// reads mediaStream.getVideoTracks()[0] directly instead of keeping a
  /// separate ref for it - this app keeps one for the mute/switch-camera
  /// controls' convenience).
  MediaStreamTrack? get localVideoTrack =>
      mediaStream?.getVideoTracks().isNotEmpty == true
          ? mediaStream!.getVideoTracks().first
          : null;

  // ════════════════════════════════════════════════════════════════════
  // cleanupLocalCallResources (CallWindow.tsx lines 149-173)
  // ════════════════════════════════════════════════════════════════════
  void _cleanupLocalCallResources() {
    for (final t in mediaStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      t.stop();
    }
    for (final t in screenStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      t.stop();
    }
    sendTransport?.close();
    recvTransport?.close();
    for (final entry in consumers.values) {
      entry.consumer.close();
    }
    consumers.clear();
    pendingProducerIds.clear();
    pendingConsumeResponses.clear();
    joinedParticipants.clear();
    participantStatuses.clear();
    _producerOwner.clear();
    _producerSource.clear();
    _audioProducer?.close();
    _videoProducer?.close();
    _screenProducer?.close();
    _screenAudioProducer?.close();
    _audioProducer = null;
    _videoProducer = null;
    _screenProducer = null;
    _screenAudioProducer = null;
    _pendingProduceTracks.clear();
    screenStream = null;
    isScreenSharing = false;
    // Adaptation (see file header): the original doesn't null these,
    // since its whole component instance is destroyed right after this
    // runs - this singleton needs to start the NEXT call clean instead.
    mediaStream = null;
    sendTransport = null;
    recvTransport = null;
    device = null;
    connectTransportState.params = null;
    connectTransportState.instance = null;
    connectTransportState.triggered = false;
    connectRecvTransportState.params = null;
    connectRecvTransportState.instance = null;
    connectRecvTransportState.triggered = false;
    _sendTransportState = null;
    _recvTransportState = null;
    _videoProduceAttempts = 0;
    videoProduceFailed = false;
  }

  // ════════════════════════════════════════════════════════════════════
  // cleanupTransportsOnly (CallWindow.tsx lines 178-205) - reconnect-only
  // teardown, preserves media/participants for UI stability. M9's
  // concern; not wired to a reconnect trigger yet, ported for structural
  // fidelity.
  // ════════════════════════════════════════════════════════════════════
  void _cleanupTransportsOnly() {
    sendTransport?.close();
    recvTransport?.close();
    for (final entry in consumers.values) {
      entry.consumer.close();
    }
    consumers.clear();
    pendingProducerIds.clear();
    pendingConsumeResponses.clear();
    _producerOwner.clear();
    _producerSource.clear();
    _audioProducer?.close();
    _videoProducer?.close();
    _audioProducer = null;
    _videoProducer = null;
    _pendingProduceTracks.clear();
    sendTransport = null;
    recvTransport = null;
    device = null;
    connectTransportState.params = null;
    connectTransportState.instance = null;
    connectTransportState.triggered = false;
    connectRecvTransportState.params = null;
    connectRecvTransportState.instance = null;
    connectRecvTransportState.triggered = false;
  }

  // ════════════════════════════════════════════════════════════════════
  // rejoinRoom (CallWindow.tsx lines 209-236) - M9's concern (reconnect),
  // ported for structural fidelity, not wired to a trigger yet.
  // ════════════════════════════════════════════════════════════════════
  // ignore: unused_element
  Future<void> _rejoinRoom() async {
    _hasJoined = false;
    _isReconnecting = true;
    try {
      await _webrtcApi.joinRoomRequest(
        conversationID: conversationID!,
        members: members,
        muted: !enableMic,
        cameraOff: !enableCamera,
        username: appStore.state.userAuth.user.username,
        clientId: clientId,
      );
    } finally {
      _hasJoined = true;
      _isReconnecting = false;
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // leaveCallProcess (CallWindow.tsx lines 238-320) - this app's public
  // leaveCall() below is the entry point; keepalive (browser tab-close
  // fetch) has no mobile equivalent and is simplified away, always
  // running the normal leave-room request instead.
  // ════════════════════════════════════════════════════════════════════
  Future<void> leaveCall() async {
    if (_hasLeft) return;
    _hasLeft = true;
    status = CallEngineStatus.leaving;
    notifyListeners();

    // The REST call and local teardown below must never leave `status`
    // stuck on `leaving` - a screen watching this controller (ActiveCallView)
    // only pops once status reaches `idle`, so any unhandled exception here
    // (a failed/timed-out leave-room request, or closing an already-closed
    // transport/producer/consumer during a remote-initiated teardown) would
    // otherwise strand the user on the call screen with no way out.
    try {
      final recepients =
          endCallRecepients.isNotEmpty ? endCallRecepients : members;

      // Only the caller ever notifies the other side explicitly (matches
      // webapp's isCaller gate exactly) - a callee hanging up just leaves
      // the mediasoup room below, surfacing to the caller as an ordinary
      // participant-left roster event.
      if (isOutgoing && recepients.isNotEmpty && conversationID != null) {
        await _webrtcApi.leaveRoomRequest(
          conversationID: conversationID!,
          clientId: clientId,
          recipients: recepients,
        );
      } else if (conversationID != null) {
        await _webrtcApi.leaveRoomRequest(
          conversationID: conversationID!,
          clientId: clientId,
        );
      }
    } catch (e) {
      if (kDebugMode) print("[CallController] leave-room request failed: $e");
    }

    try {
      _cleanupLocalCallResources();
    } catch (e) {
      if (kDebugMode) print("[CallController] cleanup failed: $e");
    }

    status = CallEngineStatus.idle;
    conversationID = null;
    conversationType = null;
    callType = null;
    lastError = null;
    isOutgoing = false;
    endCallRecepients = const [];
    members = const [];
    _hasJoined = false;
    _hasLeft = false;
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════════════
  // createTransportProcess (CallWindow.tsx lines 340-364)
  // ════════════════════════════════════════════════════════════════════
  Future<void> _createTransportProcess(String? instance) async {
    // notify-voice-join - webapp calls this unconditionally before
    // creating transports, fanning out a "voice-joined" presence event
    // and registering with a separate participant tracker
    // (server/routes/users/index.js's /notify-voice-join,
    // reusables/hooks/sse.js's ReachVoiceRecepients + addParticipant).
    // Ported for fidelity; failures here are non-fatal to the call itself.
    try {
      final me = appStore.state.userAuth.user;
      await _dio.post('/u/notify-voice-join', data: {
        'clientID': clientId,
        'profile': me.activeAvatarSrc,
        'channelID': conversationID,
        'recipients': members,
        'instance': instance,
      });
    } catch (e) {
      if (kDebugMode) print("[CallController] notify-voice-join failed: $e");
    }

    await _webrtcApi.createTransportRequest(
      conversationID: conversationID!,
      direction: "send",
      clientId: clientId,
    );
    await _webrtcApi.createTransportRequest(
      conversationID: conversationID!,
      direction: "recv",
      clientId: clientId,
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // joinRoomProcess (CallWindow.tsx lines 366-406)
  // ════════════════════════════════════════════════════════════════════
  Future<void> _joinRoomProcess(Map<String, dynamic> routerRtpCapabilities,
      String? instance, List<CallParticipantRaw> participants) async {
    final incoming = participants.where((p) => p.clientId != clientId).toList();

    for (final p in incoming) {
      joinedParticipants.removeWhere((jp) => jp.clientId == p.clientId);
      joinedParticipants
          .add(JoinedParticipant(clientId: p.clientId, username: p.username));
      participantStatuses[p.clientId] =
          ParticipantStatusEntry(muted: p.muted, cameraOff: p.cameraOff);
    }
    notifyListeners();

    final newDevice = Device();
    await newDevice.load(
        routerRtpCapabilities: RtpCapabilities.fromMap(routerRtpCapabilities));
    device = newDevice;
    notifyListeners();

    await _createTransportProcess(instance);
  }

  // ════════════════════════════════════════════════════════════════════
  // useEffect #2 - send transport creation (CallWindow.tsx lines 408-557)
  // ════════════════════════════════════════════════════════════════════
  void _maybeCreateSendTransport() {
    if (device == null ||
        connectTransportState.params == null ||
        mediaStream == null ||
        connectTransportState.triggered) {
      return;
    }
    connectTransportState.triggered = true;

    final transport = device!.createSendTransportFromMap(
      connectTransportState.params!,
      producerCallback: _handleProducerCreated,
    );
    sendTransport = transport;
    notifyListeners();

    transport.on('connect', (data) {
      final callback = data['callback'] as Function;
      final errback = data['errback'] as Function;
      try {
        _webrtcApi.transportConnectRequest(
          conversationID: conversationID!,
          transportId: connectTransportState.params!['id'],
          dtlsParameters: (data['dtlsParameters'] as DtlsParameters).toMap(),
          clientId: clientId,
        );
        callback();
      } catch (e) {
        errback(e);
      }
    });
    transport.on('connectionstatechange', (data) {
      _sendTransportState = data['connectionState']?.toString();
      _maybeAutoEndOnTransportClosed();
    });

    transport.on('produce', (data) async {
      final callback = data['callback'] as Function;
      final errback = data['errback'] as Function;
      final rtpParams = data['rtpParameters'] as RtpParameters;
      // CRITICAL: data['kind'] is the track's kind as a plain STRING
      // ("audio"/"video") - it comes straight from `arguments.track.kind`
      // in mediasoup_client_flutter's Transport._produce (transport.dart
      // line 884), NOT the RTCRtpMediaType enum. The previous code here
      // compared it against RTCRtpMediaType.RTCRtpMediaTypeAudio (an
      // enum), which a String can never equal - so EVERY produce, audio
      // included, was labelled "video" and sent to /webrtc/produce with
      // kind:"video". That created a bogus server-side "video" producer
      // carrying an opus (audio) codec; when webapp tried to consume it,
      // setupTransport threw "no a=setup found at SDP session or media
      // level", which poisoned webapp's whole recv transport so the real
      // video consumer then also failed with "Failed to setup RTCP mux".
      // One bug, both webapp symptoms, both media directions dead.
      // Derive kind from the actual first codec's mimeType instead -
      // bulletproof regardless of what type data['kind'] arrives as.
      final firstMime = rtpParams.codecs.isNotEmpty
          ? rtpParams.codecs.first.mimeType.toLowerCase()
          : "";
      final kind = firstMime.startsWith("audio") ? "audio" : "video";
      final source = (data['appData'] is Map)
          ? (data['appData'] as Map)['source']?.toString()
          : null;
      final pendingIndex = _pendingProduceTracks.indexWhere((entry) =>
          entry.kind == kind && (source == null || entry.source == source));
      if (pendingIndex >= 0) _pendingProduceTracks.removeAt(pendingIndex);

      final completer = Completer<String>();
      final pending = _PendingProduce(kind, completer);
      _produceCompleters.add(pending);
      try {
        final rtpParametersMap =
            _normalizeProduceRtpParameters(rtpParams.toMap());
        if (kDebugMode) {
          print("[CallController] PRODUCE $kind rtpParameters: "
              "${jsonEncode(rtpParametersMap)}");
        }
        final ok = await _webrtcApi.produceRequest(
          conversationID: conversationID!,
          transportId: connectTransportState.params!['id'],
          kind: kind,
          rtpParameters: rtpParametersMap,
          members: members,
          clientId: clientId,
          appData: data['appData'] ?? {},
        );
        if (!ok) throw StateError("produce request failed");
        // 30s (raised from 15s) is generous under normal conditions, but
        // the server (server/reusables/hooks/webRTC.js's produce()) awaits
        // fanning "new_producer" out to every other room member before
        // publishing OUR OWN "produce-response" confirmation - a slow/
        // stuck publish to any one of them (confirmed on-device: happens
        // intermittently, video only, ~1 in 3 calls) delays or fully drops
        // our own confirmation even though the producer was created
        // successfully server-side. Not something a client-side change
        // can fix at the root - so instead of waiting on produce-response
        // alone, the SSE handler below ALSO resolves this same completer
        // from our own "new_producer" echo (that fan-out publishes to
        // every member including the producer itself, and Redis pub/sub
        // delivery to each subscriber isn't gated by the server's
        // Promise.all as a whole - so our own echo can and does arrive
        // even when the gated produce-response never does). Whichever
        // signal arrives first wins. The longer timeout below and the
        // one-shot retry in the catch block are the remaining client-only
        // mitigations available given the server side of this isn't being
        // changed.
        final id = await completer.future.timeout(const Duration(seconds: 30));
        // Raw string id, NOT {id: id} - mediasoup_client_flutter's
        // _produce() expects the bare id string, unlike mediasoup-
        // client-js's {id} wrapper convention.
        callback(id);
      } catch (e) {
        _produceCompleters.remove(pending);
        errback(e);
        if (kind == 'video') {
          if (kDebugMode) {
            print("[CallController] video produce failed (attempt "
                "${_videoProduceAttempts + 1}): $e");
          }
        }
        if (kind == 'video' && _videoProduceAttempts == 0) {
          // One bounded retry - the failed attempt's local transceiver is
          // already unwound by the package's own errback-triggered
          // stopSending() above, so this is a clean fresh attempt, not a
          // stacked one. If the original produce actually DID succeed
          // server-side and only the confirmation was lost, this creates
          // a second, orphaned server-side producer for this client - an
          // accepted small risk given the alternative (no video at all)
          // is worse, and there's no way to close a producer whose id we
          // were never told.
          _videoProduceAttempts = 1;
          if (sendTransport != null) _produceVideoTrack(sendTransport!);
        } else if (kind == 'video') {
          videoProduceFailed = true;
          notifyListeners();
        }
      }
    });

    _startStreaming(transport);
  }

  // ════════════════════════════════════════════════════════════════════
  // Normalizes the rtpParameters map before it goes to /webrtc/produce,
  // to match what mediasoup-client-js (webapp) sends rather than what
  // mediasoup_client_flutter's RtcpParameters.toMap() emits verbatim.
  //
  // The confirmed problem (traced from webapp's own console errors when
  // consuming a mobile producer - "no a=setup found at SDP session or
  // media level" on the first consumer, "Failed to setup RTCP mux" on the
  // video consumer): this package's RtcpParameters default constructor
  // leaves `mux` as null, and its toMap() serializes that as an explicit
  // `"mux": null` in the JSON. webapp's mediasoup-client-js instead omits
  // the field entirely (its rtcp starts as `{}` and only ever gets a
  // cname set). An explicit JSON null is NOT the same as an omitted field
  // to the server's rtcp validation, and it propagates into a malformed
  // consumer m-section that Chrome then rejects - which is exactly the
  // asymmetry observed (webapp->mobile video works, mobile->webapp fails).
  // Forcing mux:true here (rtcp-mux IS always used by mediasoup) is the
  // correct value and removes the null. Same treatment for any other
  // stray nulls the package leaves in the rtcp block.
  // ════════════════════════════════════════════════════════════════════
  Map<String, dynamic> _normalizeProduceRtpParameters(
      Map<String, dynamic> map) {
    final rtcp = map['rtcp'];
    if (rtcp is Map) {
      final normalizedRtcp = Map<String, dynamic>.from(rtcp);
      normalizedRtcp['mux'] = true;
      normalizedRtcp['reducedSize'] = normalizedRtcp['reducedSize'] ?? true;
      // Drop a null cname rather than sending it explicitly null.
      if (normalizedRtcp['cname'] == null) normalizedRtcp.remove('cname');
      map = Map<String, dynamic>.from(map);
      map['rtcp'] = normalizedRtcp;
    }
    return map;
  }

  // ════════════════════════════════════════════════════════════════════
  // startStreaming (CallWindow.tsx lines 514-553) - mic first, then
  // camera. webapp does camera-then-mic; swapped here because real device
  // testing found video's produce() call prone to stalling (and, on
  // failure, corrupting the whole send transport via
  // mediasoup_client_flutter's own errback cleanup path) specifically
  // when joining a room that already has a participant in it. Producing
  // audio first means it's already fully established before video's own
  // produce() even starts, so a video stall can no longer drag a working
  // audio call down with it.
  // ════════════════════════════════════════════════════════════════════
  Future<void> _startStreaming(Transport transport) async {
    try {
      // mediasoup_client_flutter's Transport constructor kicks off
      // _handler.run() (which does `_pc = await createPeerConnection(...)`)
      // as fire-and-forget - the constructor returns before _pc exists, and
      // there's no public signal for when it's ready. Calling .produce()
      // too early hits `_pc!.addTransceiver(...)` while _pc is still null,
      // throwing inside the package's own FlexQueue task - which swallows
      // the error silently (no errback surfaces it, since it never reaches
      // our own 'produce' listener), silently hanging every produce
      // Completer forever. Confirmed on-device: the crash lands ~25ms
      // after transport creation. webapp has no equivalent race (the
      // browser's RTCPeerConnection constructor is synchronous), so this
      // gap has no webapp counterpart to mirror - it's a Dart/
      // flutter_webrtc-specific footgun this delay works around.
      await Future.delayed(const Duration(milliseconds: 500));

      final audioTrack = mediaStream!.getAudioTracks().isNotEmpty
          ? mediaStream!.getAudioTracks().first
          : null;
      if (audioTrack != null) {
        _pendingProduceTracks.add(_PendingProduceTrack(
            kind: 'audio', track: audioTrack, source: 'microphone'));
        transport.produce(
          track: audioTrack,
          stream: mediaStream!,
          source: "microphone",
          // Kept false, though this project no longer calls
          // Producer.pause()/.resume() at all (see _setSenderTrack's doc
          // comment for why - the short version: with this false, those
          // two methods do nothing to the real RTP stream, which is
          // exactly why toggleMic()/toggleCamera() bypass them entirely
          // and talk to the RTCRtpSender directly instead). Left false
          // anyway for clarity, so nothing in this codebase ever
          // accidentally relies on the package's own track.enabled
          // toggling, which is what caused the OS mic/camera indicator to
          // flicker on every mute/camera toggle in the first place.
          disableTrackOnPause: false,
        );
        if (!enableMic) {
          // See _setSenderTrack's doc comment - starting muted is
          // expressed by replacing the sender's track with null once the
          // producer exists (in _handleProducerCreated below), never by
          // disabling the local track.
          _pauseAudioOnNextProducer = true;
        }
      }

      _produceVideoTrack(transport);
    } catch (e) {
      if (kDebugMode) print("[CallController] Produce failed: $e");
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // Video produce, pulled out of _startStreaming so it can be re-invoked
  // for the bounded retry below and from the user-facing retryVideo()
  // control. No webapp counterpart needs this - mediasoup-client-js's
  // produce() is a single attempt because the equivalent server response
  // is reliable there; on mobile it intermittently never arrives at all
  // (see the 'produce' transport listener's catch block for the full
  // account), so this exists purely to make that failure recoverable
  // instead of a silent frozen tile.
  // ════════════════════════════════════════════════════════════════════
  void _produceVideoTrack(Transport transport) {
    final videoTrack = mediaStream?.getVideoTracks().isNotEmpty == true
        ? mediaStream!.getVideoTracks().first
        : null;
    if (videoTrack == null) return;

    videoProduceFailed = false;
    _pendingProduceTracks.add(_PendingProduceTrack(
        kind: 'video', track: videoTrack, source: 'camera'));
    // Deliberately NOT passing webapp's 3-layer simulcast encodings here
    // (server's CAMERA_ENCODINGS, fetched into _encodings above) -
    // confirmed on-device that supplying them crashes this produce()
    // call inside the package's own FlexQueue task ("type 'String' is
    // not a subtype of type 'int'", swallowed silently by the package
    // same as the _pc-null race above, hanging the produce Completer
    // forever). Root-caused to somewhere in mediasoup_client_flutter/
    // flutter_webrtc's multi-encoding transceiver setup on Android, not
    // to our own encoding values (single-encoding video produce, i.e. no
    // `encodings:` at all, works reliably - matches audio's already-
    // working no-encodings path). mediasoup's server accepts a non-
    // simulcast video producer fine; the only cost is no bitrate-
    // adaptive layers.
    transport.produce(
      track: videoTrack,
      stream: mediaStream!,
      source: "camera",
      disableTrackOnPause: false, // see the audio produce() call above
    );
    if (callType != "video" && _videoProduceAttempts == 0) {
      // producerCallback (below) sets _videoProducer once the FlexQueue
      // task actually resolves - pausing happens there instead of here,
      // since the Producer object doesn't exist yet at this point
      // (matches webapp's own sequencing where videoProducerRef.current
      // is only assigned once `await transport.produce(...)` resolves,
      // then immediately paused). Only set on the FIRST attempt - a
      // retry after the user has since toggled the camera on/off
      // shouldn't clobber their choice back to the call's original
      // starting state.
      _pauseVideoOnNextProducer = true;
    }
  }

  /// User-facing retry for the "Video couldn't connect" error state -
  /// resets the attempt counter so this counts as a fresh first try, same
  /// as the automatic one-shot retry below.
  void retryVideo() {
    if (sendTransport == null) return;
    _videoProduceAttempts = 0;
    videoProduceFailed = false;
    notifyListeners();
    _produceVideoTrack(sendTransport!);
  }

  bool _pauseAudioOnNextProducer = false;
  bool _pauseVideoOnNextProducer = false;
  int _videoProduceAttempts = 0;

  /// Set when video's produce() has exhausted its automatic retry - the UI
  /// (ActiveCallView) surfaces a dismissable "Video couldn't connect"
  /// affordance calling retryVideo() when this is true, rather than
  /// leaving a permanently frozen/blank local preview with no explanation
  /// or recourse. The call itself continues audio-only; this never blocks
  /// _waitForActiveOrFailure() from reaching `active`, which only requires
  /// ONE of the two producers to exist.
  bool videoProduceFailed = false;

  final List<_PendingProduce> _produceCompleters = [];

  // ════════════════════════════════════════════════════════════════════
  // Transport-close safety net for end-call detection. webapp has no
  // direct equivalent of this specific check (its useReconnect.ts listens
  // to the same 'connectionstatechange' event, but only to drive its
  // reconnect state machine - M9's concern here, not yet built). This is
  // a narrow fallback for a DIFFERENT purpose: if the normal signal that
  // a call ended (sse_events.dart's JWT-decoded "callreject" case calling
  // leaveCall() directly) is ever missed or delayed, both transports
  // still independently observe the server tearing the mediasoup room
  // down and will eventually report 'failed' or 'closed'. Gated on
  // `status == active` specifically so it can never fire during normal
  // setup (transports start at 'new', not 'closed') or during our OWN
  // leaveCall()-driven teardown (status is already `leaving` by the time
  // _cleanupLocalCallResources() closes the transports itself).
  // ════════════════════════════════════════════════════════════════════
  String? _sendTransportState;
  String? _recvTransportState;

  void _maybeAutoEndOnTransportClosed() {
    if (status != CallEngineStatus.active) return;
    const deadStates = {'failed', 'closed'};
    if (deadStates.contains(_sendTransportState) &&
        deadStates.contains(_recvTransportState)) {
      if (kDebugMode) {
        print("[CallController] both transports dead "
            "(send=$_sendTransportState, recv=$_recvTransportState) while "
            "active - treating as call ended");
      }
      leaveCall();
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // useEffect #3 - screen share producing (CallWindow.tsx lines 559-620).
  // Ported for structural fidelity; no UI control exposes this yet
  // (out of this milestone's scope), so screenStream never actually gets
  // set today - this only fires if/when something sets it.
  // ════════════════════════════════════════════════════════════════════
  void _maybeProduceScreenShare() {
    if (sendTransport == null ||
        screenStream == null ||
        _screenProducer != null) {
      return;
    }
    final screenTrack = screenStream!.getVideoTracks().isNotEmpty
        ? screenStream!.getVideoTracks().first
        : null;
    final screenAudioTrack = screenStream!.getAudioTracks().isNotEmpty
        ? screenStream!.getAudioTracks().first
        : null;
    if (screenTrack == null && screenAudioTrack == null) return;

    try {
      if (screenTrack != null) {
        _pendingProduceTracks.add(_PendingProduceTrack(
            kind: 'video', track: screenTrack, source: 'screen'));
        final screenEncodings =
            (_encodings?['screenshare'] as List?) ?? const [];
        sendTransport!.produce(
          track: screenTrack,
          stream: screenStream!,
          source: "screen",
          encodings: screenEncodings
              .whereType<Map>()
              .map((e) => RtpEncodingParameters(
                    rid: e['rid']?.toString(),
                    maxBitrate: (e['maxBitrate'] as num?)?.toInt(),
                    scaleResolutionDownBy:
                        (e['scaleResolutionDownBy'] as num?)?.toDouble(),
                  ))
              .toList(),
        );
      }
      if (screenAudioTrack != null) {
        _pendingProduceTracks.add(_PendingProduceTrack(
            kind: 'audio', track: screenAudioTrack, source: 'screen-audio'));
        sendTransport!.produce(
            track: screenAudioTrack,
            stream: screenStream!,
            source: "screen-audio");
      }
    } catch (e) {
      if (kDebugMode) print("[CallController] Screen share produce failed: $e");
      isScreenSharing = false;
      notifyListeners();
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // connectTransport / connectRecvTransport (CallWindow.tsx lines 622-624,
  // 658-660)
  // ════════════════════════════════════════════════════════════════════
  void _connectTransport(Map<String, dynamic> params, String? instance) {
    connectTransportState.params = params;
    connectTransportState.instance = instance;
    connectTransportState.triggered = false;
    _maybeCreateSendTransport();
  }

  void _connectRecvTransport(Map<String, dynamic> params, String? instance) {
    connectRecvTransportState.params = params;
    connectRecvTransportState.instance = instance;
    connectRecvTransportState.triggered = false;
    _maybeCreateRecvTransport();
  }

  // ════════════════════════════════════════════════════════════════════
  // useEffect #4 - recv transport creation (CallWindow.tsx lines 626-656)
  // ════════════════════════════════════════════════════════════════════
  void _maybeCreateRecvTransport() {
    if (device == null ||
        connectRecvTransportState.params == null ||
        connectRecvTransportState.triggered) {
      return;
    }
    connectRecvTransportState.triggered = true;

    final transport = device!.createRecvTransportFromMap(
      connectRecvTransportState.params!,
      consumerCallback: _handleConsumerCreated,
    );
    recvTransport = transport;
    notifyListeners();

    transport.on('connect', (data) {
      final callback = data['callback'] as Function;
      final errback = data['errback'] as Function;
      try {
        _webrtcApi.transportConnectRequest(
          conversationID: conversationID!,
          transportId: connectRecvTransportState.params!['id'],
          dtlsParameters: (data['dtlsParameters'] as DtlsParameters).toMap(),
          clientId: clientId,
        );
        callback();
      } catch (e) {
        errback(e);
      }
    });
    transport.on('connectionstatechange', (data) {
      _recvTransportState = data['connectionState']?.toString();
      _maybeAutoEndOnTransportClosed();
    });

    _maybeFlushPendingProducerIds();
  }

  // ════════════════════════════════════════════════════════════════════
  // consumeProducers (CallWindow.tsx lines 662-685)
  // ════════════════════════════════════════════════════════════════════
  void _consumeProducers(String conversationID, String producerId) {
    final recvTransportId = connectRecvTransportState.params?['id'];
    final instance =
        connectRecvTransportState.instance ?? connectTransportState.instance;

    if (recvTransportId == null || instance == null || device == null) {
      if (!pendingProducerIds.contains(producerId)) {
        pendingProducerIds.add(producerId);
      }
      return;
    }

    _webrtcApi.consumeRequest(
      conversationID: conversationID,
      transportId: recvTransportId,
      producerId: producerId,
      rtpCapabilities: device!.rtpCapabilities.toMap(),
      clientId: clientId,
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // consumeResponseHandler (CallWindow.tsx lines 687-735)
  // ════════════════════════════════════════════════════════════════════
  Future<void> _consumeResponseHandler(_PendingConsumeResponse pending) async {
    if (recvTransport == null) return;

    final createdCompleter = Completer<Consumer>();
    _pendingConsumerCreated[pending.producerId] = createdCompleter;
    recvTransport!.consume(
      id: pending.id,
      producerId: pending.producerId,
      peerId: pending.ownerClientId ?? "",
      kind: RTCRtpMediaTypeExtension.fromString(pending.kind),
      rtpParameters: RtpParameters.fromMap(pending.rtpParameters),
    );
    final consumer =
        await createdCompleter.future.timeout(const Duration(seconds: 15));

    if (consumers.containsKey(pending.producerId)) {
      consumer.close();
      return;
    }
    consumers[pending.producerId] = ConsumerEntry(
      id: pending.id,
      kind: pending.kind,
      consumer: consumer,
      ownerClientId: pending.ownerClientId,
      source: pending.source,
    );
    notifyListeners();
  }

  final Map<String, Completer<Consumer>> _pendingConsumerCreated = {};

  // ════════════════════════════════════════════════════════════════════
  // useEffect #5 - drains pendingConsumeResponses one at a time
  // (CallWindow.tsx lines 737-764)
  // ════════════════════════════════════════════════════════════════════
  Future<void> _maybeDrainConsumeQueue() async {
    if (recvTransport == null ||
        pendingConsumeResponses.isEmpty ||
        _isConsuming) {
      return;
    }
    final next = pendingConsumeResponses.first;
    _isConsuming = true;
    try {
      await _consumeResponseHandler(next);
    } catch (e) {
      if (kDebugMode)
        print("[CallController] Consume response handler failed: $e");
    } finally {
      pendingConsumeResponses.remove(next);
      _isConsuming = false;
      // Re-run for the next queued item, matching the effect's own
      // dependency on pendingConsumeResponses shrinking and firing again.
      _maybeDrainConsumeQueue();
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // useEffect #6 - flushes pendingProducerIds once the recv transport is
  // ready (CallWindow.tsx lines 766-794)
  // ════════════════════════════════════════════════════════════════════
  void _maybeFlushPendingProducerIds() {
    if (pendingProducerIds.isEmpty ||
        connectRecvTransportState.params?['id'] == null ||
        connectRecvTransportState.instance == null ||
        device == null) {
      return;
    }
    final queued = List<String>.from(pendingProducerIds);
    pendingProducerIds.clear();
    for (final producerId in queued) {
      _webrtcApi.consumeRequest(
        conversationID: conversationID!,
        transportId: connectRecvTransportState.params!['id'],
        producerId: producerId,
        rtpCapabilities: device!.rtpCapabilities.toMap(),
        clientId: clientId,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // initLocalMedia (CallWindow.tsx lines 796-833) - two SEPARATE
  // getUserMedia calls, each own try/catch, combined into one MediaStream
  // - a camera failure alone never blocks audio, and vice versa.
  // ════════════════════════════════════════════════════════════════════
  Future<void> _initLocalMedia() async {
    MediaStream? audioStream;
    MediaStream? videoStream;
    try {
      audioStream = await navigator.mediaDevices
          .getUserMedia({"audio": true, "video": false});
    } catch (e) {
      if (kDebugMode) print("[CallController] Audio device not available: $e");
    }
    try {
      videoStream = await navigator.mediaDevices
          .getUserMedia({"video": true, "audio": false});
    } catch (e) {
      if (kDebugMode) print("[CallController] Video device not available: $e");
    }

    final tracks = <MediaStreamTrack>[
      ...(audioStream?.getAudioTracks() ?? const []),
      ...(videoStream?.getVideoTracks() ?? const []),
    ];
    if (tracks.isEmpty) return;

    final combined = await createLocalMediaStream("local");
    for (final t in tracks) {
      await combined.addTrack(t);
    }
    // Tracks are left enabled regardless of the starting muted/camera-off
    // state - toggleMic()/toggleCamera()'s doc comment explains why
    // touching `enabled` is avoided entirely. Starting muted/camera-off is
    // instead achieved by pausing the producer right after it's created
    // (see _pauseAudioOnNextProducer/_pauseVideoOnNextProducer in
    // _startStreaming/_handleProducerCreated below).
    mediaStream = combined;
    notifyListeners();
    _maybeCreateSendTransport();
  }

  // ════════════════════════════════════════════════════════════════════
  // notifyProducerClosed (CallWindow.tsx lines 835-860)
  // ════════════════════════════════════════════════════════════════════
  // ignore: unused_element
  void _notifyProducerClosed(String? producerId) {
    if (producerId == null || conversationID == null) return;
    _webrtcApi.closeProducerRequest(
      conversationID: conversationID!,
      producerId: producerId,
      clientId: clientId,
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // participant-status broadcast effect (CallWindow.tsx lines 888-914)
  // ════════════════════════════════════════════════════════════════════
  void _pushParticipantStatus() {
    if (conversationID == null || _hasLeft) return;
    _webrtcApi.participantStatusRequest(
      conversationID: conversationID!,
      clientId: clientId,
      muted: !enableMic,
      cameraOff: !enableCamera,
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // Public controls - mic/camera toggle mirror webapp's own control
  // buttons exactly (CallWindow.tsx lines 1360-1390: pause()/resume() on
  // the producer ref, flip the enable flag, nothing else). speakerOn/
  // switchCamera are mobile-only additions with no webapp equivalent.
  // ════════════════════════════════════════════════════════════════════
  Future<void> toggleMic() async {
    enableMic = !enableMic;
    await _setSenderTrack(
        _audioProducer, enableMic, mediaStream?.getAudioTracks());
    _pushParticipantStatus();
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    enableCamera = !enableCamera;
    await _setSenderTrack(
        _videoProducer, enableCamera, mediaStream?.getVideoTracks());
    _pushParticipantStatus();
    notifyListeners();
  }

  /// The actual mute/camera-off mechanism - deliberately NOT
  /// Producer.pause()/.resume(). Two things were tried and ruled out on
  /// real devices before landing here:
  ///   - `track.enabled = false`: silences correctly, but on Android this
  ///     releases the underlying AudioRecord/Camera, so the OS privacy
  ///     indicator visibly flickers on every toggle.
  ///   - `Producer.pause()`/`.resume()` with `disableTrackOnPause: false`
  ///     (the fix for the flicker above): stops touching the track, but
  ///     also - confirmed by reading the package source - stops doing
  ///     ANYTHING to the real RTP stream. `pause()`/`.resume()` only
  ///     touch `track.enabled` (now disabled) or, if `zeroRtpOnPause` is
  ///     set, fire an internal `@replacetrack` event - which is itself
  ///     broken in this package version (pause() emits it with no data
  ///     payload at all, resume() emits it under the wrong key `_track`
  ///     instead of `track`, and the listener that would call the native
  ///     RTCRtpSender.replaceTrack() reads `data['track']` - so on either
  ///     path it silently no-ops instead of throwing). Net effect: with
  ///     that fix in place, mute/camera-off stopped doing anything at all
  ///     - confirmed on-device as the cause of audio/video "always
  ///     getting through even when toggled off".
  ///
  /// The fix that actually satisfies both constraints at once: talk to
  /// the underlying RTCRtpSender directly. `sender.replaceTrack(null)`
  /// detaches the track from the sender - the encoder has nothing to
  /// encode, so the other side genuinely receives nothing - while local
  /// capture keeps running untouched (`track.enabled` never changes), so
  /// there's no OS indicator flicker. `sender.replaceTrack(track)`
  /// re-attaches the same, still-live track to resume. This is the
  /// closest actual mobile equivalent of "keep the mic transport
  /// connected, just mute/unmute the stream" - webapp's own
  /// `.pause()`/`.resume()` achieves the same end result on browsers
  /// (where `track.enabled` toggling has no hardware cost), just via a
  /// different, browser-appropriate mechanism.
  Future<void> _setSenderTrack(Producer? producer, bool enabled,
      List<MediaStreamTrack>? liveTracks) async {
    final sender = producer?.rtpSender;
    if (sender == null) return;
    try {
      if (enabled) {
        final track =
            (liveTracks?.isNotEmpty ?? false) ? liveTracks!.first : null;
        await sender.replaceTrack(track);
      } else {
        await sender.replaceTrack(null);
      }
    } catch (e) {
      if (kDebugMode) print("[CallController] replaceTrack failed: $e");
    }
  }

  /// Front/back camera - no webapp equivalent (desktop has no rear/front
  /// camera concept), kept from the earlier mobile-only pass.
  Future<void> switchCamera() async {
    final track = localVideoTrack;
    if (track == null) return;
    await Helper.switchCamera(track);
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    await Helper.setSpeakerphoneOn(speakerOn);
    notifyListeners();
  }

  // Backwards-compat aliases for the UI layer, which was written against
  // the previous (non-webapp-mirrored) field names.
  bool get muted => !enableMic;
  bool get cameraOff => !enableCamera;

  // ════════════════════════════════════════════════════════════════════
  // Main SSE listener (CallWindow.tsx lines 916-1170)
  // ════════════════════════════════════════════════════════════════════
  Map<String, dynamic>? _decode(dynamic raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  void _onSseEvent(SSEModel event) {
    final data = _decode(event.data);
    if (data == null) return;

    // Matches webapp's isScopedEvent filter exactly (CallWindow.tsx lines
    // 919-932) - these six events are always addressed to whoever made
    // the originating REST call, so anything not matching our own
    // clientId is stale/foreign and gets dropped.
    const scopedEvents = {
      "join-room-response",
      "create-transport-response",
      "transport-connect-response",
      "consume-response",
      "consume-error",
      "consume-transport-error",
    };
    if (scopedEvents.contains(event.event) &&
        data['clientId'] != null &&
        data['clientId'] != clientId) {
      return;
    }

    switch (event.event) {
      case "join-room-response":
        final rawParticipants = data['participants'];
        final participants = rawParticipants is List
            ? rawParticipants
                .whereType<Map>()
                .map((p) =>
                    CallParticipantRaw.fromJson(Map<String, dynamic>.from(p)))
                .toList()
            : <CallParticipantRaw>[];
        final rtpCaps = data['routerRtpCapabilities'];
        if (rtpCaps is Map) {
          _joinRoomProcess(Map<String, dynamic>.from(rtpCaps),
              data['instance']?.toString(), participants);
        }
        return;
      case "create-transport-response":
        final response = data['response'];
        if (response is Map) {
          if (data['direction'] == 'send') {
            _connectTransport(Map<String, dynamic>.from(response),
                data['instance']?.toString());
          } else {
            _connectRecvTransport(Map<String, dynamic>.from(response),
                data['instance']?.toString());
          }
        }
        return;
      case "transport-connect-response":
        if (kDebugMode)
          print("[CallController] transport-connect-response: $data");
        return;
      case "participant-joined":
        if (data['conversationID'] == conversationID &&
            data['clientId'] != null &&
            data['username'] != null &&
            data['clientId'] != clientId) {
          final cid = data['clientId'].toString();
          if (!joinedParticipants.any((p) => p.clientId == cid)) {
            joinedParticipants.add(JoinedParticipant(
                clientId: cid, username: data['username'].toString()));
          }
          participantStatuses[cid] = ParticipantStatusEntry(
            muted: data['muted'] == true,
            cameraOff: data['cameraOff'] == true,
          );
          notifyListeners();
        }
        return;
      case "participant-left":
        if (data['conversationID'] == conversationID) {
          final leftClientId = data['clientId']?.toString();
          final leftUsername = data['username']?.toString();

          final before = joinedParticipants.length;
          if (leftClientId != null) {
            joinedParticipants.removeWhere((p) => p.clientId == leftClientId);
          } else if (leftUsername != null) {
            joinedParticipants.removeWhere((p) => p.username == leftUsername);
          }

          // 1:1 call, roster now empty, and it wasn't just us leaving -
          // matches webapp's own auto-leaveCallProcess condition exactly
          // (CallWindow.tsx lines 998-1009).
          if (!isGroup &&
              joinedParticipants.isEmpty &&
              before != joinedParticipants.length &&
              ((leftClientId != null && leftClientId != clientId) ||
                  (leftClientId == null &&
                      leftUsername != null &&
                      leftUsername != appStore.state.userAuth.user.username))) {
            scheduleMicrotask(() => leaveCall());
          }

          if (leftClientId != null) {
            participantStatuses.remove(leftClientId);
          }

          final producerIds = data['producerIds'];
          if (producerIds is List) {
            for (final producerId in producerIds) {
              final entry = consumers.remove(producerId.toString());
              entry?.consumer.close();
              _producerSource.remove(producerId.toString());
            }
          }
          notifyListeners();
        }
        return;
      // "callreject" (webapp's equivalent of this - both /rejectcall's
      // {conversationID, rejectedBy} and /endcall's {conversationID,
      // endedBy} - is deliberately NOT handled here. Unlike every other
      // case in this switch, it arrives JWT-wrapped ({status, auth,
      // result: <JWT>}, same convention as "incomingcall"), not as plain
      // JSON - _decode() above assumes plain JSON and would silently fail
      // to extract it. This app already routes that event through
      // sse_events.dart's own "callreject" case instead, which JWT-decodes
      // it correctly and calls CallController.instance.leaveCall() itself
      // - a structural difference from webapp (which folds every room
      // event, JWT-wrapped or not, into one listener) that's intentional
      // for this app, not an oversight.
      case "participant-status":
        if (data['conversationID'] == conversationID &&
            data['clientId'] != null &&
            data['clientId'] != clientId) {
          participantStatuses[data['clientId'].toString()] =
              ParticipantStatusEntry(
            muted: data['muted'] == true,
            cameraOff: data['cameraOff'] == true,
          );
          notifyListeners();
        }
        return;
      case "producer-closed":
        if (data['conversationID'] == conversationID &&
            data['producerId'] != null) {
          final producerId = data['producerId'].toString();
          final entry = consumers.remove(producerId);
          entry?.consumer.close();
          _producerOwner.remove(producerId);
          _producerSource.remove(producerId);
          notifyListeners();
        }
        return;
      case "produce-response":
        {
          final id = data['id']?.toString();
          if (id != null && _produceCompleters.isNotEmpty) {
            final pending = _produceCompleters.removeAt(0);
            if (!pending.completer.isCompleted) pending.completer.complete(id);
          }
        }
        return;
      case "produce-error":
        if (_produceCompleters.isNotEmpty) {
          final pending = _produceCompleters.removeAt(0);
          if (!pending.completer.isCompleted) {
            pending.completer.completeError(StateError("produce-error: $data"));
          }
        }
        return;
      case "new_producer":
        if (data['clientId'] == clientId) {
          // Our own produce, echoed back because the server's fan-out
          // (server/reusables/hooks/webRTC.js's produce()) publishes
          // "new_producer" to every room member including the producer
          // itself, ahead of the gated "produce-response" confirmation -
          // see the long comment on the 'produce' transport listener.
          // Use it as a fallback resolution for whichever produce is
          // still pending, matched by kind, since produce-response can be
          // delayed or dropped independently of this echo.
          final kind = data['kind']?.toString();
          final producerId = data['producerId']?.toString();
          if (kind != null && producerId != null) {
            final pendingIndex =
                _produceCompleters.indexWhere((p) => p.kind == kind);
            if (pendingIndex >= 0) {
              final pending = _produceCompleters.removeAt(pendingIndex);
              if (!pending.completer.isCompleted) {
                pending.completer.complete(producerId);
              }
            }
          }
          return;
        }
        if (data['conversationID'] == conversationID) {
          final producerId = data['producerId']?.toString();
          final producerClientId = data['clientId']?.toString();
          if (producerId != null && producerClientId != null) {
            _producerOwner[producerId] = producerClientId;
            if (data['source'] != null) {
              _producerSource[producerId] = data['source'].toString();
            }
          }
          if (producerClientId != null &&
              data['username'] != null &&
              producerClientId != clientId) {
            if (!joinedParticipants
                .any((p) => p.clientId == producerClientId)) {
              joinedParticipants.add(JoinedParticipant(
                  clientId: producerClientId,
                  username: data['username'].toString()));
              notifyListeners();
            }
          }
          if (producerId != null) {
            _consumeProducers(conversationID!, producerId);
          }
        }
        return;
      case "consume-response":
        if (data['conversationID'] == conversationID) {
          final id = data['id']?.toString();
          final producerId = data['producerId']?.toString();
          final kind = data['kind']?.toString();
          final rtpParameters = data['rtpParameters'];
          if (id != null &&
              producerId != null &&
              kind != null &&
              rtpParameters is Map) {
            final ownerClientId = _producerOwner[producerId];
            final source =
                data['source']?.toString() ?? _producerSource[producerId];
            if (!pendingConsumeResponses.any((p) => p.id == id)) {
              pendingConsumeResponses.add(_PendingConsumeResponse(
                id: id,
                producerId: producerId,
                kind: kind,
                rtpParameters: Map<String, dynamic>.from(rtpParameters),
                ownerClientId: ownerClientId,
                source: source,
              ));
              _maybeDrainConsumeQueue();
            }
          }
        }
        return;
      case "consume-error":
      case "consume-transport-error":
        if (kDebugMode)
          print("[CallController] Consume failed: ${event.event} $data");
        return;
    }
  }

  // Resolves the two REST-response-only completers (join-room, create-
  // transport aren't SSE-scoped the same way as produce/consume, but
  // still need correlating to the async REST calls that kick them off).
  void _handleProducerCreated(Producer producer) {
    if (producer.kind == 'audio') {
      _audioProducer = producer;
      if (_pauseAudioOnNextProducer) {
        _pauseAudioOnNextProducer = false;
        // See _setSenderTrack's doc comment - producer.pause() doesn't
        // actually stop transmission with disableTrackOnPause: false, so
        // starting muted is expressed the same way toggleMic() is.
        unawaited(producer.rtpSender?.replaceTrack(null));
      }
    } else if (producer.kind == 'video') {
      _videoProducer = producer;
      _videoProduceAttempts = 0;
      videoProduceFailed = false;
      if (_pauseVideoOnNextProducer) {
        _pauseVideoOnNextProducer = false;
        unawaited(producer.rtpSender?.replaceTrack(null));
      }
      notifyListeners();
    }
    if (kDebugMode) {
      print(
          "[CallController] ${producer.kind} producer created! ${producer.id}");
    }
  }

  void _handleConsumerCreated(Consumer consumer, Function? accept) {
    final completer = _pendingConsumerCreated.remove(consumer.producerId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(consumer);
    }
    // mediasoup_client_flutter's own two-phase consume handshake - the
    // Consumer object exists locally the moment this fires, but the
    // handler withholds confirming it until we call accept() (matches
    // the proven M6 pattern in this same file's prior committed version).
    accept?.call();
  }

  // ════════════════════════════════════════════════════════════════════
  // Public entry point - mirrors the "if (data && !hasJoinedRef.current)"
  // join-trigger effect (CallWindow.tsx lines 1172-1196) plus this app's
  // own setup (SSE subscription, status bookkeeping) that webapp doesn't
  // need since it's driven by React mounting the component fresh.
  // ════════════════════════════════════════════════════════════════════
  Future<bool> joinCall({
    required String conversationID,
    required String conversationType,
    required String callType,
    required bool isOutgoing,
    List<String> recepients = const [],
    bool startMuted = false,
    bool startCameraOff = true,
  }) async {
    if (status != CallEngineStatus.idle) return false;
    status = CallEngineStatus.joining;
    this.conversationID = conversationID;
    this.conversationType = conversationType;
    this.callType = callType;
    this.isOutgoing = isOutgoing;
    endCallRecepients = recepients;
    members = recepients;
    enableMic = !startMuted;
    enableCamera = !startCameraOff;
    lastError = null;
    _hasJoined = false;
    _hasLeft = false;
    _clientId =
        "mobile-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(99999)}";
    notifyListeners();

    _sseSub ??= eventBus.on<SSEModel>().listen(_onSseEvent);

    // initLocalMedia (useEffect #7) - kicked off independently, same as
    // webapp firing it on mount rather than sequencing it after the join.
    unawaited(_initLocalMedia());

    try {
      // GetEncodingsRequest, then JoinRoomRequest (CallWindow.tsx lines
      // 1176-1194).
      _encodings = await _fetchEncodings();

      final joinOk = await _webrtcApi.joinRoomRequest(
        conversationID: conversationID,
        members: members,
        muted: !enableMic,
        cameraOff: !enableCamera,
        username: appStore.state.userAuth.user.username,
        clientId: clientId,
      );
      if (!joinOk) throw StateError("join-room request failed");
      _hasJoined = true;

      // From here on, this app's own producerCallback/consumerCallback
      // wiring (webapp gets the equivalent via awaiting transport.produce
      // /consume directly, which this package's fire-and-forget API
      // doesn't support) needs the send/recv transports to exist, which
      // only happens once _maybeCreateSendTransport/_maybeCreateRecvTransport
      // fire from the SSE-driven chain above. Wait here for the call to
      // either become active or fail/timeout.
      final activated = await _waitForActiveOrFailure();
      if (!activated) {
        throw StateError("call setup did not complete in time");
      }

      status = CallEngineStatus.active;
      notifyListeners();
      return true;
    } catch (e) {
      lastError = e.toString();
      status = CallEngineStatus.idle;
      _cleanupLocalCallResources();
      _hasLeft = false;
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> _fetchEncodings() async {
    try {
      final response = await _dio.get(_endpoints.webrtcEncodings);
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
    } catch (e) {
      if (kDebugMode) print("[CallController] GetEncodingsRequest failed: $e");
    }
    return null;
  }

  /// Polls status every 200ms up to 20s, since the actual "are we live"
  /// signal is the reactive SSE-driven chain above (join-room-response ->
  /// device load -> create-transport x2 -> transport connect -> produce),
  /// not a single awaitable Future the way the rest of this class's
  /// REST calls are.
  Future<bool> _waitForActiveOrFailure() async {
    const timeout = Duration(seconds: 20);
    const step = Duration(milliseconds: 200);
    var waited = Duration.zero;
    while (waited < timeout) {
      if (sendTransport != null &&
          (_audioProducer != null || _videoProducer != null)) {
        return true;
      }
      if (_hasLeft) return false;
      await Future.delayed(step);
      waited += step;
    }
    return false;
  }

  // ════════════════════════════════════════════════════════════════════
  // Unmount cleanup (CallWindow.tsx lines 1212-1216) - dispose() here is
  // for app-lifetime teardown (never actually called in practice, since
  // this is a singleton), not per-call cleanup - leaveCall() already
  // covers that.
  // ════════════════════════════════════════════════════════════════════
  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }
}

/// {clientId, username, muted?, cameraOff?} - the shape join-room-response
/// carries per participant (CallWindow.tsx lines 369-374).
class CallParticipantRaw {
  final String clientId;
  final String username;
  final bool muted;
  final bool cameraOff;
  const CallParticipantRaw({
    required this.clientId,
    required this.username,
    this.muted = false,
    this.cameraOff = false,
  });

  factory CallParticipantRaw.fromJson(Map<String, dynamic> json) {
    return CallParticipantRaw(
      clientId: (json['clientId'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      muted: json['muted'] == true,
      cameraOff: json['cameraOff'] == true,
    );
  }
}
