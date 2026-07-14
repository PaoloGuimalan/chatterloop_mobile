// ignore_for_file: use_build_context_synchronously

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  bool _refreshed = false;

  /// Mirrors the webapp: it always round-trips through GET
  /// /api/user/auth/:username/ for the profile screen, even for your own
  /// profile, rather than only trusting the JWT-cached copy from login.
  Future<void> _refreshFromServer(BuildContext context, String username) async {
    if (_refreshed || username.isEmpty) return;
    _refreshed = true;

    final fresh = await ProfileApi().getPublicProfileRequest(username);
    if (!mounted || fresh == null) return;

    final current = StoreProvider.of<AppState>(context).state.userAuth.user;
    StoreProvider.of<AppState>(context).dispatch(DispatchModel(
        setUserAuthT,
        UserAuth(
            true,
            UserAccount.fromPublicProfile(fresh,
                allowedModules: current.allowedModules,
                activeEntity: current.activeEntity,
                personalEntityId: current.personalEntityId))));
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState, AppState>(
      builder: (context, state) {
        final user = state.userAuth.user;
        _refreshFromServer(context, user.username);

        final displayName = [
          user.firstname,
          if (user.middlename.isNotEmpty && user.middlename != "N/A")
            user.middlename,
          user.lastname,
        ].where((part) => part.trim().isNotEmpty).join(" ");

        return Scaffold(
          backgroundColor: p.bg,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                CLAvatar(
                  id: user.id,
                  name: displayName.isEmpty ? user.username : displayName,
                  src: user.profile != "none" ? user.profile : null,
                  size: 96,
                ),
                const SizedBox(height: 12),
                Text(displayName.isEmpty ? user.username : displayName,
                    style: TextStyle(
                        color: p.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                Text("@${user.username}",
                    style: TextStyle(color: p.text2, fontSize: 13)),
                if (!user.isVerified)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: CLBadge(
                        label: "Email not verified", tone: CLBadgeTone.pink),
                  ),
                const SizedBox(height: 20),
                CLBtn(
                  label: "Edit Profile",
                  size: CLBtnSize.lg,
                  block: true,
                  onPressed: () => context.push('/profile/edit'),
                ),
              ],
            ),
          ),
        );
      },
      converter: (store) => store.state,
    );
  }
}
