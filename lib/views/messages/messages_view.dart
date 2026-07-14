// ignore_for_file: use_build_context_synchronously

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
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

  Future<void> getConversationListProcess(BuildContext context) async {
    final res = await ConversationsApi().getConversationListRequest();

    if (res != null) {
      if (!mounted) return;
      setState(() => isInitialized = true);

      StoreProvider.of<AppState>(context)
          .dispatch(DispatchModel(setMessagesListT, res.items));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      List<MessageItem> messagesList = state.messages;
      if (!isInitialized) {
        getConversationListProcess(context);
      }
      return Scaffold(
        backgroundColor: p.bg,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  CLChip(
                      label: "Create Group Chat",
                      icon: Icons.people_alt_outlined,
                      onTap: null),
                ],
              ),
            ),
            Expanded(
              child: messagesList.isEmpty
                  ? Center(
                      child: Text(
                          "No conversations yet - search for people to start one.",
                          style: TextStyle(color: p.text2)))
                  : ListView.builder(
                      key: ValueKey(messagesList.isEmpty
                          ? 0
                          : state.messages
                              .map((message) => message.unread)
                              .reduce((a, b) => a + b)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: messagesList.length,
                      itemBuilder: (context, index) {
                        return MessageItemView(
                            message: messagesList[index],
                            userID: state.userAuth.user.id);
                      },
                    ),
            ),
          ],
        ),
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
