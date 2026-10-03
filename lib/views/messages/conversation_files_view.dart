// A conversation's shared files - the mobile counterpart of webapp's
// ConversationFilesPanel (inside ConversationInfoModal).
//
// Two pieces, the way phone messengers lay it out:
//
//   - [ConversationMediaPreview]: a "Shared media" section on the info screen,
//     the latest few photos and videos with a See all.
//   - [ConversationFilesScreen]: what See all opens - Photos / Videos / Audio /
//     Files tabs, each paged from /m/conversationfiles as it scrolls.
//
// Neither is fetched until it is on screen. That list used to ride along,
// whole, on every /conversationinfo call, which every conversation open makes.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/reusables/players/voice_message_player.dart';
import 'package:chatterloop_app/core/reusables/widgets/media_viewer.dart';
import 'package:chatterloop_app/core/reusables/widgets/paginated_scroll.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/core/utils/media_downloader.dart';
import 'package:chatterloop_app/models/messages_models/conversation_files_model.dart';
import 'package:flutter/material.dart';

/// Fetches one page. The screens take it as a parameter so tests can hand
/// them pages without a server; [conversationFilesFetcher] is the real one.
typedef ConversationFilesFetch = Future<ConversationFilesPage?> Function(
  List<ConversationFileKind> kinds,
  String? cursor,
  int limit,
);

/// The real [ConversationFilesFetch] for one conversation.
ConversationFilesFetch conversationFilesFetcher(
  String conversationId,
  String conversationType,
) =>
    (kinds, cursor, limit) => ConversationsApi().getConversationFilesRequest(
          conversationID: conversationId,
          conversationType: conversationType,
          kinds: kinds,
          cursor: cursor,
          limit: limit,
        );

/// The tabs, in order. Labels match webapp's.
const _tabs = <(ConversationFileKind, String)>[
  (ConversationFileKind.image, 'Photos'),
  (ConversationFileKind.video, 'Videos'),
  (ConversationFileKind.audio, 'Audio'),
  (ConversationFileKind.file, 'Files'),
];

/// One calendar day's run of shared files, newest first.
class ConversationFileDay {
  final String label;
  final List<ConversationFileItem> items;

  const ConversationFileDay(this.label, this.items);
}

/// [items] (newest first) split into days - "Today", "Yesterday", "Jul 8,
/// 2026". Each day is one consecutive run, so a page that ends part-way
/// through a day carries on into the same group when the next one lands.
/// Mirrors webapp's groupByDay in ConversationFilesPanel.
List<ConversationFileDay> groupFilesByDay(
  List<ConversationFileItem> items, {
  DateTime? now,
}) {
  final days = <ConversationFileDay>[];
  String? lastKey;
  for (final item in items) {
    final at = item.sentAt;
    final key = at == null ? 'undated' : '${at.year}-${at.month}-${at.day}';
    if (key != lastKey) {
      days.add(ConversationFileDay(
          at == null ? 'Earlier' : dayLabel(at, now: now), []));
      lastKey = key;
    }
    days.last.items.add(item);
  }
  return days;
}

void _openViewer(
  BuildContext context,
  List<ConversationFileItem> visual,
  int index,
) {
  openMediaViewer(
    context,
    [
      for (final item in visual)
        MediaViewerItem(
          source: item.content,
          isVideo: item.kind == ConversationFileKind.video,
          mimeType: item.mimeType,
        ),
    ],
    index,
  );
}

/// A photo or video as a square tile: the picture, or a video's first frame
/// with a play badge. Never a live player - a page is dozens of these.
class _MediaTile extends StatelessWidget {
  final ConversationFileItem item;
  final VoidCallback onTap;

  const _MediaTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final url = chatMediaUrl(item.content, item.attachment);

