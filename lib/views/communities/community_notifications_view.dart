import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/reusables/widgets/paginated_scroll.dart';
import 'package:chatterloop_app/core/reusables/widgets/notification_row.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/models/notifications_models/community_notification_model.dart';
import 'package:chatterloop_app/views/communities/community_requests_view.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

class CommunityNotificationsView extends StatefulWidget {
  final String realmId;
  final CommunityApi? api;
  const CommunityNotificationsView(
      {super.key, required this.realmId, this.api});

  @override
  State<CommunityNotificationsView> createState() =>
      _CommunityNotificationsViewState();
}

class _CommunityNotificationsViewState extends State<CommunityNotificationsView>
    with WidgetsBindingObserver {
  final _items = <CommunityNotification>[];
  bool _loading = true, _loadingMore = false, _hasNext = false, _failed = false;
  bool _reviewing = false;
  int _page = 1, _generation = 0, _total = 0;
  late String _actor;
  StreamSubscription? _identitySubscription;

  @override
  void initState() {
    super.initState();
    _actor = appStore.state.userAuth.user.entityId;
    _identitySubscription = appStore.onChange.listen((_) {
      final actor = appStore.state.userAuth.user.entityId;
      if (actor != _actor) {
        _actor = actor;
        _load();
      }
    });
    communityNotificationsChanges.addListener(_refresh);
    communityChanges.addListener(_refresh);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant CommunityNotificationsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.realmId != widget.realmId) _load();
  }

  void _refresh() => _load();

  bool _isCurrent(int generation, String actor) =>
      mounted &&
      generation == _generation &&
      actor == _actor &&
      actor == appStore.state.userAuth.user.entityId;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    _identitySubscription?.cancel();
    communityNotificationsChanges.removeListener(_refresh);
    communityChanges.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    if (page > 1 && (_loading || _loadingMore || !_hasNext)) return;
    final generation = ++_generation;
    final actor = _actor;
    setState(() {
      _failed = false;
      _loading = page == 1;
      _loadingMore = page > 1;
      if (page == 1) {
        _items.clear();
        _total = 0;
        _hasNext = false;
      }
    });
    try {
      final api = widget.api ??
          CommunityApi(authToken: await ApiClient.instance.readToken());
      if (!_isCurrent(generation, actor)) return;
      final result = await api.notifications(widget.realmId, page: page);
      if (!_isCurrent(generation, actor)) return;
      setState(() {
        final ids = _items.map((item) => item.id).toSet();
        _items.addAll(result.results.where((item) => ids.add(item.id)));
        _total = result.count;
        _hasNext = result.hasNext;
        _page = page;
        _loading = _loadingMore = false;
      });
      if (page == 1 && result.activityRevision != null) {
        try {
          await api.acknowledgeNotifications(widget.realmId,
              activityRevision: result.activityRevision!);
        } catch (error) {
          if (!_isCurrent(generation, actor)) return;
          CLAlerts.requestError(error,
              fallback: 'Could not mark community activity as read.');
        }
      }
    } catch (error) {
      if (!_isCurrent(generation, actor)) return;
      CLAlerts.requestError(error, fallback: 'Could not load notifications.');
      setState(() {
        _loading = _loadingMore = false;
        _failed = true;
        if (error is DioException &&
            [401, 403, 404].contains(error.response?.statusCode)) {
          _items.clear();
          _total = 0;
          _hasNext = false;
        }
      });
    }
  }

  Future<void> _review() async {
    if (_reviewing) return;
    final actor = _actor;
    final generation = _generation;
    setState(() => _reviewing = true);
    try {
      final api = widget.api ??
          CommunityApi(authToken: await ApiClient.instance.readToken());
      if (!_isCurrent(generation, actor)) return;
      // The notifications route accepts a slug too; the existing requests
      // lifecycle takes a realm ID, so resolve before opening that screen.
      final community = await api.detail(widget.realmId);
      if (!mounted || !_isCurrent(generation, actor)) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CommunityRequestsView(realmId: community.realmId)));
      if (_isCurrent(generation, actor)) _load();
    } catch (error) {
      if (_isCurrent(generation, actor)) {
        CLAlerts.requestError(error, fallback: 'Could not open join requests.');
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(
        leadingWidth: 48,
        titleSpacing: 0,
        title: const Text('Notifications'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: CLSpacing.contentGutter),
            child: Center(child: CLCountPill(count: _loading ? null : _total)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              CLSpacing.contentGutter, 12, CLSpacing.contentGutter, 24),
          children: [
            if (_loading)
              for (var i = 0; i < 6; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: CLNotificationRowSkeleton(detail: true),
                )
            else ...[
              if (_items.isEmpty)
                CLSectionEmpty(
                  icon:
                      _failed ? Icons.error_outline : Icons.notifications_none,
                  title: _failed
                      ? 'Could not load notifications'
                      : 'You’re all caught up',
                  subtitle: _failed
                      ? 'Try again to see community activity.'
                      : 'Join requests and activity on community posts appear here.',
                ),
              for (final item in _items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CommunityNotificationRow(
                    item: item,
                    onReview: _reviewing ? null : _review,
                    onOpen: item.postRoute == null
                        ? null
                        : () => context.push(item.postRoute!),
                  ),
                ),
              if (_failed || _hasNext) ...[
                const SizedBox(height: 8),
                CLBtn(
                  label: _failed ? 'Try again' : 'Load more',
                  variant: CLBtnVariant.outline,
                  onPressed: _loadingMore
                      ? null
                      : () => _load(page: _items.isEmpty ? 1 : _page + 1),
                ),
              ],
              if (_loadingMore)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: CLNotificationRowSkeleton(detail: true),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommunityNotificationRow extends StatelessWidget {
  final CommunityNotification item;
  final VoidCallback? onReview;
  final VoidCallback? onOpen;
  const _CommunityNotificationRow({
    required this.item,
    required this.onReview,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final actor = item.isAnonymous ? null : item.actor;
    final badge = switch (item.type) {
      'community_join_request' => (Icons.person_add, p.brand),
      'post_comment' => (Icons.mode_comment, p.green),
      'post_reaction' || 'comment_reaction' => (Icons.favorite, p.pink),
      _ => (Icons.notifications, p.text3),
    };
    final name = actor?.displayName ?? '';
    final hasNamePrefix = name.isNotEmpty && item.description.startsWith(name);
    final markers = actor == null
        ? <Widget>[]
        : clEntityMarkers(context,
            isVerified: actor.isVerified,
            isPage: actor.isPage,
            isBot: actor.isBot,
            kindSize: 14);
    if (actor?.realmType == 'community') {
      markers.add(Padding(
          padding: const EdgeInsets.only(left: 3),
          child: Icon(Icons.groups_outlined,
              size: 15, color: p.text3, semanticLabel: 'Community')));
    }
    final onTap = item.canReview ? onReview : onOpen;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CLRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CLAvatar(
                        size: 40,
                        id: actor?.entityId,
                        name: actor?.displayName,
                        src: actor?.profile,
                        kind: actor == null ? 'anonymous' : actor.entityType),
                    Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                                color: p.surface, shape: BoxShape.circle),
                            child: Icon(badge.$1, size: 13, color: badge.$2))),
                  ],
                )),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text.rich(
                      TextSpan(children: [
                        if (hasNamePrefix)
                          TextSpan(
                              text: name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        if (hasNamePrefix)
                          for (final marker in markers)
                            WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: marker),
                        TextSpan(
                            text: hasNamePrefix
                                ? item.description.substring(name.length)
                                : item.description),
                        if (!hasNamePrefix)
                          for (final marker in markers)
                            WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: marker),
                      ]),
                      style: TextStyle(
                          fontSize: CLType.bodySm, color: p.text, height: 1.4)),
                  const SizedBox(height: 4),
                  Text(
                      [
                        if (item.createdAt != null) timeSince(item.createdAt!),
                        if (item.type == 'community_join_request')
                          switch (item.requestStatus) {
                            'pending' => 'Pending',
                            'accepted' => 'Approved',
                            'declined' => 'Declined',
                            'revoked' => 'Cancelled',
                            _ => 'Join request',
                          },
                      ].join(' · '),
                      style: TextStyle(fontSize: CLType.meta, color: p.text3)),
                  if (item.canReview) ...[
                    const SizedBox(height: 8),
                    CLMiniBtn(
                        label: 'Review request',
                        variant: CLBtnVariant.soft,
                        onPressed: onReview),
                  ],
                ])),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: p.text3),
            ],
          ]),
        ),
      ),
    );
  }
}
