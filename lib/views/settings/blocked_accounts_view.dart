// Blocked Accounts settings section - mobile counterpart of webapp's
// BlockedAccounts.tsx. Lists accounts the user has blocked
// (GET /api/user/blocks) and unblocks any of them
// (DELETE /api/user/blocks {entityID}).

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/settings_api.dart';
import 'package:chatterloop_app/models/user_models/blocked_account_model.dart';
import 'package:flutter/material.dart';

class BlockedAccountsScreen extends StatefulWidget {
  const BlockedAccountsScreen({super.key});

  @override
  State<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends State<BlockedAccountsScreen> {
  bool _loading = true;
  List<BlockedAccount> _accounts = const [];
  String? _unblockingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final accounts = await SettingsApi().listBlockedAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _loading = false;
    });
  }

  Future<void> _unblock(BlockedAccount acc) async {
    setState(() => _unblockingId = acc.entityID);
    final ok = await SettingsApi().unblockAccount(acc.entityID);
    if (!mounted) return;
    setState(() {
      _unblockingId = null;
      if (ok) {
        _accounts =
            _accounts.where((a) => a.entityID != acc.entityID).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text('Blocked Accounts')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              "Accounts you've blocked can't contact you, see your posts, or find your profile in search.",
              style: TextStyle(fontSize: 14, color: p.text2),
            ),
            const SizedBox(height: 16),
            if (_loading)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator(color: p.brand)),
              )
            else if (_accounts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                  child: Text("You haven't blocked anyone.",
                      style: TextStyle(color: p.text2)),
                ),
              )
            else
              for (final acc in _accounts) ...[
                _accountTile(p, acc),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Widget _accountTile(CLPalette p, BlockedAccount acc) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: Row(
        children: [
          CLAvatar(
            id: acc.username,
            name: acc.firstName.isNotEmpty ? acc.firstName : acc.username,
            src: acc.profile != 'none' && acc.profile.isNotEmpty
                ? acc.profile
                : null,
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  acc.displayName.isEmpty ? '@${acc.username}' : acc.displayName,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: p.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text('@${acc.username}',
                    style: TextStyle(fontSize: 12, color: p.text2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _unblockBtn(p, acc),
        ],
      ),
    );
  }

  Widget _unblockBtn(CLPalette p, BlockedAccount acc) {
    final busy = _unblockingId == acc.entityID;
    return TextButton(
      onPressed: busy ? null : () => _unblock(acc),
      style: TextButton.styleFrom(
        backgroundColor: p.surface,
        foregroundColor: p.text,
        minimumSize: const Size(80, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CLRadii.sm)),
      ),
      child: Text(busy ? 'Unblocking…' : 'Unblock',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
