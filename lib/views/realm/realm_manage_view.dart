// Manage a realm - the mobile counterpart of webapp's ManageRealm.
//
// A realm is a page, a group, a channel (a group with a parent), a voice room
// or a server, and they do NOT all get the same screen: web varies both the
// sections and the Details fields by kind. Those two rules live at the top of
// this file as tables copied from web, because they are product decisions and
// the only way to keep them honest is to keep them side by side.
//
// Webapp lays this out as a persistent left rail of sections beside a content
// pane, collapsing to a slide-over drawer under 800px. Neither shape belongs
// on a phone: a drawer over a full-screen pane is two navigation systems for
// five destinations. This is the same five sections as a list you push into,
// which is what every other settings-shaped screen in this app already does
// (see settings_view.dart) - the rail's job was to show you where you are,
// and a pushed screen with a title does that without a drawer.
//
// SCOPE: Profile Details, Media, Members and Followers are built (the last two
// share RealmRosterScreen - see realm_sections.dart). Dashboard is a
// placeholder, which is what it is on web too: its whole component is a
// centred "Dashboard is currently unavailable."
//
// ADDING members is the one deliberate gap. Web's ContactMember picker is a
// contacts-and-server-members browser with its own search, selection state and
// two different add endpoints (/m/addnewmember for a group, a separate one for
// a server), and it needs a mobile design of its own rather than a squeezed
// port. Removing works, so a roster can be corrected; growing one still has to
// happen on web.
//
// Kinds this app cannot otherwise reach - channels, voice rooms, servers -
// are handled here anyway: they resolve, render their own field preset, and
// their rosters page. Nothing about this screen assumes a page.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/views/realm/realm_sections.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A realm's kind for the purposes of this screen.
///
/// Not simply `realm.type`: webapp derives a fifth kind, "channel", from a
/// GROUP that has a parent, and gives it its own form. Everything below keys
/// off this rather than the raw type so the derivation happens exactly once.
String realmFormKind(RealmProfile realm) =>
    realm.type == "group" && (realm.parent ?? '').isNotEmpty
        ? "channel"
        : realm.type;

/// Which Details fields each kind gets - webapp's `formPreset`, copied
/// verbatim because it is a product decision, not a derivation:
///
///   group:   name, privacy
///   channel: name                (privacy is noted there as "for future" -
///   voice:   name                 it needs every server member added on a
///                                 switch to public, so it is deliberately
///                                 not offered yet)
///   page:    name, description, email, slug
///   server:  name, description, privacy
///
/// An unknown kind falls back to name alone, which is the only field every
/// preset has - better than showing a page's form for something that isn't a
/// page.
const Map<String, List<String>> _kFormPresets = {
  "group": ["name", "privacy"],
  "channel": ["name"],
  "voice": ["name"],
  "page": ["name", "description", "email", "slug"],
  "server": ["name", "description", "privacy"],
};

List<String> realmFormFields(RealmProfile realm) =>
    _kFormPresets[realmFormKind(realm)] ?? const ["name"];

/// Webapp's field labels, unchanged. "Slug" in particular is deliberately not
/// renamed to something friendlier - it is the word the product uses.
const Map<String, String> _kFieldLabels = {
  "name": "Name",
  "slug": "Slug",
  "description": "Description",
  "email": "Email",
  "privacy": "Privacy",
};

/// Whether a realm has followers at all - which gates BOTH the Followers
/// section and the follower count under its name. Page only, matching webapp's
/// `realmState.type === "page" && (...)` around that nav button.
///
/// Nothing else can be followed: a group, channel or server has MEMBERS, and
/// showing "0 followers" under one is not an empty state, it is a category
/// error.
bool realmHasFollowers(RealmProfile realm) => realm.type == "page";

/// Whether a realm gets the Dashboard section. Page only.
///
/// Kept separate from [realmHasFollowers] despite the identical test today:
/// they answer different questions (what this realm HAS vs what this screen
/// SHOWS), and collapsing them would mean a future change to one silently
/// moving the other.
bool realmHasDashboard(RealmProfile realm) => realm.type == "page";

/// What to call this realm in prose - webapp writes "Manage your {channel |
/// group | page | server | voice} details", deriving channel the same way.
String realmKindNoun(RealmProfile realm) => realmFormKind(realm);

/// Whether a realm has a cover photo to set.
///
/// Pages and servers only. NOT transcribed from web, which offers the cover
/// uploader for every kind - this is a deliberate product rule on top of it:
/// a group, channel or voice room has no surface that renders a banner, so
/// uploading one there is a file that goes nowhere.
bool realmHasCoverPhoto(RealmProfile realm) =>
    realm.type == "page" || realm.type == "server";