    return Semantics(
      button: true,
      label: item.kind == ConversationFileKind.video ? 'Video' : 'Photo',
      child: GestureDetector(
        onTap: onTap,
        child: ColoredBox(
          color: p.surface2,
          child: item.kind == ConversationFileKind.video
              ? VideoFirstFrame(source: url)
              : LayoutBuilder(
                  builder: (context, box) => CLNetworkImage(
                    src: url,
                    width: box.maxWidth,
                    height: box.maxHeight,
                  ),
                ),
        ),
      ),
    );
  }
}

// -------- Info screen section ------------------------------------------------

/// "Shared media" on the conversation info screen: the latest few photos and
/// videos, and a See all into [ConversationFilesScreen].
///
/// See all is offered even when there are no photos or videos, since the
/// conversation can still hold audio and files.
class ConversationMediaPreview extends StatefulWidget {
  final String conversationId;
  final String conversationType;

  /// Heading for the screen See all opens.
  final String title;

  /// Overrides the network fetch - for tests.
  final ConversationFilesFetch? fetch;

  const ConversationMediaPreview({
    super.key,
    required this.conversationId,
    required this.conversationType,
    required this.title,
    this.fetch,
  });

  /// One row of tiles.
  static const int count = 4;

  @override
  State<ConversationMediaPreview> createState() =>
      _ConversationMediaPreviewState();
}

class _ConversationMediaPreviewState extends State<ConversationMediaPreview> {
  List<ConversationFileItem>? _items;
  bool _failed = false;

  ConversationFilesFetch get _fetch =>
      widget.fetch ??
      conversationFilesFetcher(widget.conversationId, widget.conversationType);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _items = null;
    });
    final page = await _fetch(
      const [ConversationFileKind.image, ConversationFileKind.video],
      null,
      ConversationMediaPreview.count,
    );
    if (!mounted) return;
    setState(() {
      _items = page?.items;
      _failed = page == null;
    });
  }

  void _openAll() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationFilesScreen(
        conversationId: widget.conversationId,
        conversationType: widget.conversationType,
        title: widget.title,
        fetch: widget.fetch,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final items = _items;

    Widget body;
    if (_failed) {
      body = _InlineRetry(
        message: "Couldn't load shared media.",
        onRetry: _load,
      );
    } else if (items != null && items.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'No photos or videos yet',
          style: TextStyle(fontSize: CLType.caption, color: p.text2),
        ),
      );
    } else {
      // A fixed row of equal squares - the same four slots whether they hold
      // skeletons or tiles, so nothing moves when the page lands.
      body = Row(
        children: [
          for (var i = 0; i < ConversationMediaPreview.count; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CLRadii.xs),
                  child: items == null
                      ? const CLSkeleton(
                          width: double.infinity,
                          height: double.infinity,
                          borderRadius: BorderRadius.zero,
                        )
                      : i < items.length
                          ? _MediaTile(
                              item: items[i],
                              onTap: () => _openViewer(context, items, i),
                            )
                          : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(title: 'Shared media', onSeeAll: _openAll),
        const SizedBox(height: 8),
        body,
      ],
    );
  }
}

/// The section's heading - the members heading's size and weight, with a See
/// all beside it.
class _SectionHeading extends StatelessWidget {
  final String title;
  final VoidCallback onSeeAll;

  const _SectionHeading({required this.title, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: CLType.sectionTitle,
                fontWeight: FontWeight.w700,
                color: p.text),
          ),
        ),
        InkWell(
          onTap: onSeeAll,
          borderRadius: BorderRadius.circular(CLRadii.xs),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              'See all',
              style: TextStyle(
                  fontSize: CLType.label,
                  fontWeight: FontWeight.w600,
                  color: CLAccent.textOf(context)),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Couldn't load … Try again", for a failure that should not take over the
/// whole area - a section, or a page past the first.
class _InlineRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            message,
            style: TextStyle(fontSize: CLType.caption, color: p.text2),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: Text(
            'Try again',
            style: TextStyle(
                fontSize: CLType.label,
                fontWeight: FontWeight.w600,
                color: CLAccent.textOf(context)),
          ),
        ),
      ],
    );
  }
}

