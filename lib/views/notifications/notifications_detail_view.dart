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
import 'package:chatterloop_app/core/reusables/widgets/paginated_scroll.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_v2_model.dart';
import 'package:chatterloop_app/views/notifications/notifications_view.dart';
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
  final List<NotificationV2> _items = [];

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
        if (page == 1) _items.clear();
        _items.addAll(result.items);
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
        for (var i = 0; i < _items.length; i++) {
          if (_items[i].referenceID == item.referenceID) {
            _items[i] = _items[i].copyWith(referenceStatus: true);
          }
        }
      }
    });

    final kind = item.isFollowRequest ? "Follow" : "Contact";
    final label = accept ? "accepted" : "declined";
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? "$kind request $label"
          : "Couldn't ${accept ? 'accept' : 'decline'} the request. Try again."),
      duration: const Duration(seconds: 2),
    ));
  }

  ({IconData icon, String subtitle}) get _emptyState => switch (widget.section) {
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
          : _items.isEmpty
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
                  itemCount: _items.length + (_isLoadingMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index >= _items.length) {
                      return const CLLoadMoreIndicator();
                    }
                    final item = _items[index];
                    return CLNotificationRow(
                      notification: item,
                      detail: true,
                      busy: _pendingActions.contains(item.referenceID),
                      onAccept: (target) => _respond(target, accept: true),
                      onDecline: (target) => _respond(target, accept: false),
                    );
                  },
                ),
    );
  }
}
