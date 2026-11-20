import 'package:chatterloop_app/views/realm/realm_review_card.dart';
import 'package:flutter/foundation.dart';
import 'realm_role_name_dialog.dart';
import 'package:chatterloop_app/core/design/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/roles_api.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/models/user_models/realm_policy_model.dart';
import 'package:chatterloop_app/models/user_models/role_model.dart';
import 'realm_private_state.dart';

class RealmPermissionsView extends StatefulWidget {
  final String realmId;
  final RolesApi? api;
  const RealmPermissionsView({super.key, required this.realmId, this.api});
  @override
  State<RealmPermissionsView> createState() => _RealmPermissionsViewState();
}

class _RealmPermissionsViewState
    extends RealmPrivateState<RealmPermissionsView> {
  RealmPermissionSettings? _data;
  List<RoleDefinition> _roles = [];
  Map<int, Set<String>> _draft = {};
  bool _loading = true, _saving = false, _failed = false;
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
  void didUpdateWidget(covariant RealmPermissionsView old) {
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
      _roles = [];
      _draft = {};
      _loading = true;
      _failed = false;
      _saving = false;
    });
    final ticket = await requestTicket();
    try {
      final api = widget.api ?? RolesApi(authToken: ticket.token);
      RealmPermissionSettings? data;
      List<RoleDefinition> roles;
      try {
        data = await api.permissions(widget.realmId);
        roles = data.roles;
      } catch (error) {
        // Role administrators may manage names without permission-matrix access.
        if (error is! DioException || error.response?.statusCode != 403) {
          rethrow;
        }
        roles = await api.list(realmId: widget.realmId);
      }
      if (!await isCurrent(ticket)) return;
      setState(() {
        _data = data;
        _roles = roles;
        _draft = {for (final role in roles) role.id: role.permissions.toSet()};
        _loading = false;
      });
    } catch (error) {
      if (!await isCurrent(ticket)) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      CLAlerts.requestError(error, fallback: 'Could not load permissions.');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ticket = await requestTicket(invalidate: false);
    if (!await isCurrent(ticket)) return;
    try {
      await (widget.api ?? RolesApi(authToken: ticket.token))
          .savePermissions(widget.realmId, {
        for (final role in _roles)
          if (role.permissionsEditable &&
              !setEquals(role.permissions.toSet(), _draft[role.id]))
            role.id: _draft[role.id]!.toList()
      });
      if (!await isCurrent(ticket)) return;
      CLAlerts.success('Permissions saved.');
      reloadPrivate();
    } catch (error) {
      if (await isCurrent(ticket)) {
        setState(() => _saving = false);
        CLAlerts.requestError(error, fallback: 'Could not save permissions.');
      }
    }
  }

  Future<void> _roleAction({RoleDefinition? role, bool remove = false}) async {
    if (_saving) return;
    final ticket = await requestTicket(invalidate: false);
    if (!mounted) return;
    final value = remove
        ? await showDialog<String>(
            context: context,
            builder: (ctx) => AppDialog(
                    title: 'Delete role?',
                    description:
                        'Roles referenced by members or invitations cannot be deleted.',
                    icon: Icons.delete_outline,
                    iconBesideTitle: true,
                    actions: [
                      AppDialogAction(
                        label: 'Cancel',
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      AppDialogAction(
                        label: 'Delete',
                        destructive: true,
                        onPressed: () => Navigator.pop(ctx, 'delete'),
                      )
                    ]))
        : await showDialog<String>(
            context: context,
            builder: (_) => RealmRoleNameDialog(
                title: role == null ? 'Create role' : 'Rename role',
                initialValue: role?.name ?? ''));
    if (value == null || value.isEmpty || !await isCurrent(ticket)) return;
    setState(() => _saving = true);
    try {
      final api = widget.api ?? RolesApi(authToken: ticket.token);
      if (remove) {
        await api.delete(widget.realmId, role!.id);
      } else if (role == null) {
        await api.create(widget.realmId, value);
      } else {
        await api.update(widget.realmId, role.id, name: value);
      }
      if (await isCurrent(ticket)) reloadPrivate();
    } catch (error) {
      if (await isCurrent(ticket)) {
        setState(() => _saving = false);
        CLAlerts.requestError(error, fallback: 'Could not update this role.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return CLScreen(
        appBar: AppBar(
            leadingWidth: 48,
            titleSpacing: 0,
            title: const Text('Permissions')),
        body: _loading
            ? ListView(
                padding: const EdgeInsets.all(CLSpacing.contentGutter),
                children: [
                    for (var i = 0; i < 4; i++)
                      const _PermissionsCard(
                          child: Padding(
                              padding: EdgeInsets.all(14),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CLSkeleton(width: 140, height: 16),
                                    SizedBox(height: 10),
                                    CLSkeleton(width: 210, height: 12),
                                  ])))
                  ])
            : ListView(
                padding: const EdgeInsets.all(CLSpacing.contentGutter),
                children: [
                    if (_failed)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child:
                              CLBtn(label: 'Retry', onPressed: reloadPrivate)),
                    if (!_failed) ...[
                      const Text('Roles and permissions',
                          style: TextStyle(
                              fontSize: CLType.sectionTitle,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(
                          'The Owner always has all available permissions. Changes apply only to this realm.',
                          style:
                              TextStyle(fontSize: CLType.body, color: p.text2)),
                      const SizedBox(height: 12),
                      if (_data?.capabilities.allows('can_manage_roles') ==
                              true ||
                          _roles.any((role) => role.editable))
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: AppDialogAction(
                                    label: 'Create role',
                                    onPressed:
                                        _saving ? null : () => _roleAction()))),
                      for (final role in _roles)
                        _PermissionsCard(
                            child: ExpansionTile(
                                shape: const Border(),
                                collapsedShape: const Border(),
                                tilePadding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                childrenPadding:
                                    const EdgeInsets.only(bottom: 14),
                                title: Text(role.name,
                                    style: TextStyle(
                                        color: p.text,
                                        fontSize: CLType.title,
                                        fontWeight: FontWeight.w600)),
                                subtitle: role.code == 'owner' && role.isDefault
                                    ? Text('Always allowed all permissions',
                                        style: TextStyle(
                                            fontSize: CLType.caption,
                                            color: p.text2))
                                    : null,
                                children: [
                              if (role.code != 'owner')
                                for (final entry in _data?.catalog ??
                                    <RealmPermissionEntry>[])
                                  CheckboxListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 14),
                                      controlAffinity:
                                          ListTileControlAffinity.trailing,
                                      title: Text(entry.name,
                                          style: TextStyle(
                                              fontSize: CLType.title,
                                              fontWeight: FontWeight.w500,
                                              color: p.text)),
                                      subtitle: entry.description.isNotEmpty &&
                                              entry.description != entry.name
                                          ? Text(entry.description,
                                              style: TextStyle(
                                                  fontSize: CLType.caption,
                                                  color: p.text2))
                                          : null,
                                      value: _draft[role.id]!
                                          .contains(entry.permission),
                                      onChanged: !_saving &&
                                              role.permissionsEditable &&
                                              (entry.grantable ||
                                                  _draft[role.id]!.contains(
                                                      entry.permission))
                                          ? (value) => setState(() {
                                                if (value == true) {
                                                  _draft[role.id]!
                                                      .add(entry.permission);
                                                } else {
                                                  _draft[role.id]!
                                                      .remove(entry.permission);
                                                }
                                              })
                                          : null),
                              if (role.editable)
                                Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(14, 8, 14, 0),
                                    child: RealmReviewActions(children: [
                                      AppDialogAction(
                                        label: 'Rename',
                                        onPressed: _saving
                                            ? null
                                            : () => _roleAction(role: role),
                                      ),
                                      if (!role.isDefault)
                                        AppDialogAction(
                                          label: 'Delete',
                                          destructive: true,
                                          onPressed: _saving
                                              ? null
                                              : () => _roleAction(
                                                  role: role, remove: true),
                                        ),
                                    ])),
                            ])),
                      if (_data?.capabilities
                              .allows('can_manage_permissions') ==
                          true)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: AppDialogAction(
                                primary: true,
                                label: _saving ? 'Saving…' : 'Save permissions',
                                onPressed: _saving ? null : _save)),
                    ]
                  ]));
  }
}

class _PermissionsCard extends StatelessWidget {
  const _PermissionsCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CLCard(
          padding: EdgeInsets.zero,
          child: Material(type: MaterialType.transparency, child: child)));
}
