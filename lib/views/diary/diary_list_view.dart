// The diary index - mirrors webapp's app/tabs/profile/diary/Diary.tsx.
//
// Always the signed-in account's OWN diary: DiaryListView on the server filters
// on `account=request.user` with no parameter to request anyone else's, so
// there is deliberately no "whose diary" input here. Another account's diary
// can only ever be summarised, via the public total endpoint that backs the
// profile card.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/diary_api.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DiaryListScreen extends StatefulWidget {
  const DiaryListScreen({super.key});

  @override
  State<DiaryListScreen> createState() => _DiaryListScreenState();
}

class _DiaryListScreenState extends State<DiaryListScreen> {
  /// Matches Diary.tsx's fixed range.
  static const int _range = 10;

  /// Fires the next fetch roughly one card before the bottom is reached.
  static const double _loadMoreThreshold = 320;

  final ScrollController _scrollController = ScrollController();

  final List<DiaryEntry> _entries = [];
  bool _isInitialized = false;
  bool _isLoadingMore = false;
  bool _hasNext = false;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _loadPage(1);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasNext || _isLoadingMore || !_isInitialized) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      _loadPage(_page + 1);
    }
  }

  /// Page 1 replaces, later pages append. The server pages properly
  /// (PageNumberPagination), so each response carries only its own slice and
  /// has to be merged - deduped by id, since a new entry created between two
  /// page fetches shifts everything down by one and would otherwise repeat.
  Future<void> _loadPage(int page) async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    final result = await DiaryApi().getEntries(page: page, range: _range);
    if (!mounted) return;

    setState(() {
      if (page == 1) _entries.clear();
      final seen = _entries.map((e) => e.id).toSet();
      for (final entry in result.results) {
        if (seen.add(entry.id)) _entries.add(entry);
      }
      _page = page;
      _hasNext = result.hasNext;
      _isLoadingMore = false;
      _isInitialized = true;
    });
  }

  Future<void> _openCompose() async {
    final created = await context.push<bool>('/diary/new');
    // The compose screen pops with true once the POST succeeds; reload from
    // the top so the new entry appears in its server-assigned position.
    if (created == true && mounted) _loadPage(1);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text("Diary")),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCompose,
        backgroundColor: p.brand,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: !_isInitialized
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: CLListSkeleton(),
            )
          : _entries.isEmpty
              ? Center(
                  child: CLEmptyState(
                    icon: Icons.menu_book_outlined,
                    iconBg: p.brandSoft,
                    iconColor: p.brand,
                    title: "No entries yet",
                    subtitle: "Your diary is private by default.",
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadPage(1),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _groupedEntries.length + (_hasNext ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _groupedEntries.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final group = _groupedEntries[index];
                      return _DayGroup(
                          date: group.date, entries: group.entries);
                    },
                  ),
                ),
    );
  }

  /// Same-day entries collapse into ONE list item, so the list reads day by
  /// day - each day being that day's collection of entries.
  ///
  /// Mirrors the webapp's `entriesByDate` memo (Diary.tsx:57), whose ordering
  /// is easy to get subtly wrong: sort by entry_date ASCENDING with ties
  /// broken by created_at DESCENDING, then reverse BOTH the per-day list and
  /// the outer list. Net effect - newest day first, and within a day the
  /// oldest entry first.
  List<({DateTime date, List<DiaryEntry> entries})> get _groupedEntries {
    final dated = _entries.where((e) => e.entryDate != null).toList()
      ..sort((a, b) {
        final byDate = a.entryDate!.compareTo(b.entryDate!);
        if (byDate != 0) return byDate;
        final ac = a.createdAt, bc = b.createdAt;
        if (ac == null || bc == null) return 0;
        return bc.compareTo(ac);
      });

    final buckets = <String, List<DiaryEntry>>{};
    final order = <String>[];
    for (final entry in dated) {
      final d = entry.entryDate!;
      final key = "${d.year}-${d.month}-${d.day}";
      if (buckets.putIfAbsent(key, () => []).isEmpty) order.add(key);
      buckets[key]!.add(entry);
    }

    return order.reversed
        .map((key) => (
              date: buckets[key]!.first.entryDate!,
              entries: buckets[key]!.reversed.toList(),
            ))
        .toList();
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final DiaryEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final preview = entry.plainTextPreview;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(CLRadii.md),
        onTap: () => context.push('/diary/entry/${entry.id}'),
        child: CLCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (entry.mood != null) ...[
                    Text(entry.mood!.emoji,
                        // Emoji glyph sized to its container - not a CLType step.
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      entry.title.isEmpty ? "Untitled" : entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.text,
                          fontWeight: FontWeight.w700,
                          fontSize: CLType.sectionTitle),
                    ),
                  ),
                  // Private is the default, so the lock marks the norm rather
                  // than the exception - it's the PUBLIC entries that are
                  // worth flagging, since they're readable by anyone.
                  if (!entry.isPrivate)
                    Icon(Icons.public, size: 16, color: p.text3),
                ],
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.text2, fontSize: CLType.bodySm, height: 1.35),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 13, color: p.text3),
                  const SizedBox(width: 5),
                  Text(
                    entry.entryDate != null
                        ? _formatEntryDate(entry.entryDate!)
                        : "",
                    style: TextStyle(color: p.text3, fontSize: CLType.caption),
                  ),
                  if (entry.attachments.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.attachment, size: 13, color: p.text3),
                    const SizedBox(width: 4),
                    Text("${entry.attachments.length}",
                        style: TextStyle(color: p.text3, fontSize: CLType.caption)),
                  ],
                  if (entry.mood != null) ...[
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        entry.mood!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.text3, fontSize: CLType.caption),
                      ),
                    ),
                  ],
                ],
              ),
              if (entry.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: entry.tags
                      .take(4)
                      .map((tag) => CLChip(label: tag.name))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "3rd of March, 2026" - reuses the shared ordinalSuffix helper so diary
  /// dates read the same as dates elsewhere in the app.
  String _formatEntryDate(DateTime date) {
    const months = [
      "January", "February", "March", "April", "May", "June",
      "July", "August", "September", "October", "November", "December",
    ];
    return "${ordinalSuffix(date.day)} of ${months[date.month - 1]}, ${date.year}";
  }
}

/// One list item per DAY, holding that day's entries.
///
/// The grouping is display-only - nothing is merged in the data, and each
/// entry still renders as its own card underneath the date heading.
class _DayGroup extends StatelessWidget {
  const _DayGroup({required this.date, required this.entries});

  final DateTime date;
  final List<DiaryEntry> entries;

  static const _months = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ];

  String get _label => "${_months[date.month - 1]} ${date.day}, ${date.year}";

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 6, bottom: 6),
          child: Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 13, color: p.text3),
              const SizedBox(width: 6),
              Text(
                _label,
                style: TextStyle(
                  color: p.text2,
                  fontSize: CLType.caption,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (entries.length > 1) ...[
                const SizedBox(width: 8),
                Text("${entries.length} entries",
                    style: TextStyle(color: p.text3, fontSize: CLType.meta)),
              ],
            ],
          ),
        ),
        for (final entry in entries) _EntryCard(entry: entry),
        const SizedBox(height: 6),
      ],
    );
  }
}
