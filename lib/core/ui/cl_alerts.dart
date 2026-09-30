// The app's one notice surface - errors, warnings, confirmations - pinned to
// the top of the screen ABOVE everything the app draws.
//
// Why not SnackBars: a SnackBar belongs to a Scaffold. With a tab shell, pushed
// screens, bottom sheets and dialogs, whichever Scaffold happens to be current
// decides where it lands - so a failure could sit behind the bottom nav, under
// a sheet, or on a screen the user had already left. CLAlertHost is mounted in
// MaterialApp.router's `builder`, which wraps the Navigator itself: every
// route, sheet and dialog is BELOW it, so a notice can't be covered, and it
// can be raised from anywhere without a BuildContext.
//
//   CLAlerts.error("...")                          a plain notice
//   CLAlerts.requestError(e, fallback: "...")      a failed request (Dio or not)
//   CLAlerts.responseFailure(body, "...")          a `{status: false}` refusal
//
// Styled from the design tokens (CLPalette, CLRadii, CLType): a surface card
// like CLCard, with the tone carried by a soft badge the way CLBadge does it.

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/errors/request_errors.dart';
import 'package:chatterloop_call_native/chatterloop_call_native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum CLAlertType { success, info, warning, error }

/// A single button on a notice ("Undo", "Open", "Retry").
class CLAlertAction {
  final String label;
  final VoidCallback onPressed;

  const CLAlertAction({required this.label, required this.onPressed});
}

class CLAlert {
  final int id;
  final CLAlertType type;
  final String message;
  final String? title;
  final CLAlertAction? action;

  /// How long it stays once it is on screen.
  final Duration duration;

  /// Flipped when the notice is on its way out, so the card can animate away
  /// before it is removed.
  final ValueNotifier<bool> leaving = ValueNotifier<bool>(false);

  /// Bumped when the same notice is raised again - its card restarts the
  /// countdown rather than a second copy appearing.
  final ValueNotifier<int> restarts = ValueNotifier<int>(0);

  CLAlert({
    required this.id,
    required this.type,
    required this.message,
    required this.duration,
    this.title,
    this.action,
  });
}

class CLAlerts {
  CLAlerts._();

  /// Newest first. More than this and the top of the screen is all notices.
  static const int maxVisible = 3;

  static final ValueNotifier<List<CLAlert>> _active =
      ValueNotifier<List<CLAlert>>(const []);
  static int _nextId = 0;

  /// The notices currently up, newest first.
  static ValueListenable<List<CLAlert>> get active => _active;

  /// How long a notice stays: long enough to read, longer for the ones that
  /// matter, and longer again when there is a button to reach for.
  static Duration _durationFor(CLAlertType type, {required bool hasAction}) {
    final base = switch (type) {
      CLAlertType.error => const Duration(seconds: 6),
      CLAlertType.warning => const Duration(seconds: 5),
      CLAlertType.success || CLAlertType.info => const Duration(seconds: 4),
    };
    return hasAction ? base + const Duration(seconds: 2) : base;
  }

  static void show(
    String message, {
    CLAlertType type = CLAlertType.info,
    String? title,
    CLAlertAction? action,
    Duration? duration,
  }) {
    final text = message.trim();
    if (text.isEmpty) return;

    // The same notice again - a retry that failed the same way, two taps on a
    // refused button - restarts the one already up instead of stacking a
    // copy of it.
    final current = _active.value;
    for (final alert in current) {
      if (alert.type == type &&
          alert.message == text &&
          alert.title == title &&
          !alert.leaving.value) {
        alert.restarts.value++;
        return;
      }
    }

    final alert = CLAlert(
      id: _nextId++,
      type: type,
      message: text,
      title: title,
      action: action,
      duration: duration ?? _durationFor(type, hasAction: action != null),
    );
    final next = [alert, ...current];
    // Over the cap: the oldest go without an exit animation - they are being
    // pushed out, not dismissed.
    while (next.length > maxVisible) {
      next.removeLast();
    }
    _active.value = next;
  }

  static void success(String message, {String? title, CLAlertAction? action}) =>
      show(message, type: CLAlertType.success, title: title, action: action);

  static void info(String message, {String? title, CLAlertAction? action}) =>
      show(message, type: CLAlertType.info, title: title, action: action);

  static void warning(String message, {String? title, CLAlertAction? action}) =>
      show(message, type: CLAlertType.warning, title: title, action: action);

  static void error(String message, {String? title, CLAlertAction? action}) =>
      show(message, type: CLAlertType.error, title: title, action: action);

  /// A request that failed or was refused with an error status. [fallback]
  /// says what was being attempted ("We couldn't create that channel.") and
  /// is used when the server said nothing a person should read. Silent for a
  /// cancelled request.
  static void requestError(Object error,
      {String? fallback, CLAlertAction? action}) {
    final described = describeRequestError(error, fallback: fallback);
    if (described.silent) return;
    if (kDebugMode) debugPrint('[request] $error');
    show(described.message, type: described.type, action: action);
  }

