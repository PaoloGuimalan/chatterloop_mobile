import 'dart:async';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/views/messages/messages_gate.dart';
import 'package:flutter/material.dart';

/// /conversation serves personal chats and server/conference channels. Resolve
/// the authoritative setup before choosing the Messages access boundary.
class ConversationMessagesGate extends StatefulWidget {
  const ConversationMessagesGate(
      {super.key, required this.conversationId, required this.builder});
  final String conversationId;
  final Widget Function(Future<Map<String, dynamic>?> setupRequest) builder;
  @override
  State<ConversationMessagesGate> createState() =>
      _ConversationMessagesGateState();
}

class _ConversationMessagesGateState extends State<ConversationMessagesGate> {
  StreamSubscription? _accountSubscription;
  late Future<Map<String, dynamic>?> _setupRequest;
  bool _protected = false;
  int _generation = 0;
  String get _identity =>
      '${appStore.state.userAuth.user.id}/${appStore.state.userAuth.user.entityId}';
  @override
  void initState() {
    super.initState();
    var identity = _identity;
    _accountSubscription = appStore.onChange.listen((_) {
      if (_identity != identity) {
        identity = _identity;
        _load();
      }
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant ConversationMessagesGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.conversationId != oldWidget.conversationId) _load();
  }

  Future<void> _load() async {
    final ticket = ++_generation, owner = _identity, id = widget.conversationId;
    setState(() {
      _protected = false;
      _setupRequest = ConversationsApi().getConversationSetupRequest(id);
    });
    final setup = await _setupRequest;
    if (!mounted ||
        ticket != _generation ||
        owner != _identity ||
        id != widget.conversationId) {
      return;
    }
    final type = setup?['conversationType'];
    const excluded = {'channel', 'server', 'voice', 'conference'};
    // Only known server/conference types bypass the Messages lock. Unknown
    // or failed setup keeps protection while the normal screen handles errors.
    final protected = !excluded.contains(type);
    MessagesGate.setConversationProtection(id, protected: protected);
    setState(() => _protected = protected);
  }

  @override
  void dispose() {
    _generation++;
    _accountSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MessagesGate(
      enabled: _protected,
      child: KeyedSubtree(
          key: ValueKey('$_identity/${widget.conversationId}'),
          child: widget.builder(_setupRequest)),
    );
  }
}
