// ignore_for_file: use_build_context_synchronously

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/notifications/conversation_shortcuts.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/message_item.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class MessagesView extends StatefulWidget {
  const MessagesView({super.key});

  @override
  MessagesStateView createState() => MessagesStateView();
}

/// Rows per page. Must match what the requests below ask for - the reset in
/// build() infers "this is a fresh first page" from the list's length.
const int _kPageSize = 20;

class MessagesStateView extends State<MessagesView> {
  bool isInitialized = false;
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  /// Item count at the previous build, to notice the list being replaced from
  /// under us - see the reset in build().
  int _lastCount = 0;

  /// Loads page 1 and REPLACES the list. Also what pull-to-refresh runs, hence
  /// resetting the paging cursor - continuing from an old `_page` after the
  /// list was replaced would skip or duplicate a page.
  Future<void> getConversationListProcess(BuildContext context) async {
    final res =
        await ConversationsApi().getConversationListRequest(range: _kPageSize);

    if (!mounted) return;
    if (res != null) {
      setState(() {
        isInitialized = true;
        _page = 1;
        _hasMore = res.hasNext;
      });
      StoreProvider.of<AppState>(context)
          .dispatch(DispatchModel(setMessagesListT, res.items));
      // Fire-and-forget: publishes Android conversation shortcuts so incoming
      // message notifications get the avatar-forward Conversation layout. Not
      // awaited - it fetches avatars, and nothing on screen depends on it.
      ConversationShortcuts.sync(res.items);
    } else {
      setState(() => isInitialized = true);
    }
  }

  /// Fetch the next page and APPEND it to the Redux list (read fresh at
  /// dispatch time so a concurrent SSE update isn't clobbered). Guarded so
  /// the repeated scroll notifications only kick off one request at a time.
  ///
  /// Deliberately shows NO spinner. `_hasMore` now answers "is there another
  /// page" correctly, so reaching the bottom either quietly appends rows or
  /// does nothing at all - and a loader that appears only to vanish with the
  /// list unchanged is worse than no loader. `_loadingMore` survives purely as
  /// the concurrency guard it always was.
  Future<void> _loadMore(BuildContext context) async {
    if (!_hasMore || _loadingMore) return;
    _loadingMore = true;
    final store = StoreProvider.of<AppState>(context);
    final res = await ConversationsApi()
        .getConversationListRequest(page: _page + 1, range: _kPageSize);
    if (!mounted) return;
    if (res != null) {
      store.dispatch(DispatchModel(
          setMessagesListT, [...store.state.messages, ...res.items]));
      setState(() {
        _page += 1;
        _hasMore = res.hasNext;
      });
    }
    _loadingMore = false;
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState,
        ({List<MessageItem> messages, String entityId})>(
        // Only the conversations list + own id matter here; each row's typing/
        // online dot is handled by MessageItemView's own narrowed connector.
        // distinct keeps this list off the rebuild path for presence/typing/
        // notification dispatches - it only rebuilds when the list changes.
        distinct: true,
        builder: (context, state) {
      List<MessageItem> messagesList = state.messages;
      if (!isInitialized) {
        getConversationListProcess(context);
      }

      // The SSE handler re-fetches PAGE 1 and replaces this whole list on every
      // incoming message (sse_events.dart's "messages_list" case), so a list
      // the user had paged into gets truncated under us while `_page` keeps
      // counting up - the next load-more would then ask for page _page+1 and
      // silently skip everything between. A shrunken list means exactly that
      // happened, so the cursor goes back to the start. Plain field writes, not
      // setState: nothing on screen depends on them until the next scroll.
      if (messagesList.length < _lastCount) {
        _page = 1;
        // A full page back means there is probably more behind it; a partial
        // one is the whole list. Guessing high is safe now that paging is
        // silent - a wrong guess costs one request and no visible loader.
        _hasMore = messagesList.length >= _kPageSize;
      }
      _lastCount = messagesList.length;
      return Scaffold(
        backgroundColor: p.bg,
        body: Column(
          children: [
            // Create Group Chat is not functional yet (no group-creation
            // flow/screen exists) - commented out rather than left visible
            // and disabled, until that flow is built.
            // Padding(
            //   padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            //   child: Row(
            //     children: [
            //       CLChip(
            //           label: "Create Group Chat",
            //           icon: Icons.people_alt_outlined,
            //           onTap: null),
            //     ],
            //   ),
            // ),
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: !isInitialized
                    ? const Padding(
                        key: ValueKey('loading'),
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: CLListSkeleton(),
                      )
                    : messagesList.isEmpty
                        // Scrollable even when empty, so pull-to-refresh is a
                        // way to retry a load that came back with nothing.
                        ? RefreshIndicator(
                            key: const ValueKey('empty'),
                            onRefresh: () =>
                                getConversationListProcess(context),
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.22),
                                Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: CLEmptyState(
                                    icon: Icons.forum,
                                    iconBg: p.surface2,
                                    iconColor: p.text2,
                                    iconBorderColor: p.border,
                                    title: "No conversations yet",
                                    subtitle:
                                        "Search for people to start one.",
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            key: const ValueKey('list'),
                            onRefresh: () =>
                                getConversationListProcess(context),
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (n) {
                                if (n.metrics.pixels >=
                                    n.metrics.maxScrollExtent - 240) {
                                  _loadMore(context);
                                }
                                return false;
                              },
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                itemCount: messagesList.length,
                                itemBuilder: (context, index) => MessageItemView(
                                    message: messagesList[index],
                                    userID: state.entityId),
                              ),
                            ),
                          ),
              ),
            ),
          ],
        ),
      );
    }, converter: (store) => (
          messages: store.state.messages,
          entityId: store.state.userAuth.user.entityId,
        ));
  }
}
