// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/requests/notifications_api.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_item_model.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_state_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_redux/flutter_redux.dart';

class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});

  @override
  NotificationsStateView createState() => NotificationsStateView();
}

class NotificationsStateView extends State<NotificationsView> {
  /// Matches webapp's Notifications.tsx (page starts at 1, range fixed).
  static const int _range = 20;

  /// How close to the bottom triggers the next page. Roughly one card's
  /// height, so the fetch starts before the spinner is actually reached.
  static const double _loadMoreThreshold = 320;

  final ScrollController _scrollController = ScrollController();
  StreamSubscription<SSEModel>? _eventBusSubscription;

  int _page = 1;
  bool isNotificationsInitialized = false;
  bool isReadNotificationsInitialized = false;
  bool _isLoadingMore = false;
  bool _hasNext = false;

  /// referenceIDs (connection ids) with an accept/decline in flight. Keyed per
  /// item rather than one global flag so acting on one request doesn't freeze
  /// the buttons on every other one in the list.
  final Set<String> _pendingActions = <String>{};

  /// referenceIDs resolved during this session. The server flips
  /// referenceStatus, but the already-fetched list in Redux still carries the
  /// old value, so without this the buttons would linger until a full reload.
  final Set<String> _locallyHandled = <String>{};

  @override
  void initState() {
    super.initState();
    // Kicked off here rather than from build()'s post-frame callback: this
    // screen is a StoreConnector, so every unrelated Redux change rebuilds it,
    // and a build-time guard re-enters until the async response lands.
    _loadPage(1);
    _scrollController.addListener(_onScroll);
    _eventBusSubscription = eventBus.on<SSEModel>().listen((SSEModel event) {
      if (event.event != "notifications") return;
      readNotificationsProcess();
      // A newly arrived notification belongs at the top. Only refresh when the
      // user hasn't paged further in - otherwise this would yank pages 2..n
      // out from under them mid-scroll.
      if (_page == 1) _loadPage(1);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _eventBusSubscription?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasNext || _isLoadingMore || !isNotificationsInitialized) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      _loadPage(_page + 1);
    }
  }

  /// Fetches one page. Page 1 replaces the list; later pages append.
  ///
  /// The server pages properly (`$skip: (page-1)*range, $limit: range`), so a
  /// later page contains ONLY its own slice - it has to be merged with what's
  /// already in Redux, deduped by notificationID exactly like webapp's
  /// SET_NOTIFICATIONS_LIST reducer does.
  Future<void> _loadPage(int page) async {
    if (_isLoadingMore) return;
    if (mounted) setState(() => _isLoadingMore = true);

    final EncodedResponse? response = await NotificationsApi()
        .getNotificationsListRequest(page: page, range: _range);

    if (!mounted) return;

    if (response == null) {
      setState(() {
        _isLoadingMore = false;
        isNotificationsInitialized = true;
      });
      return;
    }

    final Map<String, dynamic>? decoded = JwtCodec.decode(response.result);
    final List<dynamic> raw = (decoded?["notifications"] as List?) ?? const [];
    final List<NotificationsItemModel> incoming =
        raw.map((n) => NotificationsItemModel.fromJson(n)).toList();

    final existing = page == 1
        ? const <NotificationsItemModel>[]
        : appStore.state.notificationsstate.notificationsList;

    final merged = <NotificationsItemModel>[...existing];
    final seen = merged.map((n) => n.notificationID).toSet();
    for (final item in incoming) {
      if (seen.add(item.notificationID)) merged.add(item);
    }

    setState(() {
      _page = page;
      _hasNext = decoded?["next"] == true;
      _isLoadingMore = false;
      isNotificationsInitialized = true;
    });

    StoreProvider.of<AppState>(context).dispatch(DispatchModel(
        setNotificationsListT,
        NotificationsStateModel(
          merged,
          decoded?["totalunread"] ?? 0,
          decoded?["total"] ?? merged.length,
          _hasNext,
        )));

    if (!isReadNotificationsInitialized &&
        (decoded?["totalunread"] ?? 0) > 0) {
      readNotificationsProcess();
    }
  }

