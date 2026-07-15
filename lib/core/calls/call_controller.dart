// The real (non-spike) mediasoup engine, built on WebrtcApi + the
// call_models data classes from M2. Wraps join-room -> create-transport ->
// transport-connect -> produce/consume into a reusable ChangeNotifier
// singleton, so UI (M5's incoming-call screen, M6's active-call screen) can
// just rebuild off it via ListenableBuilder instead of each owning its own
// copy of this state. Deliberately kept OUT of Redux (see the mobile
// calling plan's state-split rationale) - Device/Transport/Consumer/
// MediaStream are non-serializable, high-churn, UI-framework-adjacent
// objects with no business round-tripping through a reducer.
//
// Subscribes to the app's existing global eventBus directly (same pattern
// conversation_view.dart already uses for its own screen-scoped SSE
// handling) rather than sse_events.dart importing call-engine code - keeps
// sse_events.dart focused on the cross-screen redux side effects
// (incomingcall/callreject) that genuinely belong there instead.
//
// This is the same join-room -> create-transport -> transport-connect ->
// produce -> consume sequence proven in lib/views/calls/dev/
// call_spike_view.dart (M1), now driven by WebrtcApi instead of hand-rolled
// Dio calls, and parameterized instead of hardcoded to one conversationID.
// Nothing here is single-vs-group special-cased - mediasoup's SFU model
// already treats a 2-participant room the same as an N-participant one, so
// group support (M8) is mostly a UI/roster-rendering concern layered on
// top of this, not a rewrite of it. Video production/consumption is M7's
// concern - this milestone stays audio-only.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:chatterloop_app/core/requests/webrtc_api.dart';
import 'package:chatterloop_app/models/call_models/call_participant_model.dart';
import 'package:chatterloop_app/models/call_models/webrtc_payloads_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:mediasoup_client_flutter/mediasoup_client_flutter.dart';

enum CallEngineStatus { idle, joining, active, leaving }

class CallController extends ChangeNotifier {
  CallController._();
  static final CallController instance = CallController._();

  final _webrtcApi = WebrtcApi();

  CallEngineStatus status = CallEngineStatus.idle;
  String? conversationID;
  String? conversationType; // "single" | "group"
  String? callType; // "audio" | "video"
  String? clientId;
  String? lastError;

  bool muted = false;
  bool cameraOff = true;
  bool speakerOn = false;

  final List<CallParticipant> participants = [];
  final Map<String, Consumer> consumers = {}; // keyed by producerId

  /// True once at least one remote participant has joined this session -
  /// distinguishes "nobody has answered yet" (participants empty, still
  /// ringing) from "everyone left" (participants empty again, call is
  /// over) so _maybeEndOnEmptyRoster below only fires for the latter.
  bool _hasHadPeer = false;

  Device? _device;
  Transport? _sendTransport;
  Transport? _recvTransport;
  MediaStream? _localStream;
  StreamSubscription? _sseSub;

  Completer<JoinRoomResponse>? _joinRoomCompleter;
  Completer<CreateTransportResponse>? _sendTransportCompleter;
  Completer<CreateTransportResponse>? _recvTransportCompleter;
  Completer<void>? _transportConnectCompleter;
  Completer<String>? _produceCompleter;
  final Map<String, Completer<ConsumeResponse>> _consumeCompleters = {};

  bool get isGroup =>
      conversationType != null && conversationType != "single";
  bool get isActive => status == CallEngineStatus.active;

