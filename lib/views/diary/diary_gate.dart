import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chatterloop_app/core/design/passphrase_dialog.dart';
import 'package:chatterloop_app/core/encryption/diary_session.dart';
import 'package:chatterloop_app/core/requests/encryption_api.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/views/settings/passphrase_section.dart';

/// Mounted above each Diary route: children never fetch or render before entry.
class DiaryGate extends StatefulWidget {
  const DiaryGate({super.key, required this.child});
  final Widget child;
  @override
  State<DiaryGate> createState() => _DiaryGateState();
}

class _DiaryGateState extends State<DiaryGate> with WidgetsBindingObserver {
  static final _mountedGates = <_DiaryGateState>{};
  final _session = DiarySession.instance;
  StreamSubscription? _subscription;
  GoRouter? _router;
  bool _ready = false, _loading = false;
  String? _error;
  String get _identity =>
      '${appStore.state.userAuth.user.id}/${appStore.state.userAuth.user.entityId}';
  @override
  void initState() {
    super.initState();
    _mountedGates.add(this);
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_locked);
    _subscription = appStore.onChange.listen((_) {
      if (_session.identity != null && _session.identity != _identity) {
        _session.clear();
        _exit();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_routeChanged);
      _router = router;
      router.routerDelegate.addListener(_routeChanged);
    }
  }

  void _routeChanged() {
    // A push retains the underlying URI; the last match is the visible screen.
    final path = _router
            ?.routerDelegate.currentConfiguration.lastOrNull?.matchedLocation ??
        '';
    if (path != '/diary' && !path.startsWith('/diary/')) {
      _session.clear();
    } else if (!_ready && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) _enter();
      });
    }
  }

  void _locked() {
    if (mounted) {
      setState(
          () => _ready = _session.data != null && !_session.purposeEnabled);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _session.clear();
    }
    if (state == AppLifecycleState.resumed &&
        mounted &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      _enter();
    }
  }

  void _exit() {
    if (!mounted) return;
    _session.clear();
    if (context.canPop()) {
      context.pop();
      return;
    }
    final username = appStore.state.userAuth.user.username;
    context.go(username.isEmpty ? '/newsfeed' : '/user/$username');
  }

  Future<void> _enter() async {
    if (_loading || !mounted) return;
    if (_session.ready && _session.identity == _identity) {
      setState(() => _ready = true);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final ticket = _session.generation, owner = _identity;
    try {
      final data = await EncryptionApi().load(purpose: 'diary');
      if (!mounted || ticket != _session.generation || owner != _identity) {
        return;
      }
      _session.install(data, owner);
      setState(() {});
      final active = _session.active;
      if (_session.purposeEnabled && active != null) {
        final unlocked =
            await promptPassphrase(context, active, forVisit: true);
        if (!mounted || ticket != _session.generation || owner != _identity) {
          unlocked?.key.fillRange(0, unlocked.key.length, 0);
          return;
        }
        if (unlocked == null) {
          _exit();
          return;
        }
        _session.addKey(active['id'] as String, unlocked.key);
      } else if (_session.purposeEnabled && _session.configurations.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final flag = 'diary-protection-intro-v1/$owner';
        if (!prefs.containsKey(flag) && mounted) {
          final setup = await showDialog<bool>(
              context: context,
              builder: (context) => PassphraseDialog(
                      title: 'Protect your Diary',
                      description:
                          'Add a passphrase to encrypt the titles and writing in new entries. Only you can unlock them.',
                      actions: [
                        PassphraseAction(
                          label: 'Not now',
                          onPressed: () => Navigator.pop(context, false),
                        ),
                        PassphraseAction(
                          label: 'Set up passphrase',
                          primary: true,
                          onPressed: () => Navigator.pop(context, true),
                        )
                      ],
                      children: const [
                        Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                                'Attachments, tags, moods, dates and other metadata are not encrypted. There is no passphrase recovery.'))
                      ]));
          await prefs.setBool(flag, true);
          if (setup == true && mounted) {
            context.go('/settings/data-privacy');
            return;
          }
        }
      }
      if (mounted && ticket == _session.generation && owner == _identity) {
        setState(() => _ready = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load Diary protection. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _router?.routerDelegate.removeListener(_routeChanged);
    _session.removeListener(_locked);
    WidgetsBinding.instance.removeObserver(this);
    _mountedGates.remove(this);
    // List, reader and composer share a visit only while a Diary gate exists.
    if (_mountedGates.isEmpty) _session.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ready && _session.ready
      ? KeyedSubtree(key: ValueKey(_session.generation), child: widget.child)
      : Scaffold(
          appBar: AppBar(
              title: const Text('Diary'),
              leading: IconButton(
                  onPressed: _exit, icon: const Icon(Icons.arrow_back))),
          body: Center(
              child: _loading && _session.data == null
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error ?? 'Unlock Diary to continue.'),
                      if (!_loading)
                        TextButton(
                            onPressed: _enter, child: const Text('Try again'))
                    ])));
}
