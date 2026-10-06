// An invite at its own route - `/invite/:token`.
//
// Where an invite's notification and its push lead (Django
// community/invite_rules.py invite_route - the apps always get this page, the
// web opens a conference's own lobby instead). It says who invited you to
// what, and takes the answer; accepting goes on to the realm when the app has
// a screen for it. Counterpart of the webapp's InvitePage.
//
// A CONFERENCE has no screen in the app. Its invite leads to the conference's
// lobby on the web - "Join conference" opens it in the browser, and the
// address is spelled out underneath to tap or copy - so nobody is left
// wondering where to go.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/invites_api.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/models/user_models/realm_invite_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> _launchInBrowser(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

class RealmInviteScreen extends StatefulWidget {
  final String token;

  /// Injectable for tests.
  final InvitesApi? api;

  /// Opens a web address outside the app. Injectable for tests.
  final Future<bool> Function(Uri uri) openExternal;

  const RealmInviteScreen({
    super.key,
    required this.token,
    this.api,
    this.openExternal = _launchInBrowser,
  });

  @override
  State<RealmInviteScreen> createState() => _RealmInviteScreenState();
}

class _RealmInviteScreenState extends State<RealmInviteScreen> {
  late final InvitesApi _api = widget.api ?? InvitesApi();

  RealmInvite? _invite;
  bool _loaded = false;

