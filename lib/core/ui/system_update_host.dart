// The update screen. Mounted once, above the router (main.dart's builder), so
// it can cover any screen - the login screen included - without being a route
// that a back press or a redirect could take away.
//
// Required updates cover the app with no way past. Optional ones can be
// skipped, and stay skipped for that build.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/system_update_api.dart';
import 'package:chatterloop_app/core/utils/app_version.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SystemUpdateHost extends StatefulWidget {
  final Widget child;

  const SystemUpdateHost({super.key, required this.child});

  @override
  State<SystemUpdateHost> createState() => _SystemUpdateHostState();
}

class _SystemUpdateHostState extends State<SystemUpdateHost>
    with WidgetsBindingObserver {
  /// The build whose optional update was skipped. By build, so the same
  /// release does not come back every launch while a newer one still does.
  static const _skippedBuildKey = 'system_update_skipped_build';

  /// How long coming back to the app waits before asking again. A required
  /// release has to reach someone who leaves the app in the background for
  /// days, but not every switch back needs a request.
  static const _recheckAfter = Duration(minutes: 30);

  SystemUpdateInfo? _update;
  DateTime? _lastCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    if (last != null && DateTime.now().difference(last) < _recheckAfter) {
      return;
    }
    _check();
  }

  Future<void> _check() async {
    _lastCheck = DateTime.now();
    final update = await SystemUpdateApi().check();
    // Null means "nothing to offer" OR "could not ask" - so it never clears
    // what is already showing. Going offline must not be a way past a
    // required update; a restart (which updating is) asks afresh anyway.
    if (update == null || !mounted) return;
    if (!update.required) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt(_skippedBuildKey) == update.build) return;
    }
    if (!mounted) return;
    setState(() => _update = update);
  }

  Future<void> _skip(SystemUpdateInfo update) async {
    setState(() => _update = null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_skippedBuildKey, update.build);
  }

  Future<void> _openStore(SystemUpdateInfo update) async {
    var url = update.storeUrl;
    // Android's listing follows from the package name. iOS needs the App
    // Store id, which only the release row can supply.
    if (url.isEmpty &&
        AppVersion.platform == 'android' &&
        AppVersion.packageName.isNotEmpty) {
      url =
          'https://play.google.com/store/apps/details?id=${AppVersion.packageName}';
    }
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final update = _update;
    return Stack(
      children: [
        widget.child,
        if (update != null)
          Positioned.fill(
            child: _SystemUpdateScreen(
              update: update,
              onUpdate: () => _openStore(update),
              onSkip: update.required ? null : () => _skip(update),
            ),
          ),
      ],
    );
  }
}

class _SystemUpdateScreen extends StatelessWidget {
  final SystemUpdateInfo update;
  final VoidCallback onUpdate;

  /// Null for a required update - there is no way past it.
  final VoidCallback? onSkip;

  const _SystemUpdateScreen({
    required this.update,
    required this.onUpdate,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final title = update.title.isNotEmpty
        ? update.title
        : update.required
            ? 'Update required'
            : 'Update available';
    final message = update.required
        ? 'This version of Chatterloop is no longer supported. Update to '
            'version ${update.version} to keep using the app.'
        : 'Version ${update.version} of Chatterloop is available.';

    return Material(
      color: p.bg,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                children: [
                  const Spacer(),
                  const CLLogoTile(size: 88),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: CLType.hero,
                      fontWeight: FontWeight.w800,
                      color: p.text,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: CLType.body,
                      color: p.text2,
                      height: 1.4,
                    ),
                  ),
                  if (update.details.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    // Scrolls inside its card when the release notes are
                    // long, so the buttons can never be pushed off-screen.
                    Flexible(
                      flex: 4,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: p.surface,
                          borderRadius: BorderRadius.circular(CLRadii.md),
                          border: Border.all(color: p.border),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            update.details,
                            style: TextStyle(
                              fontSize: CLType.bodySm,
                              color: p.text2,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  CLBtn(
                    label: 'Update now',
                    onPressed: onUpdate,
                    size: CLBtnSize.lg,
                    block: true,
                  ),
                  if (onSkip != null) ...[
                    const SizedBox(height: 8),
                    CLBtn(
                      label: 'Not now',
                      onPressed: onSkip,
                      variant: CLBtnVariant.ghost,
                      size: CLBtnSize.lg,
                      block: true,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
