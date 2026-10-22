import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:chatterloop_app/core/encryption/purpose_status.dart';
import 'package:chatterloop_app/core/design/passphrase_dialog.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/encryption_api.dart';
import 'package:chatterloop_app/views/settings/passphrase_section.dart';

bool _messagesPath(String path) =>
    path == '/messages' ||
    path.startsWith('/conversation/') ||
    path == '/new-message' ||
    path == '/new-group-chat';

/// A visit shares only an access decision, never passphrases or derived keys.
/// Observing the router also catches tab switches while a branch stays mounted.
class _MessagesVisit extends ChangeNotifier {
  GoRouter? router;
  String path = '', previous = '/newsfeed';
  String? excludedConversation;
  String? identity;
  bool ready = false;
  int generation = 0;
  void attach(GoRouter value) {
    if (router == value) return;
    router?.routerDelegate.removeListener(_routeChanged);
    router = value;
    ready = false;
    identity = null;
    generation++;
    path = '';
    previous = '/newsfeed';
    excludedConversation = null;
    value.routerDelegate.addListener(_routeChanged);
    _routeChanged();
  }

  void _routeChanged() {
    final next = router
            ?.routerDelegate.currentConfiguration.lastOrNull?.matchedLocation ??
        '';
    if (!_messagesPath(next) || next == excludedConversation) {
      if (next.isNotEmpty) {
        final uri = router!.routerDelegate.currentConfiguration.uri;
        previous = uri.path == next ? uri.toString() : next;
      }
      ready = false;
      identity = null;
      generation++;
    } else if (!_messagesPath(path) || path == excludedConversation) {
      ready = false;
      identity = null;
      generation++;
    }
    path = next;
    notifyListeners();
  }

  void lock() {
    ready = false;
    identity = null;
    generation++;
    notifyListeners();
  }

  void allow(String owner) {
    identity = owner;
    ready = true;
    notifyListeners();
  }
}

