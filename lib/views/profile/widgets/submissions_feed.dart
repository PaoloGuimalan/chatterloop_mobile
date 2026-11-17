import 'package:chatterloop_app/views/realm/realm_review_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_item.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/models/user_models/realm_approval_model.dart';
import 'package:chatterloop_app/views/realm/realm_private_state.dart';

class SubmissionsFeed extends StatefulWidget {
  final String ownerEntityId;
  final NewsfeedApi? api;
  const SubmissionsFeed({super.key, required this.ownerEntityId, this.api});
  @override
  State<SubmissionsFeed> createState() => SubmissionsFeedState();
}

class SubmissionsFeedState extends RealmPrivateState<SubmissionsFeed> {
  final _items = <CommunitySubmission>[];
  bool _loading = true, _failed = false, _hasNext = false, _saving = false;
  int _page = 1;
  @override
  void initState() {
    super.initState();
    communityChanges.addListener(reloadPrivate);
    communityPostChanges.addListener(reloadPrivate);
    reloadPrivate();
  }

  @override
  void dispose() {
    communityChanges.removeListener(reloadPrivate);
    communityPostChanges.removeListener(reloadPrivate);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SubmissionsFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerEntityId != widget.ownerEntityId) reloadPrivate();
  }

  @override
  void reloadPrivate() {
    reload();
  }

  Future<void> reload() => _load();
  Future<void> loadMore() =>
      _loading || !_hasNext ? Future.value() : _load(page: _page + 1);
  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _failed = false;
      if (page == 1) {
        _saving = false;
        _items.clear();
        _hasNext = false;
      }
    });
    final ticket = await requestTicket();
    if (actingEntityId != widget.ownerEntityId) {
      if (await isCurrent(ticket)) setState(() => _loading = false);
      return;
    }
    try {
      final result = await (widget.api ?? NewsfeedApi(authToken: ticket.token))
          .submissions(page: page);
      if (!await isCurrent(ticket) || actingEntityId != widget.ownerEntityId) {
        return;
      }
      setState(() {
        final ids = _items.map((row) => row.post.postId).toSet();
        _items.addAll(result.results.where((row) => ids.add(row.post.postId)));
        _hasNext = result.hasNext;
        _page = page;
        _loading = false;
      });
    } catch (error) {
      if (!await isCurrent(ticket)) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
      CLAlerts.requestError(error, fallback: 'Could not load submissions.');
    }
  }

  Future<void> _withdraw(CommunitySubmission row) async {
    if (_saving) return;
    final ticket = await requestTicket(invalidate: false);
    if (!mounted) return;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Withdraw this submission?'),
                content: const Text(
                    'This deletes your submission. You can create a new post later.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Withdraw'))
                ]));
    if (accepted != true || !await isCurrent(ticket)) return;
    setState(() => _saving = true);
    try {
      final ok = await (widget.api ?? NewsfeedApi(authToken: ticket.token))
          .deletePostRequest(row.post.postId);
      if (!await isCurrent(ticket)) return;
      if (ok) await reload();
    } finally {
      if (await isCurrent(ticket)) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (actingEntityId != widget.ownerEntityId) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                  'Only you can see your pending and unapproved community posts here.')),
          for (final row in _items)
            RealmReviewCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                row.approval == 0
                                    ? 'Pending approval'
                                    : 'Unapproved',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            if (row.decision?.reason.isNotEmpty == true) ...[
                              const SizedBox(height: 6),
                              Text(row.decision!.reason)
                            ]
                          ])),
                  PostItem(
                      key: ValueKey('${row.post.postId}:${row.contentVersion}'),
                      post: row.post,
                      embedded: true,
                      showEngagement: false),
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: RealmReviewActions(children: [
                        if (row.decision != null && row.approval == 2)
                          TextButton(
                              onPressed: () => context.push(
                                  '/realm-review/${Uri.encodeComponent(row.decision!.id)}'),
                              child: const Text('View decision')),
                        CLBtn(
                            label: 'Withdraw',
                            variant: CLBtnVariant.soft,
                            onPressed: _saving ? null : () => _withdraw(row))
                      ]))
                ])),
          if (_loading) const PostItemSkeleton(),
          if (_failed) CLBtn(label: 'Retry', onPressed: reload),
          if (!_loading && !_failed && _items.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No pending or unapproved submissions.')),
          if (_hasNext)
            CLBtn(label: 'Load more', onPressed: _loading ? null : loadMore),
        ]));
  }
}