class RealmManageScreen extends StatefulWidget {
  final String slug;
  const RealmManageScreen({super.key, required this.slug});

  @override
  State<RealmManageScreen> createState() => _RealmManageScreenState();
}

class _RealmManageScreenState extends State<RealmManageScreen> {
  RealmProfile? _realm;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // forManage mirrors webapp's ManageRealmContainer, which asks the same
    // profile route with ?type=manage. `slug` is whatever the caller had: a
    // real slug from a page profile, or a conversation's contactID from a
    // group chat - the route resolves both.
    final realm =
        await ProfileApi().getRealmProfileRequest(widget.slug, forManage: true);
    if (!mounted) return;
    setState(() {
      _realm = realm;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final realm = _realm;

    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(
          title: Text(
              realm == null ? 'Manage' : 'Manage ${realmKindNoun(realm)}')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: p.brand))
          : realm == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: CLEmptyState(
                      icon: Icons.error_outline,
                      iconBg: p.surface2,
                      iconColor: p.text2,
                      iconBorderColor: p.border,
                      title: "Unavailable",
                      subtitle: "This could not be loaded.\n"
                          "It may have been removed, or you may no longer "
                          "administer it.",
                    ),
                  ),
                )
              // Not gated on isAdmin: administering is not the same as BEING
              // the page, and the server resolves what you may edit from the
              // acting entity in the token either way. A non-admin's PUT is
              // refused there; hiding the screen here would only add a second,
              // divergent copy of that rule.
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                      CLSpacing.contentGutter, 12, CLSpacing.contentGutter, 24),
                  children: [
                    _RealmHeader(realm: realm),
                    const SizedBox(height: 16),
                    _SectionTile(
                      icon: Icons.tune,
                      title: 'Profile Details',
                      subtitle: realmFormFields(realm)
                          .map((field) => _kFieldLabels[field] ?? field)
                          .join(', '),
                      onTap: () async {
                        final updated = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => RealmDetailsScreen(realm: realm),
                          ),
                        );
                        // Re-read rather than patching locally: the server
                        // normalises a slug, so what you typed is not always
                        // what it stored.
                        if (updated == true) _load();
                      },
                    ),
                    if (realmHasDashboard(realm))
                      _SectionTile(
                        icon: Icons.insights_outlined,
                        title: 'Dashboard',
                        subtitle: 'Not available yet',
                        enabled: false,
                      ),
                    _SectionTile(
                      icon: Icons.photo_library_outlined,
                      title: 'Media',
                      subtitle: 'Profile picture and cover photo',
                      onTap: () async {
                        final changed = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => RealmMediaScreen(realm: realm),
                          ),
                        );
                        if (changed == true) _load();
                      },
                    ),
                    _SectionTile(
                      icon: Icons.group_outlined,
                      title: 'Members',
                      subtitle: 'Who belongs to this '
                          '${realmKindNoun(realm)}',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              RealmRosterScreen(realm: realm, members: true),
                        ),
                      ),
                    ),
                    // Pages only - a group has members, not followers, and
                    // webapp hides this button entirely for them rather than
                    // showing an empty list.
                    if (realmHasFollowers(realm))
                      _SectionTile(
                        icon: Icons.favorite_outline,
                        title: 'Followers',
                        subtitle:
                            '${clCompactCount(realm.followersCount)} following '
                            'this page',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                RealmRosterScreen(realm: realm, members: false),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _RealmHeader extends StatelessWidget {
  final RealmProfile realm;
  const _RealmHeader({required this.realm});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final parent = realm.parent ?? '';
    final subtitle = realmHasFollowers(realm)
        ? '${clCompactCount(realm.followersCount)} followers'
        : (parent.isNotEmpty ? parent : null);

    return Row(
      children: [
        CLAvatar(id: realm.id, name: realm.name, src: realm.profile, size: 52),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                realm.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: CLType.sectionTitle,
                  fontWeight: FontWeight.w800,
                  color: p.text,
                ),
              ),
              // Followers for a page; otherwise the parent, which is the only
              // secondary line webapp's own manage header has (it renders
              // `realmState.parent` there and nothing else). A group with
              // neither gets just its name, which is all there is to say.
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: CLType.caption, color: p.text2),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  const _SectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: p.surface,
          border: Border.all(color: p.border),
          borderRadius: BorderRadius.circular(CLRadii.md),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          enabled: enabled,
          onTap: onTap,
          leading: Icon(icon, size: 20, color: p.text2),
          minLeadingWidth: 0,
          title: Text(title,
              style: TextStyle(
                  fontSize: CLType.body,
                  fontWeight: FontWeight.w700,
                  color: p.text)),
          subtitle: Text(subtitle,
              style: TextStyle(fontSize: CLType.caption, color: p.text2)),
          trailing: enabled
              ? Icon(Icons.chevron_right, size: 18, color: p.text3)
              : null,
        ),
      ),
    );
  }
}

