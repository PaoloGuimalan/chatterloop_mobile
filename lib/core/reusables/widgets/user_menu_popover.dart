// Account menu anchored below the shell header avatar.

import 'dart:math' as math;

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/reusables/widgets/user_app_shortcuts.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/requests/entity_api.dart';
import 'package:chatterloop_app/views/realm/realm_manage_view.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
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

  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    // An OverlayEntry is built OUTSIDE the page's widget tree, so it inherits no
    // Material - and therefore no DefaultTextStyle. Any Text in here then falls
    // back to DefaultTextStyle.fallback, whose yellow double-underline
    // decoration shows through even when the Text sets its own size and colour:
    // that's what put yellow lines under "SWITCH ACCOUNT" and "No pages to
    // manage" (the only labels here not already inside a _MenuRow, which wraps
    // itself in Material for its ink splash). One Material at the root covers
    // the whole menu, including anything added to it later. transparency = no
    // paint of its own, so the popover's own decoration is untouched.
    builder: (overlayContext) => Material(
      type: MaterialType.transparency,
      child: _UserMenuOverlay(
        anchorTopLeft: anchorTopLeft,
        anchorSize: anchorSize,
        onClose: () => entry.remove(),
        onOpenProfile: onOpenProfile,
        onLogout: onLogout,
      ),
    ),
  );
  overlay.insert(entry);
}

class _UserMenuOverlay extends StatefulWidget {
  final Offset anchorTopLeft;
  final Size anchorSize;
  final VoidCallback onClose;
  final VoidCallback onOpenProfile;
  final VoidCallback onLogout;

  const _UserMenuOverlay({
    required this.anchorTopLeft,
    required this.anchorSize,
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
    final screen = MediaQuery.of(context);
    final width = math.min(_popoverWidth, screen.size.width - 16);
    final anchorCenterX = widget.anchorTopLeft.dx + widget.anchorSize.width / 2;
    final popoverLeft = (anchorCenterX - width / 2)
        .clamp(8.0, math.max(8.0, screen.size.width - width - 8))
        .toDouble();
    final pointerLeft = (anchorCenterX - popoverLeft - _pointerSize / 2)
        .clamp(8.0, math.max(8.0, width - 8 - _pointerSize))
        .toDouble();
    // Keep the pointer close to the avatar; its layout adds 14px above the card.
    final popoverTop = widget.anchorTopLeft.dy + widget.anchorSize.height - 4;
    final maxHeight = math.max(
        0.0,
        math.min(
            440.0,
            screen.size.height -
                screen.padding.bottom -
                screen.viewInsets.bottom -
                popoverTop -
                _pointerSize -
                8));

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
          top: popoverTop,
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(left: pointerLeft),
                child: Transform.translate(
                  offset: const Offset(0, _pointerSize / 2 + 1),
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
              Container(
                constraints: BoxConstraints(maxHeight: maxHeight),
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
                child: UserMenuContent(
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
                  onTapManageRealm: () {
                    final entity = StoreProvider.of<AppState>(context)
                        .state
                        .userAuth
                        .user
                        .activeEntity;
                    // realm_id FIRST, deliberately - webapp's onSettingsClick
                    // is `navigate(/realms/${activeEntityContext.realm_id})`,
                    // and unlike the profile row right above (which reaches
                    // for slug first, matching ITS webapp counterpart) the
                    // manage route is keyed by id. A page whose active-entity
                    // payload carries no slug would otherwise fall through to
                    // the entity id, which is not a realm id and resolves to
                    // nothing.
                    final target =
                        entity?.realmId ?? entity?.slug ?? entity?.id ?? '';
                    if (target.isEmpty) {
                      // Better than a tap that silently does nothing, which is
                      // indistinguishable from a broken button.
                      CLAlerts.show("Couldn't open this page's settings.",
                          type: CLAlertType.error);
                      widget.onClose();
                      return;
                    }
                    openRealmManage(context, target);
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
            ],
          ),
        ),
      ],
    );
  }
}

class UserMenuContent extends StatelessWidget {
  final bool showApps;
  final VoidCallback? onTapCommunities;
  final List<RealmSummary> realms;
  final bool isLoadingRealms;
  final VoidCallback onTapProfile;
  final VoidCallback onTapSettings;

  /// Taken instead of [onTapSettings] while acting as a page.
  final VoidCallback onTapManageRealm;
  final VoidCallback onTapSwitchToSelf;
  final void Function(RealmSummary) onTapSwitchToPage;
  final VoidCallback onTapLogout;

  const UserMenuContent({
    super.key,
    this.showApps = false,
    this.onTapCommunities,
    required this.realms,
    required this.isLoadingRealms,
    required this.onTapProfile,
    required this.onTapSettings,
    required this.onTapManageRealm,
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
          physics: showApps ? const AlwaysScrollableScrollPhysics() : null,
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
                      entityId: user.entityId,
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
                                fontSize: CLType.title,
                                fontWeight: FontWeight.w700,
                                color: p.text),
                          ),
                          Text(user.activeHandle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: CLType.caption, color: p.text2)),
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
                        fontSize: CLType.meta,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: p.text3)),
              ),
              _MenuRow(
                onTap: isSwitched ? onTapSwitchToSelf : null,
                highlighted: !isSwitched,
                child: Row(
                  children: [
                    // Your own face (or initials), like the page rows below -
                    // while acting as a page, this is the way back to you.
                    CLAvatar(
                      id: user.id,
                      name: user.personalDisplayName.isEmpty
                          ? user.username
                          : user.personalDisplayName,
                      src: user.profile != null && user.profile != "none"
                          ? user.profile
                          : null,
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          user.personalDisplayName.isEmpty
                              ? user.username
                              : user.personalDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: CLType.bodySm,
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
                      style:
                          TextStyle(fontSize: CLType.caption, color: p.text2)),
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
                                  fontSize: CLType.bodySm,
                                  fontWeight: FontWeight.w600,
                                  color: user.activeEntity?.realmId == realm.id
                                      ? p.brand
                                      : p.text)),
                        ),
                      ],
                    ),
                  ),
              ],
              if (showApps) ...[
                const SizedBox(height: 18),
                UserAppShortcuts(
                    onCommunities: onTapCommunities,
                    onSettings: user.isActingAsEntity
                        ? onTapManageRealm
                        : onTapSettings,
                    isActingAsPage: user.isActingAsEntity),
              ],
              Padding(
                padding: EdgeInsets.only(top: showApps ? 2 : 6, bottom: 6),
                child: Divider(height: 1, color: p.border),
              ),
              // REPLACED while acting as a page, not hidden. Settings edits
              // the personal account, which doesn't apply to a page - but
              // managing the page does, and this menu is the one surface that
              // already follows the acting entity, so the slot is the natural
              // home for it. (This is what the note here used to say was
              // missing.)
              if (!showApps)
                _MenuRow(
                  onTap:
                      user.isActingAsEntity ? onTapManageRealm : onTapSettings,
                  child: Row(
                    children: [
                      Icon(
                          user.isActingAsEntity
                              ? Icons.tune
                              : Icons.settings_outlined,
                          size: 18,
                          color: p.text2),
                      const SizedBox(width: 10),
                      Text(user.isActingAsEntity ? "Manage realm" : "Settings",
                          style: TextStyle(
                              fontSize: CLType.bodySm,
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
                            fontSize: CLType.bodySm,
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
