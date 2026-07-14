import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
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
  bool isOpeningMessage = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await ProfileApi().getPublicProfileRequest(widget.username);
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
    final ok = await ContactsApi().requestContactRequest(profile!.id);
    if (!mounted) return;
    setState(() => isRequestingContact = false);
    if (ok) {
      await _load();
    }
  }

  /// Mirrors webapp's Profile.tsx Message button: independent of
  /// connection status. If already connected, jump straight to the
  /// existing conversation; otherwise get-or-create one via /m/crtc.
  Future<void> _openMessage() async {
    if (profile == null) return;

    if (profile!.connectionAccomplished == true &&
        profile!.connectionId != null) {
      context.push('/conversation/${profile!.connectionId}');
      return;
    }

    setState(() => isOpeningMessage = true);
    final conversationId = await ConversationsApi()
        .createInitialConversationRequest(profile!.entityId);
    if (!mounted) return;
    setState(() => isOpeningMessage = false);

    if (conversationId != null) {
      context.push('/conversation/$conversationId');
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
                      CLBtn(
                        label: isOpeningMessage ? "Opening…" : "Message",
                        size: CLBtnSize.lg,
                        block: true,
                        onPressed: isOpeningMessage ? null : _openMessage,
                      ),
                      const SizedBox(height: 10),
                      if (profile!.hasConnection == true &&
                          profile!.connectionAccomplished != true)
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
                            variant: CLBtnVariant.outline,
                            onPressed:
                                isRequestingContact ? null : _addContact),
                    ],
                  ),
                ),
    );
  }
}
