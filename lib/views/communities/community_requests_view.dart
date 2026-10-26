import 'dart:async';
import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/requests/invites_api.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/models/user_models/realm_invite_model.dart';

/// Join requests use the existing realm invite lifecycle and role checks.
class CommunityRequestsView extends StatefulWidget {
  final String realmId;
  const CommunityRequestsView({super.key, required this.realmId});
  @override
  State<CommunityRequestsView> createState() => _CommunityRequestsViewState();
}

class _CommunityRequestsViewState extends State<CommunityRequestsView> {
  List<RealmInvite> _requests = [];
  bool _loading = true;
  String? _busy;
  int _generation = 0;
  StreamSubscription? _subscription;
  late String _actor;
  @override
  void initState() {
    super.initState();
    _actor = appStore.state.userAuth.user.entityId;
    communityChanges.addListener(_load);
    _subscription = appStore.onChange.listen((_) {
      if (_actor != appStore.state.userAuth.user.entityId) {
        _actor = appStore.state.userAuth.user.entityId;
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    communityChanges.removeListener(_load);
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _requests = [];
    });
    final requests =
        await InvitesApi().pending(widget.realmId, kind: 'request');
    if (!mounted || generation != _generation) return;
    setState(() {
      _requests = requests;
      _loading = false;
    });
  }

  Future<void> _answer(RealmInvite invite, String status) async {
    if (_busy != null) return;
    final actor = _actor;
    setState(() => _busy = invite.id);
    final settled = await InvitesApi().answer(invite.token, status);
    if (!mounted || actor != _actor) return;
    setState(() => _busy = null);
    if (settled != null) {
      communityChanges.value++;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: cl(context).bg,
      appBar: AppBar(
          leadingWidth: 48,
          titleSpacing: 0,
          title: const Text('Join requests')),
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(14), children: [
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (!_loading && _requests.isEmpty)
              const CLSectionEmpty(
                  icon: Icons.check_circle_outline,
                  title: 'You’re all caught up',
                  subtitle: 'No pending join requests.'),
            for (final invite in _requests)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CLCard(
                      child: Row(children: [
                    CLAvatar(
                        size: 32,
                        id: invite.targetEntity?.id,
                        src: invite.targetEntity?.profile,
                        name: invite.targetEntity?.name),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            invite.targetEntity?.name ??
                                invite.targetEmail ??
                                'Member',
                            style: const TextStyle(
                                fontSize: CLType.title,
                                fontWeight: FontWeight.w600))),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Approve',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                          backgroundColor: cl(context).brandSoft,
                          foregroundColor: cl(context).brand),
                      onPressed: _busy != null
                          ? null
                          : () => _answer(invite, 'accepted'),
                      icon: const Icon(Icons.check, size: 18),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Decline',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                          backgroundColor: cl(context).surface2,
                          foregroundColor: cl(context).text2),
                      onPressed: _busy != null
                          ? null
                          : () => _answer(invite, 'declined'),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ]))),
          ])));
}
