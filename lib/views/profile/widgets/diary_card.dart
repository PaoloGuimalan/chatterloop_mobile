// The diary summary shown on a profile - mirrors the Diary block in webapp's
// Profile.tsx (the "Diary" heading, latest-entry date, entry count and top
// tags, linking to /:userID/diary).
//
// Backed by GET /api/diary/total/<username>/, the one diary endpoint that
// allows anonymous access - which is why this renders on anyone's profile even
// though their entries themselves are unreadable. Reading the entries is
// self-only (DiaryListView filters on request.user), so the tap-through is
// offered only on your own profile.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/diary_api.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ProfileDiaryCard extends StatefulWidget {
  const ProfileDiaryCard({
    super.key,
    required this.username,
    required this.isSelf,
  });

  final String username;

  /// Only your own diary is readable, so this decides whether the card is a
  /// link or just a summary.
  final bool isSelf;

  @override
  State<ProfileDiaryCard> createState() => _ProfileDiaryCardState();
}

class _ProfileDiaryCardState extends State<ProfileDiaryCard> {
  DiaryTotal? _total;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfileDiaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The profile screens are reused across usernames when navigating between
    // profiles, so refetch rather than showing the previous person's counts.
    if (oldWidget.username != widget.username) _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final result = await DiaryApi().getDiaryTotal(widget.username);
    if (!mounted) return;
    setState(() {
      _total = result;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    // A profile whose diary can't be summarised shows nothing at all rather
    // than an empty card - the endpoint 500s for accounts that have never
    // touched the feature.
    if (!_isLoading && _total == null) return const SizedBox.shrink();

    final total = _total;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: InkWell(
        borderRadius: BorderRadius.circular(CLRadii.md),
        onTap: widget.isSelf ? () => context.push('/diary') : null,
        child: CLCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: p.brandSoft,
                      borderRadius: BorderRadius.circular(CLRadii.sm),
                    ),
                    child: Icon(Icons.menu_book_outlined,
                        size: 17, color: p.brand),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text("Diary",
                        style: TextStyle(
                            color: p.text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800)),
                  ),
                  if (widget.isSelf)
                    Icon(Icons.chevron_right, size: 20, color: p.text3),
                ],
              ),
              const SizedBox(height: 12),
              if (_isLoading)
                const CLSkeleton(width: 150, height: 13)
              else ...[
                Row(
                  children: [
                    Icon(Icons.article_outlined, size: 14, color: p.text3),
                    const SizedBox(width: 6),
                    Text(
                      "${total!.totalEntries} "
                      "${total.totalEntries == 1 ? 'entry' : 'entries'}",
                      style: TextStyle(
                          color: p.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                if (total.latestEntry != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 14, color: p.text3),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          "Last written ${timeSince(total.latestEntry!)}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.text2, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ],
                if (total.topTags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text("Writes most about",
                      style: TextStyle(color: p.text3, fontSize: 11.5)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: total.topTags
                        .map((t) => CLChip(label: t.name))
                        .toList(),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
