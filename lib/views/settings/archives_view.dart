// Archives settings section - mobile counterpart of webapp's
// ArchivedMessages.tsx. Lists the user's archived conversations
// (GET /m/archives) with the same card as the Messages list (MessageItemView,
// which opens the conversation on tap - where it can be Unarchived from the
// conversation menu). Paginates with the same scroll-to-load-more as the
// Messages/Contacts tabs.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/message_item.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:flutter/material.dart';

class ArchivesScreen extends StatefulWidget {
  const ArchivesScreen({super.key});

  @override
  State<ArchivesScreen> createState() => _ArchivesScreenState();
}

class _ArchivesScreenState extends State<ArchivesScreen> {
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = false;
  int _page = 1;
  List<MessageItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ConversationsApi().getArchivesRequest(
        myEntityId: appStore.state.userAuth.user.entityId, page: 1);
    if (!mounted) return;
    setState(() {
      _items = res?.items ?? const [];
      _hasNext = res?.hasNext ?? false;
      _page = 1;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (!_hasNext || _loadingMore) return;
    setState(() => _loadingMore = true);
    final res = await ConversationsApi().getArchivesRequest(
        myEntityId: appStore.state.userAuth.user.entityId, page: _page + 1);
    if (!mounted) return;
    setState(() {
      if (res != null) {
        _items = [..._items, ...res.items];
        _page += 1;
        _hasNext = res.hasNext;
      }
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final userID = appStore.state.userAuth.user.entityId;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text('Archives')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: p.brand))
          : _items.isEmpty
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                      Center(
                        child: Text('No archived conversations.',
                            style: TextStyle(color: p.text2)),
                      ),
                    ],
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 240) {
                      _loadMore();
                    }
                    return false;
                  },
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: _items.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _items.length) {
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
                            message: _items[index], userID: userID);
                      },
                    ),
                  ),
                ),
    );
  }
}