  Future<void> readNotificationsProcess() async {
    if (mounted) {
      setState(() => isReadNotificationsInitialized = true);
    }
    await NotificationsApi().readNotificationsRequest();
  }

  /// A contact request is actionable only while it's still pending -
  /// referenceStatus flips to true once it's been accepted. Same condition as
  /// webapp's `isContactRequest && !ntfs.referenceStatus`.
  bool _showsActions(NotificationsItemModel notif) =>
      notif.type == "contact_request" &&
      !notif.referenceStatus &&
      !_locallyHandled.contains(notif.referenceID);

  Future<void> _respondToContactRequest(
    NotificationsItemModel notif, {
    required bool accept,
  }) async {
    if (_pendingActions.contains(notif.referenceID)) return;
    setState(() => _pendingActions.add(notif.referenceID));

    final ok = accept
        ? await ContactsApi().acceptContactRequest(
            connectionId: notif.referenceID,
            entityId: notif.fromUserID,
          )
        // "decline" rejects an incoming request; "remove" is for cancelling a
        // sent one, which isn't reachable from this screen.
        : await ContactsApi().declineContactRequest(
            connectionId: notif.referenceID,
            entityId: notif.fromUserID,
            action: "decline",
          );

    if (!mounted) return;
    setState(() {
      _pendingActions.remove(notif.referenceID);
      if (ok) _locallyHandled.add(notif.referenceID);
    });

    final label = accept ? "accepted" : "declined";
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? "Contact request $label"
          : "Couldn't ${accept ? 'accept' : 'decline'} the request. Try again."),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState,
            ({NotificationsStateModel notificationsstate})>(
        distinct: true,
        converter: (store) =>
            (notificationsstate: store.state.notificationsstate),
        builder: (context, state) {
          final notificationslist = state.notificationsstate.notificationsList;

          return Scaffold(
            backgroundColor: p.bg,
            appBar: AppBar(title: const Text("Notifications")),
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: !isNotificationsInitialized
                  ? const Padding(
                      key: ValueKey('loading'),
                      padding: EdgeInsets.all(12),
                      child: CLListSkeleton(),
                    )
                  : notificationslist.isEmpty
                      ? Center(
                          key: const ValueKey('empty'),
                          child: Text("No notifications yet",
                              style: TextStyle(color: p.text2)))
                      : RefreshIndicator(
                          key: const ValueKey('list'),
                          onRefresh: () => _loadPage(1),
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(12),
                            // One extra row for the load-more spinner.
                            itemCount:
                                notificationslist.length + (_hasNext ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= notificationslist.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }
                              return _buildItem(notificationslist[index], p);
                            },
                          ),
                        ),
            ),
          );
        });
  }

  Widget _buildItem(NotificationsItemModel notif, CLPalette p) {
    final showActions = _showsActions(notif);
    final isPending = _pendingActions.contains(notif.referenceID);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CLCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CLAvatar(
              id: notif.fromUserID,
              name: notif.content.headline,
              src: notif.fromUser?.profile != null &&
                      notif.fromUser!.profile != "none"
                  ? notif.fromUser!.profile
                  : null,
              size: 46,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notif.content.headline,
                      style: TextStyle(
                          color: p.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(notif.content.details,
                      style: TextStyle(color: p.text2, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text("${notif.date.date} · ${notif.date.time}",
                      style: TextStyle(color: p.text3, fontSize: 11)),
                  if (showActions) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        CLBtn(
                          label: "Confirm",
                          size: CLBtnSize.sm,
                          onPressed: isPending
                              ? null
                              : () => _respondToContactRequest(notif,
                                  accept: true),
                        ),
                        const SizedBox(width: 8),
                        CLBtn(
                          label: "Decline",
                          size: CLBtnSize.sm,
                          variant: CLBtnVariant.outline,
                          onPressed: isPending
                              ? null
                              : () => _respondToContactRequest(notif,
                                  accept: false),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (!notif.isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: p.brand),
              ),
          ],
        ),
      ),
    );
  }
}
