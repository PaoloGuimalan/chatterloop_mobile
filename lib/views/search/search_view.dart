import 'dart:async';

import 'package:chatterloop_app/core/design/app_colors.dart';
import 'package:chatterloop_app/core/design/app_text_field.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
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
    final found = await APIRequests().searchUsersRequest(query);
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
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        title: Text("Search", style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(12),
            child: AppTextField(
                hint: "Search by name or @username",
                onChanged: _onQueryChanged),
          ),
          if (isSearching)
            Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator()),
          if (!isSearching && hasSearched && results.isEmpty)
            Padding(
              padding: EdgeInsets.all(20),
              child: Text("No users found",
                  style: TextStyle(color: AppColors.textPrimary)),
            ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: 12),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final user = results[index];
                return Container(
                  margin: EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      ClipOval(
                        child: Container(
                          width: 44,
                          height: 44,
                          color: AppColors.border,
                          child: user.profile != null &&
                                  user.profile!.isNotEmpty
                              ? Image.network(user.profile!, fit: BoxFit.cover)
                              : Icon(Icons.person,
                                  color: AppColors.textPrimary),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                user.displayName.isEmpty
                                    ? user.username
                                    : user.displayName,
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            Text("@${user.username}",
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: user.connectionAccomplished
                            ? () {
                                if (user.connectionId != null) {
                                  context.push(
                                      '/conversation/${user.connectionId}');
                                }
                              }
                            : user.hasConnection
                                ? null
                                : () async {
                                    final ok = await APIRequests()
                                        .requestContactRequest(user.id);
                                    if (ok && mounted) {
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
                                                    connectionAccomplished:
                                                        false,
                                                    connectionId:
                                                        u.connectionId,
                                                    isActionByEntity: true,
                                                  )
                                                : u)
                                            .toList();
                                      });
                                    }
                                  },
                        child: Text(_statusLabel(user)),
                      ),
                      IconButton(
                        icon: Icon(Icons.chevron_right,
                            color: AppColors.textPrimary),
                        onPressed: () => context.push('/user/${user.username}'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