  Future<bool> joinCall({
    required String conversationID,
    required String conversationType,
    required String callType,
    bool startMuted = false,
    bool startCameraOff = true,
  }) async {
    if (status != CallEngineStatus.idle) return false;
    status = CallEngineStatus.joining;
    this.conversationID = conversationID;
    this.conversationType = conversationType;
    this.callType = callType;
    muted = startMuted;
    cameraOff = startCameraOff;
    speakerOn = false;
    // Generated once per call and reused for every REST call in this
    // session - M9's reconnect will persist and reuse the same value
    // across reconnect attempts too, so the server evicts the correct
    // stale session (see WebrtcApi.reconnectRequest's doc comment).
    clientId =
        "mobile-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(99999)}";
    lastError = null;
    _hasHadPeer = false;
    notifyListeners();

    _sseSub ??= eventBus.on<SSEModel>().listen(_onSseEvent);

    try {
      final myName = appStore.state.userAuth.user.personalDisplayName;

      // 1. join-room - server responds with routerRtpCapabilities (needed
      // to load the Device) and replays new_producer for anyone already in
      // the room (late-join sync) - no separate fetch is needed.
      _joinRoomCompleter = Completer<JoinRoomResponse>();
      final joinOk = await _webrtcApi.joinRoomRequest(
        conversationID: conversationID,
        members: const [],
        muted: muted,
        cameraOff: cameraOff,
        username: myName,
        clientId: clientId!,
      );
      if (!joinOk) throw StateError("join-room request failed");
      final joinData = await _joinRoomCompleter!.future
          .timeout(const Duration(seconds: 15));
      participants
        ..clear()
        ..addAll(joinData.participants);
      if (joinData.participants.isNotEmpty) _hasHadPeer = true;

      // 2. load device
      _device = Device();
      await _device!.load(
          routerRtpCapabilities:
              RtpCapabilities.fromMap(joinData.routerRtpCapabilities));

      // 3. create send transport, wire its connect/produce events to the
      // matching REST calls - mediasoup_client_flutter's produce()/connect
      // listeners are void+callback based (not Future-returning), so the
      // REST round-trip has to happen inside the listener and invoke
      // callback()/errback() itself.
      _sendTransportCompleter = Completer<CreateTransportResponse>();
      final sendReqOk = await _webrtcApi.createTransportRequest(
          conversationID: conversationID, direction: "send", clientId: clientId!);
      if (!sendReqOk) throw StateError("create-transport(send) request failed");
      final sendData = await _sendTransportCompleter!.future
          .timeout(const Duration(seconds: 15));
      final sendTransportId = sendData.params["id"];
      _sendTransport = _device!.createSendTransportFromMap(
        sendData.params,
        producerCallback: (producer) {
          if (kDebugMode) {
            print(
                "[CallController] local producer created: ${producer.id} (${producer.kind})");
          }
        },
      );
      _wireTransportConnect(_sendTransport!);
      _sendTransport!.on('produce', (data) async {
        final callback = data['callback'] as Function;
        final errback = data['errback'] as Function;
        try {
          _produceCompleter = Completer<String>();
          final ok = await _webrtcApi.produceRequest(
            conversationID: conversationID,
            transportId: sendTransportId,
            kind: data['kind'] == RTCRtpMediaType.RTCRtpMediaTypeAudio
                ? "audio"
                : "video",
            rtpParameters: (data['rtpParameters'] as RtpParameters).toMap(),
            members: const [],
            clientId: clientId!,
            appData: data['appData'] ?? {},
          );
          if (!ok) throw StateError("produce request failed");
          final id = await _produceCompleter!.future
              .timeout(const Duration(seconds: 15));
          // Raw string id, NOT {id: id} - mediasoup_client_flutter's
          // _produce() expects the bare id string, unlike mediasoup-
          // client-js's {id} wrapper convention (see the M1 spike's doc
          // comment for the full explanation of this footgun).
          callback(id);
        } catch (e) {
          errback(e);
        }
      });

      // 4. create recv transport
      _recvTransportCompleter = Completer<CreateTransportResponse>();
      final recvReqOk = await _webrtcApi.createTransportRequest(
          conversationID: conversationID, direction: "recv", clientId: clientId!);
      if (!recvReqOk) throw StateError("create-transport(recv) request failed");
      final recvData = await _recvTransportCompleter!.future
          .timeout(const Duration(seconds: 15));
      _recvTransport = _device!.createRecvTransportFromMap(
        recvData.params,
        consumerCallback: (consumer, accept) {
          consumers[consumer.producerId] = consumer;
          notifyListeners();
          if (accept != null) accept();
        },
      );
      _wireTransportConnect(_recvTransport!);

      // 5. produce local mic - audio-only at this milestone (cameraOff
      // above is only ever a status flag right now, video production is
      // M7's concern).
      final stream = await navigator.mediaDevices
          .getUserMedia({"audio": true, "video": false});
      _localStream = stream;
      final audioTracks = stream.getAudioTracks();
      if (audioTracks.isEmpty) {
        throw StateError(
            "getUserMedia returned a stream with no audio tracks - mic permission likely wasn't actually granted");
      }
      final audioTrack = audioTracks.first;
      audioTrack.enabled = !muted;
      _sendTransport!.produce(track: audioTrack, stream: stream, source: "mic");

      status = CallEngineStatus.active;
      notifyListeners();
      return true;
    } catch (e) {
      lastError = e.toString();
      status = CallEngineStatus.idle;
      await _cleanup();
      notifyListeners();
      return false;
    }
  }

