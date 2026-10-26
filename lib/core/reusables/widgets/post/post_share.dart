// Sharing a post onto your own feed.
//
// This is web's share, not the OS share sheet: web's PostItem opens the
// composer with `toShare` set, which creates a NEW post whose single reference
// points at the original. Same thing here, minus the full composer - a caption
// field, destination, identity and tags describe the new post; the original
// remains its referenced content.
//
// The preview at the top is the shared post as it will appear, so what you're
// about to publish is visible before you publish it.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/feed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/link_preview_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_attachments.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_tagging.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'community_destination_picker.dart';
import '../community_identity_toggle.dart';

/// Privacy options, matching the composer's `privacy.status` values on web.
const List<(String, String, IconData)> _kPrivacyOptions = [
  ('public', 'Public', Icons.public),
  ('connections', 'Connections', Icons.group),
  ('private', 'Only me', Icons.lock_outline),
];

/// Opens the share sheet. Resolves true once a share has been created.
Future<bool> showSharePostSheet(
  BuildContext context, {
  required PostPreview post,
}) async {
  final p = cl(context);
  final result = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CLRadii.lg)),
    ),
    builder: (sheetContext) => Padding(
      // Lifts the sheet above the keyboard once you tap into the caption -
      // the field no longer autofocuses, so this only applies after you do.
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: _SharePostSheet(
          post: post, allowCommunity: communityDestinationAllowed(context)),
    ),
  );
  return result == true;
}

class _SharePostSheet extends StatefulWidget {
  final PostPreview post;
  final bool allowCommunity;

  const _SharePostSheet({required this.post, required this.allowCommunity});

  @override
  State<_SharePostSheet> createState() => _SharePostSheetState();
}

class _SharePostSheetState extends State<_SharePostSheet> {
  final TextEditingController _caption = TextEditingController();
  String _privacy = 'public';
  bool _sharing = false;
  List<SearchResultUser> _tagged = const [];
  bool _anonymous = false;
  final _actor = appStore.state.userAuth.user.entityId;
  late Community? _community =
      widget.allowCommunity && widget.post.community?.isPrivate == true
          ? widget.post.community
          : null;

  Future<void> _pickDestination() async {
    if (_sharing) return;
    try {
      final result = await pickCommunityDestination(context,
          taggedEntityIds: _tagged.map((entity) => entity.entityId).toList(),
          privateSource: widget.post.community?.isPrivate == true
              ? widget.post.community
              : null);
      if (!mounted ||
          result == null ||
          _actor != appStore.state.userAuth.user.entityId) {
        return;
      }
      setState(() {
        _community = result.entityId.isEmpty ? null : result;
        _anonymous = false;
      });
    } catch (error) {
      if (mounted) {
        CLAlerts.requestError(error,
            fallback: 'Could not load community destinations.');
      }
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_sharing) return;
    if (_actor != appStore.state.userAuth.user.entityId) {
      CLAlerts.show('Your profile changed. Reopen the share composer.');
      return;
    }
    setState(() => _sharing = true);
    final token = await ApiClient.instance.readToken();
    if (!mounted || _actor != appStore.state.userAuth.user.entityId) return;
    final ok = await NewsfeedApi(authToken: token).sharePostRequest(
      postId: widget.post.postId,
      caption: _caption.text.trim(),
      privacy: _community == null
          ? _privacy
          : _community!.isPrivate
              ? 'private'
              : 'public',
      taggedEntityIds: _tagged.map((entity) => entity.entityId).toList(),
      communityEntityId: _community?.entityId,
      isAnonymous: _community == null ? null : _anonymous,
    );
    if (!mounted || _actor != appStore.state.userAuth.user.entityId) return;

    if (!ok) {
      setState(() => _sharing = false);
      // Already reported by the request (reportedAction).
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    // Outer supplies the system gap, inner the content padding - deliberately
    // not a SafeArea wrapped around content that already pads itself, which
    // stacks the two into a band of empty sheet on any device with a
    // navigation bar.
    return SingleChildScrollView(
        child: Padding(
      padding: EdgeInsets.only(
          bottom: clSheetBottomGap(context, minimum: 16, extra: 8)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: p.border2,
                  borderRadius: BorderRadius.circular(CLRadii.pill),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              "Share post",
              style: TextStyle(
                fontSize: CLType.sectionTitle,
                fontWeight: FontWeight.w700,
                color: p.text,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.post.community?.isPrivate == true &&
                !widget.allowCommunity)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('Open the community to share this private post.',
                    style: TextStyle(fontSize: CLType.bodySm, color: p.text2)),
              ),
            TextField(
              controller: _caption,
              minLines: 2,
              maxLines: 4,
              // Same reason as the composer: the sheet should not arrive with
              // the keyboard already over it, hiding the post you are sharing.
              autofocus: false,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: p.text, fontSize: CLType.title),
              decoration: InputDecoration(
                hintText: "Say something about this…",
                hintStyle: TextStyle(color: p.text3),
                filled: true,
                fillColor: p.input,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CLRadii.md),
                  borderSide: BorderSide(color: p.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CLRadii.md),
                  borderSide: BorderSide(color: p.border),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Outcome preview: this is what the shared post will look like,
            // including nested shared-post recursion (without action rows).
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: _ShareOutcomePreview(
                  source: widget.post,
                  caption: _caption.text.trim(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TagEntityPicker(
              communityEntityId: _community?.entityId,
              selected: _tagged,
              onChanged: (next) => setState(() => _tagged = next),
            ),
            const SizedBox(height: 10),
            if (widget.allowCommunity)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading:
                      Icon(Icons.groups_outlined, color: p.brand, size: 20),
                  title: Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Post in '),
                        TextSpan(
                            text: _community?.name ?? 'Your timeline',
                            style: const TextStyle(fontWeight: FontWeight.w600))
                      ]),
                      style: const TextStyle(fontSize: CLType.label)),
                  trailing: const Icon(Icons.expand_more, size: 18),
                  onTap: _sharing ? null : _pickDestination),
            if (_community != null)
              CommunityIdentityToggle(
                  compact: true,
                  title: 'Post anonymously',
                  subtitle: _anonymous ? 'Anonymous member' : 'My profile',
                  value: _anonymous,
                  onChanged: _sharing
                      ? null
                      : (value) => setState(() => _anonymous = value)),
            if (_community == null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _kPrivacyOptions)
                    CLChip(
                      label: option.$2,
                      icon: option.$3,
                      active: _privacy == option.$1,
                      onTap: () => setState(() => _privacy = option.$1),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            _sharing
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  )
                : CLBtn(
                    label: "Share",
                    iconL: Icons.share_outlined,
                    block: true,
                    size: CLBtnSize.lg,
                    onPressed: widget.post.community?.isPrivate == true &&
                            !widget.allowCommunity
                        ? null
                        : _share,
                  ),
          ],
        ),
      ),
    ));
  }
}

