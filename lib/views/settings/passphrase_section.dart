import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/passphrase_dialog.dart';
import 'package:chatterloop_app/core/encryption/passphrase_crypto.dart';
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
        {bool exitOnFailure = false, bool forEncryption = false}) =>
    showDialog<({List<int> key, String proof})>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UnlockDialog(
            configuration: configuration,
            exitOnFailure: exitOnFailure,
            forEncryption: forEncryption));

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog(
      {required this.configuration,
      required this.exitOnFailure,
      required this.forEncryption});
  final Map<String, dynamic> configuration;
  final bool exitOnFailure;
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
      if (mounted && widget.exitOnFailure) {
        Navigator.pop(context);
        return;
      }
      if (mounted) {
        _phrase.clear();
        setState(() {
          _busy = false;
          _error = widget.forEncryption
              ? 'Could not confirm the active passphrase. Please try again.'
              : 'Could not unlock. Check your passphrase.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PassphraseDialog(
        title: widget.forEncryption
            ? 'Confirm entry encryption'
            : widget.exitOnFailure
                ? 'Unlock your Diary'
                : 'Unlock older entries',
        description: widget.forEncryption
            ? 'Confirm your active passphrase to encrypt this entry title and writing before saving.'
            : widget.exitOnFailure
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
              errorText: _error,
              onSubmitted: (_) {
                if (!_busy) _unlock();
              }),
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
  Map<String, dynamic> get _group => Map<String, dynamic>.from(
      (_data!['purposes'] as List).firstWhere((e) => e['purpose'] == 'diary')
          as Map);
  List<Map<String, dynamic>> get _rows => (_group['configurations'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  Map<String, dynamic>? get _active =>
      _rows.where((c) => c['is_active'] == true).firstOrNull;
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
            version: _group['scope_version'] as String));
    if (payload != null && mounted) {
      await _mutate(() => EncryptionApi().create(payload));
    }
  }

  Future<void> _rename(Map<String, dynamic> c) async {
    final value = await showDialog<String>(
        context: context,
        builder: (_) => _RenameDialog(name: c['name'] as String));
    if (value != null && mounted) {
      await _mutate(() => EncryptionApi()
          .rename(c['id'] as String, value, _group['scope_version'] as String));
    }
  }

  Future<void> _change(Map<String, dynamic> target, bool disable) async {
    if (_busy) return;
    setState(() => _busy = true);
    final version = _group['scope_version'] as String;
    try {
      final proofs = await showDialog<({String? active, String? target})>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              _ChangeDialog(active: _active, target: target, disable: disable));
      if (proofs == null || !mounted) return;
      if (disable) {
        await EncryptionApi()
            .disable(target['id'] as String, version, proofs.active!);
      } else {
        await EncryptionApi().activate(
            target['id'] as String, version, proofs.target!, proofs.active);
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

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Passphrase',
          style: TextStyle(
              fontSize: CLType.title,
              fontWeight: FontWeight.w700,
              color: p.text)),
      const SizedBox(height: 5),
      Text(
          'Manage the passphrases used to protect your private data. Keep every passphrase you still need: Chatterloop cannot recover it.',
          style:
              TextStyle(fontSize: CLType.bodySm, color: p.text2, height: 1.4)),
      const SizedBox(height: 14),
      Text('Passphrase uses',
          style: TextStyle(fontWeight: FontWeight.w600, color: p.text)),
      const SizedBox(height: 8),
      if (_error != null) ...[
        Text(_error!, style: TextStyle(color: p.text2)),
        TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('Reload passphrases'))
      ],
      if (_data == null && _error == null) const LinearProgressIndicator(),
      if (_data != null)
        Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: p.surface,
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(12)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Icon(Icons.book_outlined, color: p.brand),
                    const SizedBox(width: 8),
                    const Expanded(
                        child: Text('Diary',
                            style: TextStyle(fontWeight: FontWeight.w700))),
                    Text(_active == null ? 'Not active' : 'Protected',
                        style: TextStyle(color: p.text2))
                  ]),
                  const SizedBox(height: 8),
                  Text(
                      'Only entry titles and text are encrypted. Attachments, tags, moods and dates are outside this protection. Existing entries keep their original protection.',
                      style:
                          TextStyle(color: p.text2, fontSize: CLType.caption)),
                  if (_rows.isEmpty)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No passphrase configurations yet.')),
                  for (final row in _rows)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(row['name'] as String,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                        '${row['is_active'] == true ? 'Active' : 'Inactive'} · Created ${(row['created_at'] as String? ?? '').split('T').first}',
                                        style: TextStyle(
                                            color: p.text3,
                                            fontSize: CLType.caption))
                                  ])),
                              PopupMenuButton<String>(
                                  enabled: !_busy,
                                  onSelected: (action) {
                                    if (action == 'rename') {
                                      _rename(row);
                                    } else {
                                      _change(row, action == 'disable');
                                    }
                                  },
                                  itemBuilder: (_) => [
                                        const PopupMenuItem(
                                            value: 'rename',
                                            child: Text('Rename')),
                                        PopupMenuItem(
                                            value: row['is_active'] == true
                                                ? 'disable'
                                                : 'activate',
                                            child: Text(row['is_active'] == true
                                                ? 'Disable'
                                                : 'Activate'))
                                      ]),
                            ])),
                  const SizedBox(height: 10),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                          onPressed: _busy ? null : _add,
                          icon: const Icon(Icons.add),
                          label: const Text('Add passphrase'))),
                  if (_busy) const LinearProgressIndicator(),
                ])),
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
      {required this.entity, required this.user, required this.version});
  final String entity, user, version;
  @override
  State<_SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends _SecretDialogState<_SetupDialog> {
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
    if (!_ack ||
        _name.text.trim().isEmpty ||
        _name.text.trim().runes.length > 80 ||
        !PassphraseCrypto.validPhrase(_phrase.text) ||
        _phrase.text != _confirm.text) {
      setState(() => _error =
          'Enter a name, at least 15 characters, matching confirmation, and acknowledge recovery.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = await PassphraseCrypto().setup(
          _name.text, _phrase.text, widget.entity, widget.user, widget.version);
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
          description:
              'Add an inactive passphrase, then activate it when you are ready.',
          actions: [
            PassphraseAction(
                label: 'Cancel', onPressed: () => Navigator.pop(context)),
            PassphraseAction(
                label: _busy ? 'Working…' : 'Add passphrase',
                primary: true,
                onPressed: _busy ? null : _save)
          ],
          children: [
            PassphraseField(
                label: 'Name',
                controller: _name,
                enabled: !_busy,
                maxLength: 80,
                autofocus: true),
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
}
