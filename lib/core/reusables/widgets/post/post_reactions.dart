// Reaction palette, tally row, and the local tally arithmetic they share.
//
// Posts and comments react identically - same verbs, same palette, same
// optimistic update - so everything here takes plain values rather than a post
// or a comment, and both callers (and the newsfeed later) reuse it.
//
// One deliberate difference from web: webapp's picker plays a Lottie animation
// per emoji (DotLottieReact + a cached LottieJSONRequest). This renders the
// emoji GLYPH instead. The app has no Lottie dependency, and adding one to
// animate a picker that's on screen for a second - then caching JSON per emoji
// on a phone - is a poor trade. `animated_preview` is still parsed on the
// model, so this can be upgraded without touching the API layer.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/models/post_models/newsfeed_models.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';

/// Applies a reaction change to a tally list WITHOUT refetching.
///
/// The server is authoritative and gets asked afterwards, but a reaction has
/// to look instant - so the counts move here first and are reconciled later.
/// Removing the last of an emoji drops its entry entirely, which is what keeps
/// a "0" from lingering in the row.
///
/// Everything here is keyed by EMOJI ID, not by the glyph. `preview[].emoji`
/// is a ForeignKey, so DRF serializes it as the emoji's primary key - a uuid -
/// and `entity_reaction` is that same id. The glyph only appears at render
/// time, via [ReactionPalette.glyphFor].
List<PostReactionCount> applyReactionLocally({
  required List<PostReactionCount> current,
  required String? previousEmojiId,
  required String? nextEmojiId,
}) {
  final counts = <String, int>{
    for (final reaction in current) reaction.emoji: reaction.count,
  };

  if (previousEmojiId != null && previousEmojiId.isNotEmpty) {
    final remaining = (counts[previousEmojiId] ?? 1) - 1;
    if (remaining > 0) {
      counts[previousEmojiId] = remaining;
    } else {
      counts.remove(previousEmojiId);
    }
  }
  if (nextEmojiId != null && nextEmojiId.isNotEmpty) {
    counts[nextEmojiId] = (counts[nextEmojiId] ?? 0) + 1;
  }

  // Biggest tally first, matching how the row reads on web.
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries
      .map((entry) => PostReactionCount(emoji: entry.key, count: entry.value))
      .toList();
}

/// The palette, fetched once per app run.
///
/// Static rather than per-widget: every post and every comment opens the same
/// picker, and re-requesting the emoji list for each one would be a request
/// per tap in a feed.
class ReactionPalette {
  ReactionPalette._();

  static List<Emoji>? _cached;
  static Future<List<Emoji>>? _inFlight;

  static Future<List<Emoji>> load() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    // Share one request between simultaneous callers rather than firing several
    // - a feed can easily open two pickers before the first response lands.
    return _inFlight ??= NewsfeedApi().getEmojisRequest().then((emojis) {
      if (emojis.isNotEmpty) _cached = emojis;
      _inFlight = null;
      return emojis;
    });
  }

  /// Preloads the palette without a request. For tests, and for any future
  /// warm-start path that already has the emoji list to hand.
  @visibleForTesting
  static void seed(List<Emoji> emojis) {
    _cached = emojis;
    _inFlight = null;
  }

  /// The glyph for an emoji id, for rendering "your reaction" without another
  /// lookup at the call site. Null until [load] has completed once.
  static String? glyphFor(String? emojiId) {
    if (emojiId == null || emojiId.isEmpty) return null;
    for (final emoji in _cached ?? const <Emoji>[]) {
      if (emoji.emojiId == emojiId) return emoji.content;
    }
    return null;
  }
}

/// Horizontal strip of emoji buttons, shown in a bottom sheet.
///
/// Returns the tapped emoji id via [onSelected]; the caller decides what verb
/// that becomes (see [reactionMethodFor]) and owns the optimistic update.
class ReactionPicker extends StatelessWidget {
  final String? currentEmojiId;
  final ValueChanged<Emoji> onSelected;

  const ReactionPicker({
    super.key,
    required this.currentEmojiId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return FutureBuilder<List<Emoji>>(
      future: ReactionPalette.load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 76,
            child: Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }
        final emojis = snapshot.data ?? const <Emoji>[];
        if (emojis.isEmpty) {
          return SizedBox(
            height: 76,
            child: Center(
              child: Text("Reactions are unavailable right now",
                  style: TextStyle(fontSize: CLType.caption, color: p.text3)),
            ),
          );
        }
        return SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            itemCount: emojis.length,
            separatorBuilder: (_, __) => const SizedBox(width: 2),
            itemBuilder: (context, index) {
              final emoji = emojis[index];
              final selected = emoji.emojiId == currentEmojiId;
              return InkWell(
                onTap: () => onSelected(emoji),
                borderRadius: BorderRadius.circular(CLRadii.pill),
                child: Container(
                  width: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // The one already chosen is tinted, so tapping it again to
                    // remove it doesn't feel like a blind guess.
                    color: selected ? p.brandSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(CLRadii.md),
                  ),
                  child:
                      Text(emoji.content, style: const TextStyle(fontSize: 20)),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Opens the palette and reports the choice. Null when dismissed.
Future<Emoji?> showReactionPicker(
  BuildContext context, {
  required String? currentEmojiId,
}) {
  final p = cl(context);
  return showModalBottomSheet<Emoji>(
    context: context,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CLRadii.lg)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ReactionPicker(
        currentEmojiId: currentEmojiId,
        onSelected: (emoji) => Navigator.of(sheetContext).pop(emoji),
      ),
    ),
  );
}

/// The tally row - "👍❤️😂 12". Renders nothing when there are no reactions,
/// so a fresh post has no empty furniture under it.
///
/// A tally's `emoji` is an emoji ID, so this resolves each one to its glyph
/// through the palette - and waits for the palette rather than rendering the
/// raw ids, which is a row of uuids.
class ReactionSummary extends StatelessWidget {
  final List<PostReactionCount> reactions;
  final VoidCallback? onTap;

  const ReactionSummary({super.key, required this.reactions, this.onTap});

  @override
  Widget build(BuildContext context) {
    // count > 0 only: the server keeps a tally row at zero once an emoji has
    // ever been used on the post, and web filters the same way.
    final live = reactions.where((reaction) => reaction.count > 0).toList();
    if (live.isEmpty) return const SizedBox.shrink();

    final p = cl(context);
    final total = live.fold<int>(0, (sum, reaction) => sum + reaction.count);

    return FutureBuilder<List<Emoji>>(
      future: ReactionPalette.load(),
      builder: (context, snapshot) {
        final glyphs = <String>[];
        for (final reaction in live.take(3)) {
          final glyph = ReactionPalette.glyphFor(reaction.emoji);
          if (glyph != null) glyphs.add(glyph);
        }
        // Until the palette lands there is no glyph to show - the count alone
        // is right, where the ids would just be noise.
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CLRadii.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final glyph in glyphs)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Text(glyph, style: const TextStyle(fontSize: 15)),
                  ),
                if (glyphs.isNotEmpty) const SizedBox(width: 4),
                Text("$total",
                    style: TextStyle(fontSize: CLType.caption, color: p.text3)),
              ],
            ),
          ),
        );
      },
    );
  }
}