/// Whether [conversationType] is a server's channel - the conversations
/// painted gold instead of the brand blue.
bool isChannelConversation(String conversationType) =>
    conversationType == 'channel' || conversationType == 'server';

/// A conversation's own screens (its info, its shared files) in its accent,
/// as the chat itself is - conversation_view wraps the thread in the same
/// CLAccent. A channel is gold, with the darker gold for anything drawn as
/// text; every other conversation keeps the brand blue.
class ConversationAccentScope extends StatelessWidget {
  final String conversationType;
  final Widget child;

  const ConversationAccentScope({
    super.key,
    required this.conversationType,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!isChannelConversation(conversationType)) return child;
    final p = cl(context);
    return CLAccent(color: p.gold, onSurface: p.goldText, child: child);
  }
}

// -------- See all ------------------------------------------------------------

/// Everything shared in a conversation, by kind: Photos / Videos / Audio /
/// Files. Each tab loads its first page when first shown, then the next as it
/// nears the bottom, and keeps what it has while the screen is open.
class ConversationFilesScreen extends StatelessWidget {
  final String conversationId;
  final String conversationType;
  final String title;
  final ConversationFileKind initialKind;

  /// Overrides the network fetch - for tests.
  final ConversationFilesFetch? fetch;

  const ConversationFilesScreen({
    super.key,
    required this.conversationId,
    required this.conversationType,
    required this.title,
    this.initialKind = ConversationFileKind.image,
    this.fetch,
  });

  @override
  Widget build(BuildContext context) => ConversationAccentScope(
        conversationType: conversationType,
        // A Builder, so what follows reads the scope's accent.
        child: Builder(builder: _build),
      );

  Widget _build(BuildContext context) {
    final p = cl(context);
    final load =
        fetch ?? conversationFilesFetcher(conversationId, conversationType);

    return DefaultTabController(
      length: _tabs.length,
      initialIndex:
          _tabs.indexWhere((tab) => tab.$1 == initialKind).clamp(0, 3),
      child: CLScreen(
        // Surface, like the info screen this is pushed from.
        backgroundColor: p.surface,
        appBar: AppBar(
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: TabBar(
            labelColor: p.text,
            unselectedLabelColor: p.text2,
            indicatorColor: CLAccent.of(context),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: p.border,
            labelStyle: const TextStyle(
                fontSize: CLType.bodySm, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(
                fontSize: CLType.bodySm, fontWeight: FontWeight.w600),
            tabs: [for (final tab in _tabs) Tab(text: tab.$2)],
          ),
        ),
        body: TabBarView(
          children: [
            for (final tab in _tabs) _FilesTab(kind: tab.$1, fetch: load),
          ],
        ),
      ),
    );
  }
}

class _FilesTab extends StatefulWidget {
  final ConversationFileKind kind;
  final ConversationFilesFetch fetch;

  const _FilesTab({required this.kind, required this.fetch});