  /// A refusal inside an otherwise-successful response - `{"status": false,
  /// "message": ...}`. Takes a Dio Response or the body.
  static void responseFailure(Object? response, String fallback,
      {CLAlertType type = CLAlertType.warning}) {
    show(resolveResponseMessage(response, fallback), type: type);
  }

  /// Takes a notice down, with its exit animation.
  static void dismiss(int id) {
    for (final alert in _active.value) {
      if (alert.id == id) {
        alert.leaving.value = true;
        return;
      }
    }
  }

  /// Every notice, at once - for signing out.
  static void clear() {
    _active.value = const [];
  }

  /// Called by the card once its exit animation has finished.
  static void _remove(int id) {
    _active.value = _active.value.where((a) => a.id != id).toList();
  }

  @visibleForTesting
  static void resetForTest() {
    clear();
    _nextId = 0;
  }
}

/// Draws the active notices over [child]. Mount ONCE, as
/// `MaterialApp.router(builder: (context, child) => CLAlertHost(child: child!))`.
class CLAlertHost extends StatelessWidget {
  final Widget child;

  const CLAlertHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: CallNative.inPip,
      builder: (context, _, __) => Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: ValueListenableBuilder<List<CLAlert>>(
              valueListenable: CLAlerts.active,
              builder: (context, alerts, _) {
                // Nothing over a call's PiP window - it is a video, not the
                // app. The notices wait for the app to come back.
                if (alerts.isEmpty || CallNative.inPip.value) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    // A phone's width, and no wider on a tablet - a notice
                    // stretched edge to edge reads as a banner, not a note.
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final alert in alerts)
                            _CLAlertCard(key: ValueKey(alert.id), alert: alert),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
      ),
    );
  }
}

class _CLAlertCard extends StatefulWidget {
  final CLAlert alert;

  const _CLAlertCard({super.key, required this.alert});

  @override
  State<_CLAlertCard> createState() => _CLAlertCardState();
}

class _CLAlertCardState extends State<_CLAlertCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// The countdown belongs to the CARD, not to CLAlerts: it only runs while
  /// the notice is actually on screen, and it dies with the card - so a
  /// notice raised where no host is mounted (a widget test, a teardown)
  /// leaves no timer behind.
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    widget.alert.leaving.addListener(_onLeaving);
    widget.alert.restarts.addListener(_startCountdown);
    _startCountdown();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    widget.alert.leaving.removeListener(_onLeaving);
    widget.alert.restarts.removeListener(_startCountdown);
    _controller.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdown?.cancel();
    _countdown =
        Timer(widget.alert.duration, () => CLAlerts.dismiss(widget.alert.id));
  }

  void _onLeaving() {
    if (!widget.alert.leaving.value) return;
    _countdown?.cancel();
    _controller.reverse().whenComplete(() => CLAlerts._remove(widget.alert.id));
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    return SizeTransition(
      sizeFactor: _curve,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.35),
            end: Offset.zero,
          ).animate(_curve),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Dismissible(
              key: ValueKey('dismiss-${alert.id}'),
              // Sideways, the way a system notification is flicked away.
              direction: DismissDirection.horizontal,
              onDismissed: (_) => CLAlerts._remove(alert.id),
              child: _AlertBody(alert: alert),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertBody extends StatelessWidget {
  final CLAlert alert;

  const _AlertBody({required this.alert});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final (icon, tint, soft) = switch (alert.type) {
      CLAlertType.success => (Icons.check_circle_rounded, p.green, p.greenSoft),
      CLAlertType.info => (Icons.info_rounded, p.brand, p.brandSoft),
      CLAlertType.warning => (Icons.warning_amber_rounded, p.gold, p.goldSoft),
      CLAlertType.error => (Icons.error_rounded, p.pink, p.pinkSoft),
    };

    return Semantics(
      container: true,
      liveRegion: true,
      label: [alert.title, alert.message].whereType<String>().join('. '),
      // Transparent Material: gives the text a theme-derived DefaultTextStyle
      // and the buttons an ink surface, which nothing above the Navigator
      // otherwise provides.
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => CLAlerts.dismiss(alert.id),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: p.surface,
              border: Border.all(color: p.border),
              borderRadius: BorderRadius.circular(CLRadii.md),
              boxShadow: [
                // CLCard's hairline shadow, plus a lift: this floats over
                // content rather than sitting in it.
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration:
                      BoxDecoration(color: soft, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: tint),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (alert.title != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            alert.title!,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: CLType.label,
                              fontWeight: FontWeight.w700,
                              color: p.text,
                            ),
                          ),
                        ),
                      Text(
                        alert.message,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: CLType.bodySm,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: p.text,
                        ),
                      ),
                    ],
                  ),
                ),
                if (alert.action != null)
                  TextButton(
                    onPressed: () {
                      CLAlerts.dismiss(alert.id);
                      alert.action!.onPressed();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: p.brand,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: CLType.label,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(alert.action!.label),
                  ),
                IconButton(
                  onPressed: () => CLAlerts.dismiss(alert.id),
                  tooltip: null,
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, color: p.text3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
