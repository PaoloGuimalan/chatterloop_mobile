// An invite at its own route - `/invite/:token`.
//
// Where an invite's notification and its push lead (Django
// community/invite_rules.py invite_route - the apps always get this page, the
// web opens a conference's own lobby instead). It says who invited you to
// what, and takes the answer; accepting goes on to the realm when the app has
// a screen for it. Counterpart of the webapp's InvitePage.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/invites_api.dart';
import 'package:chatterloop_app/models/user_models/realm_invite_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RealmInviteScreen extends StatefulWidget {
  final String token;

  /// Injectable for tests.
  final InvitesApi? api;

  const RealmInviteScreen({super.key, required this.token, this.api});

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

  const _InviteCard({
    required this.invite,
    required this.answering,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final inviter = invite.inviter;
    final destination = invite.destination;

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
                  child: CLBtn(
                    label: answering == 'accepted' ? 'Accepting…' : 'Accept',
                    block: true,
                    onPressed:
                        answering != null ? null : () => onAnswer('accepted'),
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
                          'accepted' => invite.realmType == 'conference'
                              ? 'You accepted. Conferences open on the web.'
                              : 'You accepted this invite.',
                          'declined' => 'You declined this invite.',
                          _ => 'This invite was withdrawn.',
                        },
                        style: TextStyle(
                            fontSize: CLType.bodySm, color: p.text2),
                      ),
                    ),
                  ],
                ),
                if (invite.status == 'accepted' && destination != null) ...[
                  const SizedBox(height: 12),
                  CLBtn(
                    label: 'Open',
                    size: CLBtnSize.sm,
                    onPressed: () => context.push(destination),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
