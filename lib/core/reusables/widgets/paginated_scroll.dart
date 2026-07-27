// Shared "load the next page as the list is scrolled" plumbing for the three
// redesigned See-all screens (Explore sections, Contacts sections,
// Notifications sections).
//
// The non-obvious half is [ensureFilled]. A scroll-driven list stalls at page 1
// whenever the first page doesn't fill its viewport: with nothing to scroll,
// maxScrollExtent is 0, no scroll notification can ever fire, and the next page
// is never requested. Tall screens, short pages and heavily-filtered results
// all hit this. Web has the same bug and the same fix (needsMoreToFill in
// webapp's reusables/hooks/reusable.ts) - any new paginated list needs it too;
// the scroll listener alone is not sufficient.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:flutter/material.dart';

mixin PaginatedScrollMixin<T extends StatefulWidget> on State<T> {
  final ScrollController paginationController = ScrollController();

  /// True while there IS a next page and no request is already in flight.
  bool get canLoadMore;

  /// Fetch the next page. Implementations should call [ensureFilled] once the
  /// response has been applied.
  void loadNextPage();

  /// How close to the bottom starts the next fetch - roughly one card, so the
  /// request is already running by the time the user reaches the end.
  double get loadMoreThreshold => 280;

  @override
  void initState() {
    super.initState();
    paginationController.addListener(_onScroll);
  }

  @override
  void dispose() {
    paginationController.removeListener(_onScroll);
    paginationController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!canLoadMore || !paginationController.hasClients) return;
    final position = paginationController.position;
    if (position.pixels >= position.maxScrollExtent - loadMoreThreshold) {
      loadNextPage();
    }
  }

  /// Keeps pulling pages until the list actually overflows its viewport. Call
  /// after every page is applied.
  void ensureFilled() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !canLoadMore) return;
      // No clients yet means the list hasn't laid out - the next load's
      // ensureFilled will pick it up.
      if (!paginationController.hasClients) return;
      if (paginationController.position.maxScrollExtent <= 0) loadNextPage();
    });
  }
}

/// The trailing "fetching the next page" row shared by those same screens.
class CLLoadMoreIndicator extends StatelessWidget {
  const CLLoadMoreIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// The count pill in a See-all screen's header ("38", "214"). Renders nothing
/// while the first page is still loading, since the total isn't known until
/// the server's paginated response lands.
class CLCountPill extends StatelessWidget {
  final int? count;

  const CLCountPill({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == null) return const SizedBox.shrink();
    final p = cl(context);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.surface3,
        borderRadius: BorderRadius.circular(CLRadii.pill),
      ),
      child: Text(
        "$count",
        style: TextStyle(
          fontSize: CLType.caption,
          fontWeight: FontWeight.w600,
          color: p.text2,
        ),
      ),
    );
  }
}
