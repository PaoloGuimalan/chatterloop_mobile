// "is with A, B and C" - the tagged-entity summary in a post header, and the
// picker that puts them there.
//
// Flutter counterpart of webapp's TaggingSummary, with the same rules: at most
// three named, the rest collapsed into "and N others" so a heavily-tagged post
// can't blow out the header. Tagged entities are users AND pages, so both the
// summary and the picker treat them identically - which is also why the payload
// key is a plain list of ENTITY ids.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/search_api.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// How many tagged entities are named before the rest collapse.
const int _kMaxNamedTags = 3;

/// Inline spans for "is with A, B and C", to be appended after the author's
/// name in the header's Text.rich.
///
/// Spans rather than widgets so the whole header wraps as ONE sentence - a Row
/// of chips would break mid-phrase and can't share a line with the name.
List<InlineSpan> taggingSummarySpans(
  BuildContext context,
  List<PostPreviewAuthor> tagged, {
  required TextStyle baseStyle,
  required Color linkColor,
}) {
  if (tagged.isEmpty) return const [];

  final named = tagged.take(_kMaxNamedTags).toList();
  final remaining = tagged.length - named.length;
  final spans = <InlineSpan>[TextSpan(text: " is with ", style: baseStyle)];

  for (var i = 0; i < named.length; i++) {
    if (i > 0) {
      // "A, B and C" - the last separator is "and" only when nothing is being
      // collapsed after it, otherwise it reads "A, B and 2 others".
      final isLastNamed = i == named.length - 1 && remaining == 0;
      spans.add(TextSpan(text: isLastNamed ? " and " : ", ", style: baseStyle));
    }
    final entity = named[i];
    spans.add(TextSpan(
      text: entity.displayName,
      style: baseStyle.copyWith(
          fontWeight: FontWeight.w700, color: linkColor),
      recognizer: TapGestureRecognizer()
        ..onTap = () {
          if (entity.handle.isEmpty) return;
          context.push(entity.isRealm
              ? '/realm/${entity.handle}'
              : '/user/${entity.handle}');
        },
    ));
    if (entity.isVerified) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Icon(Icons.verified, size: 13, color: linkColor),
        ),
      ));
    }
  }

  if (remaining > 0) {
    spans.add(TextSpan(
      text: " and $remaining other${remaining > 1 ? 's' : ''}",
      style: baseStyle,
    ));
  }
  return spans;
}

/// Entity picker for the share composer: search, tap to select, chips to
/// remove. Selection is reported as ENTITY ids, which is what `tagging.users`
/// takes.
class TagEntityPicker extends StatefulWidget {
  final List<SearchResultUser> selected;
  final ValueChanged<List<SearchResultUser>> onChanged;

  const TagEntityPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<TagEntityPicker> createState() => _TagEntityPickerState();
}

class _TagEntityPickerState extends State<TagEntityPicker> {
  final TextEditingController _controller = TextEditingController();
  List<SearchResultUser> _results = const [];
  bool _searching = false;
  bool _open = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    // The flat entity search - people AND pages in one list, which is exactly
    // what can be tagged. realmTypes stays at its "page" default: a server or
    // a group chat is not a taggable subject.
    final found = await SearchApi().searchEntitiesRequest(query.trim());
    if (!mounted || _controller.text.trim() != query.trim()) return;
    setState(() {
      _results = found;
      _searching = false;
    });
  }

  void _toggle(SearchResultUser entity) {
    final next = [...widget.selected];
    final index = next.indexWhere((e) => e.entityId == entity.entityId);
    if (index >= 0) {
      next.removeAt(index);
    } else {
      next.add(entity);
    }
    widget.onChanged(next);
    setState(() {
      _controller.clear();
      _results = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(CLRadii.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.person_add_alt, size: 17, color: p.brand),
                const SizedBox(width: 6),
                Text(
                  widget.selected.isEmpty
                      ? "Tag people or pages"
                      : "Tagged ${widget.selected.length}",
                  style: TextStyle(
                    fontSize: CLType.label,
                    fontWeight: FontWeight.w600,
                    color: p.brand,
                  ),
                ),
                const Spacer(),
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: p.text3),
              ],
            ),
          ),
        ),
        if (widget.selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entity in widget.selected)
                  InkWell(
                    onTap: () => _toggle(entity),
                    borderRadius: BorderRadius.circular(CLRadii.pill),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: p.brandSoft,
                        borderRadius: BorderRadius.circular(CLRadii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entity.displayName.isEmpty
                                ? entity.username
                                : entity.displayName,
                            style: TextStyle(
                                fontSize: CLType.caption,
                                fontWeight: FontWeight.w600,
                                color: p.brand),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.close, size: 13, color: p.brand),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (_open) ...[
          const SizedBox(height: 8),
          CLField(
            icon: Icons.search,
            placeholder: "Search people and pages",
            controller: _controller,
            onChanged: _search,
          ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else if (_results.isNotEmpty)
            ConstrainedBox(
              // Capped: the sheet already holds a caption, a preview and the
              // privacy row, so results scroll rather than push those away.
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final entity = _results[index];
                  final picked = widget.selected
                      .any((e) => e.entityId == entity.entityId);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CLAvatar(
                      id: entity.entityId,
                      name: entity.displayName,
                      src: entity.profile,
                      size: 30,
                    ),
                    title: Text(
                      entity.displayName.isEmpty
                          ? entity.username
                          : entity.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: CLType.bodySm, color: p.text),
                    ),
                    subtitle: Text("@${entity.username}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: CLType.caption, color: p.text3)),
                    trailing: Icon(
                      picked ? Icons.check_circle : Icons.add_circle_outline,
                      size: 20,
                      color: picked ? p.brand : p.text3,
                    ),
                    onTap: () => _toggle(entity),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }
}