/// Webapp's Details tab. Pops `true` once something was actually saved.
class RealmDetailsScreen extends StatefulWidget {
  final RealmProfile realm;
  const RealmDetailsScreen({super.key, required this.realm});

  @override
  State<RealmDetailsScreen> createState() => _RealmDetailsScreenState();
}

class _RealmDetailsScreenState extends State<RealmDetailsScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.realm.name);
  late final TextEditingController _slug =
      TextEditingController(text: widget.realm.slug ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.realm.description ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.realm.email ?? '');

  late bool _isPrivate = widget.realm.isPrivate;
  bool _saving = false;

  late final List<String> _fields = realmFormFields(widget.realm);

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _description.dispose();
    _email.dispose();
    super.dispose();
  }

  /// Only what changed, matching web's stateDifference. Sending the whole form
  /// would let a field the user never touched overwrite an edit made from
  /// another device between load and save.
  /// Every comparison is guarded by the preset as well as by having changed:
  /// a field this realm kind doesn't have is never sent, even though its
  /// controller exists. Sending `slug: ""` for a group would be an edit the
  /// form never showed.
  Map<String, dynamic> get _changed {
    final fields = <String, dynamic>{};
    void text(String key, TextEditingController controller, String original) {
      if (!_fields.contains(key)) return;
      if (controller.text.trim() != original) {
        fields[key] = controller.text.trim();
      }
    }

    text('name', _name, widget.realm.name);
    text('slug', _slug, widget.realm.slug ?? '');
    text('description', _description, widget.realm.description ?? '');
    text('email', _email, widget.realm.email ?? '');
    if (_fields.contains('privacy') && _isPrivate != widget.realm.isPrivate) {
      fields['is_private'] = _isPrivate;
    }
    return fields;
  }

  Future<void> _save() async {
    final fields = _changed;
    if (fields.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('A page needs a name.')));
      return;
    }

    setState(() => _saving = true);
    final ok = await ProfileApi().updateRealmRequest(widget.realm.id, fields);
    if (!mounted) return;
    setState(() => _saving = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text('Details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            CLSpacing.contentGutter, 16, CLSpacing.contentGutter, 24),
        children: [
          // Labels and placeholders are webapp's, verbatim - "Slug" is called
          // Slug there and stays Slug here. Order follows the preset.
          for (final field in _fields) ...[
            switch (field) {
              'name' =>
                CLField(controller: _name, label: 'Name', placeholder: 'Name'),
              'slug' =>
                CLField(controller: _slug, label: 'Slug', placeholder: 'Slug'),
              'description' => CLField(
                  controller: _description,
                  label: 'Description',
                  placeholder: 'Description'),
              'email' => CLField(
                  controller: _email,
                  label: 'Email',
                  placeholder: 'Email',
                  keyboardType: TextInputType.emailAddress),
              'privacy' => _PrivacyField(
                  isPrivate: _isPrivate,
                  enabled: !_saving,
                  onChanged: (value) => setState(() => _isPrivate = value),
                ),
              _ => const SizedBox.shrink(),
            },
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 20),
          CLBtn(
            label: _saving ? 'Saving…' : 'Save changes',
            block: true,
            size: CLBtnSize.lg,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

/// Webapp's Privacy select - two options, false = Public, true = Private -
/// as a segmented control, which is what a two-value choice looks like on a
/// phone.
class _PrivacyField extends StatelessWidget {
  final bool isPrivate;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _PrivacyField({
    required this.isPrivate,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Privacy',
            style: TextStyle(
                fontSize: CLType.bodySm,
                fontWeight: FontWeight.w600,
                color: p.text)),
        const SizedBox(height: 6),
        Row(
          children: [
            CLChip(
              label: 'Public',
              active: !isPrivate,
              onTap: enabled ? () => onChanged(false) : null,
            ),
            const SizedBox(width: 8),
            CLChip(
              label: 'Private',
              active: isPrivate,
              onTap: enabled ? () => onChanged(true) : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Pushes the manage screen for [slug].
void openRealmManage(BuildContext context, String slug) =>
    context.push('/realm/${Uri.encodeComponent(slug)}/manage');
