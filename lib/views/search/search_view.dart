import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/requests/search_api.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Timer? _debounce;
  List<SearchResultUser> results = const [];
  bool isSearching = false;
  bool hasSearched = false;
  final _controller = TextEditingController();

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        results = const [];
        hasSearched = false;
      });
      return;
    }
    setState(() => isSearching = true);
    final found = await SearchApi().searchUsersRequest(query);
    if (!mounted) return;
    setState(() {
      results = found;
      isSearching = false;
      hasSearched = true;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  String _statusLabel(SearchResultUser user) {
    if (user.connectionAccomplished) return "Message";
    if (user.hasConnection) return "Pending";
    return "Add";
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: CLField(
                icon: Icons.search,
                placeholder: "Search by name or @username",
                controller: _controller,
                onChanged: _onQueryChanged,
              ),
            ),
            if (isSearching)
              Padding(
                padding: const EdgeInsets.all(12),
                child: CircularProgressIndicator(color: p.brand),
              ),
            if (!isSearching && hasSearched && results.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text("No users found", style: TextStyle(color: p.text2)),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final user = results[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: CLCard(
                      child: Row(
                        children: [
                          CLAvatar(
                              id: user.id,
                              name: user.displayName,
                              src: user.profile,
                              size: 44),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    user.displayName.isEmpty
                                        ? user.username
                                        : user.displayName,
                                    style: TextStyle(
                                        color: p.text,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                                Text("@${user.username}",
                                    style: TextStyle(
                                        color: p.text2, fontSize: 12)),
                              ],
                            ),
                          ),
                          CLBtn(
                            label: _statusLabel(user),
                            size: CLBtnSize.sm,
                            variant: user.connectionAccomplished
                                ? CLBtnVariant.primary
                                : user.hasConnection
                                    ? CLBtnVariant.outline
                                    : CLBtnVariant.soft,
                            onPressed: user.connectionAccomplished
                                ? () {
                                    if (user.connectionId != null) {
                                      context.push(
                                          '/conversation/${user.connectionId}');
                                    }
                                  }
                                : user.hasConnection
                                    ? null
                                    : () => _requestContact(user),
                          ),
                          CLIconBtn(
                            icon: Icons.chevron_right,
                            onPressed: () =>
                                context.push('/user/${user.username}'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestContact(SearchResultUser user) async {
    final ok = await ContactsApi().requestContactRequest(user.id);
    if (!ok || !mounted) return;
    setState(() {
      results = results
          .map((u) => u.id == user.id
              ? SearchResultUser(
                  id: u.id,
                  username: u.username,
                  firstName: u.firstName,
                  middleName: u.middleName,
                  lastName: u.lastName,
                  profile: u.profile,
                  gender: u.gender,
                  hasConnection: true,
                  connectionAccomplished: false,
                  connectionId: u.connectionId,
                  isActionByEntity: true,
                )
              : u)
          .toList();
    });
  }
}
