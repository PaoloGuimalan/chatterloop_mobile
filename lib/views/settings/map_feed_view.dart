// Map Feed Access settings section - mobile counterpart of webapp's
// MapFeedSettings.tsx. Two local toggles: "Enable location", and (only when
// that's on) "Share location". Persisted client-side per account, matching
// the webapp (there's no server endpoint for these).

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/utils/map_feed_prefs.dart';
import 'package:flutter/material.dart';

class MapFeedSettingsScreen extends StatefulWidget {
  const MapFeedSettingsScreen({super.key});

  @override
  State<MapFeedSettingsScreen> createState() => _MapFeedSettingsScreenState();
}

class _MapFeedSettingsScreenState extends State<MapFeedSettingsScreen> {
  late final String _entityId;
  bool _enableLocation = false;
  bool _shareLocation = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _entityId = appStore.state.userAuth.user.entityId;
    _load();
  }

  Future<void> _load() async {
    final (enable, share) = await MapFeedPrefs.read(_entityId);
    if (!mounted) return;
    setState(() {
      _enableLocation = enable;
      _shareLocation = share;
      _loaded = true;
    });
  }

  Future<void> _setEnable(bool v) async {
    setState(() => _enableLocation = v);
    await MapFeedPrefs.setEnable(_entityId, v);
  }

  Future<void> _setShare(bool v) async {
    setState(() => _shareLocation = v);
    await MapFeedPrefs.setShare(_entityId, v);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text('Map Feed Access')),
      body: !_loaded
          ? Center(child: CircularProgressIndicator(color: p.brand))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _toggleSection(
                    p,
                    title: 'Enable location',
                    desc: 'Let the app use your location.',
                    value: _enableLocation,
                    onLabel: 'Enabled',
                    offLabel: 'Disabled',
                    onChanged: _setEnable,
                  ),
                  if (_enableLocation) ...[
                    const SizedBox(height: 26),
                    _toggleSection(
                      p,
                      title: 'Share location',
                      desc:
                          'Let your friends know where you are, and let anyone nearby see your location.',
                      value: _shareLocation,
                      onLabel: 'Sharing',
                      offLabel: 'Disabled',
                      onChanged: _setShare,
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _toggleSection(
    CLPalette p, {
    required String title,
    required String desc,
    required bool value,
    required String onLabel,
    required String offLabel,
    required ValueChanged<bool> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(height: 4),
        Text(desc, style: TextStyle(fontSize: 13, color: p.text2, height: 1.4)),
        const SizedBox(height: 8),
        Row(
          children: [
            Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: p.brand,
            ),
            const SizedBox(width: 6),
            Text(value ? onLabel : offLabel,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: p.text2)),
          ],
        ),
      ],
    );
  }
}