  @override
  State<_FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<_FilesTab>
    with PaginatedScrollMixin<_FilesTab>, AutomaticKeepAliveClientMixin {
  // Whole rows of a 3-wide grid; a list page fills a phone about twice.
  static const _gridPage = 30;
  static const _listPage = 20;

  final List<ConversationFileItem> _items = [];
  String? _nextCursor;
  bool _loaded = false;
  bool _loading = false;
  bool _failed = false;

  bool get _isGrid => widget.kind.isVisual;

  /// A tab keeps its pages while the screen is open, so swiping back to it
  /// neither refetches nor loses the scroll position.
  @override
  bool get wantKeepAlive => true;

  @override
  bool get canLoadMore =>
      _loaded && _nextCursor != null && !_loading && !_failed;

  @override
  void loadNextPage() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    if (_loaded && _nextCursor == null) return;
    setState(() {
      _loading = true;
      _failed = false;
    });

    final page = await widget.fetch(
      [widget.kind],
      _nextCursor,
      _isGrid ? _gridPage : _listPage,
    );
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (page == null) {
        _failed = true;
        return;
      }
      // Keyset paging cannot repeat a row, but a retried page could.
      final seen = {for (final item in _items) item.messageID};
      _items.addAll(page.items.where((item) => !seen.contains(item.messageID)));
      _nextCursor = page.nextCursor;
      _loaded = true;
    });
    ensureFilled();
  }

  /// Audio, grouped by day: a day's label once, then its clips as full-width
  /// rows, and a wider gap before the next day. Flattened into ONE lazy list
  /// (labels and clips as siblings) rather than a widget per day, because
  /// every clip opens an audio player as it is built - a day of forty must
  /// not build forty at once.
  Widget _audioSliver(int skeletons) {
    final entries = <Object>[];
    for (final day in groupFilesByDay(_items)) {
      entries.add(day.label);
      entries.addAll(day.items);
    }
    // Before the first page, a label's skeleton heads the placeholder rows.
    final leadingLabelSkeleton = !_loaded;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
          CLSpacing.contentGutter, 12, CLSpacing.contentGutter, 10),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            if (leadingLabelSkeleton && i == 0) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CLSkeleton(width: 84, height: 10),
                ),
              );
            }
            final index = leadingLabelSkeleton ? i - 1 : i;
            if (index >= entries.length) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: _AudioRowSkeleton(),
              );
            }
            final entry = entries[index];
            if (entry is String) {
              return _DayHeading(label: entry, first: index == 0);
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AudioRow(item: entry as ConversationFileItem),
            );
          },
          childCount:
              entries.length + skeletons + (leadingLabelSkeleton ? 1 : 0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_loaded && _failed) {
      return _CenteredMessage(
        icon: Icons.cloud_off_outlined,
        title: "Couldn't load this tab",
        onRetry: _load,
      );
    }

    if (_loaded && _items.isEmpty) {
      final (icon, what) = switch (widget.kind) {
        ConversationFileKind.image => (Icons.photo_outlined, 'photos'),
        ConversationFileKind.video => (Icons.videocam_outlined, 'videos'),
        ConversationFileKind.audio => (Icons.graphic_eq, 'audio'),
        ConversationFileKind.file => (Icons.description_outlined, 'files'),
      };
      return ListView(
        padding: const EdgeInsets.all(CLSpacing.contentGutter),
        children: [
          CLSectionEmpty(
            icon: icon,
            title: 'No $what yet',
            subtitle: "What's shared in this conversation shows up here.",
          ),
        ],
      );
    }

    // Skeletons stand in for the first page, and are appended under the
    // loaded ones while the next page is on its way - infinite loading.
    final skeletons =
        !_loaded ? (_isGrid ? 15 : 6) : (_loading ? (_isGrid ? 6 : 2) : 0);

    return CustomScrollView(
      controller: paginationController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (_isGrid)
          SliverPadding(
            padding: const EdgeInsets.all(2),
            sliver: SliverGrid(
              // By width rather than a fixed count: three across a phone held
              // upright, more on its side.
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => i < _items.length
                    ? _MediaTile(
                        item: _items[i],
                        onTap: () => _openViewer(context, _items, i),
                      )
                    : const CLSkeleton(
                        width: double.infinity,
                        height: double.infinity,
                        borderRadius: BorderRadius.zero,
                      ),
                childCount: _items.length + skeletons,
              ),
            ),
          )
        else if (widget.kind == ConversationFileKind.audio)
          _audioSliver(skeletons)
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                CLSpacing.contentGutter, 10, CLSpacing.contentGutter, 10),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: i < _items.length
                      ? _FileRow(item: _items[i])
                      : const _RowSkeleton(),
                ),
                childCount: _items.length + skeletons,
              ),
            ),
          ),
        if (_loaded && _failed)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _InlineRetry(
                message: "Couldn't load more.",
                onRetry: _load,
              ),
            ),
          ),
      ],
    );
  }
}

