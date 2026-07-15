// Manual mediasoup test harness, originally built for M1 (proving the
// join-room -> create-transport -> transport-connect -> produce -> consume
// sequence works end to end against the real server). M1 passed (confirmed
// via real-device logs: produce/consume both clean across multiple join
// cycles) and the feature has since moved on to the real architecture
// (WebrtcApi/CallApi/CallController, M2+) - this screen is NOT part of that
// production call flow and nothing depends on it.
//
// Kept intentionally (not deleted) as a low-level debugging tool: if a
// future milestone (reconnect, group calls, video) misbehaves, this gives a
// way to exercise the raw mediasoup REST+SSE sequence directly, without
// CallController/Redux/UI layers in the way, and read the raw log output.
// Not wired into app_router.dart - push it manually while debugging, e.g.
// `Navigator.push(context, MaterialPageRoute(builder: (_) =>
// const CallSpikeView()))`.
//
// Every REST field name/shape and every mediasoup_client_flutter API call
// here was confirmed directly against source (server/reusables/hooks/
// webRTC.js, server/routes/webrtc/index.js, and the pub-cached
// mediasoup_client_flutter-0.8.5 package) rather than assumed from the
// webapp JS - the two SDKs have different calling conventions (this
// package's produce()/consume() are void + callback-based, not
// promise/Future-returning, unlike mediasoup-client-js).

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:mediasoup_client_flutter/mediasoup_client_flutter.dart';

const String _spikeConversationID = "84186354038942661132";

class CallSpikeView extends StatefulWidget {
  const CallSpikeView({super.key});

  @override
  State<CallSpikeView> createState() => _CallSpikeViewState();
}

class _CallSpikeViewState extends State<CallSpikeView> {
  final _dio = ApiClient.instance.dio;
  late final String _clientId;
  final List<String> _logLines = [];
  StreamSubscription? _sseSub;

  Device? _device;
  Transport? _sendTransport;
  Transport? _recvTransport;
  MediaStream? _localStream;
  final Map<String, Consumer> _consumers = {};

  Completer<Map<String, dynamic>>? _joinRoomCompleter;
  Completer<Map<String, dynamic>>? _sendTransportCompleter;
  Completer<Map<String, dynamic>>? _recvTransportCompleter;
  Completer<void>? _transportConnectCompleter;
  Completer<String>? _produceCompleter;
  final Map<String, Completer<Map<String, dynamic>>> _consumeCompleters = {};

  bool _joining = false;
  bool _joined = false;

  @override
  void initState() {
    super.initState();
    _clientId =
        "spike-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(99999)}";
    // Same eventBus every other SSE-consuming screen in this app already
    // uses (conversation_view.dart, notifications_view.dart) - the single
    // global SSE connection fans every event out through this.
    _sseSub = eventBus.on<SSEModel>().listen(_onSseEvent);
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _cleanup();
    super.dispose();
  }

