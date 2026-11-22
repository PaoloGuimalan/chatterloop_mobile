import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/realm_lifecycle_api.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/confirm_dialog.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/models/user_models/realm_lifecycle_model.dart';
import 'realm_private_state.dart';

class RealmLifecycleView extends StatefulWidget {
  final String realmId;
  final RealmLifecycleApi? api;
  const RealmLifecycleView({super.key, required this.realmId, this.api});
  @override
  State<RealmLifecycleView> createState() => _RealmLifecycleViewState();
}

class _RealmLifecycleViewState extends RealmPrivateState<RealmLifecycleView> {
  RealmLifecycle? _data;
  bool _loading = true, _busy = false;
  @override
  void initState() {
    super.initState();
    communityChanges.addListener(reloadPrivate);
    reloadPrivate();
  }

  @override
  void dispose() {
    communityChanges.removeListener(reloadPrivate);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RealmLifecycleView old) {
    super.didUpdateWidget(old);
    if (old.realmId != widget.realmId) reloadPrivate();
  }

  @override
  void reloadPrivate() {
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _data = null;
      _loading = true;
    });
    final ticket = await requestTicket();
    try {
      final data =
          await (widget.api ?? RealmLifecycleApi(authToken: ticket.token))
              .get(widget.realmId);
      if (await isCurrent(ticket)) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (error) {
      if (await isCurrent(ticket)) {
        setState(() => _loading = false);
        CLAlerts.requestError(error,
            fallback: 'Could not load realm settings.');
      }
    }
  }

  Future<void> _submit(bool delete) async {
    final data = _data;
    if (data == null || _busy) return;
    setState(() => _busy = true);
    try {
      final ticket = await requestTicket(invalidate: false);
      if (!mounted) return;
      final confirmed = await showCLConfirm(context,
          title: delete ? 'Delete realm permanently?' : 'Deactivate realm?',
          message: delete
              ? 'Permanently delete ${data.name} and its content? This cannot be undone.'
              : 'Everyone will lose access to ${data.name} until it is reactivated. Data is preserved.',
          confirmLabel: delete ? 'Permanently delete' : 'Deactivate',
          confirmationName: delete ? data.name : null);
      if (!await isCurrent(ticket)) return;
      if (!confirmed) {
        setState(() => _busy = false);
        return;
      }
      try {
        final api = widget.api ?? RealmLifecycleApi(authToken: ticket.token);
        if (delete) {
          await api.delete(widget.realmId, data.name);
        } else {
          await api.deactivate(widget.realmId);
        }
        if (!await isCurrent(ticket)) return;
        CLAlerts.show(
            delete ? 'Deletion started.' : '${data.name} was deactivated.',
            type: CLAlertType.success);
        communityChanges.value++;
        if (mounted)
          context.go(data.returnServerId == null
              ? '/newsfeed'
              : '/server/${Uri.encodeComponent(data.returnServerId!)}');
      } catch (error) {
        if (await isCurrent(ticket)) {
          CLAlerts.requestError(error, fallback: 'Could not update the realm.');
          setState(() => _busy = false);
          reloadPrivate();
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context), data = _data;
    Widget card(String title, String description, Widget action) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: CLCard(
            padding: EdgeInsets.zero,
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: p.text,
                              fontSize: CLType.sectionTitle,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      Text(description,
                          style:
                              TextStyle(color: p.text2, fontSize: CLType.body)),
                      const SizedBox(height: 14),
                      action
                    ]))));
    final children = data?.kind == 'server'
        ? ' This includes ${data!.childCount} channels and voice channels.'
        : '';
    return CLScreen(
        appBar: AppBar(
            leadingWidth: 48,
            titleSpacing: 0,
            title: const Text('Deactivation & deletion')),
        body: ListView(
            padding: const EdgeInsets.all(CLSpacing.contentGutter),
            children: [
              if (_loading)
                for (var i = 0; i < 2; i++)
                  const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: CLSkeleton(width: double.infinity, height: 180)),
              if (!_loading && data == null)
                CLBtn(label: 'Retry', onPressed: reloadPrivate),
              if (data != null) ...[
                if (data.capabilities.allows('can_deactivate_realm'))
                  card(
                      'Deactivate realm',
                      'Hide the realm and its content from everyone, including its owner. Data is preserved.$children Restore it from Settings → Realms → Deactivated Realms.${data.capabilities.allows('can_reactivate_realm') ? '' : ' You cannot currently reactivate this realm; an owner or authorized member must restore it.'}',
                      CLBtn(
                          label: 'Deactivate realm',
                          onPressed: _busy ? null : () => _submit(false))),
                if (data.capabilities.allows('can_delete_realm'))
                  card(
                      'Permanently delete realm',
                      'Permanently remove the realm, its posts, conversations, membership, invitations and settings.$children Shared files and reported evidence follow existing retention rules. This cannot be undone.${data.blockerCount > 0 ? ' Transfer ownership of ${data.blockerCount} other realms first${data.blockers.isEmpty ? '.' : ': ${data.blockers.join(', ')}.'}' : ''}',
                      CLBtn(
                          label: 'Delete realm',
                          variant: CLBtnVariant.danger,
                          onPressed: _busy || data.blockerCount > 0
                              ? null
                              : () => _submit(true))),
              ],
            ]));
  }
}
