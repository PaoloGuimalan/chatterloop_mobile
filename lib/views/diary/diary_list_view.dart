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
import 'package:chatterloop_app/views/notes/writing_widgets.dart';
import 'dart:async';
import 'package:chatterloop_app/core/redux/store.dart';
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
  final _search = TextEditingController();
  StreamSubscription? _accountSubscription;
  String get _currentAccount =>
      '${appStore.state.userAuth.user.id}/${appStore.state.userAuth.user.entityId}';
  late String _accountKey;
  int _generation = 0;
  bool _isInitialized = false;
  bool _isLoadingMore = false;
  bool _hasNext = false;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _accountKey = _currentAccount;
    _accountSubscription = appStore.onChange.listen((_) {
      if (_accountKey == _currentAccount) return;
      _accountKey = _currentAccount;
      _generation++;
      _entries.clear();
      _isLoadingMore = false;
      _isInitialized = false;
      _loadPage(1);
    });
    _loadPage(1);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _accountSubscription?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _search.dispose();
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
    final generation = _generation;
    setState(() => _isLoadingMore = true);

    final result = await DiaryApi().getEntries(page: page, range: _range);
    if (!mounted || generation != _generation) return;

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
    if (_search.text.trim().isNotEmpty && _hasNext) _loadPage(_page + 1);
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

    final groups = _groupedEntries;
    return CLScreen(
        backgroundColor: p.bg,
        appBar: AppBar(
            title: Row(children: [
              Image.asset('assets/images/app-icon-diary.png',
                  width: 27, height: 27),
              const SizedBox(width: 9),
              const Text('Diary')
            ]),
            actions: [
              TextButton.icon(
                  onPressed: _openCompose,
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('New entry'))
            ]),
        body: Column(children: [
          const WritingOwner(diary: true),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                  decoration: BoxDecoration(
                      color: p.surface2,
                      border: Border.all(color: p.border),
                      borderRadius: BorderRadius.circular(10)),
                  child: TextField(
                      controller: _search,
                      onChanged: (_) {
                        setState(() {});
                        if (_search.text.trim().isNotEmpty &&
                            _hasNext &&
                            !_isLoadingMore) {
                          _loadPage(_page + 1);
                        }
                      },
                      decoration: writingInput('Search diary').copyWith(
                          prefixIcon: const Icon(Icons.search, size: 19))))),
          Expanded(
              child: !_isInitialized
                  ? const Padding(
                      padding: EdgeInsets.all(12), child: CLListSkeleton())
                  : RefreshIndicator(
                      onRefresh: () => _loadPage(1),
                      child: ListView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          children: [
                            if (groups.isEmpty)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 60),
                                  child: Center(
                                      child: Text(
                                          _entries.isEmpty
                                              ? 'Your story starts here.\nWrite your first entry.'
                                              : 'No matching entries',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: p.text3)))),
                            for (final group in groups)
                              _DayGroup(
                                  date: group.date, entries: group.entries),
                            if (_hasNext)
                              TextButton(
                                  onPressed: _isLoadingMore
                                      ? null
                                      : () => _loadPage(_page + 1),
                                  child: Text(_isLoadingMore
                                      ? 'Loading…'
                                      : 'Load more entries')),
                          ]))),
        ]));
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
    final query = _search.text.trim().toLowerCase();
    final dated = _entries
        .where((e) =>
            e.entryDate != null &&
            (query.isEmpty ||
                '${e.title} ${e.plainTextPreview} ${e.tags.map((t) => t.name).join(' ')} ${e.mood?.name ?? ''}'
                    .toLowerCase()
                    .contains(query)))
        .toList()
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(CLRadii.md),
        onTap: () => context.push('/diary/entry/${entry.id}'),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
              color: p.surface,
              border: Border.all(color: p.border),
              borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.title.isEmpty ? "Untitled" : entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ),
                  if (entry.mood != null) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 112),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(entry.mood!.emoji,
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Flexible(
                              child: Text(entry.mood!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      TextStyle(color: p.text2, fontSize: 11))),
                        ])),
                  ],
                ],
              ),
              if (entry.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: entry.tags
                      .take(3)
                      .map((tag) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                              color: p.brand.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(tag.name,
                              style: TextStyle(color: p.brand, fontSize: 11))))
                      .toList(),
                ),
              ],
              if (entry.plainTextPreview.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(entry.plainTextPreview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: p.text2, fontSize: 12, height: 1.65)),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Icon(entry.isPrivate ? Icons.lock_outline : Icons.public,
                    size: 12, color: p.text2),
                const SizedBox(width: 5),
                Text(entry.isPrivate ? 'Private' : 'Public',
                    style: TextStyle(color: p.text2, fontSize: 11)),
                if (entry.attachments.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.attachment, size: 13, color: p.text3),
                  const SizedBox(width: 4),
                  Text('${entry.attachments.length}',
                      style:
                          TextStyle(color: p.text3, fontSize: CLType.caption)),
                ],
                const Spacer(),
                if (entry.createdAt != null)
                  Text(
                      TimeOfDay.fromDateTime(entry.createdAt!.toLocal())
                          .format(context),
                      style: TextStyle(color: p.text2, fontSize: 11)),
              ]),
            ],
          ),
        ),
      ),
    );
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
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];

  String get _label => "${_months[date.month - 1]} ${date.day}, ${date.year}";

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 13, bottom: 10),
          child: Row(
            children: [
              Text(
                _label,
                style: TextStyle(
                  color: p.text2,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (entries.length > 1) ...[
                const SizedBox(width: 8),
                Text("${entries.length} entries",
                    style: TextStyle(color: p.text3, fontSize: CLType.meta)),
              ],
              const SizedBox(width: 10),
              Expanded(child: Divider(color: p.border, height: 1)),
            ],
          ),
        ),
        for (final entry in entries) _EntryCard(entry: entry),
        const SizedBox(height: 6),
      ],
    );
  }
}
