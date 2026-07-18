// Facebook-style account menu: a speech-bubble popover anchored above the
// bottom-nav Profile button, pointing down at it. Combines webapp's
// UserMenu.tsx (profile row + logout, minus the AppMenu "apps" grid, which
// was explicitly scoped out) with EntitySwitcher.tsx's account-switching
// list (personal + administered pages, matches its "always show every page
// you administer, active one highlighted" behavior) inlined into one menu,
// since webapp itself has no single unified dropdown to port 1:1 (see the
// research this was built from: EntitySwitcher only lives in a corner
// popover / inside UserMenu's profile row, Settings is a separate rail icon
// or AppMenu tile, never all three together in one component).

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/requests/entity_api.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

const double _popoverWidth = 268;
const double _pointerSize = 14;

void showUserMenuPopover(
  BuildContext context, {
  required GlobalKey anchorKey,
  required VoidCallback onOpenProfile,
  required VoidCallback onLogout,
}) {
  final renderBox = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  if (renderBox == null) return;
  final anchorTopLeft = renderBox.localToGlobal(Offset.zero);
  final anchorSize = renderBox.size;
  final screenSize = MediaQuery.of(context).size;

  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) => _UserMenuOverlay(
      anchorTopLeft: anchorTopLeft,
      anchorSize: anchorSize,
      screenSize: screenSize,
      onClose: () => entry.remove(),
      onOpenProfile: onOpenProfile,
      onLogout: onLogout,
    ),
  );
  overlay.insert(entry);
}

class _UserMenuOverlay extends StatefulWidget {
  final Offset anchorTopLeft;
  final Size anchorSize;
  final Size screenSize;
  final VoidCallback onClose;
  final VoidCallback onOpenProfile;
  final VoidCallback onLogout;

  const _UserMenuOverlay({
    required this.anchorTopLeft,
    required this.anchorSize,
    required this.screenSize,
    required this.onClose,
    required this.onOpenProfile,
    required this.onLogout,
  });

  @override
  State<_UserMenuOverlay> createState() => _UserMenuOverlayState();
}

class _UserMenuOverlayState extends State<_UserMenuOverlay> {
  bool _isLoadingRealms = true;
  List<RealmSummary> _realms = const [];

  @override
  void initState() {
    super.initState();
    EntityApi().getMyRealmsRequest().then((realms) {
      if (!mounted) return;
      setState(() {
        _realms = realms;
        _isLoadingRealms = false;
      });
    });
  }