  Future<void> leaveCall() async {
    if (status == CallEngineStatus.idle) return;
    status = CallEngineStatus.leaving;
    notifyListeners();
    if (conversationID != null && clientId != null) {
      await _webrtcApi.leaveRoomRequest(
          conversationID: conversationID!, clientId: clientId!);
    }
    await _cleanup();
    status = CallEngineStatus.idle;
    conversationID = null;
    conversationType = null;
    callType = null;
    clientId = null;
    lastError = null;
    participants.clear();
    notifyListeners();
  }

  void toggleMic() {
    if (_localStream == null) return;
    muted = !muted;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !muted;
    }
    _pushParticipantStatus();
    notifyListeners();
  }

  /// Flips the flag and notifies the room - actually producing/toggling a
  /// camera track is M7's concern, this device never produces video yet.
  void toggleCamera() {
    cameraOff = !cameraOff;
    _pushParticipantStatus();
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    await Helper.setSpeakerphoneOn(speakerOn);
    notifyListeners();
  }

  void _pushParticipantStatus() {
    if (conversationID == null || clientId == null) return;
    _webrtcApi.participantStatusRequest(
      conversationID: conversationID!,
      clientId: clientId!,
      muted: muted,
      cameraOff: cameraOff,
    );
  }

  void _wireTransportConnect(Transport transport) {
    // transport-connect-response carries no transportId/direction field
    // (confirmed against transportConnect()'s publish call in webRTC.js) -
    // correlating by "whichever connect is currently pending" is correct
    // because send/recv connects happen sequentially, never concurrently,
    // in this call flow.
    transport.on('connect', (data) async {
      final callback = data['callback'] as Function;
      final errback = data['errback'] as Function;
      try {
        _transportConnectCompleter = Completer<void>();
        final ok = await _webrtcApi.transportConnectRequest(
          conversationID: conversationID!,
          transportId: transport.id,
          dtlsParameters: (data['dtlsParameters'] as DtlsParameters).toMap(),
          clientId: clientId!,
        );
        if (!ok) throw StateError("transport-connect request failed");
        await _transportConnectCompleter!.future
            .timeout(const Duration(seconds: 15));
        callback();
      } catch (e) {
        errback(e);
      }
    });
  }

  Future<void> _consumeProducer(NewProducerEvent event) async {
    if (_recvTransport == null || _device == null || conversationID == null) {
      return;
    }
    if (consumers.containsKey(event.producerId)) return;
    try {
      _consumeCompleters[event.producerId] = Completer<ConsumeResponse>();
      final ok = await _webrtcApi.consumeRequest(
        conversationID: conversationID!,
        transportId: _recvTransport!.id,
        producerId: event.producerId,
        rtpCapabilities: _device!.rtpCapabilities.toMap(),
        clientId: clientId!,
      );
      if (!ok) throw StateError("consume request failed");
      final consumeData = await _consumeCompleters[event.producerId]!
          .future
          .timeout(const Duration(seconds: 15));
      _recvTransport!.consume(
        id: consumeData.id,
        producerId: event.producerId,
        peerId: event.clientId,
        kind: RTCRtpMediaTypeExtension.fromString(consumeData.kind),
        rtpParameters: RtpParameters.fromMap(consumeData.rtpParameters),
      );
    } catch (e) {
      if (kDebugMode) {
        print("[CallController] consume failed for ${event.producerId}: $e");
      }
    } finally {
      _consumeCompleters.remove(event.producerId);
    }
  }

  Map<String, dynamic>? _decode(dynamic raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// Every mediasoup room event is plain JSON on the wire - NOT JWT-wrapped
  /// like incomingcall/callreject/notifications (confirmed directly against
  /// webRTC.js's publish(...) calls).
  void _onSseEvent(SSEModel event) {
    switch (event.event) {
      case "join-room-response":
        final data = _decode(event.data);
        if (data == null) return;
        final response = JoinRoomResponse.fromJson(data);
        if (_joinRoomCompleter?.isCompleted == false) {
          _joinRoomCompleter?.complete(response);
        }
        return;
      case "create-transport-response":
        final data = _decode(event.data);
        if (data == null) return;
        final response = CreateTransportResponse.fromJson(data);
        if (response.direction == 'send' &&
            _sendTransportCompleter?.isCompleted == false) {
          _sendTransportCompleter?.complete(response);
        } else if (response.direction == 'recv' &&
            _recvTransportCompleter?.isCompleted == false) {
          _recvTransportCompleter?.complete(response);
        }
        return;
      case "transport-connect-response":
        if (_transportConnectCompleter?.isCompleted == false) {
          _transportConnectCompleter?.complete();
        }
        return;
      case "transport-connect-error":
        if (_transportConnectCompleter?.isCompleted == false) {
          _transportConnectCompleter?.completeError(StateError(
              "transport-connect-error: ${event.data}"));
        }
        return;
      case "produce-response":
        final data = _decode(event.data);
        if (data == null) return;
        final response = ProduceResponse.fromJson(data);
        if (_produceCompleter?.isCompleted == false) {
          _produceCompleter?.complete(response.id);
        }
        return;
      case "produce-error":
        if (_produceCompleter?.isCompleted == false) {
          _produceCompleter
              ?.completeError(StateError("produce-error: ${event.data}"));
        }
        return;
      case "new_producer":
        final data = _decode(event.data);
        if (data == null) return;
        final producerEvent = NewProducerEvent.fromJson(data);
        if (producerEvent.clientId == clientId) return; // our own, ignore
        _consumeProducer(producerEvent);
        return;
      case "consume-response":
        final data = _decode(event.data);
        if (data == null) return;
        final response = ConsumeResponse.fromJson(data);
        final completer = _consumeCompleters[response.producerId];
        if (completer?.isCompleted == false) completer?.complete(response);
        return;
      case "consume-error":
      case "consume-transport-error":
        // No producerId to key a specific completer off of in this error
        // shape - the relevant consume Completer simply times out instead.
        if (kDebugMode) print("[CallController] ${event.event}: ${event.data}");
        return;
      case "participant-joined":
        final data = _decode(event.data);
        if (data == null) return;
        final participant = CallParticipant.fromJson(data);
        participants.removeWhere((p) => p.clientId == participant.clientId);
        participants.add(participant);
        _hasHadPeer = true;
        notifyListeners();
        return;
      case "participant-left":
        final data = _decode(event.data);
        if (data == null) return;
        final left = ParticipantLeftEvent.fromJson(data);
        participants.removeWhere((p) => p.clientId == left.clientId);
        for (final producerId in left.producerIds) {
          consumers.remove(producerId)?.close();
        }
        notifyListeners();
        _maybeEndOnEmptyRoster();
        return;
      case "participant-status":
        final data = _decode(event.data);
        if (data == null) return;
        final targetClientId = data['clientId']?.toString();
        final idx =
            participants.indexWhere((p) => p.clientId == targetClientId);
        if (idx != -1) {
          participants[idx] = participants[idx].copyWith(
            muted: data['muted'] == true,
            cameraOff: data['cameraOff'] == true,
          );
          notifyListeners();
        }
        return;
      case "producer-closed":
        final data = _decode(event.data);
        if (data == null) return;
        final producerId = data['producerId']?.toString();
        if (producerId != null && consumers.containsKey(producerId)) {
          consumers.remove(producerId)?.close();
          notifyListeners();
        }
        return;
    }
  }

  /// webapp's CallWindow.tsx only ever sends an explicit end signal
  /// (/u/endcall) from whichever side placed the call (its isCaller gate) -
  /// if the OTHER side hangs up, we never receive a callreject/endcall SSE
  /// event at all, only the ordinary mediasoup participant-left event that
  /// empties our roster. Without this, the screen would sit forever
  /// showing "Ringing…" (status stays active, participants is just empty)
  /// instead of actually ending. Guarded to status==active so a
  /// participant-left arriving mid-leaveCall() (the async gap between
  /// status flipping to leaving and the SSE subscription actually being
  /// cancelled) can't trigger a second, overlapping leaveCall().
  void _maybeEndOnEmptyRoster() {
    if (_hasHadPeer && participants.isEmpty && status == CallEngineStatus.active) {
      leaveCall();
    }
  }

  Future<void> _cleanup() async {
    for (final track in _localStream?.getTracks() ?? const []) {
      track.stop();
    }
    _localStream = null;
    for (final c in consumers.values) {
      c.close();
    }
    consumers.clear();
    _sendTransport?.close();
    _recvTransport?.close();
    _sendTransport = null;
    _recvTransport = null;
    _device = null;
    await _sseSub?.cancel();
    _sseSub = null;
  }
}
