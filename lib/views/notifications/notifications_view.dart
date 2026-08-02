// Notifications - the redesigned screen. Ported from webapp's
// src/app/tabs/feed/Notifications.tsx at the mobile layout from the mockup:
// three stacked section cards (Activity / Connections / System), each showing a
// short preview with its own unread pill and a "See all" into the paginated
// detail screen (notifications_detail_view.dart).
//
// Fed by the sectioned v2 Node endpoints - one overview call settles all three
// on load. The v1 flow (/u/getNotifications + the redux notifications slice) is
// untouched and still drives the topbar badge and the SSE refresh, which is
// also what this screen listens to for live updates.
// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/requests/notifications_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:chatterloop_app/core/reusables/widgets/notification_row.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_v2_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:go_router/go_router.dart';

/// One value for the preview AND the per-page size, so the server's Mongo
/// $skip arithmetic stays aligned across loads (page 2 starts at item 11).
const int kNotificationsRange = 10;

/// How many of a section's preview rows the card shows. The overview fetches
/// [kNotificationsRange] so the See-all screen's first page is already warm.
const int _kPreviewRows = 3;

/// Section chrome. System's purple has no palette token - it's the one accent
/// in the design that isn't part of the brand/green/gold/pink set.
const Color _kSystemColor = Color(0xFF8B5CF6);

