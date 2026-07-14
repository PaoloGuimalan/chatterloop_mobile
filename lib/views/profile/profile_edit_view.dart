import 'package:chatterloop_app/core/design/app_button.dart';
import 'package:chatterloop_app/core/design/app_colors.dart';
import 'package:chatterloop_app/core/design/app_text_field.dart';
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
  late String firstName;
  late String middleName;
  late String lastName;
  late String username;
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
    firstName = user.firstname;
    middleName = user.middlename;
    lastName = user.lastname;
    username = user.username;
    gender = user.gender;
    _initialized = true;
  }

  Future<void> _save() async {
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
    return StoreConnector<AppState, AppState>(
      builder: (context, state) {
        _initFrom(state.userAuth.user);

        return Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            backgroundColor: AppColors.white,
            elevation: 0,
            title: Text("Edit Profile",
                style: TextStyle(color: AppColors.textPrimary)),
            iconTheme: IconThemeData(color: AppColors.textPrimary),
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _photoButton(
                        label: "Change photo",
                        loading: isUploadingAvatar,
                        onPressed: () => _pickAndUpload(false)),
                    SizedBox(width: 10),
                    _photoButton(
                        label: "Change cover",
                        loading: isUploadingCover,
                        onPressed: () => _pickAndUpload(true)),
                  ],
                ),
                if (infoMessage != null)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(infoMessage!,
                        style: TextStyle(color: AppColors.brand, fontSize: 12)),
                  ),
                SizedBox(height: 16),
                AppTextField(
                    hint: "First name",
                    onChanged: (v) => firstName = v,
                    obscureText: false),
                SizedBox(height: 10),
                AppTextField(
                    hint: "Middle name", onChanged: (v) => middleName = v),
                SizedBox(height: 10),
                AppTextField(hint: "Last name", onChanged: (v) => lastName = v),
                SizedBox(height: 10),
                AppTextField(hint: "Username", onChanged: (v) => username = v),
                SizedBox(height: 10),
                Container(
                  constraints: BoxConstraints(minHeight: 50),
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(10)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      hint: Text("Gender"),
                      value: gender,
                      items: ["male", "female", "other"]
                          .map(
                              (g) => DropdownMenuItem(value: g, child: Text(g)))
                          .toList(),
                      onChanged: (v) => setState(() => gender = v),
                    ),
                  ),
                ),
                SizedBox(height: 10),
                Container(
                  constraints: BoxConstraints(minHeight: 50),
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    (_original.email == null || _original.email!.isEmpty)
                        ? "No email on file"
                        : "${_original.email} (changing email is temporarily disabled)",
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 12),
                  ),
                ),
                if (errorMessage != null)
                  Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(errorMessage!,
                        style:
                            TextStyle(color: AppColors.danger, fontSize: 13)),
                  ),
                SizedBox(height: 16),
                AppButton(label: "Save", onPressed: _save, loading: isSaving),
              ],
            ),
          ),
        );
      },
      converter: (store) => store.state,
    );
  }

  Widget _photoButton(
      {required String label,
      required bool loading,
      required VoidCallback onPressed}) {
    return Expanded(
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label, style: TextStyle(fontSize: 12)),
      ),
    );
  }
}
