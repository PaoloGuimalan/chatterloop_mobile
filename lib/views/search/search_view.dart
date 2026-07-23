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
    // Entity search (v2): people AND pages in one normalized shape.
    final found = await SearchApi().searchEntitiesRequest(query);
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

  (String, CLBadgeTone) _status(SearchResultUser user) {
    // Pages carry no connection state - they are not contact targets from
    // search, so they get a kind label instead of a relationship one.
    if (user.isRealm) return ("Page", CLBadgeTone.brand);
    if (user.connectionAccomplished) return ("Connected", CLBadgeTone.green);
    if (user.hasConnection) return ("Pending", CLBadgeTone.gold);
    return ("New", CLBadgeTone.grey);
  }

  /// Pages live at /realm/:slug, people at /user/:username. `username` holds
  /// the handle for both kinds (v2's `handle`).
  String _profilePath(SearchResultUser user) =>
      user.isRealm ? '/realm/${user.username}' : '/user/${user.username}';

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Scaffold(
      backgroundColor: p.bg,
      // top: false - the shell's global header already reserves the status
      // bar; a second SafeArea here duplicated that inset and produced a
      // large gap under the header.
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: CLField(
                icon: Icons.search,
                placeholder: "Search people and pages",
                controller: _controller,
                onChanged: _onQueryChanged,
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                // Results from the previous query would otherwise stay on
                // screen (stale) while a new search is in flight - showing
                // the skeleton in their place instead makes it clear a
                // fresh search is happening, not that nothing changed.
                child: isSearching
                    ? const Padding(
                        key: ValueKey('loading'),
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: CLListSkeleton(avatarSize: 52, count: 4),
                      )
                    : !hasSearched
                        ? Center(
                            key: const ValueKey('initial'),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: CLEmptyState(
                                icon: Icons.manage_search,
                                iconBg: p.brandSoft,
                                iconColor: p.brand,
                                title: "Search people and pages",
                                subtitle:
                                    "Start typing a name or handle to find people and pages.",
                              ),
                            ),
                          )
                        : results.isEmpty
                            ? Center(
                                key: const ValueKey('empty'),
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: CLEmptyState(
                                    icon: Icons.search_off,
                                    iconBg: p.surface2,
                                    iconColor: p.text2,
                                    iconBorderColor: p.border,
                                    title: "No results found",
                                    subtitle:
                                        "Try a different name or handle.",
                                  ),
                                ),
                              )
                            : ListView.builder(
                                key: const ValueKey('list'),
                                padding:
                                    const EdgeInsets.fromLTRB(14, 0, 14, 14),
                                itemCount: results.length,
                                itemBuilder: (context, index) =>
                                    _resultCard(context, results[index]),
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(BuildContext context, SearchResultUser user) {
    final p = cl(context);
    final (statusLabel, statusTone) = _status(user);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CLCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(CLRadii.pill),
              onTap: () => context.push(_profilePath(user)),
              child: CLAvatar(
                  id: user.id,
                  name: user.displayName,
                  src: user.profile,
                  size: 52),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () => context.push(_profilePath(user)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                              user.displayName.isEmpty
                                  ? user.username
                                  : user.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15)),
                        ),
                        const SizedBox(width: 8),
                        CLBadge(label: statusLabel, tone: statusTone),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text("@${user.username}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.text2, fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (user.isRealm)
              // Pages are not connection targets from search - open the page
              // and follow / add from there.
              CLBtn(
                label: "View page",
                size: CLBtnSize.sm,
                variant: CLBtnVariant.outline,
                onPressed: () => context.push(_profilePath(user)),
              )
            else if (user.connectionAccomplished)
              CLBtn(
                label: "Message",
                size: CLBtnSize.sm,
                variant: CLBtnVariant.outline,
                onPressed: user.connectionId != null
                    ? () => context.push('/conversation/${user.connectionId}')
                    : null,
              )
            else if (!user.hasConnection)
              CLBtn(
                label: "Add",
                iconL: Icons.person_add_alt,
                size: CLBtnSize.sm,
                variant: CLBtnVariant.soft,
                onPressed: () => _requestContact(user),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestContact(SearchResultUser user) async {
    final ok = await ContactsApi().requestContactRequest(user.entityId);
    if (!ok || !mounted) return;
    setState(() {
      results = results
          .map((u) => u.id == user.id
              ? SearchResultUser(
                  id: u.id,
                  entityId: u.entityId,
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
                  type: u.type,
                  realmType: u.realmType,
                )
              : u)
          .toList();
    });
  }
}