class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  StreamSubscription<SSEModel>? _eventBusSubscription;

  NotificationsOverviewV2? _overview;
  bool _isLoading = true;

  /// Auto-read on open is kept behavior - fire once per visit, after the first
  /// successful load. The topbar badge re-syncs by itself: /u/readnotifications
  /// triggers the notifications_reload SSE, which refreshes the redux slice.
  bool _hasAutoRead = false;

  /// referenceIDs (connection ids) with an accept/decline in flight. Keyed per
  /// item rather than one global flag so acting on one request doesn't freeze
  /// the buttons on every other one.
  final Set<String> _pendingActions = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
    // Live updates with no extra plumbing: a NEW notification raises the
    // "notifications" SSE event, which re-settles all three sections. Reading
    // them raises "notifications_reload" instead, which is deliberately NOT
    // handled here - it fires moments after the auto-read below and refetching
    // then would instantly wipe the unread highlights the user came to see.
    _eventBusSubscription = eventBus.on<SSEModel>().listen((event) {
      if (event.event != "notifications") return;
      _load();
    });
  }

  @override
  void dispose() {
    _eventBusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await NotificationsApi()
        .notificationsOverviewV2Request(range: kNotificationsRange);
    if (!mounted) return;
    setState(() {
      if (result != null) _overview = result;
      _isLoading = false;
    });
    if (result != null && !_hasAutoRead) {
      _hasAutoRead = true;
      NotificationsApi().readNotificationsRequest();
    }
  }

  /// Rebuilds every section through [transform] - a read/handled flip can
  /// affect any of them, and a notification's section isn't known here.
  void _mapSections(
      NotificationV2 Function(NotificationV2 item) transform,
      {bool zeroUnread = false}) {
    final overview = _overview;
    if (overview == null) return;
    NotificationSectionData patch(NotificationSectionData section) =>
        NotificationSectionData(
          items: section.items.map(transform).toList(),
          total: section.total,
          unread: zeroUnread ? 0 : section.unread,
          hasNext: section.hasNext,
        );
    setState(() {
      _overview = NotificationsOverviewV2(
        activity: patch(overview.activity),
        connections: patch(overview.connections),
        system: patch(overview.system),
      );
    });
  }

  void _markAllRead() {
    NotificationsApi().readNotificationsRequest();
    _mapSections((item) => item.copyWith(isRead: true), zeroUnread: true);
  }

  /// Accept/decline reuse the SAME contact endpoints as everywhere else;
  /// referenceStatus flips locally so the buttons disappear immediately rather
  /// than lingering until a refetch.
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
          // "decline" rejects an incoming request; "remove" is for cancelling
          // a sent one, which isn't reachable from this screen.
          : await api.declineContactRequest(
              connectionId: item.referenceID,
              entityId: item.fromUserID,
              action: "decline",
            );
    }

    if (!mounted) return;
    setState(() => _pendingActions.remove(item.referenceID));
    if (ok) {
      _mapSections((candidate) => candidate.referenceID == item.referenceID
          ? candidate.copyWith(referenceStatus: true)
          : candidate);
    }

    final kind = item.isFollowRequest ? "Follow" : "Contact";
    final label = accept ? "accepted" : "declined";
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? "$kind request $label"
          : "Couldn't ${accept ? 'accept' : 'decline'} the request. Try again."),
      duration: const Duration(seconds: 2),
    ));
  }

  // -------- sections ---------------------------------------------------------

  ({IconData icon, Color color, String emptyText}) _chrome(
      NotificationSection section, CLPalette p) {
    return switch (section) {
      NotificationSection.activity => (
          icon: Icons.bolt,
          color: p.brand,
          emptyText: "New reactions, comments and shares land here."
        ),
      NotificationSection.connections => (
          icon: Icons.person,
          color: p.green,
          emptyText: "Contact requests and new followers land here."
        ),
      NotificationSection.system => (
          icon: Icons.campaign,
          color: _kSystemColor,
          emptyText: "Updates from ChatterLoop land here."
        ),
    };
  }

  Widget _unreadPill(int count, CLPalette p) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 19),
      height: 19,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.pink,
        borderRadius: BorderRadius.circular(CLRadii.pill),
      ),
      child: Text(
        "$count",
        style: const TextStyle(
          fontSize: CLType.meta,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _sectionCard(NotificationSection section, CLPalette p) {
    final data = _overview?.section(section) ?? NotificationSectionData.empty;
    final chrome = _chrome(section, p);
    final visible = data.items.take(_kPreviewRows).toList();

    return CLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(chrome.icon, size: 19, color: chrome.color),
              const SizedBox(width: 8),
              Text(
                section.title,
                style: TextStyle(
                  fontSize: CLType.sectionTitle,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                  color: p.text,
                ),
              ),
              const SizedBox(width: 8),
              _unreadPill(data.unread, p),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            ...List.generate(
              _kPreviewRows,
              (_) => const CLNotificationRowSkeleton(),
            )
          else if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              child: Column(
                children: [
                  Icon(chrome.icon, size: 32, color: p.text3),
                  const SizedBox(height: 6),
                  Text(
                    "You're all caught up!",
                    style: TextStyle(
                        fontSize: CLType.body,
                        fontWeight: FontWeight.w700,
                        color: p.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    chrome.emptyText,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: CLType.caption, color: p.text3),
                  ),
                ],
              ),
            )
          else
            ...visible.map((item) => Padding(
                  padding:
                      EdgeInsets.only(bottom: item == visible.last ? 0 : 8),
                  child: CLNotificationRow(
                    notification: item,
                    busy: _pendingActions.contains(item.referenceID),
                    onAccept: (target) => _respond(target, accept: true),
                    onDecline: (target) => _respond(target, accept: false),
                  ),
                )),
          if (!_isLoading && data.total > visible.length) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => context.push('/notifications/${section.slug}'),
                borderRadius: BorderRadius.circular(CLRadii.xs),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    "See all ${data.total} →",
                    style: TextStyle(
                      fontSize: CLType.label,
                      fontWeight: FontWeight.w600,
                      color: p.brand,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: const Text("Notifications"),
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _markAllRead,
            icon: Icon(Icons.done_all, size: 18, color: p.brand),
            label: Text(
              "Mark all read",
              style: TextStyle(
                fontSize: CLType.label,
                fontWeight: FontWeight.w600,
                color: p.brand,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _sectionCard(NotificationSection.activity, p),
            const SizedBox(height: 16),
            _sectionCard(NotificationSection.connections, p),
            const SizedBox(height: 16),
            _sectionCard(NotificationSection.system, p),
          ],
        ),
      ),
    );
  }
}
