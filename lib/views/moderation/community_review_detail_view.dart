import 'package:chatterloop_app/views/realm/realm_review_card.dart';
import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_item.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/models/user_models/realm_approval_model.dart';
import 'package:chatterloop_app/views/realm/realm_private_state.dart';

class CommunityReviewDetailView extends StatefulWidget {
  final String decisionId;
  final NewsfeedApi? api;
  const CommunityReviewDetailView(
      {super.key, required this.decisionId, this.api});
  @override
  State<CommunityReviewDetailView> createState() =>
      _CommunityReviewDetailViewState();
}

class _CommunityReviewDetailViewState
    extends RealmPrivateState<CommunityReviewDetailView> {
  RealmReviewDetail? _detail;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    reloadPrivate();
  }

  @override
  void didUpdateWidget(covariant CommunityReviewDetailView old) {
    super.didUpdateWidget(old);
    if (old.decisionId != widget.decisionId) reloadPrivate();
  }

  @override
  void reloadPrivate() {
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _detail = null;
      _loading = true;
    });
    final ticket = await requestTicket();
    try {
      final result = await (widget.api ?? NewsfeedApi(authToken: ticket.token))
          .reviewDecision(widget.decisionId);
      if (await isCurrent(ticket)) {
        setState(() {
          _detail = result;
          _loading = false;
        });
      }
    } catch (error) {
      if (await isCurrent(ticket)) {
        setState(() => _loading = false);
        CLAlerts.requestError(error,
            fallback: 'This community decision is unavailable.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final palette = cl(context);
    final localizations = MaterialLocalizations.of(context);
    final decidedAt = detail?.decision.createdAt?.toLocal();
    return CLScreen(
        appBar: AppBar(
            leadingWidth: 48,
            titleSpacing: 0,
            title: const Text('Community decision')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (_loading)
            const PostItemSkeleton()
          else if (detail == null) ...[
            const Text('This decision is unavailable.'),
            CLBtn(label: 'Retry', onPressed: reloadPrivate)
          ] else ...[
            RealmReviewCard(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              detail.decision.action == 'takedown'
                                  ? 'Post taken down'
                                  : detail.decision.action == 'reject'
                                      ? 'Post not approved'
                                      : 'Post approved',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          Text(detail.decision.reason.isEmpty
                              ? 'No explanation was provided.'
                              : detail.decision.reason),
                          if (decidedAt != null) ...[
                            const SizedBox(height: 8),
                            Text(
                                '${localizations.formatShortDate(decidedAt)} · ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(decidedAt))}',
                                style: TextStyle(
                                    fontSize: CLType.meta,
                                    color: palette.text2))
                          ]
                        ]))),
            if (detail.content != null) ...[
              if (!detail.matchesReviewedVersion)
                const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                        'This is the current retained content; it may differ from what was reviewed.')),
              RealmReviewCard(
                  child: PostItem(
                      post: detail.content!.copyWith(readOnly: true),
                      embedded: true,
                      showEngagement: false))
            ] else
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('The post is no longer available.')),
          ]
        ]));
  }
}
