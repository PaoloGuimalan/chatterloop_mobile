// Paginated mood picker - the mobile equivalent of webapp's AsyncPaginate
// mood select in NewEntry.tsx, which loads 10 at a time and fetches the next
// page as the list is scrolled.
//
// A bottom sheet rather than a DropdownButton because a dropdown menu can't
// page: it needs its whole item list up front, which is exactly what the
// paginated endpoint is there to avoid.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/diary_api.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'package:flutter/material.dart';

/// Opens the picker. Resolves to the chosen mood, or null if dismissed.
///
/// Returning a nullable [Mood] can't express "clear the selection", so the
/// clear action is a row inside the sheet that pops a sentinel the caller
/// unwraps - see [MoodSelection].
Future<MoodSelection?> showMoodPickerSheet(
  BuildContext context, {
  Mood? selected,
}) {
  return showModalBottomSheet<MoodSelection>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _MoodPickerSheet(selected: selected),
  );
}

/// Wrapper so "cleared" is distinguishable from "dismissed".
class MoodSelection {
  const MoodSelection(this.mood);
  final Mood? mood;
}

class _MoodPickerSheet extends StatefulWidget {
  const _MoodPickerSheet({this.selected});

  final Mood? selected;

  @override
  State<_MoodPickerSheet> createState() => _MoodPickerSheetState();
}

class _MoodPickerSheetState extends State<_MoodPickerSheet> {
  /// Matches webapp's `GetMoodListRequest({page, range: 10})`.
  static const int _range = 10;

  final ScrollController _scrollController = ScrollController();
  final List<Mood> _moods = [];

  bool _isLoading = true;
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
    if (!_hasNext || _isLoadingMore || _isLoading) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 120) {
      _loadPage(_page + 1);
    }
  }

  Future<void> _loadPage(int page) async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    final result = await DiaryApi().getMoods(page: page, range: _range);
    if (!mounted) return;

    setState(() {
      if (page == 1) _moods.clear();
      final seen = _moods.map((m) => m.id).toSet();
      for (final mood in result.results) {
        if (seen.add(mood.id)) _moods.add(mood);
      }
      _page = page;
      _hasNext = result.hasNext;
      _isLoadingMore = false;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(CLRadii.lg)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: p.border2,
              borderRadius: BorderRadius.circular(CLRadii.pill),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text("Select Mood",
                      style: TextStyle(
                          color: p.text,
                          fontSize: CLType.sectionTitle,
                          fontWeight: FontWeight.w800)),
                ),
                if (widget.selected != null)
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(const MoodSelection(null)),
                    child: Text("Clear",
                        style:
                            TextStyle(color: p.text2, fontSize: CLType.bodySm)),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: p.border),
          Flexible(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _moods.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text("No moods available",
                            style: TextStyle(color: p.text3)),
                      )
                    : SingleChildScrollView(
                        controller: _scrollController,
                        child: Column(children: [
                          GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 8,
                                      crossAxisSpacing: 8,
                                      mainAxisExtent: 55),
                              itemCount: _moods.length,
                              itemBuilder: (context, index) {
                                final mood = _moods[index];
                                final selected = widget.selected?.id == mood.id;
                                return Material(
                                    color: selected ? p.brandSoft : p.surface2,
                                    borderRadius: BorderRadius.circular(9),
                                    child: InkWell(
                                        borderRadius: BorderRadius.circular(9),
                                        onTap: () => Navigator.of(context)
                                            .pop(MoodSelection(mood)),
                                        child: Padding(
                                            padding: const EdgeInsets.all(10),
                                            child: Row(children: [
                                              Text(mood.emoji,
                                                  style: const TextStyle(
                                                      fontSize: 20)),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                  child: Text(mood.name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: p.text))),
                                              if (selected)
                                                Icon(Icons.check,
                                                    size: 15, color: p.brand),
                                            ]))));
                              }),
                          if (_hasNext)
                            TextButton(
                                onPressed: _isLoadingMore
                                    ? null
                                    : () => _loadPage(_page + 1),
                                child: Text(_isLoadingMore
                                    ? 'Loading…'
                                    : 'Load more moods')),
                        ])),
          ),
          SizedBox(height: clSheetBottomGap(context, minimum: 8)),
        ],
      ),
    );
  }
}
