// Device Sessions settings section - the mobile counterpart of webapp's
// DeviceSessions.tsx. Lists active sessions (GET /api/user/devices) and lets
// the user sign out of any that isn't the current device (DELETE
// /api/user/devices {sessionID}).

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/settings_api.dart';
import 'package:chatterloop_app/models/user_models/device_session_model.dart';
import 'package:flutter/material.dart';

class DeviceSessionsScreen extends StatefulWidget {
  const DeviceSessionsScreen({super.key});

  @override
  State<DeviceSessionsScreen> createState() => _DeviceSessionsScreenState();
}

class _DeviceSessionsScreenState extends State<DeviceSessionsScreen> {
  bool _loading = true;
  List<DeviceSession> _sessions = const [];
  String? _revokingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sessions = await SettingsApi().listDeviceSessions();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  Future<void> _revoke(DeviceSession s) async {
    setState(() => _revokingId = s.sessionID);
    final ok = await SettingsApi().revokeDeviceSession(s.sessionID);
    if (!mounted) return;
    setState(() {
      _revokingId = null;
      if (ok) {
        _sessions =
            _sessions.where((x) => x.sessionID != s.sessionID).toList();
      }
    });
  }

  IconData _deviceIcon(String type) {
    if (type == 'mobile') return Icons.smartphone;
    if (type == 'tablet') return Icons.tablet_mac;
    return Icons.computer;
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text('Device Sessions')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              "See where you're logged in and sign out of devices you don't recognize.",
              style: TextStyle(fontSize: 14, color: p.text2),
            ),
            const SizedBox(height: 16),
            if (_loading)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator(color: p.brand)),
              )
            else if (_sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                  child: Text('No active sessions found.',
                      style: TextStyle(color: p.text2)),
                ),
              )
            else
              for (final s in _sessions) ...[
                _sessionTile(p, s),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Widget _sessionTile(CLPalette p, DeviceSession s) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle),
            child: Icon(_deviceIcon(s.deviceType), size: 18, color: p.text2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '${s.browser} on ${s.os}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p.text)),
                    if (s.isCurrentDevice)
                      TextSpan(
                          text: '  · This device',
                          style: TextStyle(fontSize: 11, color: p.brand)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${s.ip} · ${s.status ? 'Active now' : 'Last seen ${_timeSince(s.lastSeen)}'}',
                  style: TextStyle(fontSize: 12, color: p.text2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!s.isCurrentDevice) ...[
            const SizedBox(width: 8),
            _signOutBtn(p, s),
          ],
        ],
      ),
    );
  }

  Widget _signOutBtn(CLPalette p, DeviceSession s) {
    final revoking = _revokingId == s.sessionID;
    return TextButton(
      onPressed: revoking ? null : () => _revoke(s),
      style: TextButton.styleFrom(
        backgroundColor: p.surface,
        foregroundColor: p.text,
        minimumSize: const Size(80, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CLRadii.sm)),
      ),
      child: Text(revoking ? 'Signing out…' : 'Sign out',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  String _timeSince(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }
}