class MessagesGate extends StatefulWidget {
  const MessagesGate({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  static final _visit = _MessagesVisit();
  static void observe(GoRouter router) => _visit.attach(router);
  static void setConversationProtection(String id, {required bool protected}) {
    final path = '/conversation/$id';
    if (_visit.path != path) return;
    if (!protected) {
      _visit.excludedConversation = path;
      _visit._routeChanged();
    } else if (_visit.excludedConversation == path) {
      _visit.excludedConversation = null;
      _visit.lock();
    }
  }

  @override
  State<MessagesGate> createState() => _MessagesGateState();
}

class _MessagesGateState extends State<MessagesGate>
    with WidgetsBindingObserver {
  final _visit = MessagesGate._visit;
  final _visitActive = ValueNotifier(false);
  StreamSubscription? _accountSubscription;
  String? _path;
  int _observedGeneration = -1;
  int? _promptGeneration;
  int _routeAttempt = 0;
  int? _promptAttempt;
  bool _loading = false, _foreground = true;
  String? _error;
  OverlayEntry? _pendingBarrier;
  String get _identity =>
      '${appStore.state.userAuth.user.id}/${appStore.state.userAuth.user.entityId}';
  bool get _visible => widget.enabled && _foreground && _path == _visit.path;
  bool get _ready => _visit.ready && _visit.identity == _identity;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visit.addListener(_changed);
    var identity = _identity;
    _accountSubscription = appStore.onChange.listen((_) {
      if (identity != _identity) {
        identity = _identity;
        _visitActive.value = false;
        _visit.lock();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final path = GoRouterState.of(context).uri.path;
    if (path != _path) {
      _path = path;
      _routeAttempt++;
    }
    MessagesGate.observe(GoRouter.of(context));
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void didUpdateWidget(covariant MessagesGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
    }
  }

  void _removePendingBarrier() {
    _pendingBarrier?.remove();
    _pendingBarrier?.dispose();
    _pendingBarrier = null;
  }

  void _changed() {
    if (!mounted) return;
    if (_observedGeneration != _visit.generation) {
      _observedGeneration = _visit.generation;
      _error = null;
    }
    _visitActive.value = _visible &&
        (_promptGeneration == null || _promptGeneration == _visit.generation) &&
        (_promptAttempt == null || _promptAttempt == _routeAttempt);
    if (!_visible) _removePendingBarrier();
    setState(() {});
    if (_visible && !_ready && !_loading && _error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _visible) _enter();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _visitActive.value = false;
      _visit.lock();
    } else {
      _changed();
    }
  }

  void _exit() {
    if (!mounted || !_visible) return;
    _visitActive.value = false;
    _visit.lock();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(_visit.previous);
    }
  }

  Future<void> _enter() async {
    if (_loading || !_visible || !mounted || _ready) return;
    final ticket = _visit.generation, owner = _identity;
    final routeAttempt = _routeAttempt;
    var retry = false;
    setState(() {
      _loading = true;
      _error = null;
    });
    _promptGeneration = ticket;
    _promptAttempt = routeAttempt;
    _visitActive.value = true;
    // Block the root app while checking protection without replacing or
    // decorating the existing screen. The visible modal follows if required.
    _pendingBarrier = OverlayEntry(
        builder: (_) => const FocusScope(
              autofocus: true,
              child:
                  ModalBarrier(dismissible: false, color: Colors.transparent),
            ));
    Navigator.of(context, rootNavigator: true)
        .overlay!
        .insert(_pendingBarrier!);
    try {
      final data = await EncryptionApi().load(purpose: 'messages');
      if (!mounted ||
          !_visible ||
          routeAttempt != _routeAttempt ||
          ticket != _visit.generation ||
          owner != _identity) {
        return;
      }
      final group = (data['purposes'] as List)
          .cast<Map>()
          .singleWhere((group) => group['purpose'] == 'messages');
      final activeId = group['active_configuration_id'];
      final active = (group['configurations'] as List)
          .cast<Map>()
          .where((config) =>
              config['id'] == activeId && config['is_active'] == true)
          .firstOrNull;
      if (isEncryptionPurposeEnabled(Map<String, dynamic>.from(group)) &&
          activeId != null &&
          active == null) {
        throw const FormatException('Invalid Messages protection');
      }
      if (isEncryptionPurposeEnabled(Map<String, dynamic>.from(group)) &&
          active != null) {
        _promptGeneration = ticket;
        _promptAttempt = routeAttempt;
        _visitActive.value = true;
        _removePendingBarrier();
        final unlocked = await promptPassphrase(
            context, Map<String, dynamic>.from(active),
            forVisit: true, visitLabel: 'Messages', visitActive: _visitActive);
        // The prompt has already verified locally. Retain no cryptographic key.
        unlocked?.key.fillRange(0, unlocked.key.length, 0);
        if (!mounted ||
            !_visible ||
            routeAttempt != _routeAttempt ||
            ticket != _visit.generation ||
            owner != _identity) {
          return;
        }
        if (unlocked == null) {
          _exit();
          return;
        }
      }
      if (mounted &&
          _visible &&
          routeAttempt == _routeAttempt &&
          ticket == _visit.generation &&
          owner == _identity) {
        _visit.allow(owner);
      }
    } catch (_) {
      if (mounted &&
          _visible &&
          routeAttempt == _routeAttempt &&
          ticket == _visit.generation &&
          owner == _identity) {
        _error = 'Could not load Messages protection. Try again.';
        _removePendingBarrier();
        final again = await _showLoadError();
        if (mounted &&
            _visible &&
            ticket == _visit.generation &&
            routeAttempt == _routeAttempt &&
            owner == _identity) {
          if (again == true) {
            _error = null;
            retry = true;
          } else {
            _exit();
          }
        }
      }
    } finally {
      if (mounted) {
        _removePendingBarrier();
        _promptGeneration = null;
        _promptAttempt = null;
        setState(() {
          _loading = false;
        });
        // An account/route change can invalidate a pending request without
        // disposing an indexed-stack branch. Start the new visit after it ends.
        if (_visible &&
            !_ready &&
            _error == null &&
            (retry ||
                ticket != _visit.generation ||
                routeAttempt != _routeAttempt)) {
          _changed();
        }
      }
    }
  }

  Future<bool?> _showLoadError() async {
    final message = _error!;
    BuildContext? dialogContext;
    void dismissIfInactive() {
      if (_visitActive.value) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final modal = dialogContext;
        if (modal == null || !modal.mounted) return;
        final route = ModalRoute.of(modal);
        if (route?.isActive ?? false) {
          Navigator.of(modal, rootNavigator: true).removeRoute(route!);
        }
      });
    }

    _visitActive.addListener(dismissIfInactive);
    try {
      return await showDialog<bool>(
          context: context,
          useRootNavigator: true,
          barrierDismissible: false,
          builder: (modal) {
            dialogContext = modal;
            return PassphraseDialog(
                title: 'Messages protection unavailable',
                description: message,
                actions: [
                  PassphraseAction(
                      label: 'Cancel',
                      onPressed: () => Navigator.pop(modal, false)),
                  PassphraseAction(
                      label: 'Try again',
                      primary: true,
                      onPressed: () => Navigator.pop(modal, true)),
                ]);
          });
    } finally {
      _visitActive.removeListener(dismissIfInactive);
    }
  }

  @override
  void dispose() {
    _removePendingBarrier();
    _visitActive.value = false;
    _visitActive.dispose();
    _accountSubscription?.cancel();
    _visit.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
