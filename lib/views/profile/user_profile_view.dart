import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
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
    final p = cl(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text("Profile")),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: p.brand))
          : notFound || profile == null
              ? Center(
                  child: Text("This profile is unavailable",
                      style: TextStyle(color: p.text2)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      CLAvatar(
                          id: profile!.id,
                          name: profile!.displayName,
                          src: profile!.profile,
                          size: 96),
                      const SizedBox(height: 12),
                      Text(
                          profile!.displayName.isEmpty
                              ? profile!.username
                              : profile!.displayName,
                          style: TextStyle(
                              color: p.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                      Text("@${profile!.username}",
                          style: TextStyle(color: p.text2, fontSize: 13)),
                      const SizedBox(height: 20),
                      if (profile!.connectionAccomplished == true)
                        CLBtn(
                          label: "Message",
                          size: CLBtnSize.lg,
                          block: true,
                          onPressed: profile!.connectionId == null
                              ? null
                              : () => context.push(
                                  '/conversation/${profile!.connectionId}'),
                        )
                      else if (profile!.hasConnection == true)
                        CLBtn(
                            label: "Request Pending",
                            size: CLBtnSize.lg,
                            block: true,
                            variant: CLBtnVariant.outline,
                            onPressed: null)
                      else if (profile!.hasConnection == false)
                        CLBtn(
                            label: isRequestingContact
                                ? "Sending…"
                                : "Add Contact",
                            size: CLBtnSize.lg,
                            block: true,
                            onPressed:
                                isRequestingContact ? null : _addContact),
                    ],
                  ),
                ),
    );
  }
}