  /// Hands the actual switch call off to a dedicated full-screen
  /// /switching route instead of running it here - the switch does a
  /// wholesale AppState reset (see EntityApi), and running that while this
  /// popover's own StoreConnector is still live was fragile. Matches
  /// webapp's own post-switch full page reload much more directly: nothing
  /// else is on screen while it happens.
  ///
  /// Navigates BEFORE closing, not after - widget.onClose() removes this
  /// OverlayEntry synchronously, which deactivates this exact context. Any
  /// context.go/push call made on it afterward is a deactivated-widget
  /// lookup and silently fails (surfaced as "page not found") - every
  /// navigation call site in this file follows this same navigate-then-
  /// close order for that reason.
  void _switchTo(BuildContext context, Future<bool> Function() call) {
    context.go('/switching', extra: call);
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final anchorCenterX = widget.anchorTopLeft.dx + widget.anchorSize.width / 2;
    final popoverLeft = (anchorCenterX - _popoverWidth / 2)
        .clamp(8.0, widget.screenSize.width - _popoverWidth - 8.0);
    final pointerLeft = (anchorCenterX - popoverLeft - _pointerSize / 2)
        .clamp(16.0, _popoverWidth - 16.0 - _pointerSize);
    final popoverBottom =
        widget.screenSize.height - widget.anchorTopLeft.dy + 4;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: const SizedBox.shrink(),
          ),
        ),
        Positioned(
          left: popoverLeft,
          bottom: popoverBottom,
          width: _popoverWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 440),
                decoration: BoxDecoration(
                  color: p.surface,
                  border: Border.all(color: p.border),
                  borderRadius: BorderRadius.circular(CLRadii.md),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _MenuContent(
                  realms: _realms,
                  isLoadingRealms: _isLoadingRealms,
                  // Entity-aware, same target as the top-bar avatar
                  // (home_tab_scaffold.dart): your personal Profile tab
                  // normally, or the switched-to page's own read-only
                  // profile screen while acting as it. Navigates before
                  // closing - see _switchTo's doc comment on why order
                  // matters here.
                  onTapProfile: () {
                    final user =
                        StoreProvider.of<AppState>(context).state.userAuth.user;
                    if (user.isActingAsEntity) {
                      context.push(
                          '/realm/${user.activeEntity?.slug ?? user.activeEntity?.id}');
                    } else {
                      widget.onOpenProfile();
                    }
                    widget.onClose();
                  },
                  onTapSettings: () {
                    context.push('/settings');
                    widget.onClose();
                  },
                  onTapSwitchToSelf: () =>
                      _switchTo(context, () => EntityApi().switchBackRequest()),
                  onTapSwitchToPage: (realm) => _switchTo(
                      context, () => EntityApi().switchEntityRequest(realm.id)),
                  onTapLogout: () {
                    widget.onClose();
                    widget.onLogout();
                  },
                ),
              ),
              // Pointer triangle - a 45°-rotated square straddling the card's
              // bottom edge, offset so its tip always lines up with the
              // anchor button's horizontal center even if the card itself
              // got clamped to stay on-screen.
              Padding(
                padding: EdgeInsets.only(left: pointerLeft),
                child: Transform.translate(
                  offset: const Offset(0, -_pointerSize / 2 - 1),
                  child: Transform.rotate(
                    angle: 0.7853981633974483, // 45deg
                    child: Container(
                      width: _pointerSize,
                      height: _pointerSize,
                      decoration: BoxDecoration(
                        color: p.surface,
                        border: Border.all(color: p.border),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuContent extends StatelessWidget {
  final List<RealmSummary> realms;
  final bool isLoadingRealms;
  final VoidCallback onTapProfile;
  final VoidCallback onTapSettings;
  final VoidCallback onTapSwitchToSelf;
  final void Function(RealmSummary) onTapSwitchToPage;
  final VoidCallback onTapLogout;

  const _MenuContent({
    required this.realms,
    required this.isLoadingRealms,
    required this.onTapProfile,
    required this.onTapSettings,
    required this.onTapSwitchToSelf,
    required this.onTapSwitchToPage,
    required this.onTapLogout,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState, ({UserAuth userAuth})>(
      distinct: true,
      builder: (context, state) {
        final user = state.userAuth.user;
        final isSwitched = user.isActingAsEntity;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuRow(
                onTap: onTapProfile,
                child: Row(
                  children: [
                    CLAvatar(
                      id: user.activeAvatarSeed,
                      name: user.activeDisplayName,
                      src: user.activeAvatarSrc,
                      size: 40,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.activeDisplayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: p.text),
                          ),
                          Text(user.activeHandle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: p.text2)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                child: Text("SWITCH ACCOUNT",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: p.text3)),
              ),
              _MenuRow(
                onTap: isSwitched ? onTapSwitchToSelf : null,
                highlighted: !isSwitched,
                child: Row(
                  children: [
                    Icon(Icons.person,
                        size: 18, color: !isSwitched ? p.brand : p.text2),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          user.personalDisplayName.isEmpty
                              ? user.username
                              : user.personalDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: !isSwitched ? p.brand : p.text)),
                    ),
                  ],
                ),
              ),
              if (isLoadingRealms) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    CLListRowSkeleton(
                        avatarSize: 26,
                        padding: EdgeInsets.symmetric(vertical: 4)),
                    SizedBox(height: 4),
                    CLListRowSkeleton(
                        avatarSize: 26,
                        padding: EdgeInsets.symmetric(vertical: 4)),
                  ]),
                ),
              ] else if (realms.isEmpty) ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text("No pages to manage",
                      style: TextStyle(fontSize: 12, color: p.text2)),
                ),
              ] else ...[
                for (final realm in realms)
                  _MenuRow(
                    onTap: user.activeEntity?.realmId == realm.id
                        ? null
                        : () => onTapSwitchToPage(realm),
                    highlighted: user.activeEntity?.realmId == realm.id,
                    child: Row(
                      children: [
                        CLAvatar(
                          id: realm.id,
                          name: realm.name,
                          src: realm.profile,
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(realm.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: user.activeEntity?.realmId == realm.id
                                      ? p.brand
                                      : p.text)),
                        ),
                      ],
                    ),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1, color: p.border),
              ),
              // Hidden while acting as a page - Settings edits the personal
              // account, which doesn't apply here. Should eventually route
              // to a "Manage realm" settings screen for the active page
              // instead (not built yet), rather than just being absent.
              if (!user.isActingAsEntity)
                _MenuRow(
                  onTap: onTapSettings,
                  child: Row(
                    children: [
                      Icon(Icons.settings_outlined, size: 18, color: p.text2),
                      const SizedBox(width: 10),
                      Text("Settings",
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: p.text)),
                    ],
                  ),
                ),
              _MenuRow(
                onTap: onTapLogout,
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: p.pink),
                    const SizedBox(width: 10),
                    Text("Logout",
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p.pink)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      converter: (store) => (userAuth: store.state.userAuth),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final VoidCallback? onTap;
  final bool highlighted;
  final Widget child;

  const _MenuRow(
      {required this.onTap, this.highlighted = false, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Material(
      color: highlighted ? p.brandSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: child,
        ),
      ),
    );
  }
}