  /// The answer in flight - "accepted" or "declined".
  String? _answering;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final invite = await _api.getByToken(widget.token);
    if (!mounted) return;
    setState(() {
      // A join REQUEST shares the endpoint but is not something to answer
      // here - the host does that.
      _invite = invite != null && invite.kind == 'invite' ? invite : null;
      _loaded = true;
    });
  }

  Future<void> _answer(String status) async {
    final invite = _invite;
    if (invite == null || _answering != null) return;
    setState(() => _answering = status);
    // Null means it did not take - the reason is already on screen.
    final settled = await _api.answer(invite.token, status);
    if (!mounted) return;
    setState(() {
      _answering = null;
      if (settled != null) _invite = settled;
    });
    if (settled != null && status == 'accepted') {
      final destination = settled.destination;
      if (destination != null) context.pushReplacement(destination);
    }
  }

  /// The conference's lobby, in the browser. When it cannot be opened, the
  /// link is copied instead, so it can be pasted into one.
  Future<void> _openConference(String url) async {
    final opened = await widget.openExternal(Uri.parse(url));
    if (opened) return;
    await Clipboard.setData(ClipboardData(text: url));
    CLAlerts.show(
      "Couldn't open your browser - the conference link is copied.",
      type: CLAlertType.warning,
    );
  }

  Future<void> _copyConference(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    CLAlerts.show('Conference link copied.', type: CLAlertType.success);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final invite = _invite;

    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text('Invite')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            CLSpacing.contentGutter, 24, CLSpacing.contentGutter, 24),
        children: [
          if (!_loaded)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (invite == null)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: CLEmptyState(
                icon: Icons.link_off,
                iconBg: p.surface2,
                iconColor: p.text2,
                iconBorderColor: p.border,
                title: "This invite can't be opened",
                subtitle: 'It may have been withdrawn, or the link is wrong.',
              ),
            )
          else
            _InviteCard(
              invite: invite,
              answering: _answering,
              onAnswer: _answer,
              onOpenConference: _openConference,
              onCopyConference: _copyConference,
            ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final RealmInvite invite;
  final String? answering;
  final ValueChanged<String> onAnswer;
  final ValueChanged<String> onOpenConference;
  final ValueChanged<String> onCopyConference;

  const _InviteCard({
    required this.invite,
    required this.answering,
    required this.onAnswer,
    required this.onOpenConference,
    required this.onCopyConference,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final inviter = invite.inviter;
    final destination = invite.destination;
    final conferenceUrl = invite.conferenceUrl;
    final showsConference = conferenceUrl != null &&
        invite.status != 'declined' &&
        invite.status != 'revoked';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.lg),
      ),
      child: Column(
        children: [
          // The realm, with whoever invited you tucked onto its corner.
          SizedBox(
            width: 84,
            height: 78,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CLAvatar(
                  id: invite.realmId,
                  name: invite.realmName,
                  src: invite.realmProfile,
                  size: 72,
                  cornerRadius: invite.realmType == 'page' ? null : 18,
                ),
                if (inviter != null)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: p.surface, width: 3),
                      ),
                      child: CLAvatar(
                        id: inviter.id,
                        name: inviter.name,
                        src: inviter.profile,
                        kind: inviter.type,
                        size: 30,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            invite.realmName,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: CLType.screenTitle,
                fontWeight: FontWeight.w700,
                color: p.text),
          ),
          const SizedBox(height: 6),
          Text(
            invite.sentence,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: CLType.body, height: 1.45, color: p.text2),
          ),
          const SizedBox(height: 18),
          if (invite.isPending)
            Row(
              children: [
                Expanded(
                  child: CLBtn(
                    label: answering == 'declined' ? 'Declining…' : 'Decline',
                    variant: CLBtnVariant.outline,
                    block: true,
                    onPressed:
                        answering != null ? null : () => onAnswer('declined'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  // A conference is answered in its lobby, where joining
                  // happens - so its button goes there.
                  child: conferenceUrl != null
                      ? CLBtn(
                          label: 'Join conference',
                          iconL: Icons.videocam_outlined,
                          block: true,
                          onPressed: answering != null
                              ? null
                              : () => onOpenConference(conferenceUrl),
                        )
                      : CLBtn(
                          label: answering == 'accepted'
                              ? 'Accepting…'
                              : 'Accept',
                          block: true,
                          onPressed: answering != null
                              ? null
                              : () => onAnswer('accepted'),
                        ),
                ),
              ],
            )
          else
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      invite.status == 'accepted'
                          ? Icons.check_circle_outline
                          : Icons.do_not_disturb_on_outlined,
                      size: 18,
                      color: p.text2,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        switch (invite.status) {
                          'accepted' => 'You accepted this invite.',
                          'declined' => 'You declined this invite.',
                          _ => 'This invite was withdrawn.',
                        },
                        style: TextStyle(
                            fontSize: CLType.bodySm, color: p.text2),
                      ),
                    ),
                  ],
                ),
                if (invite.status == 'accepted' && conferenceUrl != null) ...[
                  const SizedBox(height: 12),
                  CLBtn(
                    label: 'Open conference',
                    iconL: Icons.videocam_outlined,
                    onPressed: () => onOpenConference(conferenceUrl),
                  ),
                ] else if (invite.status == 'accepted' &&
                    destination != null) ...[
                  const SizedBox(height: 12),
                  CLBtn(
                    label: 'Open',
                    size: CLBtnSize.sm,
                    onPressed: () => context.push(destination),
                  ),
                ],
              ],
            ),
          if (showsConference) ...[
            const SizedBox(height: 16),
            _ConferenceLink(
              address: invite.conferenceAddress!,
              onOpen: () => onOpenConference(conferenceUrl),
              onCopy: () => onCopyConference(conferenceUrl),
            ),
          ],
        ],
      ),
    );
  }
}

/// The conference's address, to tap (it opens in the browser) or to copy.
class _ConferenceLink extends StatelessWidget {
  final String address;
  final VoidCallback onOpen;
  final VoidCallback onCopy;

  const _ConferenceLink({
    required this.address,
    required this.onOpen,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: p.surface2,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 17, color: p.text3),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              link: true,
              child: InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: CLType.caption,
                      color: p.brand,
                      decoration: TextDecoration.underline,
                      decorationColor: p.brand,
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy link',
            icon: Icon(Icons.copy_rounded, size: 18, color: p.text2),
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
