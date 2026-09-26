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
import 'package:chatterloop_app/views/moments/thoughts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

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

  /// The Thoughts rail, so pull-to-refresh can reload it with the list.
  final _railKey = GlobalKey<ThoughtsRailViewState>();

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

  /// Pull-to-refresh: the conversations and the thoughts above them together,
  /// so the spinner stays up until both are current.
  Future<void> _refresh(BuildContext context) => Future.wait([
        getConversationListProcess(context),
        _railKey.currentState?.refresh() ?? Future<void>.value(),
      ]);

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

  /// Pick someone and land in the thread.
  ///
  /// Both of these are ROUTER routes, pushed by location rather than as
  /// imperative MaterialPageRoutes - a screen pushed outside go_router's stack
  /// cannot then navigate within it, which is exactly what picking somebody
  /// has to do.
  ///
  /// Nothing to refresh on the way back: that screen pushes the conversation
  /// on top of itself, so returning here means the user left without starting
  /// one - and if they did start one, the conversation itself brings the list
  /// up to date over SSE.
  void _openNewMessage(BuildContext context) => context.push('/new-message');

  /// The group-chat form.
  ///
  /// Refreshes on return, because /u/createContactGroupChat answers with
  /// {status, message} and no conversationID. The new conversation does reach
  /// the client on its own over SSE, but only while this screen is mounted and
  /// listening - and it was not, it was under the create form - so waiting for
  /// that leaves the list looking like nothing happened.
  Future<void> _openCreateGroup(BuildContext context) async {
    final created = await context.push<bool>('/new-group-chat');
    if (!mounted || created != true) return;
    if (context.mounted) await getConversationListProcess(context);
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
            // ONE scroll view for the whole screen, so a pull anywhere on it
            // refreshes - list and thoughts both - and the spinner comes down
            // from the top of the screen. It used to start under the thoughts,
            // where the list began, and reloaded the list only. The actions
            // and the rail scroll away with the conversations as a result.
            body: RefreshIndicator(
              onRefresh: () => _refresh(context),
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  // depth 0 is this screen's own scroll. The rail's sideways
                  // one reports from deeper, and must not page the list.
                  if (n.depth == 0 &&
                      n.metrics.pixels >= n.metrics.maxScrollExtent - 240) {
                    _loadMore(context);
                  }
                  return false;
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child:
                          // The two ways to start something, above the list rather than
                          // behind a floating button: web puts Create Group in the Messages
                          // header, and on a phone the header is already carrying the tab
                          // bar. Side by side and equal width because neither is the
                          // secondary one - a DM and a group chat are both just "a new
                          // conversation".
                          //
                          // md, not sm: these are the screen's primary actions sitting above
                          // a list of 60px rows, and at 32px they read as a filter chip
                          // rather than something to press. The labels ellipsise if a narrow
                          // device cannot fit them at this size (see CLBtn).
                          //
                          // softStrong, not soft and not primary. Two solid blue buttons
                          // out-shout the list they sit above - the inbox is the screen, and
                          // these only start something. But plain `soft` is #E7F0FE in LIGHT
                          // mode, near enough to white to read as disabled. softStrong is
                          // exactly `soft` in dark, where the tint already worked, and a
                          // deeper fill in light, where it did not.
                          Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: CLBtn(
                                label: "Write message",
                                iconL: Icons.edit_square,
                                variant: CLBtnVariant.softStrong,
                                size: CLBtnSize.md,
                                // One step down from md's own CLType.title, which is
                                // the size a conversation NAME is drawn at below - a
                                // button louder than the list it introduces is the wrong
                                // way round. Height stays at md.
                                labelSize: CLType.bodySm,
                                block: true,
                                onPressed: () => _openNewMessage(context),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: CLBtn(
                                label: "Create group",
                                iconL: Icons.group_add,
                                variant: CLBtnVariant.softStrong,
                                size: CLBtnSize.md,
                                // One step down from md's own CLType.title, which is
                                // the size a conversation NAME is drawn at below - a
                                // button louder than the list it introduces is the wrong
                                // way round. Height stays at md.
                                labelSize: CLType.bodySm,
                                block: true,
                                onPressed: () => _openCreateGroup(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Thoughts, under the screen's actions and just above the
                    // conversations - where web puts it (below search and the
                    // list filters). No divider under it.
                    SliverToBoxAdapter(
                      child: Padding(
                        // A little air between the thoughts and the conversations.
                        padding: const EdgeInsets.only(top: 4, bottom: 10),
                        child: ThoughtsRailView(key: _railKey),
                      ),
                    ),
                    if (!isInitialized)
                      const SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        sliver: SliverToBoxAdapter(child: CLListSkeleton()),
                      )
                    else if (messagesList.isEmpty)
                      // The pull still works here, so it is a way to retry a
                      // load that came back with nothing.
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                              24,
                              MediaQuery.of(context).size.height * 0.22 + 24,
                              24,
                              24),
                          child: CLEmptyState(
                            icon: Icons.forum,
                            iconBg: p.surface2,
                            iconColor: p.text2,
                            iconBorderColor: p.border,
                            title: "No conversations yet",
                            subtitle: "Search for people to start one.",
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        sliver: SliverList.builder(
                          itemCount: messagesList.length,
                          itemBuilder: (context, index) => MessageItemView(
                              message: messagesList[index],
                              userID: state.entityId),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
        converter: (store) => (
              messages: store.state.messages,
              entityId: store.state.userAuth.user.entityId,
            ));
  }
}