/// A whole-tab message with a retry - the first page failed.
class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onRetry;

  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return ListView(
      padding: const EdgeInsets.all(CLSpacing.contentGutter),
      children: [
        const SizedBox(height: 40),
        Icon(icon, size: 30, color: p.text3),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: CLType.body,
              fontWeight: FontWeight.w700,
              color: p.text),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: onRetry,
            child: Text(
              'Try again',
              style: TextStyle(
                  fontSize: CLType.label,
                  fontWeight: FontWeight.w600,
                  color: CLAccent.textOf(context)),
            ),
          ),
        ),
      ],
    );
  }
}

/// The shape of a [_FileRow] / [_AudioRow] while it loads.
class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.sm),
      ),
      child: const Row(
        children: [
          CLSkeleton(
            width: 38,
            height: 38,
            borderRadius: BorderRadius.all(Radius.circular(CLRadii.xs)),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CLSkeleton(width: 160, height: 12),
                SizedBox(height: 7),
                CLSkeleton(width: 80, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A day's heading in the Audio tab: the label, with a hairline running out to
/// the right. The gap above it (none above the first) is what separates one
/// day from the next; clips of the same day sit closer together.
class _DayHeading extends StatelessWidget {
  final String label;
  final bool first;

  const _DayHeading({required this.label, required this.first});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 10, bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: CLType.caption,
                fontWeight: FontWeight.w600,
                color: p.text2),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: p.border)),
        ],
      ),
    );
  }
}

/// A shared audio clip: the chat's own voice-note player as a received one -
/// tinted with the conversation's accent, exactly as in the chat - stretched
/// to the row like a Files row. Its day heading carries the date.
class _AudioRow extends StatelessWidget {
  final ConversationFileItem item;

  const _AudioRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return VoiceMessagePlayer(
      src: chatMediaUrl(item.content, item.attachment),
      isSender: false,
      fullWidth: true,
    );
  }
}

/// The shape of an [_AudioRow] while it loads.
class _AudioRowSkeleton extends StatelessWidget {
  const _AudioRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const CLSkeleton(
      width: double.infinity,
      height: 66,
      borderRadius: BorderRadius.all(Radius.circular(CLRadii.md)),
    );
  }
}

/// A shared file. Tapping downloads it, as tapping a file card in the chat
/// does - the same downloader, so a download started in either place shows
/// its progress in both.
class _FileRow extends StatelessWidget {
  final ConversationFileItem item;

  const _FileRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final sentAt = item.sentAt;

    return Material(
      color: p.surface2,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.sm),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => MediaDownloader.instance.download(
          chatMediaUrl(item.content, item.attachment),
          mimeType: item.attachment?.mime ?? item.mimeType,
          fileName: item.attachment == null
              ? null
              : chatMediaFileName(item.content, attachment: item.attachment),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _FileGlyph(content: chatMediaUrl(item.content, item.attachment)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // Name and size come from the message's attachment.
                      item.attachment?.name ?? "File",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: CLType.body,
                          fontWeight: FontWeight.w600,
                          color: p.text),
                    ),
                    if (sentAt != null || item.attachment != null)
                      Text(
                        [
                          if (item.attachment?.available == false)
                            "No longer available"
                          else if (item.attachment?.sizeLabel.isNotEmpty ==
                              true)
                            item.attachment!.sizeLabel,
                          if (sentAt != null) timeSince(sentAt),
                        ].join(" · "),
                        style:
                            TextStyle(fontSize: CLType.caption, color: p.text2),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The file icon, or a progress ring while that file is downloading - read
/// off the downloader, which outlives this row.
class _FileGlyph extends StatelessWidget {
  final String content;

  const _FileGlyph({required this.content});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.xs),
      ),
      child: ValueListenableBuilder<Map<String, double>>(
        valueListenable: MediaDownloader.instance.progress,
        builder: (context, running, _) {
          final value = running[chatMediaUrl(content)];
          if (value == null) {
            return Icon(Icons.description_outlined,
                size: 20, color: CLAccent.textOf(context));
          }
          return SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: CLAccent.textOf(context),
              // 0 = no Content-Length to measure against: spin instead.
              value: value > 0 ? value : null,
            ),
          );
        },
      ),
    );
  }
}
