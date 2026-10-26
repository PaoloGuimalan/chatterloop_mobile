import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'community_widgets.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';

/// A pushed destination: deliberately owns its Scaffold outside the tab shell.
class CommunitiesView extends StatefulWidget {
  final CommunityApi? api;
  const CommunitiesView({super.key, this.api});
  @override
  State<CommunitiesView> createState() => _CommunitiesViewState();
}

class _CommunitiesViewState extends State<CommunitiesView>
    with WidgetsBindingObserver {
  late final _api = widget.api ?? CommunityApi();
  final _search = TextEditingController();
  final _items = <Community>[];
  Timer? _debounce;
  StreamSubscription? _identitySubscription;
  late String _actor;
  bool _joined = false, _loading = true, _failed = false, _next = false;
  int _page = 1, _generation = 0;
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
    communityChanges.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _identitySubscription?.cancel();
    communityChanges.removeListener(_load);
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load({int page = 1}) async {
    final generation = ++_generation;
    final actor = appStore.state.userAuth.user.entityId;
    setState(() {
      _loading = true;
      _failed = false;
      if (page == 1) _items.clear();
    });
    try {
      final result = await _api.discover(
          search: _search.text.trim(), joined: _joined, page: page);
      if (!mounted ||
          generation != _generation ||
          actor != appStore.state.userAuth.user.entityId) {
        return;
      }
      setState(() {
        _items.addAll(result.results
            .where((c) => !_items.any((old) => old.realmId == c.realmId)));
        _next = result.hasNext;
        _page = page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      CLAlerts.requestError(e, fallback: 'Could not load communities.');
      setState(() {
        _items.clear();
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
            leadingWidth: 48,
            titleSpacing: 0,
            title: const Text('Communities')),
        body: RefreshIndicator(
            onRefresh: () => _load(),
            child: ListView(padding: const EdgeInsets.all(14), children: [
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _search,
                        style: TextStyle(fontSize: CLType.title, color: p.text),
                        decoration: InputDecoration(
                            constraints:
                                const BoxConstraints.tightFor(height: 38),
                            isDense: true,
                            prefixIconConstraints: const BoxConstraints(
                                minWidth: 38, minHeight: 38),
                            hintText: 'Search communities',
                            hintStyle: TextStyle(
                                fontSize: CLType.caption, color: p.text3),
                            prefixIcon: const Icon(Icons.search, size: 20),
                            filled: true,
                            fillColor: p.surface,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(CLRadii.sm),
                                borderSide: BorderSide(color: p.border)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(CLRadii.sm),
                                borderSide: BorderSide(color: p.border))),
                        onChanged: (_) {
                          _debounce?.cancel();
                          _debounce =
                              Timer(const Duration(milliseconds: 350), _load);
                        })),
                const SizedBox(width: 10),
                CLBtn(
                    onPressed: () async {
                      await context.push('/communities/create');
                      if (mounted) _load();
                    },
                    iconL: Icons.add,
                    labelSize: CLType.label,
                    label: 'Create')
              ]),
              const SizedBox(height: 12),
              CommunitySectionTabs(
                labels: const ['Discover', 'Your communities'],
                selected: _joined ? 1 : 0,
                onSelected: (index) {
                  setState(() => _joined = index == 1);
                  _load();
                },
              ),
              const SizedBox(height: 16),
              if (_failed)
                CLCard(
                    child: Column(children: [
                  TextButton(
                      onPressed: _load,
                      child: const Text('Retry',
                          style: TextStyle(fontSize: CLType.label)))
                ])),
              LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth >= 340 &&
                        MediaQuery.textScalerOf(context).scale(1) <= 1.3
                    ? 2
                    : 1;
                return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: columns == 2 ? 0.84 : 1.4),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final community = _items[index];
                      return CommunityDirectoryCard(
                        community: community,
                        onOpen: () async {
                          await context.push(
                              '/communities/${Uri.encodeComponent(community.realmId)}');
                          if (mounted) _load();
                        },
                      );
                    });
              }),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (!_loading && !_failed && _items.isEmpty)
                const CLSectionEmpty(
                    icon: Icons.groups_outlined,
                    title: 'No communities found',
                    subtitle:
                        'Try another search or discover a community to join.'),
              if (_next && !_loading)
                TextButton(
                    onPressed: () => _load(page: _page + 1),
                    child: const Text('Load more',
                        style: TextStyle(fontSize: CLType.label))),
            ])));
  }
}
