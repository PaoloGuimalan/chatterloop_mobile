import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/realm_lifecycle_api.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/models/user_models/realm_lifecycle_model.dart';
import 'package:chatterloop_app/views/realm/realm_private_state.dart';

class DeactivatedRealmsView extends StatefulWidget {
  final RealmLifecycleApi? api;
  const DeactivatedRealmsView({super.key, this.api});
  @override
  State<DeactivatedRealmsView> createState() => _DeactivatedRealmsViewState();
}

class _DeactivatedRealmsViewState
    extends RealmPrivateState<DeactivatedRealmsView> {
  List<RecoveryRealm> _rows = [];
  final _actors = <String, String>{};
  bool _loading = true, _failed = false, _pending = false;
  String? _next, _busy;
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
  void reloadPrivate() {
    _load();
  }

  Future<void> _load({bool more = false}) async {
    final cursor = more ? _next : null;
    setState(() {
      _loading = true;
      _failed = false;
      if (!more) {
        _rows = [];
        _actors.clear();
        _next = null;
      }
    });
    final ticket = await requestTicket();
    try {
      final result =
          await (widget.api ?? RealmLifecycleApi(authToken: ticket.token))
              .deactivated(cursor: cursor);
      if (!await isCurrent(ticket)) return;
      setState(() {
        _rows = {
          for (final row in [..._rows, ...result.items]) row.id: row
        }.values.toList();
        _next = result.nextCursor;
        _loading = false;
      });
    } catch (error) {
      if (await isCurrent(ticket)) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        CLAlerts.requestError(error,
            fallback: 'Could not load deactivated realms.');
      }
    }
  }

  Future<void> _restore(RecoveryRealm row) async {
    if (_pending || row.blockedByParent || row.actors.isEmpty) return;
    _pending = true;
    setState(() => _busy = row.id);
    final ticket = await requestTicket(invalidate: false);
    try {
      await (widget.api ?? RealmLifecycleApi(authToken: ticket.token))
          .reactivate(row.id, _actors[row.id] ?? row.actors.first.id);
      if (!await isCurrent(ticket)) return;
      setState(() => _rows.removeWhere((r) => r.id == row.id));
      CLAlerts.show('${row.name} was reactivated.', type: CLAlertType.success);
      communityChanges.value++;
    } catch (error) {
      if (await isCurrent(ticket)) {
        CLAlerts.requestError(error,
            fallback: 'Could not reactivate the realm.');
        reloadPrivate();
      }
    } finally {
      _pending = false;
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return CLScreen(
        appBar: AppBar(
            leadingWidth: 48,
            titleSpacing: 0,
            title: const Text('Deactivated Realms')),
        body: ListView(
            padding: const EdgeInsets.all(CLSpacing.contentGutter),
            children: [
              Text(
                  'Realms you can restore through your profile or an authorized page. Reactivating does not switch your profile.',
                  style: TextStyle(color: p.text2, fontSize: CLType.body)),
              const SizedBox(height: 16),
              for (final row in _rows)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CLCard(
                        padding: EdgeInsets.zero,
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CLAvatar(
                                      id: row.id,
                                      name: row.name,
                                      src: row.profile,
                                      size: 42),
                                  const SizedBox(height: 10),
                                  Text(row.name,
                                      style: TextStyle(
                                          color: p.text,
                                          fontSize: CLType.title,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text('${row.kind} · Deactivated',
                                      style: TextStyle(
                                          color: p.text2,
                                          fontSize: CLType.caption)),
                                  if (row.blockedByParent) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                        row.parentRecoveryId != null
                                            ? 'Reactivate the parent server from this list first.'
                                            : 'The parent server must be restored by its owner or an authorized member first.',
                                        style: TextStyle(
                                            color: p.text2,
                                            fontSize: CLType.bodySm))
                                  ],
                                  const SizedBox(height: 12),
                                  if (row.deactivatedAt != null)
                                    Text(
                                        MaterialLocalizations.of(context)
                                            .formatMediumDate(
                                                row.deactivatedAt!.toLocal()),
                                        style: TextStyle(
                                            color: p.text2,
                                            fontSize: CLType.caption)),
                                  if (row.actors.length > 1)
                                    DropdownButtonFormField<String>(
                                        initialValue: _actors[row.id] ??
                                            row.actors.first.id,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                            labelText: 'Reactivate as'),
                                        items: row.actors
                                            .map((actor) => DropdownMenuItem(
                                                value: actor.id,
                                                child: Text(actor.name,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize:
                                                            CLType.body))))
                                            .toList(),
                                        onChanged: _busy != null || _loading
                                            ? null
                                            : (value) {
                                                if (value != null) {
                                                  setState(() =>
                                                      _actors[row.id] = value);
                                                }
                                              })
                                  else
                                    Text(
                                        'As ${row.actors.isEmpty ? '—' : row.actors.first.name}',
                                        style: TextStyle(
                                            color: p.text2,
                                            fontSize: CLType.bodySm)),
                                  const SizedBox(height: 12),
                                  CLBtn(
                                      label: _busy == row.id
                                          ? 'Reactivating…'
                                          : 'Reactivate',
                                      onPressed: _loading ||
                                              _pending ||
                                              row.blockedByParent ||
                                              row.actors.isEmpty
                                          ? null
                                          : () => _restore(row)),
                                ])))),
              if (_loading)
                for (var i = 0; i < 3; i++)
                  const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: CLSkeleton(width: double.infinity, height: 138)),
              if (!_loading && !_failed && _rows.isEmpty)
                const Text('No deactivated realms available.'),
              if (_failed)
                CLBtn(
                    label: 'Retry',
                    onPressed: () => _load(more: _rows.isNotEmpty)),
              if (!_loading && !_failed && _next != null)
                CLBtn(label: 'Load more', onPressed: () => _load(more: true)),
            ]));
  }
}
