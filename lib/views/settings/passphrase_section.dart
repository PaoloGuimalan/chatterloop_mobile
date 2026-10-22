import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/passphrase_dialog.dart';
import 'package:chatterloop_app/core/encryption/passphrase_crypto.dart';
import 'package:chatterloop_app/core/encryption/purpose_status.dart';
import 'package:chatterloop_app/core/requests/encryption_api.dart';
import 'package:chatterloop_app/core/redux/store.dart';

abstract class _SecretDialogState<T extends StatefulWidget> extends State<T>
    with WidgetsBindingObserver {
  int generation = 0;
  StreamSubscription? _identitySubscription;
  String get _identity =>
      '${appStore.state.userAuth.user.id}/${appStore.state.userAuth.user.entityId}';
  void clearSecretFields();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final identity = _identity;
    _identitySubscription = appStore.onChange.listen((_) {
      if (_identity != identity) _cancelSecrets();
    });
  }

  void _cancelSecrets() {
    generation++;
    clearSecretFields();
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.of(context).pop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancelSecrets();
  }

  @override
  void dispose() {
    generation++;
    _identitySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Secret controllers and derived keys exist only for this dialog's lifetime.
Future<({List<int> key, String proof})?> promptPassphrase(
        BuildContext context, Map<String, dynamic> configuration,
        {bool forVisit = false, bool forEncryption = false}) =>
    showDialog<({List<int> key, String proof})>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UnlockDialog(
            configuration: configuration,
            forVisit: forVisit,
            forEncryption: forEncryption));

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog(
      {required this.configuration,
      required this.forVisit,
      required this.forEncryption});
  final Map<String, dynamic> configuration;
  final bool forVisit;
  final bool forEncryption;
  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends _SecretDialogState<_UnlockDialog> {
  final _phrase = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void clearSecretFields() => _phrase.clear();
  @override
  void dispose() {
    _phrase.clear();
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy) return;
    final ticket = generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await PassphraseCrypto().unlock(widget.configuration, _phrase.text);
      if (!mounted || ticket != generation) {
        result.key.fillRange(0, result.key.length, 0);
        return;
      }
      _phrase.clear();
      Navigator.pop(context, result);
    } catch (_) {
      if (mounted && ticket == generation) {
        _phrase.clear();
        setState(() {
          _busy = false;
          _error = widget.forEncryption
              ? 'Could not confirm the active passphrase. Please try again.'
              : widget.forVisit
                  ? 'Could not unlock your Diary. Check your passphrase and try again.'
                  : 'Could not unlock this entry. Check its original passphrase and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PassphraseDialog(
        title: widget.forEncryption
            ? 'Confirm entry encryption'
            : widget.forVisit
                ? 'Unlock your Diary'
                : 'Unlock older entries',
        description: widget.forEncryption
            ? 'Confirm your active passphrase to encrypt this entry title and writing before saving.'
            : widget.forVisit
                ? 'Enter your active passphrase to open this visit.'
                : 'Entry needs a different or older key to unlock. This does not change your active passphrase.',
        actions: [
          PassphraseAction(
            label: 'Cancel',
            onPressed: () => Navigator.pop(context),
          ),
          PassphraseAction(
              label: _busy
                  ? 'Verifying…'
                  : widget.forEncryption
                      ? 'Encrypt and save'
                      : 'Unlock',
              primary: true,
              onPressed: _busy ? null : _unlock)
        ],
        children: [
          PassphraseField(
              label: widget.configuration['name'] as String,
              controller: _phrase,
              secret: true,
              enabled: !_busy,
              autofocus: true,
              onSubmitted: (_) {
                if (!_busy) _unlock();
              }),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: cl(context).pinkSoft,
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_error!,
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    height: 1.5))),
                      ]),
                ),
              ),
            ),
        ],
      );
}

class PassphraseSection extends StatefulWidget {
  const PassphraseSection({super.key});
  @override
  State<PassphraseSection> createState() => _PassphraseSectionState();
}

