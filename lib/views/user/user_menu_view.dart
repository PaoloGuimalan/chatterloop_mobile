import 'package:chatterloop_app/core/auth/logout_user.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/requests/entity_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/user_menu_popover.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/views/realm/realm_manage_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

/// Full account destination for the bottom Menu tab; the header keeps its popover.
class UserMenuView extends StatefulWidget {
  const UserMenuView({super.key});
  @override
  State<UserMenuView> createState() => _UserMenuViewState();
}

class _UserMenuViewState extends State<UserMenuView> {
  List<RealmSummary> _realms = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final realms = await EntityApi().getMyRealmsRequest();
    if (!mounted) return;
    setState(() {
      _realms = realms;
      _loading = false;
    });
  }

  void _openProfile() {
    final user = StoreProvider.of<AppState>(context).state.userAuth.user;
    final handle = user.activeEntity?.slug ??
        user.activeEntity?.realmId ??
        user.activeEntity?.id;
    final target =
        user.isActingAsEntity ? '/realm/$handle' : '/user/${user.username}';
    context.push(target);
  }

  void _manageRealm() {
    final entity =
        StoreProvider.of<AppState>(context).state.userAuth.user.activeEntity;
    final target = entity?.realmId ?? entity?.slug ?? entity?.id ?? '';
    if (target.isEmpty) {
      CLAlerts.show("Couldn't open this page's settings.",
          type: CLAlertType.error);
      return;
    }
    openRealmManage(context, target);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Center(
        child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Your profile, accounts, and Chatterloop apps.',
                  style: TextStyle(fontSize: CLType.bodySm, color: p.text2)),
              const SizedBox(height: 14),
              Expanded(
                  child: Align(
                      alignment: Alignment.topCenter,
                      child: CLCard(
                        padding: const EdgeInsets.all(8),
                        child: RefreshIndicator(
                          onRefresh: _loadAccounts,
                          child: UserMenuContent(
                              realms: _realms,
                              isLoadingRealms: _loading,
                              showApps: true,
                              onTapProfile: _openProfile,
                              onTapSettings: () => context.push('/settings'),
                              onTapManageRealm: _manageRealm,
                              onTapSwitchToSelf: () => context.go('/switching',
                                  extra: () => EntityApi().switchBackRequest()),
                              onTapSwitchToPage: (realm) => context.go(
                                  '/switching',
                                  extra: () => EntityApi()
                                      .switchEntityRequest(realm.id)),
                              onTapLogout: () => logoutUser(context)),
                        ),
                      ))),
            ],
          )),
    ));
  }
}
