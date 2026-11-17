import 'dart:async';
import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';

/// Private management/submission screens discard results from an earlier identity.
class RealmRequestTicket {
  final int generation;
  final String identity;
  final String? token;
  const RealmRequestTicket(this.generation, this.identity, this.token);
}

abstract class RealmPrivateState<T extends StatefulWidget> extends State<T>
    with WidgetsBindingObserver {
  StreamSubscription? _subscription;
  int _generation = 0;
  String get identity =>
      '${appStore.state.userAuth.auth}:${appStore.state.userAuth.user.entityId}';
  late String _identity;
  String get actingEntityId => appStore.state.userAuth.user.entityId;
  void reloadPrivate();
  @override
  void initState() {
    super.initState();
    _identity = identity;
    WidgetsBinding.instance.addObserver(this);
    _subscription = appStore.onChange.listen((_) {
      if (identity != _identity) {
        _identity = identity;
        _generation++;
        reloadPrivate();
      }
    });
  }

  Future<RealmRequestTicket> requestTicket({bool invalidate = true}) async {
    final generation = invalidate ? ++_generation : _generation;
    final actor = identity;
    final token = await ApiClient.instance.readToken();
    return RealmRequestTicket(generation, actor, token);
  }

  Future<bool> isCurrent(RealmRequestTicket ticket) async {
    if (!mounted ||
        ticket.generation != _generation ||
        ticket.identity != identity) {
      return false;
    }
    final token = await ApiClient.instance.readToken();
    return mounted &&
        ticket.generation == _generation &&
        ticket.identity == identity &&
        ticket.token == token;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) reloadPrivate();
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
