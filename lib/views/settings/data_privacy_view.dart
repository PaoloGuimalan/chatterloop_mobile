// Data & Privacy settings section - mobile counterpart of webapp's
// DataPrivacy.tsx. "Export your data" fetches GET /api/user/me/export and,
// instead of the webapp's browser download, hands the JSON to the native
// share sheet (save to Files/Drive/send). "Delete your account" is a
// two-step confirm that DELETEs /api/user/me and then signs out - exactly
// the webapp's flow (DeleteAccountRequest -> LogoutRequest on success).

import 'dart:convert';
import 'dart:io';

import 'package:chatterloop_app/core/auth/consent_prefs.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/settings_api.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class DataPrivacyScreen extends StatefulWidget {
  const DataPrivacyScreen({super.key});

  @override
  State<DataPrivacyScreen> createState() => _DataPrivacyScreenState();
}

class _DataPrivacyScreenState extends State<DataPrivacyScreen> {
  bool _exporting = false;
  bool _deleting = false;
  bool _confirmDelete = false;

  void _snack(String m) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final data = await SettingsApi().exportAccountData();
    if (!mounted) return;
    if (data == null) {
      setState(() => _exporting = false);
      _snack('Could not export your data. Please try again.');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/chatterloop-data-export-${DateTime.now().millisecondsSinceEpoch}.json';
      await File(path)
          .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      if (!mounted) return;
      setState(() => _exporting = false);
      await Share.shareXFiles(
        [XFile(path, mimeType: 'application/json')],
        subject: 'Chatterloop data export',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _exporting = false);
      _snack('Could not prepare the export file.');
    }
  }

  Future<void> _delete() async {
    if (!_confirmDelete) {
      setState(() => _confirmDelete = true);
      return;
    }
    setState(() => _deleting = true);
    final ok = await SettingsApi().deleteAccount();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _deleting = false;
        _confirmDelete = false;
      });
      _snack('Could not delete your account. Please try again.');
      return;
    }
    // Deleted server-side - sign out and return to login, mirroring the
    // webapp's LogoutRequest on delete success.
    await ApiClient.instance.clearToken();
    await ConsentPrefs.clear();
    if (!mounted) return;
    StoreProvider.of<AppState>(context).dispatch(
        DispatchModel(setUserAuthT, UserAuth(false, UserAccount.empty)));
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    const danger = Color(0xFFD64545);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text('Data & Privacy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(
                p,
                'Export your data',
                p.text,
                'Download a copy of the personal data we hold about you, including your profile, posts, comments, diary entries, realm memberships, messages, and consent history.'),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: CLBtn(
                label: _exporting ? 'Preparing…' : 'Download my data',
                variant: CLBtnVariant.soft,
                size: CLBtnSize.md,
                onPressed: _exporting ? null : _export,
              ),
            ),
            const SizedBox(height: 30),
            _header(
                p,
                'Delete your account',
                danger,
                "This permanently deactivates your account and removes your identifying information. Your account will become unusable and you'll be signed out immediately. This cannot be undone."),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                CLBtn(
                  label: _deleting
                      ? 'Deleting…'
                      : (_confirmDelete
                          ? 'Confirm permanent deletion'
                          : 'Delete my account'),
                  variant: CLBtnVariant.danger,
                  size: CLBtnSize.md,
                  onPressed: _deleting ? null : _delete,
                ),
                if (_confirmDelete && !_deleting)
                  CLBtn(
                    label: 'Cancel',
                    variant: CLBtnVariant.soft,
                    size: CLBtnSize.md,
                    onPressed: () => setState(() => _confirmDelete = false),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(CLPalette p, String title, Color titleColor, String desc) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: titleColor)),
          const SizedBox(height: 4),
          Text(desc,
              style: TextStyle(fontSize: 13, color: p.text2, height: 1.4)),
        ],
      );
}
