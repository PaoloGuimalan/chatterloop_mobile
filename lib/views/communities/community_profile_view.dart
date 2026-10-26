import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_composer.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_item.dart';
import 'package:chatterloop_app/core/utils/post_updates.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/views/profile/widgets/profile_header.dart';
import 'community_widgets.dart';

class CommunityProfileView extends StatefulWidget {
  final String id;
  final CommunityApi? api;
  const CommunityProfileView({super.key, required this.id, this.api});
  @override
  State<CommunityProfileView> createState() => _CommunityProfileViewState();
}

class _CommunityProfileViewState extends State<CommunityProfileView>
    with WidgetsBindingObserver {
  late final _api = widget.api ?? CommunityApi();
  Community? _community;
  final _posts = <PostPreview>[];
  final _members = <RealmPerson>[];
  bool _loading = true, _busy = false, _next = false;
  String? _error;
  int _page = 1, _generation = 0;
  int _section = 0;
  StreamSubscription? _identitySubscription;
  late String _actor;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _actor = appStore.state.userAuth.user.entityId;
    _identitySubscription = appStore.onChange.listen((_) {
      final actor = appStore.state.userAuth.user.entityId;
      if (actor != _actor) {
        _actor = actor;
        _load();
      }
    });
    communityChanges.addListener(_changed);
    _load();
  }

  void _changed() {
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    _identitySubscription?.cancel();
    communityChanges.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    final generation = ++_generation;
    final actor = _actor;
    setState(() {
      _loading = true;
      _error = null;
      if (page == 1) {
        _posts.clear();
        _members.clear();
        _community = null;
      }
    });
    try {
      final community = await _api.detail(widget.id);
      if (!mounted || generation != _generation || actor != _actor) return;
      final canRead = !community.isPrivate || community.isMember;
      final posts =
          canRead ? await _api.posts(community.realmId, page: page) : null;
      final members = page == 1 && community.isMember
          ? await _api.members(community.realmId)
          : null;
      if (!mounted || generation != _generation || actor != _actor) return;
      setState(() {
        _community = community;
        if (posts != null) {
          _posts.addAll(posts.results.where(
              (post) => !_posts.any((old) => old.postId == post.postId)));
          _next = posts.hasNext;
        } else {
          _posts.clear();
          _next = false;
        }
        if (members != null) _members.addAll(members.results);
        _page = page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      PostUpdates.instance.clear();
      setState(() {
        _posts.clear();
        _members.clear();
        _community = null;
        _loading = false;
        _error =
            e is DioException && [403, 404].contains(e.response?.statusCode)
                ? 'This community is unavailable or your access has changed.'
                : 'Could not load community.';
      });
    }
  }

  Future<void> _membership() async {
    if (_busy || _community == null) return;
    final community = _community!;
    final actor = _actor;
    setState(() => _busy = true);
    try {
      final token = await ApiClient.instance.readToken();
      if (!mounted || actor != _actor) return;
      final api = widget.api ?? CommunityApi(authToken: token);
      if (community.isMember || community.requestPending) {
        await api.leave(community.realmId);
      } else {
        await api.join(community.realmId);
      }
      if (!mounted || actor != _actor) return;
      PostUpdates.instance.clear();
      await _load();
    } catch (e) {
      if (mounted && actor == _actor) {
        setState(() => _error = e is DioException &&
                e.response?.statusCode == 400
            ? 'Transfer ownership through Manage Realm before leaving this community.'
            : 'Could not update membership. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildActions(Community community) {
    final canManage =
        ['owner', 'admin', 'moderator'].contains(community.myRole);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: LayoutBuilder(builder: (context, constraints) {
        final columns = canManage &&
            constraints.maxWidth >= 320 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.3;
        final width =
            columns ? (constraints.maxWidth - 8) / 2 : constraints.maxWidth;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          SizedBox(
              width: width,
              child: CLBtn(
                label: _busy
                    ? 'Updating…'
                    : community.isMember
                        ? 'Leave community'
                        : community.requestPending
                            ? 'Cancel request'
                            : community.isPrivate
                                ? 'Request to join'
                                : 'Join community',
                labelSize: CLType.label,
                variant: community.isMember || community.requestPending
                    ? CLBtnVariant.outline
                    : CLBtnVariant.primary,
                onPressed: _busy ? null : _membership,
              )),
          if (canManage)
            SizedBox(
                width: width,
                child: CLBtn(
                  label: 'Manage Realm',
                  labelSize: CLType.label,
                  iconL: Icons.tune,
                  variant: CLBtnVariant.outline,
                  onPressed: () async {
                    await context.push(
                        '/realm/${Uri.encodeComponent(community.realmId)}/manage');
                    if (mounted) _load();
                  },
                )),
        ]);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context), community = _community;
    return CLScreen(
        backgroundColor: p.bg,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () => context.pop(),
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.surface,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 6)
                  ],
                ),
                child: Icon(Icons.arrow_back, size: 18, color: p.text),
              ),
            )),
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
                padding: EdgeInsets.zero,
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_loading && community == null)
                    const ProfileHeaderSkeleton(),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.all(14),
                        child: CLCard(
                            child: Column(children: [
                          Text(_error!,
                              style: TextStyle(
                                  fontSize: CLType.body, color: p.text2)),
                          TextButton(
                              onPressed: _load,
                              child: const Text('Retry',
                                  style: TextStyle(fontSize: CLType.label)))
                        ]))),
                  if (community != null) ...[
                    ColoredBox(
                        color: p.surface,
                        child: Column(children: [
                          ProfileHeader(
                              id: community.realmId,
                              displayName: community.name,
                              username: community.slug ?? '',
                              avatarSrc: community.profile,
                              coverSrc: community.coverPhoto,
                              isBadged: community.isVerified,
                              isPrivate: community.isPrivate,
                              type: 'community',
                              actions: _buildActions(community)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Column(children: [
                              Text(
                                  '${community.isPrivate ? 'Private' : 'Public'} community · ${community.memberCount ?? 0} members',
                                  style: TextStyle(
                                      fontSize: CLType.caption,
                                      color: p.text2)),
                              const SizedBox(height: 6),
                              Text(community.description,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: CLType.body,
                                      color: p.text2,
                                      height: 1.45)),
                              const SizedBox(height: 8),
                              CommunitySectionTabs(
                                  labels: const ['Posts', 'About', 'Members'],
                                  selected: _section,
                                  onSelected: (value) =>
                                      setState(() => _section = value)),
                            ]),
                          ),
                        ])),
                    if (_section != 1 &&
                        community.isPrivate &&
                        !community.isMember)
                      const Padding(
                          padding: EdgeInsets.all(14),
                          child: CLCard(
                              child: Column(children: [
                            Icon(Icons.lock_outline, size: 32),
                            SizedBox(height: 10),
                            Text('This community is private',
                                style: TextStyle(
                                    fontSize: CLType.sectionTitle,
                                    fontWeight: FontWeight.w700)),
                            SizedBox(height: 6),
                            Text('Join to see posts and members.',
                                style: TextStyle(fontSize: CLType.body))
                          ]))),
                    if (_section == 1)
                      Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          child: CLCard(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                const Text('About this community',
                                    style: TextStyle(
                                        fontSize: CLType.sectionTitle,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 10),
                                Text(community.description,
                                    style: TextStyle(
                                        fontSize: CLType.body, color: p.text2)),
                                const SizedBox(height: 12),
                                Text(
                                    '${community.isPrivate ? 'Private' : 'Public'} community · ${community.memberCount ?? 0} members',
                                    style: TextStyle(
                                        fontSize: CLType.caption,
                                        color: p.text2))
                              ]))),
                    if (_section == 2 &&
                        (!community.isPrivate || community.isMember))
                      Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          child: CLCard(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                const Text('Members',
                                    style: TextStyle(
                                        fontSize: CLType.title,
                                        fontWeight: FontWeight.w700)),
                                for (final person in _members)
                                  Material(
                                      color: Colors.transparent,
                                      child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: CLAvatar(
                                              id: person.entityId,
                                              src: person.profile,
                                              name: person.displayName),
                                          title: Text(person.displayName,
                                              style: TextStyle(
                                                  fontSize: CLType.title,
                                                  color: p.text)),
                                          subtitle: Text(
                                              person.role ?? 'Member',
                                              style: TextStyle(
                                                  fontSize: CLType.caption,
                                                  color: p.text2)))),
                                if (_members.isEmpty)
                                  const Text('Member list is not available.',
                                      style: TextStyle(fontSize: CLType.body))
                              ]))),
                    if (_section == 0 && community.isMember)
                      Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                          child: ProfileComposerCard.forActingEntity(
                            community: community,
                            placeholder:
                                'Share something with ${community.name}…',
                            onPosted: () {
                              if (mounted) _load();
                            },
                          )),
                    if (_section == 0)
                      for (final post in _posts)
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: PostItem(
                                post: post,
                                onChanged: (updated) => setState(() {
                                      final i = _posts.indexWhere(
                                          (p) => p.postId == updated.postId);
                                      if (i >= 0) _posts[i] = updated;
                                    }),
                                onDeleted: () => setState(() =>
                                    _posts.removeWhere(
                                        (p) => p.postId == post.postId)))),
                    if (_section == 0 && _next && !_loading)
                      TextButton(
                          onPressed: () => _load(page: _page + 1),
                          child: const Text('Load more',
                              style: TextStyle(fontSize: CLType.label))),
                  ],
                  const SizedBox(height: 20),
                ])));
  }
}