class _ShareOutcomePreview extends StatelessWidget {
  final PostPreview source;
  final String caption;

  const _ShareOutcomePreview({
    required this.source,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(CLRadii.md),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Preview',
            style: TextStyle(
              fontSize: CLType.caption,
              fontWeight: FontWeight.w700,
              color: p.text2,
            ),
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              caption,
              style: TextStyle(
                fontSize: CLType.title,
                height: 1.42,
                color: p.text,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _SharedPostPreviewRecursive(post: source),
        ],
      ),
    );
  }
}

class _SharedPostPreviewRecursive extends StatefulWidget {
  final PostPreview post;
  final int depth;
  final int maxDepth;

  const _SharedPostPreviewRecursive({
    required this.post,
    this.depth = 0,
    this.maxDepth = 6,
  });

  @override
  State<_SharedPostPreviewRecursive> createState() =>
      _SharedPostPreviewRecursiveState();
}

class _SharedPostPreviewRecursiveState
    extends State<_SharedPostPreviewRecursive> {
  Future<PostPreview?>? _sharedFuture;

  @override
  void initState() {
    super.initState();
    _syncSharedFuture();
  }

  @override
  void didUpdateWidget(covariant _SharedPostPreviewRecursive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.postId != widget.post.postId ||
        oldWidget.post.sharedPostId != widget.post.sharedPostId ||
        oldWidget.post.isShared != widget.post.isShared ||
        oldWidget.depth != widget.depth) {
      _syncSharedFuture();
    }
  }

  void _syncSharedFuture() {
    final sharedId = widget.post.sharedPostId;
    if (widget.post.isShared &&
        sharedId != null &&
        sharedId.isNotEmpty &&
        widget.depth < widget.maxDepth) {
      _sharedFuture = FeedApi().getPostPreviewRequest(sharedId);
      return;
    }
    _sharedFuture = null;
  }

  Widget _unavailable(String text) {
    final p = cl(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(CLRadii.md),
        border: Border.all(color: p.border),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: CLType.caption, color: p.text3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final post = widget.post;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(CLRadii.md),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CLAvatar(
                id: post.author.entityId,
                entityId: post.author.presenceEntityId,
                name: post.author.displayName,
                src: post.author.profile,
                kind: post.author.type,
                size: 30,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        post.author.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: CLType.caption,
                          fontWeight: FontWeight.w700,
                          color: p.text,
                        ),
                      ),
                    ),
                    ...clEntityMarkers(context,
                        isVerified: post.author.isVerified),
                  ],
                ),
              ),
              if (post.datePosted != null) ...[
                const SizedBox(width: 8),
                Text(
                  timeSinceShort(post.datePosted!),
                  style: TextStyle(fontSize: CLType.caption, color: p.text3),
                ),
              ],
            ],
          ),
          if (post.community != null) ...[
            const SizedBox(height: 4),
            Text.rich(TextSpan(
                children: postDestinationSpans(context, post,
                    baseStyle:
                        TextStyle(fontSize: CLType.caption, color: p.text2),
                    linkColor: p.text))),
          ],
          if (post.caption.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              post.caption,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: CLType.title,
                height: 1.42,
                color: p.text,
              ),
            ),
          ],
          if (post.linkPreview != null) ...[
            const SizedBox(height: 10),
            LinkPreviewCard(preview: post.linkPreview),
          ],
          if (displayableReferences(post.references).isNotEmpty) ...[
            const SizedBox(height: 10),
            // A preview of what you're about to publish - it doesn't need a
            // decoder running behind the share sheet.
            PostAttachments(references: post.references, playInline: false),
          ],
          if (post.isShared) ...[
            const SizedBox(height: 10),
            Builder(
              builder: (_) {
                if (widget.depth >= widget.maxDepth) {
                  return _unavailable('Nested shared post limit reached.');
                }
                final future = _sharedFuture;
                if (future == null) {
                  return _unavailable('Original shared post is unavailable.');
                }
                return FutureBuilder<PostPreview?>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return _unavailable('Loading shared post...');
                    }
                    final nested = snapshot.data;
                    if (nested == null) {
                      return _unavailable(
                          'Original shared post is unavailable.');
                    }
                    return _SharedPostPreviewRecursive(
                      post: nested,
                      depth: widget.depth + 1,
                      maxDepth: widget.maxDepth,
                    );
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
