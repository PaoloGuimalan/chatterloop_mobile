// Sharing a post onto your own feed.
//
// This is web's share, not the OS share sheet: web's PostItem opens the
// composer with `toShare` set, which creates a NEW post whose single reference
// points at the original. Same thing here, minus the full composer - a caption
// field and a privacy choice is everything the share path actually uses (no
// media, no tagging: a share carries the original as its content).
//
// The preview at the top is the shared post as it will appear, so what you're
// about to publish is visible before you publish it.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';

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
    isScrollControlled: true,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CLRadii.lg)),
    ),
    builder: (sheetContext) => Padding(
      // Lifts the sheet above the keyboard - without this the caption field is
      // covered the moment it's focused.
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: _SharePostSheet(post: post),
    ),
  );
  return result == true;
}

class _SharePostSheet extends StatefulWidget {
  final PostPreview post;

  const _SharePostSheet({required this.post});

  @override
  State<_SharePostSheet> createState() => _SharePostSheetState();
}

class _SharePostSheetState extends State<_SharePostSheet> {
  final TextEditingController _caption = TextEditingController();
  String _privacy = 'public';
  bool _sharing = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    final ok = await NewsfeedApi().sharePostRequest(
      postId: widget.post.postId,
      caption: _caption.text.trim(),
      privacy: _privacy,
    );
    if (!mounted) return;

    if (!ok) {
      setState(() => _sharing = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't share that post. Try again."),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final author = widget.post.author;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
            TextField(
              controller: _caption,
              minLines: 2,
              maxLines: 4,
              autofocus: true,
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
            // The post being shared, in miniature.
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(CLRadii.md),
                border: Border.all(color: p.border),
              ),
              child: Row(
                children: [
                  CLAvatar(
                    id: author.entityId,
                    name: author.displayName,
                    src: author.profile,
                    size: 32,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          author.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: CLType.caption,
                            fontWeight: FontWeight.w700,
                            color: p.text,
                          ),
                        ),
                        Text(
                          widget.post.caption.isEmpty
                              ? "Shared post"
                              : widget.post.caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: CLType.caption, color: p.text2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final option in _kPrivacyOptions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: CLChip(
                      label: option.$2,
                      icon: option.$3,
                      active: _privacy == option.$1,
                      onTap: () => setState(() => _privacy = option.$1),
                    ),
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
                    onPressed: _share,
                  ),
          ],
        ),
      ),
    );
  }
}
