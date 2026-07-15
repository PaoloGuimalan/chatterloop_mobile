// Read-only profile screen for whichever page/realm entity the account is
// currently acting as - reached by tapping the top-bar avatar while
// switched (see home_tab_scaffold.dart). Reuses the same ProfileHeader
// hero webapp's RealmProfile.tsx conceptually mirrors (cover + avatar +
// name/@slug), minus the post feed and Follow/Manage actions - those need
// their own endpoints/screens this pass doesn't build yet.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/views/profile/widgets/profile_header.dart';
import 'package:flutter/material.dart';

class RealmProfileScreen extends StatefulWidget {
  final String slug;
  const RealmProfileScreen({super.key, required this.slug});

  @override
  State<RealmProfileScreen> createState() => _RealmProfileScreenState();
}

class _RealmProfileScreenState extends State<RealmProfileScreen> {
  RealmProfile? _realm;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await ProfileApi().getRealmProfileRequest(widget.slug);
    if (!mounted) return;
    setState(() {
      _realm = result;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(title: Text(_realm?.name ?? "Page")),
      body: _isLoading
          ? const SingleChildScrollView(child: ProfileHeaderSkeleton())
          : _realm == null
              ? Center(
                  child: Text("Couldn't load this page.",
                      style: TextStyle(color: p.text2)))
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      ProfileHeader(
                        id: _realm!.id,
                        displayName: _realm!.name,
                        username: _realm!.slug ?? _realm!.id,
                        avatarSrc: _realm!.profile,
                        coverSrc: _realm!.coverPhoto,
                        actions: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: CLCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_realm!.description != null &&
                                    _realm!.description!.isNotEmpty) ...[
                                  Text(_realm!.description!,
                                      style: TextStyle(
                                          color: p.text, fontSize: 14)),
                                  const SizedBox(height: 8),
                                ],
                                Row(
                                  children: [
                                    Icon(Icons.people_alt_outlined,
                                        size: 18, color: p.text2),
                                    const SizedBox(width: 8),
                                    Text(
                                        "${_realm!.followersCount} follower${_realm!.followersCount == 1 ? '' : 's'}",
                                        style: TextStyle(
                                            color: p.text,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