class _PassphraseSectionState extends State<PassphraseSection> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  int _generation = 0;
  List<Map<String, dynamic>> get _groups => (_data?['purposes'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  List<Map<String, dynamic>> _rows(Map<String, dynamic> group) =>
      (group['configurations'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  List<Map<String, dynamic>> get _configurations {
    final unique = <String, Map<String, dynamic>>{};
    for (final group in _groups) {
      for (final configuration in _rows(group)) {
        unique.putIfAbsent(configuration['id'] as String, () => configuration);
      }
    }
    return unique.values.toList();
  }

  List<Map<String, dynamic>> _linkedGroups(Map<String, dynamic> configuration) {
    final purposes = PassphraseCrypto.configurationPurposes(configuration);
    return _groups.where((g) => purposes.contains(g['purpose'])).toList();
  }

  Map<String, dynamic>? _contextFor(Map<String, dynamic> configuration,
          {bool activate = false}) =>
      _linkedGroups(configuration)
          .where((g) => !activate || isEncryptionPurposeEnabled(g))
          .firstOrNull;

  Map<String, dynamic>? get _active =>
      _configurations.where((c) => c['is_active'] == true).firstOrNull;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final data = await EncryptionApi().load();
      if (mounted && generation == _generation) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Could not load passphrases. Try again.');
      }
    }
  }

  Future<void> _mutate(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      await _load();
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 409) {
        await _load();
        if (mounted) {
          setState(() => _error =
              'Configurations changed. Review them and confirm again.');
        }
      } else if (mounted) {
        setState(() => _error = 'Could not update passphrases. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final owner = _data!['owner'] as Map;
    final payload = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SetupDialog(
            entity: owner['entity_id'] as String,
            user: owner['user_id'] as String,
            groups: _groups));
    if (payload != null && mounted) {
      await _mutate(() => EncryptionApi().create(payload));
    }
  }

  Future<void> _rename(Map<String, dynamic> c) async {
    final group = _contextFor(c);
    if (group == null) return;
    final value = await showDialog<String>(
        context: context,
        builder: (_) => _RenameDialog(name: c['name'] as String));
    if (value != null && mounted) {
      await _mutate(() => EncryptionApi().rename(
          c['id'] as String, value, group['scope_version'] as String,
          purpose: group['purpose'] as String));
    }
  }

  Future<void> _change(Map<String, dynamic> target, bool disable) async {
    if (_busy) return;
    final group = _contextFor(target, activate: !disable);
    if (group == null) return;
    setState(() => _busy = true);
    final version = group['scope_version'] as String;
    final purpose = group['purpose'] as String;
    try {
      final proofs = await showDialog<({String? active, String? target})>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              _ChangeDialog(active: _active, target: target, disable: disable));
      if (proofs == null || !mounted) return;
      if (disable) {
        await EncryptionApi().disable(
            target['id'] as String, version, proofs.active!,
            purpose: purpose);
      } else {
        await EncryptionApi().activate(
            target['id'] as String, version, proofs.target!, proofs.active,
            purpose: purpose);
      }
      await _load();
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 409) await _load();
      if (mounted) {
        setState(() => _error =
            e is DioException && e.response?.statusCode == 409
                ? 'Configurations changed. Review them and confirm again.'
                : 'Could not change the active passphrase. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _purposeBadge(String code) {
    final p = cl(context);
    final group = _groups.where((g) => g['purpose'] == code).firstOrNull;
    final label =
        code == 'diary' ? 'Diary' : group?['label'] as String? ?? code;
    final paused = group != null && !isEncryptionPurposeEnabled(group);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: paused ? p.surface2 : p.brandSoft,
            borderRadius: BorderRadius.circular(6)),
        child: Text(paused ? '$label · Paused' : label,
            style: TextStyle(
                fontSize: CLType.meta, color: paused ? p.text2 : p.brand)));
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final rows = _configurations;
    final canAdd = _groups.any(isEncryptionPurposeEnabled);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
            child: Text('Passphrase',
                style: TextStyle(
                    fontSize: CLType.title,
                    fontWeight: FontWeight.w700,
                    color: p.text))),
        TextButton.icon(
            onPressed: _busy || !canAdd ? null : _add,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add passphrase')),
      ]),
      const SizedBox(height: 5),
      Text(
          'Manage the passphrases used to protect your private data. Keep every passphrase you still need: Chatterloop cannot recover it.',
          style:
              TextStyle(fontSize: CLType.bodySm, color: p.text2, height: 1.4)),
      const SizedBox(height: 14),
      if (_error != null) ...[
        Text(_error!, style: TextStyle(color: p.text2)),
        TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('Reload passphrases'))
      ],
      if (_data == null && _error == null) const LinearProgressIndicator(),
      if (_data != null)
        Container(
            decoration: BoxDecoration(
                color: p.surface,
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(12)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (rows.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No passphrase configurations yet.')),
                  for (var index = 0; index < rows.length; index++) ...[
                    if (index > 0) Divider(height: 1, color: p.border),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(rows[index]['name'] as String,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: p.text)),
                                    const SizedBox(height: 4),
                                    Text(
                                        '${rows[index]['is_active'] == true ? 'Active' : 'Inactive'} · Created ${(rows[index]['created_at'] as String? ?? '').split('T').first}',
                                        style: TextStyle(
                                            color: p.text3,
                                            fontSize: CLType.caption)),
                                    const SizedBox(height: 8),
                                    Wrap(spacing: 6, runSpacing: 6, children: [
                                      for (final code in PassphraseCrypto
                                          .configurationPurposes(rows[index]))
                                        _purposeBadge(code),
                                    ]),
                                  ])),
                              PopupMenuButton<String>(
                                  enabled: !_busy,
                                  onSelected: (action) {
                                    if (action == 'rename') {
                                      _rename(rows[index]);
                                    } else {
                                      _change(rows[index], action == 'disable');
                                    }
                                  },
                                  itemBuilder: (_) => [
                                        const PopupMenuItem(
                                            value: 'rename',
                                            child: Text('Rename')),
                                        PopupMenuItem(
                                            enabled: rows[index]['is_active'] ==
                                                    true ||
                                                _contextFor(rows[index],
                                                        activate: true) !=
                                                    null,
                                            value:
                                                rows[index]['is_active'] == true
                                                    ? 'disable'
                                                    : 'activate',
                                            child: Text(
                                                rows[index]['is_active'] == true
                                                    ? 'Disable'
                                                    : 'Activate')),
                                      ]),
                            ])),
                  ],
                ])),
      if (_data != null)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
                'The active passphrase protects new content for its listed purposes. Older content keeps its original protection.',
                style: TextStyle(
                    color: p.text2, fontSize: CLType.caption, height: 1.4))),
      if (_busy) const LinearProgressIndicator(),
    ]);
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name});
  final String name;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.name);
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PassphraseDialog(
        title: 'Rename passphrase',
        description: 'Choose a name that helps you recognize this passphrase.',
        actions: [
          PassphraseAction(
              label: 'Cancel', onPressed: () => Navigator.pop(context)),
          PassphraseAction(
              label: 'Rename passphrase',
              primary: true,
              onPressed: () {
                if (_name.text.trim().isNotEmpty) {
                  Navigator.pop(context, _name.text.trim());
                }
              }),
        ],
        children: [
          PassphraseField(
              label: 'Name', controller: _name, maxLength: 80, autofocus: true)
        ],
      );
}

