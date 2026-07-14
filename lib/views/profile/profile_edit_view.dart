import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late UserAccount _original;
  final _firstController = TextEditingController();
  final _middleController = TextEditingController();
  final _lastController = TextEditingController();
  final _usernameController = TextEditingController();
  String? gender;
  bool _initialized = false;

  bool isSaving = false;
  bool isUploadingAvatar = false;
  bool isUploadingCover = false;
  String? errorMessage;
  String? infoMessage;

  void _initFrom(UserAccount user) {
    if (_initialized) return;
    _original = user;
    _firstController.text = user.firstname;
    _middleController.text = user.middlename == "N/A" ? "" : user.middlename;
    _lastController.text = user.lastname;
    _usernameController.text = user.username;
    gender = user.gender;
    _initialized = true;
  }

  Future<void> _save() async {
    final firstName = _firstController.text;
    final middleName = _middleController.text;
    final lastName = _lastController.text;
    final username = _usernameController.text;

    if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
      setState(() => errorMessage = "First and last name are required");
      return;
    }

    final fieldsToUpdate = <String, dynamic>{};
    if (firstName.trim() != _original.firstname) {
      fieldsToUpdate['first_name'] = firstName.trim();
    }
    if (middleName.trim() != _original.middlename) {
      fieldsToUpdate['middle_name'] =
          middleName.trim().isEmpty ? "N/A" : middleName.trim();
    }
    if (lastName.trim() != _original.lastname) {
      fieldsToUpdate['last_name'] = lastName.trim();
    }
    if (username.trim() != _original.username) {
      fieldsToUpdate['username'] = username.trim();
    }
    if (gender != null && gender != _original.gender) {
      fieldsToUpdate['gender'] = gender;
    }

    if (fieldsToUpdate.isEmpty) {
      context.pop();
      return;
    }

    setState(() {
      isSaving = true;
      errorMessage = null;
    });

    final data = await APIRequests().updateProfileRequest(fieldsToUpdate);

    if (!mounted) return;
    if (data == null) {
      setState(() {
        isSaving = false;
        errorMessage = "Could not save changes. Please try again.";
      });
      return;
    }

    _applyUpdatedAccount(UserAccount.fromDjangoJwt(data,
        allowedModules: _original.allowedModules,
        activeEntity: _original.activeEntity,
        personalEntityId: _original.personalEntityId));

    setState(() => isSaving = false);
    if (mounted) context.pop();
  }

  void _applyUpdatedAccount(UserAccount account) {
    StoreProvider.of<AppState>(context)
        .dispatch(DispatchModel(setUserAuthT, UserAuth(true, account)));
    setState(() {
      _original = account;
      _initialized = false;
    });
    _initFrom(account);
  }

  Future<void> _pickAndUpload(bool isCover) async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() {
      if (isCover) {
        isUploadingCover = true;
      } else {
        isUploadingAvatar = true;
      }
      infoMessage = null;
      errorMessage = null;
    });

    final uploaded =
        await APIRequests().uploadMediaRequest(picked.path, 'image/jpeg');
    if (uploaded == null) {
      if (!mounted) return;
      setState(() {
        isUploadingAvatar = false;
        isUploadingCover = false;
        errorMessage = "Upload failed. Please try again.";
      });
      return;
    }

    final ok = await APIRequests().setProfileOrCoverMediaRequest(
      url: uploaded.url,
      mediaType: uploaded.mediaType,
      fileName: uploaded.fileName,
      isCover: isCover,
    );

    if (!mounted) return;
    setState(() {
      isUploadingAvatar = false;
      isUploadingCover = false;
    });

    if (!ok) {
      setState(() => errorMessage = "Upload failed. Please try again.");
      return;
    }

    _applyUpdatedAccount(UserAccount.fromDjangoJwt({
      'id': _original.id,
      'username': _original.username,
      'first_name': _original.firstname,
      'middle_name': _original.middlename,
      'last_name': _original.lastname,
      'email': _original.email,
      'is_active': _original.isActivated,
      'is_verified': _original.isVerified,
      'gender': _original.gender,
      'profile': isCover ? _original.profile : uploaded.url,
      'coverphoto': isCover ? uploaded.url : _original.coverphoto,
    },
        allowedModules: _original.allowedModules,
        activeEntity: _original.activeEntity,
        personalEntityId: _original.personalEntityId));

    setState(() => infoMessage =
        "Uploaded - this also appears as a new post on your feed.");
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState, AppState>(
      builder: (context, state) {
        _initFrom(state.userAuth.user);

        return Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(title: const Text("Edit Profile")),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                CLAvatar(
                  id: _original.id,
                  name: _original.username,
                  src: _original.profile != "none" ? _original.profile : null,
                  size: 84,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CLBtn(
                          label: "Change photo",
                          variant: CLBtnVariant.outline,
                          size: CLBtnSize.sm,
                          onPressed: isUploadingAvatar
                              ? null
                              : () => _pickAndUpload(false),
                          block: true),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CLBtn(
                          label: "Change cover",
                          variant: CLBtnVariant.outline,
                          size: CLBtnSize.sm,
                          onPressed: isUploadingCover
                              ? null
                              : () => _pickAndUpload(true),
                          block: true),
                    ),
                  ],
                ),
                if (infoMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(infoMessage!,
                        style: TextStyle(color: p.brand, fontSize: 12)),
                  ),
                const SizedBox(height: 20),
                CLField(
                    icon: Icons.person_outline,
                    label: "First name",
                    controller: _firstController),
                const SizedBox(height: 13),
                CLField(label: "Middle name", controller: _middleController),
                const SizedBox(height: 13),
                CLField(
                    icon: Icons.badge_outlined,
                    label: "Last name",
                    controller: _lastController),
                const SizedBox(height: 13),
                CLField(
                    icon: Icons.alternate_email,
                    label: "Username",
                    controller: _usernameController),
                const SizedBox(height: 13),
                Text('Gender',
                    style: TextStyle(
                        color: p.text2,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  children: ["male", "female", "other"].map((g) {
                    final active = gender == g;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () => setState(() => gender = g),
                          borderRadius: BorderRadius.circular(CLRadii.sm),
                          child: Container(
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: active ? p.brand : p.surface,
                              border: Border.all(
                                  color:
                                      active ? Colors.transparent : p.border2),
                              borderRadius: BorderRadius.circular(CLRadii.sm),
                            ),
                            child: Text(g,
                                style: TextStyle(
                                    color: active ? Colors.white : p.text2,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 13),
                Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                      color: p.surface3,
                      borderRadius: BorderRadius.circular(CLRadii.sm)),
                  child: Text(
                    (_original.email == null || _original.email!.isEmpty)
                        ? "No email on file"
                        : "${_original.email} (changing email is temporarily disabled)",
                    style: TextStyle(color: p.text3, fontSize: 12),
                  ),
                ),
                if (errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(errorMessage!,
                        style: TextStyle(color: p.pink, fontSize: 13)),
                  ),
                const SizedBox(height: 18),
                CLBtn(
                  label: isSaving ? "Saving…" : "Save",
                  size: CLBtnSize.lg,
                  block: true,
                  onPressed: isSaving ? null : _save,
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
