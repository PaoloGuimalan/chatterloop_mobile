import 'package:chatterloop_app/core/design/app_button.dart';
import 'package:chatterloop_app/core/design/app_colors.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
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
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            backgroundColor: AppColors.white,
            elevation: 0,
            title:
                Text("Profile", style: TextStyle(color: AppColors.textPrimary)),
            iconTheme: IconThemeData(color: AppColors.textPrimary),
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                ClipOval(
                  child: Container(
                    width: 96,
                    height: 96,
                    color: AppColors.border,
                    child: user.profile != null &&
                            user.profile!.isNotEmpty &&
                            user.profile != "none"
                        ? Image.network(user.profile!, fit: BoxFit.cover)
                        : Icon(Icons.person,
                            size: 48, color: AppColors.textPrimary),
                  ),
                ),
                SizedBox(height: 12),
                Text(displayName.isEmpty ? user.username : displayName,
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text("@${user.username}",
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                SizedBox(height: 4),
                if (!user.isVerified)
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text("Email not verified",
                        style:
                            TextStyle(color: AppColors.danger, fontSize: 12)),
                  ),
                SizedBox(height: 20),
                AppButton(
                  label: "Edit Profile",
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
