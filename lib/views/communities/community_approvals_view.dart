import 'package:chatterloop_app/views/realm/realm_review_card.dart';
import 'package:chatterloop_app/views/realm/realm_text_dialog.dart';
import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_item.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/models/user_models/realm_approval_model.dart';
import 'package:chatterloop_app/models/user_models/realm_invite_model.dart';
import 'package:chatterloop_app/views/realm/realm_private_state.dart';

class CommunityApprovalsView extends StatefulWidget {
  final String realmId;
  final CommunityApi? api;
  final ApprovalKind? initialKind;
  final String? targetId;
  const CommunityApprovalsView(
      {super.key,
      required this.realmId,
      this.api,
      this.initialKind,
      this.targetId});
  @override
  State<CommunityApprovalsView> createState() => _CommunityApprovalsViewState();
}

class _CommunityApprovalsViewState
    extends RealmPrivateState<CommunityApprovalsView> {
  Community? _community;
  CommunityApprovalsPage? _page;
  ApprovalKind? _kind;
  String _state = 'pending';
  bool _loading = true,
      _saving = false,
      _failed = false,
      _targetCleared = false;
  int _pageNumber = 1;
  @override
  void initState() {
    super.initState();
    communityChanges.addListener(reloadPrivate);
    communityPostChanges.addListener(_changed);
    reloadPrivate();
  }

  @override
  void dispose() {
    communityChanges.removeListener(reloadPrivate);
    communityPostChanges.removeListener(_changed);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CommunityApprovalsView old) {
    super.didUpdateWidget(old);
    if (old.realmId != widget.realmId ||
        old.targetId != widget.targetId ||
        old.initialKind != widget.initialKind) {
      _kind = null;
      _targetCleared = false;
      reloadPrivate();
    }
  }

  void _changed() {
    if (communityPostChanges.value?.realmId == widget.realmId) reloadPrivate();
  }

  List<ApprovalKind> get _kinds {
    final c = _community?.capabilities;
    return [
      if (c?.allows('can_review_posts') == true) ApprovalKind.posts,
      if (c?.allows('can_review_invites') == true) ApprovalKind.invites,
      if (c?.allows('can_review_join_requests') == true ||
          c?.allows('can_decline_join_requests') == true)
        ApprovalKind.joins
    ];
  }

  @override
  void reloadPrivate() {
    _load();
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _failed = false;
      _saving = false;
      if (page == 1) {
        _page = null;
        _community = null;
      }
    });
    final ticket = await requestTicket();
    try {
      final api = widget.api ?? CommunityApi(authToken: ticket.token);
      final community = await api.detail(widget.realmId);
      if (!await isCurrent(ticket)) return;
      _community = community;
      final kinds = _kinds;
      final kind = kinds.contains(_kind)
          ? _kind
          : kinds.contains(widget.initialKind)
              ? widget.initialKind
              : kinds.firstOrNull;
      if (kind == null) {
        setState(() {
          _loading = false;
          _kind = null;
        });
        return;
      }
      _kind = kind;
      final result = await api.approvals(widget.realmId,
          kind: kind,
          state: _state,
          page: page,
          targetId: _targetCleared ? null : widget.targetId);
      if (!await isCurrent(ticket)) return;
      setState(() {
        if (page > 1 && _page != null) {
          result.posts.insertAll(0, _page!.posts);
          result.invitations.insertAll(0, _page!.invitations);
        }
        _page = result;
        _loading = false;
        _pageNumber = page;
      });
    } catch (error) {
      if (!await isCurrent(ticket)) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      CLAlerts.requestError(error, fallback: 'Could not load approvals.');
    }
  }

  Future<void> _decide(
      {CommunitySubmission? submission,
      RealmInvite? invite,
      required String action}) async {
    if (_saving || (submission != null && _selfReviewRestricted(submission))) {
      return;
    }
    final ticket = await requestTicket(invalidate: false);
    final kind = _kind!;
    if (!mounted) return;
    String comment = '';
    if (submission != null && action == 'reject') {
      final value = await showDialog<String>(
          context: context,
          builder: (_) => const RealmTextDialog(
              title: 'Reject this post?',
              label: 'Reason for the author',
              confirmLabel: 'Confirm'));
      if (value == null) return;
      comment = value;
    } else {
      final accepted = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: Text(action == 'approve'
                      ? 'Approve this submission?'
                      : 'Decline this submission?'),
                  content: Text(invite != null && kind == ApprovalKind.invites
                      ? 'Approving allows the invitation to be sent. The recipient still chooses whether to join.'
                      : 'Confirm this decision.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Confirm'))
                  ]));
      if (accepted != true) return;
    }
    if (!await isCurrent(ticket)) return;
    setState(() => _saving = true);
    try {
      final api = widget.api ?? CommunityApi(authToken: ticket.token);
      if (submission != null) {
        await api.reviewPost(widget.realmId, submission.post.postId,
            action: action,
            expectedApproval: submission.approval,
            expectedVersion: submission.contentVersion,
            reason: comment);
      } else {
        await api.reviewInvitation(widget.realmId, invite!.id,
            kind: kind, action: action, expectedStatus: invite.status);
      }
      if (!await isCurrent(ticket)) return;
      setState(() => _saving = false);
      reloadPrivate();
    } catch (error) {
      if (!await isCurrent(ticket)) return;
      setState(() => _saving = false);
      CLAlerts.requestError(error,
          fallback:
              'This submission may have changed. Refresh before reviewing.');
      reloadPrivate();
    }
  }

  bool _selfReviewRestricted(CommunitySubmission submission) =>
      submission.post.isOwnedBy(actingEntityId) &&
      _community?.capabilities.allows('can_publish_posts') != true;

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final kinds = _kinds;
    return CLScreen(
        appBar: AppBar(
            leadingWidth: 48, titleSpacing: 0, title: const Text('Approvals')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (kinds.isNotEmpty)
            RealmReviewTabs<ApprovalKind>(
                value: _kind,
                tabs: [
                  for (final kind in kinds)
                    (
                      value: kind,
                      label:
                          '${kind == ApprovalKind.posts ? 'Posts' : kind == ApprovalKind.invites ? 'Invitations' : 'Join requests'}${_page?.counts[kind.name] != null ? ' (${_page!.counts[kind.name]})' : ''}'
                    )
                ],
                onChanged: _saving
                    ? null
                    : (kind) {
                        setState(() {
                          _kind = kind;
                          _state = 'pending';
                        });
                        reloadPrivate();
                      }),
          const SizedBox(height: 12),
          if (_kind == ApprovalKind.posts)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: RealmReviewTabs<String>(
                    value: _state,
                    tabs: const [
                      (value: 'pending', label: 'Pending'),
                      (value: 'not_approved', label: 'Not approved')
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            setState(() => _state = value);
                            reloadPrivate();
                          })),
          if (widget.targetId != null && !_targetCleared)
            TextButton(
                onPressed: () {
                  setState(() => _targetCleared = true);
                  reloadPrivate();
                },
                child: const Text('Show all submissions')),
          if (_loading && _page == null) const PostItemSkeleton(),
          if (_failed) CLBtn(label: 'Retry', onPressed: reloadPrivate),
          if (!_loading &&
              !_failed &&
              (_kind == null ||
                  (_page?.posts.isEmpty != false &&
                      _page?.invitations.isEmpty != false)))
            const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No submissions to review.')),
          for (final row in _page?.posts ?? <CommunitySubmission>[])
            RealmReviewCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  PostItem(
                      key: ValueKey(
                          '${row.post.postId}:${row.contentVersion}:${row.approval}'),
                      post: row.post,
                      embedded: true,
                      showEngagement: false),
                  if (row.decision?.reason.isNotEmpty == true)
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(row.decision!.reason)),
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: RealmReviewActions(children: [
                        CLBtn(
                            label: 'Approve',
                            onPressed: _saving || _selfReviewRestricted(row)
                                ? null
                                : () => _decide(
                                    submission: row, action: 'approve')),
                        if (row.approval == 0)
                          CLBtn(
                              label: 'Reject',
                              variant: CLBtnVariant.soft,
                              onPressed: _saving || _selfReviewRestricted(row)
                                  ? null
                                  : () => _decide(
                                      submission: row, action: 'reject'))
                      ]))
                ])),
          for (final invite in _page?.invitations ?? <RealmInvite>[])
            RealmReviewCard(
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              invite.targetEntity?.name ??
                                  invite.targetEmail ??
                                  'Invitation',
                              style: TextStyle(
                                  color: p.text, fontWeight: FontWeight.w700)),
                          if (_kind == ApprovalKind.joins)
                            const Text('Wants to join the community')
                          else if (invite.inviter != null)
                            Text('Invited by ${invite.inviter!.name}'),
                          const SizedBox(height: 10),
                          RealmReviewActions(children: [
                            if (_kind != ApprovalKind.joins ||
                                _community!.capabilities
                                    .allows('can_review_join_requests'))
                              CLBtn(
                                  label: 'Approve',
                                  onPressed: _saving
                                      ? null
                                      : () => _decide(
                                          invite: invite, action: 'approve')),
                            if (_kind != ApprovalKind.joins ||
                                _community!.capabilities
                                    .allows('can_decline_join_requests'))
                              CLBtn(
                                  label: 'Decline',
                                  variant: CLBtnVariant.soft,
                                  onPressed: _saving
                                      ? null
                                      : () => _decide(
                                          invite: invite, action: 'reject'))
                          ])
                        ]))),
          if (_page?.hasNext == true)
            CLBtn(
                label: 'Load more',
                onPressed: _loading || _saving
                    ? null
                    : () => _load(page: _pageNumber + 1)),
        ]));
  }
}