class _ChangeDialog extends StatefulWidget {
  const _ChangeDialog(
      {required this.active, required this.target, required this.disable});
  final Map<String, dynamic>? active;
  final Map<String, dynamic> target;
  final bool disable;
  @override
  State<_ChangeDialog> createState() => _ChangeDialogState();
}

class _ChangeDialogState extends _SecretDialogState<_ChangeDialog> {
  final _current = TextEditingController(), _selected = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void clearSecretFields() {
    _current.clear();
    _selected.clear();
  }

  @override
  void dispose() {
    clearSecretFields();
    _current.dispose();
    _selected.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final ticket = generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Future<String?> proof(Map<String, dynamic>? c, String phrase) async {
        if (c == null) return null;
        final result = await PassphraseCrypto().unlock(c, phrase);
        try {
          return result.proof;
        } finally {
          result.key.fillRange(0, result.key.length, 0);
        }
      }

      final active = await proof(widget.active, _current.text);
      if (!mounted || ticket != generation) return;
      final target =
          widget.disable ? null : await proof(widget.target, _selected.text);
      if (!mounted || ticket != generation) return;
      clearSecretFields();
      Navigator.pop(context, (active: active, target: target));
    } catch (_) {
      if (mounted && ticket == generation) {
        clearSecretFields();
        setState(() {
          _busy = false;
          _error = 'Could not verify the passphrase. Check it and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PassphraseDialog(
        title: widget.disable ? 'Disable passphrase' : 'Activate passphrase',
        description: widget.disable
            ? 'New entries will be saved without passphrase encryption. Older encrypted entries still need their original passphrase.'
            : 'Confirm the selected passphrase and the currently active one, if any. Older entries keep their original protection.',
        actions: [
          PassphraseAction(
              label: 'Cancel', onPressed: () => Navigator.pop(context)),
          PassphraseAction(
              label: _busy
                  ? 'Working…'
                  : widget.disable
                      ? 'Disable passphrase'
                      : 'Activate passphrase',
              primary: true,
              onPressed: _busy ? null : _confirm),
        ],
        children: [
          if (widget.active != null)
            PassphraseField(
                label: 'Current passphrase · ${widget.active!['name']}',
                controller: _current,
                secret: true,
                enabled: !_busy,
                autofocus: true),
          if (!widget.disable)
            PassphraseField(
                label: 'Selected passphrase · ${widget.target['name']}',
                controller: _selected,
                secret: true,
                enabled: !_busy,
                autofocus: widget.active == null),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: const TextStyle(color: Color(0xFFD64545)))),
        ],
      );
}

class _SetupDialog extends StatefulWidget {
  const _SetupDialog(
      {required this.entity, required this.user, required this.groups});
  final String entity, user;
  final List<Map<String, dynamic>> groups;
  @override
  State<_SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends _SecretDialogState<_SetupDialog> {
  late final Set<String> _purposes = {
    if (widget.groups.any(isEncryptionPurposeEnabled))
      widget.groups.firstWhere(isEncryptionPurposeEnabled)['purpose'] as String
  };
  final _name = TextEditingController(),
      _phrase = TextEditingController(),
      _confirm = TextEditingController();
  bool _ack = false, _busy = false;
  String? _error;
  @override
  void clearSecretFields() {
    _phrase.clear();
    _confirm.clear();
  }

  @override
  void dispose() {
    _phrase.clear();
    _confirm.clear();
    _name.dispose();
    _phrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ticket = generation;
    if (_purposes.isEmpty ||
        !_ack ||
        _name.text.trim().isEmpty ||
        _name.text.trim().runes.length > 80 ||
        !PassphraseCrypto.validPhrase(_phrase.text) ||
        _phrase.text != _confirm.text) {
      setState(() => _error =
          'Choose at least one use, enter a name, at least 15 characters, matching confirmation, and acknowledge recovery.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final origin = _purposes.first;
      final group = widget.groups.firstWhere((g) => g['purpose'] == origin);
      final payload = await PassphraseCrypto().setup(_name.text, _phrase.text,
          widget.entity, widget.user, group['scope_version'] as String,
          purpose: origin, purposes: _purposes.toList());
      if (!mounted || ticket != generation) return;
      _phrase.clear();
      _confirm.clear();
      if (mounted) Navigator.pop(context, payload);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not prepare the passphrase. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PassphraseDialog(
          title: 'Add passphrase',
          iconBesideTitle: false,
          description:
              'Add an inactive passphrase, then activate it when you are ready.',
          actions: [
            PassphraseAction(
                label: 'Cancel', onPressed: () => Navigator.pop(context)),
            PassphraseAction(
                label: _busy ? 'Working…' : 'Add passphrase',
                primary: true,
                onPressed: _busy || _purposes.isEmpty ? null : _save)
          ],
          children: [
            PassphraseField(
                label: 'Name',
                controller: _name,
                enabled: !_busy,
                maxLength: 80,
                autofocus: true),
            _purposeSelector(context),
            PassphraseField(
                label: 'New passphrase',
                controller: _phrase,
                enabled: !_busy,
                secret: true),
            PassphraseField(
                label: 'Confirm passphrase',
                controller: _confirm,
                enabled: !_busy,
                secret: true),
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    'At least 15 characters. Spaces and capitalization are preserved exactly.',
                    style: TextStyle(
                        fontSize: CLType.meta,
                        color: cl(context).text2,
                        height: 1.5))),
            CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                minTileHeight: 44,
                minVerticalPadding: 0,
                minLeadingWidth: 0,
                horizontalTitleGap: 0,
                value: _ack,
                onChanged:
                    _busy ? null : (v) => setState(() => _ack = v ?? false),
                title: Text(
                    'I understand that a forgotten passphrase cannot be recovered.',
                    style: TextStyle(
                        fontSize: CLType.caption,
                        color: cl(context).text,
                        height: 1.5))),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Color(0xFFD64545))),
          ]);

  Widget _purposeSelector(BuildContext context) {
    final p = cl(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Stack(children: [
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          decoration: BoxDecoration(
              border: Border.all(color: p.border),
              borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            for (final group in widget.groups.where(isEncryptionPurposeEnabled))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                minTileHeight: 44,
                minVerticalPadding: 0,
                minLeadingWidth: 0,
                horizontalTitleGap: 0,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                    'Use for ${group['purpose'] == 'diary' ? 'Diary' : group['label'] as String? ?? group['purpose'] as String}',
                    style: TextStyle(fontSize: CLType.caption, color: p.text)),
                value: _purposes.contains(group['purpose']),
                onChanged: _busy
                    ? null
                    : (selected) => setState(() {
                          if (selected == true) {
                            _purposes.add(group['purpose'] as String);
                          } else {
                            _purposes.remove(group['purpose']);
                          }
                        }),
              ),
          ]),
        ),
        Positioned(
            top: 0,
            left: 12,
            child: ColoredBox(
              color: p.surface,
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Passphrase uses',
                      style:
                          TextStyle(fontSize: CLType.caption, color: p.text2))),
            )),
      ]),
    );
  }
}
