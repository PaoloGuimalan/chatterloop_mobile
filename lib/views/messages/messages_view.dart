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

class MessagesStateView extends State<MessagesView> {
  bool isInitialized = false;
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  Future<void> getConversationListProcess(BuildContext context) async {
    final res = await ConversationsApi().getConversationListRequest();

    if (!mounted) return;
    if (res != null) {
      setState(() {
        isInitialized = true;
        _page = 1;
        _hasMore = res.next != null;
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
  Future<void> _loadMore(BuildContext context) async {
    if (!_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    final store = StoreProvider.of<AppState>(context);
    final res =
        await ConversationsApi().getConversationListRequest(page: _page + 1);
    if (!mounted) return;
    if (res != null) {
      store.dispatch(DispatchModel(
          setMessagesListT, [...store.state.messages, ...res.items]));
      setState(() {
        _page += 1;
        _hasMore = res.next != null;
        _loadingMore = false;
      });
    } else {
      setState(() => _loadingMore = false);
    }
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
                        ? Center(
                            key: const ValueKey('empty'),
                            child: Text(
                                "No conversations yet - search for people to start one.",
                                style: TextStyle(color: p.text2)))
                        : NotificationListener<ScrollNotification>(
                            key: const ValueKey('list'),
                            onNotification: (n) {
                              if (n.metrics.pixels >=
                                  n.metrics.maxScrollExtent - 240) {
                                _loadMore(context);
                              }
                              return false;
                            },
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              itemCount:
                                  messagesList.length + (_loadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= messagesList.length) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                        child: SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))),
                                  );
                                }
                                return MessageItemView(
                                    message: messagesList[index],
                                    userID: state.entityId);
                              },
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