  void _appendLog(String s) {
    // ignore: avoid_print
    print("[CallSpike] $s");
    if (!mounted) return;
    setState(() => _logLines.insert(
        0, "${DateTime.now().toIso8601String().substring(11, 19)}  $s"));
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
  /// like incomingcall/callreject/notifications - confirmed directly
  /// against webRTC.js's `publish(...)` calls, which send the raw payload
  /// object with no JWT signing step.
  void _onSseEvent(SSEModel event) {
    switch (event.event) {
      case "join-room-response":
        final data = _decode(event.data);
        if (data == null) return;
        _appendLog("join-room-response participants=${data['participants']}");
        if (_joinRoomCompleter?.isCompleted == false) {
          _joinRoomCompleter?.complete(data);
        }
        return;
      case "create-transport-response":
        final data = _decode(event.data);
        if (data == null) return;
        _appendLog("create-transport-response direction=${data['direction']}");
        if (data['direction'] == 'send' &&
            _sendTransportCompleter?.isCompleted == false) {
          _sendTransportCompleter?.complete(data);
        } else if (data['direction'] == 'recv' &&
            _recvTransportCompleter?.isCompleted == false) {
          _recvTransportCompleter?.complete(data);
        }
        return;
      case "transport-connect-response":
        _appendLog("transport-connect-response");
        if (_transportConnectCompleter?.isCompleted == false) {
          _transportConnectCompleter?.complete();
        }
        return;
      case "transport-connect-error":
        _appendLog("ERROR transport-connect-error: ${event.data}");
        return;
      case "produce-response":
        final data = _decode(event.data);
        if (data == null) return;
        _appendLog("produce-response id=${data['id']}");
        if (_produceCompleter?.isCompleted == false) {
          _produceCompleter?.complete(data['id']?.toString());
        }
        return;
      case "produce-error":
        _appendLog("ERROR produce-error: ${event.data}");
        return;
      case "new_producer":
        final data = _decode(event.data);
        if (data == null) return;
        _appendLog(
            "new_producer producerId=${data['producerId']} kind=${data['kind']} from clientId=${data['clientId']}");
        if (data['clientId'] == _clientId) return; // our own, ignore
        _consumeProducer(data);
        return;
      case "consume-response":
        final data = _decode(event.data);
        if (data == null) return;
        final producerId = data['producerId']?.toString();
        _appendLog(
            "consume-response producerId=$producerId kind=${data['kind']}");
        if (producerId != null &&
            _consumeCompleters[producerId]?.isCompleted == false) {
          _consumeCompleters[producerId]?.complete(data);
        }
        return;
      case "consume-error":
      case "consume-transport-error":
        _appendLog("ERROR ${event.event}: ${event.data}");
        return;
      case "participant-joined":
        _appendLog("participant-joined: ${event.data}");
        return;
      case "participant-left":
        _appendLog("participant-left: ${event.data}");
        return;
    }
  }

  Future<void> _join() async {
    if (_joining || _joined) return;
    setState(() => _joining = true);
    try {
      final myName = appStore.state.userAuth.user.personalDisplayName;

      // 1. join-room - server responds with routerRtpCapabilities (needed
      // to load the Device) and replays new_producer for anyone already in
      // the room (late-join sync), confirmed in joinRoom()'s implementation.
      _joinRoomCompleter = Completer<Map<String, dynamic>>();
      await _dio.post('/webrtc/join-room', data: {
        "conversationID": _spikeConversationID,
        "members": <String>[],
        "muted": false,
        "cameraOff": true,
        "username": myName,
        "clientId": _clientId,
      });
      final joinData =
          await _joinRoomCompleter!.future.timeout(const Duration(seconds: 15));

      // 2. load device
      _device = Device();
      await _device!.load(
          routerRtpCapabilities:
              RtpCapabilities.fromMap(joinData["routerRtpCapabilities"]));
      _appendLog(
          "device loaded, canProduceAudio=${_device!.canProduce(RTCRtpMediaType.RTCRtpMediaTypeAudio)}");

      // 3. create send transport, wire its connect/produce events to the
      // matching REST calls - mediasoup_client_flutter's produce()/connect
      // listeners are void+callback based (not Future-returning), so the
      // REST round-trip has to happen inside the listener and invoke
      // callback()/errback() itself.
      _sendTransportCompleter = Completer<Map<String, dynamic>>();
      await _dio.post('/webrtc/create-transport', data: {
        "conversationID": _spikeConversationID,
        "direction": "send",
        "clientId": _clientId,
      });
      final sendData = await _sendTransportCompleter!.future
          .timeout(const Duration(seconds: 15));
      final sendTransportId = sendData["response"]["id"];
      _sendTransport = _device!.createSendTransportFromMap(
        sendData["response"],
        producerCallback: (producer) {
          _appendLog("local producer created: ${producer.id}");
        },
      );
      _wireTransportConnect(_sendTransport!);
      // If this line never appears in the log after tapping Join, the SDK's
      // internal _handler.send() (SDP offer/answer, happens BEFORE this
      // event fires) either never ran or threw somewhere mediasoup_client_
      // flutter's own FlexQueue task swallowed/logged silently instead of
      // propagating back to _join()'s try/catch - that Future is fire-and-
      // forget from produce()'s perspective, so a failure in there does NOT
      // surface as "JOIN FAILED" the way every other step here does.
      _sendTransport!.on('produce', (data) async {
        _appendLog(
            "'produce' event fired: kind=${data['kind']} - starting REST round-trip");
        final callback = data['callback'] as Function;
        final errback = data['errback'] as Function;
        try {
          _produceCompleter = Completer<String>();
          await _dio.post('/webrtc/produce', data: {
            "conversationID": _spikeConversationID,
            "transportId": sendTransportId,
            "kind": data['kind'] == RTCRtpMediaType.RTCRtpMediaTypeAudio
                ? "audio"
                : "video",
            "rtpParameters": (data['rtpParameters'] as RtpParameters).toMap(),
            "members": <String>[],
            "clientId": _clientId,
            "appData": data['appData'] ?? {},
          });
          final id = await _produceCompleter!.future
              .timeout(const Duration(seconds: 15));
          _appendLog(
              "produce REST round-trip resolved id=$id, invoking callback");
          // NOT callback({"id": id}) - unlike mediasoup-client-js, this
          // Dart port's _produce() does `String id = await
          // safeEmitAsFuture('produce', ...)`, i.e. it expects the raw id
          // string, not an {id: ...} wrapper. Passing the wrapped map threw
          // "type '_Map<String, String>' is not a subtype of type
          // 'String'" inside Transport._produce (swallowed by FlexQueue's
          // bare print(), never reaching this try/catch - confirmed via
          // logcat during the M1 device test), which triggered the
          // package's own failure-cleanup path (stopSending() on a
          // producer that was never fully created) - explains the
          // a=inactive renegotiation seen in earlier test runs.
          callback(id);
        } catch (e, st) {
          _appendLog("'produce' event handler FAILED: $e");
          // ignore: avoid_print
          print(st);
          errback(e);
        }
      });

      // 4. create recv transport
      _recvTransportCompleter = Completer<Map<String, dynamic>>();
      await _dio.post('/webrtc/create-transport', data: {
        "conversationID": _spikeConversationID,
        "direction": "recv",
        "clientId": _clientId,
      });
      final recvData = await _recvTransportCompleter!.future
          .timeout(const Duration(seconds: 15));
      _recvTransport = _device!.createRecvTransportFromMap(
        recvData["response"],
        consumerCallback: (consumer, accept) {
          _appendLog(
              "local consumer created: ${consumer.id} producerId=${consumer.producerId}");
          _consumers[consumer.producerId] = consumer;
          if (mounted) setState(() {});
          if (accept != null) accept();
        },
      );
      _wireTransportConnect(_recvTransport!);

      // 5. produce local mic - audio-only for this spike (cameraOff:true
      // above), video is M7's concern.
      final stream = await navigator.mediaDevices
          .getUserMedia({"audio": true, "video": false});
      _localStream = stream;
      final audioTracks = stream.getAudioTracks();
      _appendLog("getUserMedia resolved: ${audioTracks.length} audio track(s)");
      if (audioTracks.isEmpty) {
        throw StateError(
            "getUserMedia returned a stream with no audio tracks - mic permission likely wasn't actually granted");
      }
      final audioTrack = audioTracks.first;
      _appendLog(
          "audioTrack: enabled=${audioTrack.enabled} kind=${audioTrack.kind}");
      _appendLog("calling sendTransport.produce()...");
      _sendTransport!.produce(
        track: audioTrack,
        stream: stream,
        source: "mic",
      );
      _appendLog(
          "produce() call returned (this only means it was queued, not that it succeeded - watch for the 'produce' event line above/below)");

      setState(() {
        _joining = false;
        _joined = true;
      });
      _appendLog("JOINED - waiting for remote participants' audio");
    } catch (e, st) {
      _appendLog("JOIN FAILED: $e");
      // ignore: avoid_print
      print(st);
      if (mounted) setState(() => _joining = false);
    }
  }

  void _wireTransportConnect(Transport transport) {
    // transport-connect-response carries no transportId/direction field
    // (confirmed against transportConnect()'s publish call in webRTC.js) -
    // correlating by "whichever connect is currently pending" is correct
    // here because this spike only ever has one connect in flight at a
    // time (send transport connects on first produce(), recv transport
    // connects later on first consume() - never concurrently).
    transport.on('connect', (data) async {
      final callback = data['callback'] as Function;
      final errback = data['errback'] as Function;
      try {
        _transportConnectCompleter = Completer<void>();
        await _dio.post('/webrtc/transport-connect', data: {
          "conversationID": _spikeConversationID,
          "transportId": transport.id,
          "dtlsParameters": (data['dtlsParameters'] as DtlsParameters).toMap(),
          "clientId": _clientId,
        });
        await _transportConnectCompleter!.future
            .timeout(const Duration(seconds: 15));
        callback();
      } catch (e) {
        errback(e);
      }
    });
  }

  Future<void> _consumeProducer(Map<String, dynamic> data) async {
    if (_recvTransport == null || _device == null) return;
    final producerId = data["producerId"]?.toString();
    if (producerId == null || _consumers.containsKey(producerId)) return;
    try {
      _consumeCompleters[producerId] = Completer<Map<String, dynamic>>();
      await _dio.post('/webrtc/consume', data: {
        "conversationID": _spikeConversationID,
        "transportId": _recvTransport!.id,
        "producerId": producerId,
        "rtpCapabilities": _device!.rtpCapabilities.toMap(),
        "clientId": _clientId,
      });
      final consumeData = await _consumeCompleters[producerId]!
          .future
          .timeout(const Duration(seconds: 15));
      _recvTransport!.consume(
        id: consumeData["id"],
        producerId: producerId,
        peerId: data["clientId"]?.toString() ?? "",
        kind: RTCRtpMediaTypeExtension.fromString(consumeData["kind"]),
        rtpParameters: RtpParameters.fromMap(consumeData["rtpParameters"]),
      );
    } catch (e) {
      _appendLog("consume failed for $producerId: $e");
    } finally {
      _consumeCompleters.remove(producerId);
    }
  }

  Future<void> _leave() async {
    try {
      await _dio.post('/webrtc/leave-room', data: {
        "conversationID": _spikeConversationID,
        "clientId": _clientId,
      });
    } catch (_) {}
    _cleanup();
    if (mounted) setState(() => _joined = false);
  }

  void _cleanup() {
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;
    for (final c in _consumers.values) {
      c.close();
    }
    _consumers.clear();
    _sendTransport?.close();
    _recvTransport?.close();
    _sendTransport = null;
    _recvTransport = null;
    _device = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Call spike (mediasoup debug harness)")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _joining || _joined ? null : _join,
                    child: Text(_joining ? "Joining…" : "Join call"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _joined ? _leave : null,
                    child: const Text("Leave"),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
                "clientId: $_clientId\nconversationID: $_spikeConversationID\nremote producers: ${_consumers.length}"),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _logLines.length,
              itemBuilder: (context, i) => Text(
                _logLines[i],
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
