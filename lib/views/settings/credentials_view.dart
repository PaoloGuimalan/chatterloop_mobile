// Credentials settings section - mobile counterpart of webapp's
// Credentials.tsx. Username (editable) and Email (disabled - the webapp notes
// email change is "temporarily disabled"). Save sends the username to
// PUT /api/user/me only when it actually changed; Reset restores the opened
// value.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class CredentialsScreen extends StatefulWidget {
  const CredentialsScreen({super.key});

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> {
  late UserAccount _original;
  bool _initialized = false;
  bool _saving = false;
  final _username = TextEditingController();

  void _initFrom(UserAccount user) {
    if (_initialized) return;
    _original = user;
    _resetFields();
    _initialized = true;
  }

  void _resetFields() {
    _username.text = _original.username;
  }

  void _alert(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final username = _username.text.trim();
    if (username.isEmpty) {
      _alert('Username cannot be empty');
      return;
    }
    if (username == _original.username) {
      _alert('There are no fields to be updated');
      return;
    }

    setState(() => _saving = true);
    final data = await ProfileApi().updateProfileRequest({'username': username});
    if (!mounted) return;
    if (data == null) {
      setState(() => _saving = false);
      _alert('Could not save changes. Please try again.');
      return;
    }

    final account = UserAccount.fromDjangoJwt(data,
        allowedModules: _original.allowedModules,
        activeEntity: _original.activeEntity,
        personalEntityId: _original.personalEntityId);
    StoreProvider.of<AppState>(context)
        .dispatch(DispatchModel(setUserAuthT, UserAuth(true, account)));
    setState(() {
      _saving = false;
      _original = account;
      _initialized = false;
    });
    _initFrom(account);
    _alert('Username updated');
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState, ({UserAuth userAuth})>(
      distinct: true,
      converter: (store) => (userAuth: store.state.userAuth),
      builder: (context, state) {
        _initFrom(state.userAuth.user);
        final email = _original.email ?? '';
        return Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(title: const Text('Credentials')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionHeader(p, 'Username',
                    'Changing your username will affect how people contact, mention, and access your contents.'),
                const SizedBox(height: 10),
                CLField(
                    icon: Icons.alternate_email,
                    label: 'Username',
                    controller: _username),
                const SizedBox(height: 26),
                _sectionHeader(p, 'Email',
                    'Replace your user email. Note that this will require verification from your old and new email address (temporarily disabled).'),
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(minHeight: 46),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: p.surface3,
                    borderRadius: BorderRadius.circular(CLRadii.sm),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.email_outlined, size: 20, color: p.text3),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          email.isEmpty ? 'No email on file' : email,
                          style: TextStyle(color: p.text3, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CLBtn(
                      label: _saving ? 'Saving…' : 'Save',
                      onPressed: _saving ? null : _save,
                      size: CLBtnSize.md,
                    ),
                    const SizedBox(width: 8),
                    CLBtn(
                      label: 'Reset',
                      variant: CLBtnVariant.soft,
                      onPressed: _saving ? null : () => setState(_resetFields),
                      size: CLBtnSize.md,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionHeader(CLPalette p, String title, String desc) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(height: 2),
          Text(desc, style: TextStyle(fontSize: 13, color: p.text2)),
        ],
      );
}
