import 'package:chatterloop_app/core/design/app_button.dart';
import 'package:chatterloop_app/core/design/app_colors.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class UserProfileScreen extends StatefulWidget {
  final String username;
  const UserProfileScreen({super.key, required this.username});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  PublicProfile? profile;
  bool isLoading = true;
  bool notFound = false;
  bool isRequestingContact = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await APIRequests().getPublicProfileRequest(widget.username);
    if (!mounted) return;
    setState(() {
      profile = result;
      notFound = result == null;
      isLoading = false;
    });
  }

  Future<void> _addContact() async {
    if (profile == null) return;
    setState(() => isRequestingContact = true);
    final ok = await APIRequests().requestContactRequest(profile!.id);
    if (!mounted) return;
    setState(() => isRequestingContact = false);
    if (ok) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        title: Text("Profile", style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : notFound || profile == null
              ? Center(
                  child: Text("This profile is unavailable",
                      style: TextStyle(color: AppColors.textPrimary)))
              : SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      ClipOval(
                        child: Container(
                          width: 96,
                          height: 96,
                          color: AppColors.border,
                          child: profile!.profile != null &&
                                  profile!.profile!.isNotEmpty
                              ? Image.network(profile!.profile!,
                                  fit: BoxFit.cover)
                              : Icon(Icons.person,
                                  size: 48, color: AppColors.textPrimary),
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                          profile!.displayName.isEmpty
                              ? profile!.username
                              : profile!.displayName,
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text("@${profile!.username}",
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 13)),
                      SizedBox(height: 20),
                      if (profile!.connectionAccomplished == true)
                        AppButton(
                          label: "Message",
                          onPressed: profile!.connectionId == null
                              ? null
                              : () => context.push(
                                  '/conversation/${profile!.connectionId}'),
                        )
                      else if (profile!.hasConnection == true)
                        AppButton(label: "Request Pending", onPressed: null)
                      else if (profile!.hasConnection == false)
                        AppButton(
                            label: "Add Contact",
                            onPressed: _addContact,
                            loading: isRequestingContact),
                    ],
                  ),
                ),
    );
  }
}
