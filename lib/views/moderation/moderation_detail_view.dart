// "Your content was removed. Here is why."
//
// The one screen that renders soft-deleted content, and only to the person it
// belonged to (or platform staff). Everything about it is shaped by that: it
// opens from a notification, it shows the content as it was, and it shows the
// machine's reasoning in enough detail to be argued with.
//
// A 404 from the endpoint means EITHER no such record OR no permission - the
// server does not distinguish, so a stranger cannot learn that somebody's
// content was removed. This screen must not distinguish either, which is why
// there is one "not available" state rather than separate missing/forbidden
// ones.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/interests_api.dart';
import 'package:chatterloop_app/models/user_models/moderation_detail_model.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_attachments.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';

class ModerationDetailScreen extends StatefulWidget {
  final String moderationId;

  const ModerationDetailScreen({super.key, required this.moderationId});

  @override
  State<ModerationDetailScreen> createState() => _ModerationDetailScreenState();
}

class _ModerationDetailScreenState extends State<ModerationDetailScreen> {
  final _api = InterestsApi();

  ModerationDetail? _detail;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final detail = await _api.moderationDetail(widget.moderationId);
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final detail = _detail;

    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text("Content review")),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            CLSpacing.contentGutter,
            14,
            CLSpacing.contentGutter,
            24,
          ),
          children: [
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (detail == null)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: CLEmptyState(
                  icon: Icons.help_outline,
                  iconBg: p.surface2,
                  iconColor: p.text2,
                  iconBorderColor: p.border,
                  title: "This review isn't available",
                  subtitle:
                      "It may have been removed, or it isn't yours to view.",
                ),
              )
            else ...[
              _VerdictCard(detail: detail),
              const SizedBox(height: 10),
              _ContentCard(detail: detail),
            ],
          ],
        ),
      ),
    );
  }
}

/// The answer first. Somebody arriving from a notification wants to know what
/// happened; the content below is for checking that against.
class _VerdictCard extends StatelessWidget {
  final ModerationDetail detail;

  const _VerdictCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final moderation = detail.moderation;
    final type = detail.content.type;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.pinkSoft,
              borderRadius: BorderRadius.circular(CLRadii.sm),
            ),
            child: Icon(Icons.gavel, size: 20, color: p.pink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  moderation.removed
                      ? "This $type was removed"
                      : "This $type was reviewed",
                  style: TextStyle(
                    color: p.text,
                    fontSize: CLType.sectionTitle,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail.viewerIsOwner
                      ? "Our automated review found it likely breaks the "
                          "community guidelines."
                      : "Shown to you as a platform moderator.",
                  style: TextStyle(
                    color: p.text2,
                    fontSize: CLType.bodySm,
                    height: 1.45,
                  ),
                ),
                if (moderation.categories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final category in moderation.categories)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: p.pinkSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          // The score is shown, not hidden. "We think this is
                          // nudity, 0.81" is arguable in a way "this broke the
                          // rules" is not - and arguing with it is the point of
                          // showing somebody their own removal.
                          child: Text(
                            "${category.readable} · "
                            "${category.score.toStringAsFixed(2)}",
                            style: TextStyle(
                              color: p.pink,
                              fontSize: CLType.meta,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (moderation.unevaluated.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    // A category nobody checked is not a category that came
                    // back clean. Said plainly, so this screen cannot be read
                    // as a clean bill of health on everything it omits.
                    "Not checked: "
                    "${moderation.unevaluated.map(_readable).join(', ')}",
                    style: TextStyle(color: p.text3, fontSize: CLType.meta),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _readable(String code) {
    final spaced = code.replaceAll('_', ' ');
    if (spaced.isEmpty) return spaced;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}

/// Rings the ONE attachment the record is about, and labels it.
///
/// A wrapper rather than a flag on PostAttachments: that widget is shared with
/// the feed, the post screen and profiles, and a review-only highlight has no
/// business inside it.
class _FlaggedFrame extends StatelessWidget {
  final Widget child;

  const _FlaggedFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: p.pink, width: 2),
            borderRadius: BorderRadius.circular(CLRadii.md),
          ),
          padding: const EdgeInsets.all(2),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: p.pink,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              "Flagged",
              style: TextStyle(
                color: Colors.white,
                fontSize: CLType.meta,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The content as it was - the part no other screen will show once it is gone.
class _ContentCard extends StatelessWidget {
  final ModerationDetail detail;

  const _ContentCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final content = detail.content;
    final reviewed = detail.moderation.reviewedText;

    // Only images and video can be shown; PostAttachments filters to those
    // itself, and doing it here too keeps the "is there anything to draw"
    // check honest.
    final showable = displayableReferences(content.references);
    final flaggedId = content.flaggedReferenceId;
    final flagged = flaggedId == null
        ? const <PostReference>[]
        : showable.where((r) => r.referenceId == flaggedId).toList();
    final rest = showable.where((r) => !flagged.contains(r)).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (content.authorName != null) ...[
            Row(
              children: [
                CLAvatar(
                  name: content.authorName,
                  src: content.authorPicture,
                  size: 32,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        content.authorName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.text,
                          fontSize: CLType.bodySm,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (content.authorHandle != null)
                        Text(
                          "@${content.authorHandle}",
                          style:
                              TextStyle(color: p.text3, fontSize: CLType.meta),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Text(
            "YOUR ${content.type.toUpperCase()}",
            style: TextStyle(
              color: p.text3,
              fontSize: CLType.meta,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            (content.body ?? "").trim().isEmpty ? "No text." : content.body!,
            style: TextStyle(
              color: (content.body ?? "").trim().isEmpty ? p.text3 : p.text,
              fontSize: CLType.title,
              height: 1.45,
            ),
          ),
          // The MEDIA, rendered - not counted. Moderation acts on images and
          // video as much as on text, so a review that says "1 attachment"
          // shows the author nothing about what was judged.
          //
          // Rendered through the app's own PostAttachments rather than a second
          // media renderer, so a removed photo looks like the photo it was.
          // Split in two so the flagged one can be ringed without modifying
          // that shared widget: the flagged reference is passed on its own,
          // the rest follow underneath.
          if (flagged.isNotEmpty) ...[
            const SizedBox(height: 12),
            _FlaggedFrame(
              child: PostAttachments(references: flagged, playInline: true),
            ),
          ],
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (flagged.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  "Also in this ${content.type}",
                  style: TextStyle(color: p.text3, fontSize: CLType.meta),
                ),
              ),
            PostAttachments(references: rest, playInline: false),
          ],
          if (reviewed != null &&
              reviewed.trim().isNotEmpty &&
              reviewed != content.body) ...[
            const SizedBox(height: 14),
            Divider(color: p.border, height: 1),
            const SizedBox(height: 12),
            Text(
              // For an image or a video this is the ONLY human-readable
              // account of what the model actually judged.
              "What the review read",
              style: TextStyle(color: p.text3, fontSize: CLType.meta),
            ),
            const SizedBox(height: 4),
            Text(
              reviewed,
              style: TextStyle(
                color: p.text2,
                fontSize: CLType.bodySm,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
