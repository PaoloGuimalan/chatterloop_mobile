import 'package:flutter/widgets.dart';

/// How a moments viewer page came on: opened (from the strip, a profile, a
/// notification), or moved to from the person before or after it.
enum MomentSlide { open, next, previous }

/// The moments viewer's page. Its slides follow where things go, like any
/// stories viewer:
///  - opened, it rises from the bottom; closed - the close button, back, or
///    dragged down (it follows the finger, the screen under it showing) - it
///    slides down and away;
///  - on to the next person, the one showing goes out to the left as theirs
///    comes in from the right; back to the previous person, the other way.
class MomentPage extends Page<void> {
  final Widget child;
  final MomentSlide slide;

  const MomentPage({
    required LocalKey super.key,
    required this.child,
    this.slide = MomentSlide.open,
  });

  @override
  Route<void> createRoute(BuildContext context) => MomentPageRoute(page: this);
}

class MomentPageRoute extends PageRoute<void> {
  MomentPageRoute({required MomentPage page}) : super(settings: page) {
    // The page going out reads it as this one comes in (see
    // buildTransitions): out to the left for the next, right for the
    // previous.
    if (page.slide != MomentSlide.open) _lastSwitch = page.slide;
  }

  static MomentSlide _lastSwitch = MomentSlide.next;

  MomentSlide get _slide => (settings as MomentPage).slide;

  /// Being dragged down, or on its way out: it moves up and down, 1:1 with
  /// the animation - so the finger and the slide away never jump.
  bool _dismissing = false;
  bool _popping = false;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  /// Only moment pages move each other aside; opened over the feed, the feed
  /// stays where it is under it.
  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      nextRoute is MomentPageRoute;

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) =>
      previousRoute is MomentPageRoute;

  @override
  bool didPop(void result) {
    _popping = true;
    return super.didPop(result);
  }

  /// A drag down has begun: from here [updateDismiss] moves the page. False
  /// when it can't be dragged (already on its way).
  bool startDismiss() {
    final controller = this.controller;
    if (_popping || controller == null || controller.isAnimating) {
      return false;
    }
    _dismissing = true;
    navigator?.didStartUserGesture();
    return true;
  }

  /// [fraction] of the screen's height down.
  void updateDismiss(double fraction) {
    if (!_dismissing) return;
    controller?.value = 1 - fraction.clamp(0.0, 1.0);
  }

  /// The drag let go. [closing]: the caller now closes the viewer, and the
  /// pop carries the slide on down from where the finger left it. Otherwise
  /// the page springs back up.
  void endDismiss({required bool closing}) {
    if (!_dismissing) return;
    navigator?.didStopUserGesture();
    if (closing) return;
    controller
        ?.animateTo(1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic)
        .whenCompleteOrCancel(() => _dismissing = false);
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      (settings as MomentPage).child;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        final value = animation.value;
        final vertical = _dismissing ||
            _popping ||
            animation.status == AnimationStatus.reverse;
        final eased = Curves.easeOutCubic.transform(value);
        var offset = switch (_slide) {
          _ when vertical => Offset(0, 1 - value),
          MomentSlide.open => Offset(0, 1 - eased),
          MomentSlide.next => Offset(1 - eased, 0),
          MomentSlide.previous => Offset(eased - 1, 0),
        };
        final out = secondaryAnimation.value;
        if (out > 0) {
          final away = Curves.easeOutCubic.transform(out);
          offset += Offset(
              _lastSwitch == MomentSlide.previous ? away : -away, 0);
        }
        return FractionalTranslation(translation: offset, child: child);
      },
    );
  }
}
