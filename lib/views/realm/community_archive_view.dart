import 'package:chatterloop_app/views/realm/realm_review_card.dart';
import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/design/app_dialog.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_item.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'realm_private_state.dart';

class CommunityArchiveView extends StatefulWidget {
  final String realmId;
  final CommunityApi? api;
  const CommunityArchiveView({super.key, required this.realmId, this.api});
  @override
  State<CommunityArchiveView> createState() => _CommunityArchiveViewState();
}

class _CommunityArchiveViewState
    extends RealmPrivateState<CommunityArchiveView> {
  final _posts = <PostPreview>[];
  bool _loading = true, _failed = false, _next = false, _saving = false;
  int _page = 1;
  @override
  void initState() {
    super.initState();
    reloadPrivate();
  }

  @override
  void didUpdateWidget(covariant CommunityArchiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.realmId != widget.realmId) reloadPrivate();
  }

  @override
  void reloadPrivate() {
    _load();
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _failed = false;
      if (page == 1) {
        _saving = false;
        _posts.clear();
      }
    });
    final ticket = await requestTicket();
    try {
      final result = await (widget.api ?? CommunityApi(authToken: ticket.token))
          .archive(widget.realmId, page: page);
      if (!await isCurrent(ticket)) return;
      setState(() {
        appendDistinctPosts(_posts, result.results);
        _next = result.hasNext;
        _page = page;
        _loading = false;
      });
    } catch (error) {
      if (!await isCurrent(ticket)) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      CLAlerts.requestError(error,
          fallback: 'Could not load the community archive.');
    }
  }

  Future<void> _restore(PostPreview post) async {
    if (_saving) return;
    final ticket = await requestTicket(invalidate: false);
    if (!mounted) return;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AppDialog(
                title: 'Restore this post?',
                icon: Icons.restore_outlined,
                description:
                    'The post will return only if approved and not removed.',
                actions: [
                  AppDialogAction(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                  AppDialogAction(
                    label: 'Restore',
                    primary: true,
                    onPressed: () => Navigator.pop(ctx, true),
                  )
                ]));
    if (accepted != true || !await isCurrent(ticket)) return;
    setState(() => _saving = true);
    try {
      await (widget.api ?? CommunityApi(authToken: ticket.token))
          .archivePost(widget.realmId, post.postId, archived: false);
      if (await isCurrent(ticket)) {
        setState(() => _saving = false);
        reloadPrivate();
      }
    } catch (error) {
      if (await isCurrent(ticket)) {
        setState(() => _saving = false);
        CLAlerts.requestError(error, fallback: 'Could not restore this post.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => CLScreen(
      appBar: AppBar(
          leadingWidth: 48,
          titleSpacing: 0,
          title: const Text('Community archive')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final post in _posts)
          RealmReviewCard(
              child: Column(children: [
            PostItem(
                post: post.copyWith(readOnly: true),
                showEngagement: false,
                embedded: true),
            Padding(
                padding: const EdgeInsets.all(12),
                child: RealmReviewActions(children: [
                  CLBtn(
                      label: 'Restore post',
                      onPressed: _saving ? null : () => _restore(post))
                ]))
          ])),
        if (_loading) const PostItemSkeleton(),
        if (_failed) CLBtn(label: 'Retry', onPressed: reloadPrivate),
        if (!_loading && !_failed && _posts.isEmpty)
          const Text('No archived community posts.'),
        if (_next)
          CLBtn(
              label: 'Load more',
              onPressed: _loading ? null : () => _load(page: _page + 1))
      ]));
}
