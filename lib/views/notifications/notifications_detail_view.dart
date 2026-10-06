// One notification section, in full - the "See all" screen. Ported from the
// detail half of webapp's Notifications.tsx: the larger bordered rows with the
// type badge on the avatar, paging the section's own v2 endpoint.
//
// Reading is NOT re-triggered here - the main screen already auto-reads on
// open, so hitting /u/readnotifications again would only churn the SSE.
// ignore_for_file: use_build_context_synchronously

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/requests/notifications_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/notification_row.dart';
import 'package:chatterloop_app/core/utils/notification_actions.dart';
import 'package:go_router/go_router.dart';
import 'package:chatterloop_app/core/reusables/widgets/paginated_scroll.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_v2_model.dart';
import 'package:chatterloop_app/views/notifications/notifications_view.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:flutter/material.dart';

class NotificationsDetailScreen extends StatefulWidget {
  final NotificationSection section;

  const NotificationsDetailScreen({super.key, required this.section});

  @override
  State<NotificationsDetailScreen> createState() =>
      _NotificationsDetailScreenState();
}

class _NotificationsDetailScreenState extends State<NotificationsDetailScreen>
    with PaginatedScrollMixin<NotificationsDetailScreen> {
  /// Rows: groups of several, or notifications on their own.
  final List<NotificationGroup> _groups = [];
  final Set<String> _expanded = <String>{};

  int _page = 0;
  int? _total;
  bool _hasNext = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  final Set<String> _pendingActions = <String>{};

  @override
  bool get canLoadMore => _hasNext && !_isLoading && !_isLoadingMore;

  @override
  void initState() {
    super.initState();
    _fetch(1);
  }

  @override
  void loadNextPage() => _fetch(_page + 1);

  Future<void> _fetch(int page) async {
    if (page == 1) {
      setState(() => _isLoading = true);
    } else {
      if (_isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    }

    final result = await NotificationsApi().notificationsSectionV2Request(
      widget.section,
      page: page,
      range: kNotificationsRange,
    );
    if (!mounted) return;

    setState(() {
      if (result != null) {
        if (page == 1) _groups.clear();
        // A notification arriving between pages can move a group onto the
        // next page - it is already here, so skip it.
        final have = _groups.map((g) => g.key).toSet();
        _groups.addAll(result.groups.where((g) => !have.contains(g.key)));
        _total = result.total;
        _hasNext = result.hasNext;
        _page = page;
      }
      _isLoading = false;
      _isLoadingMore = false;
    });
    ensureFilled();
  }

  Future<void> _respond(NotificationV2 item, {required bool accept}) async {
    if (_pendingActions.contains(item.referenceID)) return;
    setState(() => _pendingActions.add(item.referenceID));

    // Two request kinds share this row and its buttons but hit different
    // endpoints with different ids:
    //
    //   contact_request - referenceID is the CONNECTION id
    //   follow_request  - referenceID is the REQUESTER'S ENTITY id, because a
    //                     follow has no connection row to point at
    //
    // Branch on the type rather than the id, since the two are
    // indistinguishable by shape.
    final bool ok;
    if (item.isFollowRequest) {
      ok = await ProfileApi().answerFollowRequest(
        requesterEntityId: item.referenceID,
        approve: accept,
      );
    } else {
      final api = ContactsApi();
      ok = accept
          ? await api.acceptContactRequest(
              connectionId: item.referenceID,
              entityId: item.fromUserID,
            )
          : await api.declineContactRequest(
              connectionId: item.referenceID,
              entityId: item.fromUserID,
              action: "decline",
            );
    }

    if (!mounted) return;
    setState(() {
      _pendingActions.remove(item.referenceID);
      if (ok) {
        _settle(item.referenceID);
      }
    });

    final kind = item.isFollowRequest ? "Follow" : "Contact";
    final label = accept ? "accepted" : "declined";
    CLAlerts.show(
        ok
            ? "$kind request $label"
            : "Couldn't ${accept ? 'accept' : 'decline'} the request. Try again.",
        type: ok ? CLAlertType.success : CLAlertType.error);
  }

  /// Server-driven action - see notifications_view.dart's _runAction, which
  /// this mirrors against this screen's rows.
  Future<void> _runAction(
      NotificationV2 item, NotificationAction action) async {
    final isCall =
        action.type == 'api-request' || action.type == 'external-api-request';
    if (isCall) {
      if (_pendingActions.contains(item.referenceID)) return;
      setState(() => _pendingActions.add(item.referenceID));
    }

    final outcome = await runNotificationAction(action);
    if (!mounted) return;

    if (outcome.navigateTo != null) {
      if (isCall) setState(() => _pendingActions.remove(item.referenceID));
      context.push(outcome.navigateTo!);
      return;
    }

    setState(() {
      if (isCall) _pendingActions.remove(item.referenceID);
      if (outcome.ok) {
        _settle(item.referenceID);
      }
    });

    if (!outcome.ok) {
      CLAlerts.show(outcome.message ?? "Couldn't complete that action.",
          type: CLAlertType.warning);
    }
  }

  /// Hides the buttons on every row answering [referenceID], inside groups too.
  void _settle(String referenceID) {
    for (var i = 0; i < _groups.length; i++) {
      _groups[i] = _groups[i].mapItems((n) => n.referenceID == referenceID
          ? n.copyWith(referenceStatus: true)
          : n);
    }
  }

  /// Row tap - only reached when the server gave this platform a destination.
  Future<void> _openNotification(NotificationV2 item) async {
    final destination = item.redirect;
    if (destination == null) return;
    final route = await resolveRedirect(destination);
    if (!mounted || route == null) return;
    context.push(route);
  }

  ({IconData icon, String subtitle}) get _emptyState =>
      switch (widget.section) {
        NotificationSection.activity => (
            icon: Icons.bolt,
            subtitle: "New reactions, comments and shares land here."
          ),
        NotificationSection.connections => (
            icon: Icons.person,
            subtitle: "Contact requests and new followers land here."
          ),
        NotificationSection.system => (
            icon: Icons.campaign,
            subtitle: "Updates from ChatterLoop land here."
          ),
      };

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final empty = _emptyState;

    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: Text(widget.section.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child:
                Center(child: CLCountPill(count: _isLoading ? null : _total)),
          ),
        ],
      ),
      body: _isLoading
          ? ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: 8,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, __) =>
                  const CLNotificationRowSkeleton(detail: true),
            )
          : _groups.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: CLEmptyState(
                      icon: empty.icon,
                      iconBg: p.surface2,
                      iconColor: p.text2,
                      iconBorderColor: p.border,
                      title: "You're all caught up!",
                      subtitle: empty.subtitle,
                    ),
                  ),
                )
              : ListView.separated(
                  controller: paginationController,
                  padding: const EdgeInsets.all(14),
                  itemCount: _groups.length + (_isLoadingMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index >= _groups.length) {
                      return const CLLoadMoreIndicator();
                    }
                    final group = _groups[index];
                    if (group.isGroup) {
                      return CLGroupedNotificationRow(
                        key: ValueKey(group.key),
                        group: group,
                        detail: true,
                        expanded: _expanded.contains(group.key),
                        onToggle: (key) => setState(() {
                          if (!_expanded.remove(key)) _expanded.add(key);
                        }),
                        busy: (item) =>
                            _pendingActions.contains(item.referenceID),
                        onAccept: (target) => _respond(target, accept: true),
                        onDecline: (target) =>
                            _respond(target, accept: false),
                        onAction: _runAction,
                        onOpen: _openNotification,
                      );
                    }
                    final item = group.items.first;
                    return CLNotificationRow(
                      key: ValueKey(group.key),
                      notification: item,
                      detail: true,
                      busy: _pendingActions.contains(item.referenceID),
                      onAccept: (target) => _respond(target, accept: true),
                      onDecline: (target) => _respond(target, accept: false),
                      onAction: _runAction,
                      onOpen: _openNotification,
                    );
                  },
                ),
    );
  }
}
