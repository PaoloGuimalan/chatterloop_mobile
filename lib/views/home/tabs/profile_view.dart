import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState, AppState>(
      builder: (context, state) {
        final user = state.userAuth.user;
        final displayName = [
          user.firstname,
          if (user.middlename.isNotEmpty && user.middlename != "N/A")
            user.middlename,
          user.lastname,
        ].where((part) => part.trim().isNotEmpty).join(" ");

        return Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(title: const Text("Profile")),
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
