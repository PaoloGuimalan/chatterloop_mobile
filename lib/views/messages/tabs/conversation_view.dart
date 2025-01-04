import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/models/view_prop_models/conversation_view_props.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class ConversationView extends StatefulWidget {
  // final MessageItem conversationMetaData;

  const ConversationView({super.key});

  @override
  ConversationStateView createState() => ConversationStateView();
}

class ConversationStateView extends State<ConversationView> {
  // late MessageItem _conversationMetaData;

  int range = 10;

  @override
  void initState() {
    super.initState();
    // _conversationMetaData = widget.conversationMetaData;
  }

  @override
  Widget build(BuildContext context) {
    final ConversationViewProps conversationMetaData =
        ModalRoute.of(context)?.settings.arguments as ConversationViewProps;
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
                "Conversation: ${conversationMetaData.conversationID} | Type: ${conversationMetaData.conversationType}"),
          ),
        ),
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
