// Creating a post: the inline trigger card that sits above a profile's feed,
// and the sheet it opens. Flutter counterpart of webapp's PostsContainer
// composer row + NewPostModal.
//
// WHO SEES THE TRIGGER is the caller's call, and the two profile screens differ:
// a person's profile shows it to the owner and to any visitor who may see the
// profile at all (canView), a page's shows it only to an admin. Neither rule
// lives here - this widget is handed a decision, not a profile.
//
// TAGGING is the one thing the composer itself is opinionated about. Writing on
// someone's profile is not "posting to their wall": there is no such thing
// server-side. It creates a post of YOUR own that TAGS them, which is exactly
// what web does by seeding NewPostModal's taggedEntities with the profile owner
// when `isViewingOtherProfile`. So the sheet takes an optional [autoTag] and
// pre-selects it - removable like any other tag, and the picker stays fully
// usable either way. Opened from your own profile, or anywhere else, it starts
// empty.

import 'dart:io';

import 'package:chatterloop_app/core/design/rails.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_tagging.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/core/utils/upload_limits.dart';
import 'package:chatterloop_app/models/post_models/newsfeed_models.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Same three values web's composer sends as `privacy.status`. "custom" is
/// deliberately absent on both clients: the backend supports it but it needs an
/// allow-list picker that doesn't exist.
const List<(String, String, IconData)> _kPrivacyOptions = [
  ('public', 'Public', Icons.public),
  ('connections', 'Contacts only', Icons.group),
  ('private', 'Only me', Icons.lock_outline),
];

/// What the composer is being used for.
///
/// Mirrors web, where changing an avatar or cover is a POST like any other -
/// it just carries content_type "profile"/"cover_photo", which makes Node's
/// /createpost write user_account.profile/.coverphoto AND file the post. That
/// is why a changed picture shows up in the feed at all.
///
/// The two media modes are deliberately narrower than a normal post: ONE image
/// (a second avatar is meaningless), no tagging, and the picked file shown at
/// full width so you can see what you are about to publish as your face.
enum ComposerMode { post, profilePhoto, coverPhoto }

extension ComposerModeX on ComposerMode {
  bool get isMedia => this != ComposerMode.post;

  /// The value Node branches on. Null for a normal post, which derives its own.
  String? get contentType => switch (this) {
        ComposerMode.post => null,
        ComposerMode.profilePhoto => 'profile',
        ComposerMode.coverPhoto => 'cover_photo',
      };

  String get sheetTitle => switch (this) {
        ComposerMode.post => 'Create a post',
        ComposerMode.profilePhoto => 'Change profile picture',
        ComposerMode.coverPhoto => 'Change cover photo',
      };

  String get submitLabel => switch (this) {
        ComposerMode.post => 'Post',
        _ => 'Save',
      };

  String get captionHint => switch (this) {
        ComposerMode.post => 'Type your caption',
        _ => 'Say something about it (optional)',
      };
}

/// The icon for a post's privacy status, or null when there is nothing worth
/// showing.
///
/// Reads from the same table the composer's chips are built from, so the icon
/// on a post always matches the one you picked when you published it - the two
/// drifting apart would be worse than showing nothing.
IconData? postPrivacyIcon(String status) {
  for (final option in _kPrivacyOptions) {
    if (option.$1 == status) return option.$3;
  }
  // "custom" is a real server value with no composer chip yet (it needs an
  // allow-list picker). It IS restricted, so it gets the closest honest icon
  // rather than falling through to nothing.
  if (status == 'custom') return Icons.groups_outlined;
  return null;
}

/// Whether [entityId] is the identity you are currently posting AS.
///
/// The one test for "is this profile mine", and deliberately the only one.
/// Administering a page is NOT the same as being it: while you're acting as
/// your personal account, your own page is another entity like any other - you
/// can't publish as it, and writing on it tags it, exactly as a stranger's
/// would. Switch to the page and the same profile becomes yours. That is also
/// what the SERVER does with the post: the author is resolved from the acting
/// entity in the token, so a composer that decided otherwise would just be
/// lying about where the post was going to land.
///
/// Compared on ENTITY id rather than username or account id, because that is
/// the id that follows an entity switch - the same rule the post and comment
/// options menus use for ownership.
bool isActingEntity(String entityId) =>
    entityId.isNotEmpty && appStore.state.userAuth.user.entityId == entityId;

/// The audience a new post starts with.
///
/// A private profile defaults to contacts-only, which is what the server would
/// apply anyway when the field is absent (post_visibility.default_privacy_status_for) -
/// mirrored here so the sheet shows what will actually happen instead of
/// claiming "Public" and being overridden. Posting AS A PAGE always starts
/// public: profile privacy is a person-level setting and a realm has none.
String defaultPostPrivacy() {
  final user = appStore.state.userAuth.user;
  final actingAsRealm = user.activeEntity?.type == "realm";
  return user.isPrivate && !actingAsRealm ? 'connections' : 'public';
}

/// Opens the composer. Resolves true once a post has been created.
Future<bool> showCreatePostSheet(
  BuildContext context, {
  /// Pre-selected tag - the profile being visited. Null on your own profile
  /// and anywhere outside a profile.
  SearchResultUser? autoTag,

  /// Opens straight into the media picker, like web's "Photo" button.
  bool withMedia = false,

  /// Normal post, or an avatar/cover change - see [ComposerMode].
  ComposerMode mode = ComposerMode.post,
}) async {
  final p = cl(context);
  final result = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CLRadii.lg)),
    ),
    builder: (sheetContext) => Padding(
      // Lifts the sheet above the keyboard once you tap into the caption.
      // The field no longer autofocuses, so this is for what you choose to do
      // rather than for how the sheet arrives.
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: _CreatePostSheet(
        autoTag: autoTag,
        // NOT forced on for the avatar/cover modes. Opening the system picker
        // the instant the sheet appears takes the decision away - you land in
        // the gallery before you have seen the sheet, and backing out of it
        // leaves you staring at an empty modal wondering what happened. The
        // "Choose a photo" button is one tap and it is yours to make.
        withMedia: withMedia,
        mode: mode,
      ),
    ),
  );
  return result == true;
}

/// A file chosen but not yet uploaded.
class PendingMedia {
  PendingMedia({required this.path, required this.name, required this.size});
  final String path;
  final String name;
  final int size;

  bool get isVideo =>
      RegExp(r'\.(mp4|mov|avi|mkv|webm|m4v)$').hasMatch(name.toLowerCase());

  /// What /posts/upload wants in `referenceMediaTypes`, and what comes back as
  /// the reference's media type.
  String get mediaType => isVideo ? 'video' : 'image';
}

class _CreatePostSheet extends StatefulWidget {
  final SearchResultUser? autoTag;
  final bool withMedia;
  final ComposerMode mode;

  const _CreatePostSheet({
    this.autoTag,
    this.withMedia = false,
    this.mode = ComposerMode.post,
  });

  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final TextEditingController _caption = TextEditingController();
  final List<PendingMedia> _media = [];

  late List<SearchResultUser> _tagged =
      widget.autoTag == null ? const [] : [widget.autoTag!];
  late String _privacy = defaultPostPrivacy();

  bool _posting = false;

  /// What the progress line says while a post is going out. Uploads run one
  /// file at a time, so on a slow connection this is the difference between
  /// "it's working" and "it's stuck".
  String _progress = '';

  @override
  void initState() {
    super.initState();
    if (widget.withMedia) {
      // After the first frame: the picker is a platform channel, and firing it
      // during build races the sheet's own open animation.
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickMedia());
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final mode = widget.mode;
    final result = await FilePicker.pickFiles(
      // An avatar or cover is ONE image - a video can't be either, and a
      // second file has nowhere to go.
      type: mode.isMedia ? FileType.image : FileType.media,
      allowMultiple: !mode.isMedia,
    );
    if (result == null || !mounted) return;

    final rejected = <String>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      if (file.size > kMaxUploadBytes) {
        rejected.add(file.name);
        continue;
      }
      if (_media.any((existing) => existing.path == path)) continue;
      // Picking again in a media mode REPLACES rather than appends: there is
      // only ever one avatar.
      if (widget.mode.isMedia) _media.clear();
      _media.add(PendingMedia(path: path, name: file.name, size: file.size));
      if (widget.mode.isMedia) break;
    }

    setState(() {});
    if (rejected.isNotEmpty) {
      _toast("Skipped ${rejected.length} file(s) over $kMaxUploadLabel");
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _post() async {
    final caption = _caption.text.trim();
    if (widget.mode.isMedia && _media.isEmpty) {
      _toast("Choose a photo first");
      return;
    }
    if (!widget.mode.isMedia && caption.isEmpty && _media.isEmpty) {
      _toast("Write a caption or add a photo first");
      return;
    }
    if (_posting) return;

    setState(() {
      _posting = true;
      _progress =
          _media.isEmpty ? 'Posting…' : 'Uploading 1 of ${_media.length}…';
    });

    // Media first: the post carries the resulting CDN urls, so a failed upload
    // has to abort before anything is created rather than publishing a post
    // that's missing half its photos.
    final uploaded = <PostMediaReference>[];
    for (var i = 0; i < _media.length; i++) {
      final pending = _media[i];
      if (mounted) {
        setState(() => _progress = 'Uploading ${i + 1} of ${_media.length}…');
      }
      final result = await ProfileApi()
          .uploadMediaRequest(pending.path, pending.mediaType);
      if (result == null) {
        if (!mounted) return;
        setState(() {
          _posting = false;
          _progress = '';
        });
        _toast("Couldn't upload ${pending.name}");
        return;
      }
      uploaded.add(PostMediaReference(
        url: result.url,
        fileName: result.fileName,
        mediaType: result.mediaType,
      ));
    }

    if (mounted) setState(() => _progress = 'Posting…');

    final ok = await NewsfeedApi().createPostRequest(
      caption: caption,
      media: uploaded,
      // Deduped: the auto-tagged profile owner is in this list like any other
      // entity, and the picker can't add them twice, but the server takes the
      // list at face value.
      // No tagging in a media mode - web sends an empty list for these too.
      taggedEntityIds: widget.mode.isMedia
          ? const []
          : _tagged.map((entity) => entity.entityId).toSet().toList(),
      privacy: _privacy,
      // What turns this from "a photo post" into an account update.
      contentType: widget.mode.contentType,
    );
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _posting = false;
        _progress = '';
      });
      _toast("Couldn't create that post. Try again.");
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    // No SafeArea around this: it would inset the content and then the 16
    // below would sit on top of the inset, which is the empty band at the
    // bottom of the sheet. clSheetBottomGap takes the larger of the two.
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, clSheetBottomGap(context, minimum: 16, extra: 8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: p.border2,
                borderRadius: BorderRadius.circular(CLRadii.pill),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.mode.sheetTitle,
            style: TextStyle(
              fontSize: CLType.sectionTitle,
              fontWeight: FontWeight.w700,
              color: p.text,
            ),
          ),
          const SizedBox(height: 12),
          // Everything above the action row scrolls: the caption grows, the
          // media list grows, and the tag picker opens a results list under
          // itself - any of which would otherwise push Post off the screen.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _caption,
                    minLines: 3,
                    maxLines: 8,
                    // Never. The sheet opening and the keyboard coming up at
                    // the same time is two animations fighting over the same
                    // space - the sheet arrives already covered, and half of
                    // what you opened it for (attachments, tagging, privacy)
                    // is off screen before you have looked at it. Tapping the
                    // field is one deliberate tap and it is yours to make.
                    autofocus: false,
                    enabled: !_posting,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(color: p.text, fontSize: CLType.title),
                    decoration: InputDecoration(
                      hintText: widget.mode.captionHint,
                      hintStyle: TextStyle(color: p.text3),
                      filled: true,
                      fillColor: p.input,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(CLRadii.md),
                        borderSide: BorderSide(color: p.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(CLRadii.md),
                        borderSide: BorderSide(color: p.border),
                      ),
                    ),
                  ),
                  // A media mode shows the ONE picked image at full width -
                  // you are choosing your own face or banner, and a 96px
                  // thumbnail is not enough to judge that by. Everything else
                  // keeps the scrolling rail.
                  if (widget.mode.isMedia && _media.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(CLRadii.md),
                      child: Stack(
                        children: [
                          // Cover for an avatar (it lands in a circle),
                          // 3:1 for a cover photo - roughly the shape the
                          // profile header will crop it to, so what you see
                          // here is what you get there.
                          AspectRatio(
                            aspectRatio: widget.mode == ComposerMode.coverPhoto
                                ? 3 / 1
                                : 1,
                            child: Image.file(
                              File(_media.first.path),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => Container(
                                color: p.surface2,
                                alignment: Alignment.center,
                                child: Icon(Icons.broken_image_outlined,
                                    size: 26, color: p.text3),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: InkWell(
                              onTap: _posting
                                  ? null
                                  : () => setState(_media.clear),
                              borderRadius: BorderRadius.circular(CLRadii.pill),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    size: 15, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (!widget.mode.isMedia && _media.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    // The same rail the Contacts screen uses for its
                    // sections, so a strip of media reads the same way
                    // app-wide - and so a tenth attachment scrolls instead of
                    // pushing the caption off the sheet.
                    CLRailSection(
                      title: _media.length == 1
                          ? "1 attachment"
                          : "${_media.length} attachments",
                      gap: 8,
                      children: [
                        for (final item in _media)
                          PostMediaPreviewTile(
                            item: item,
                            onRemove: _posting
                                ? null
                                : () => setState(() => _media.remove(item)),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _posting ? null : _pickMedia,
                    borderRadius: BorderRadius.circular(CLRadii.sm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 18, color: p.green),
                          const SizedBox(width: 6),
                          Text(
                            widget.mode.isMedia
                                ? (_media.isEmpty
                                    ? "Choose a photo"
                                    : "Choose a different photo")
                                : (_media.isEmpty
                                    ? "Add photos or videos"
                                    : "Add more"),
                            style: TextStyle(
                              fontSize: CLType.label,
                              fontWeight: FontWeight.w600,
                              color: p.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Hidden for an avatar/cover change: there is nobody to
                  // tag in a picture of yourself, and web sends an empty
                  // tagging list for these too.
                  if (!widget.mode.isMedia)
                    TagEntityPicker(
                      selected: _tagged,
                      onChanged: (next) => setState(() => _tagged = next),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    "Who can see this post?",
                    style: TextStyle(fontSize: CLType.caption, color: p.text2),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in _kPrivacyOptions)
                        CLChip(
                          label: option.$2,
                          icon: option.$3,
                          active: _privacy == option.$1,
                          onTap: _posting
                              ? null
                              : () => setState(() => _privacy = option.$1),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_posting)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text(_progress,
                    style: TextStyle(fontSize: CLType.label, color: p.text2)),
              ],
            )
          else
            CLBtn(
              label: widget.mode.submitLabel,
              iconL: Icons.send,
              block: true,
              size: CLBtnSize.lg,
              onPressed: _post,
            ),
        ],
      ),
    );
  }
}

/// One chosen file as a thumbnail in the attachments rail.
///
/// A filename told you nothing about what you were about to publish - the
/// point of a preview is seeing the actual photo, so images render from disk
/// (they're local paths; nothing is uploaded until Post).
///
/// A VIDEO shows a placeholder rather than its first frame: pulling one means
/// initialising a decoder per attachment, which is the same cost the feed rows
/// were careful to avoid. Size is shown on that tile instead - it's the number
/// that matters for a video, being the one that can hit the upload cap.
const double _kPreviewTileSize = 96;

class PostMediaPreviewTile extends StatelessWidget {
  final PendingMedia item;
  final VoidCallback? onRemove;

  const PostMediaPreviewTile({
    super.key,
    required this.item,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final mb = (item.size / (1024 * 1024)).toStringAsFixed(1);

    return SizedBox(
      width: _kPreviewTileSize,
      // Column, not a bare box: the rail stretches every child to the tallest,
      // and a Stack would let the remove button drift from the corner.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _kPreviewTileSize,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(CLRadii.sm),
                    child: Container(
                      color: p.surface2,
                      child: item.isVideo
                          // The picked file's own first frame - it is a local
                          // path, so this costs no download. Same reason as the
                          // grid: two chosen clips were two identical tiles.
                          ? VideoFirstFrame(
                              source: item.path,
                              isLocalFile: true,
                            )
                          : Image.file(
                              File(item.path),
                              fit: BoxFit.cover,
                              // Decoded at display size - a 12MP photo would
                              // otherwise land in the image cache whole, once
                              // per attachment.
                              cacheWidth: (_kPreviewTileSize *
                                      MediaQuery.devicePixelRatioOf(context))
                                  .ceil(),
                              errorBuilder: (_, __, ___) => Center(
                                child: Icon(Icons.broken_image_outlined,
                                    size: 22, color: p.text3),
                              ),
                            ),
                    ),
                  ),
                ),
                if (onRemove != null)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: InkWell(
                      onTap: onRemove,
                      borderRadius: BorderRadius.circular(CLRadii.pill),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          // Its own scrim: this sits on a photo, and a plain
                          // icon disappears against a light one.
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 13, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.isVideo ? "Video · $mb MB" : "$mb MB",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: CLType.meta, color: p.text3),
          ),
        ],
      ),
    );
  }
}

/// The card above a profile's feed that opens the composer.
///
/// A trigger, not an editor: tapping the field opens the sheet rather than
/// typing in place, because the real composer needs the keyboard, the media
/// list, the tag picker and the audience row at once - the same reason web's
/// row only focuses to open its modal.
class ProfileComposerCard extends StatelessWidget {
  /// Avatar shown on the row - the ACTING entity's, since that's who the post
  /// will be from, not the profile being viewed.
  final String? avatarId;
  final String? avatarName;
  final String? avatarSrc;

  /// "Share your thoughts…" on your own, "Write on X's wall…" on someone
  /// else's - web's exact split.
  final String placeholder;

  /// Passed straight to the sheet: the visited profile, or null.
  final SearchResultUser? autoTag;

  /// Fired after a post is created, so the feed below reloads.
  final VoidCallback onPosted;

  const ProfileComposerCard({
    super.key,
    this.avatarId,
    this.avatarName,
    this.avatarSrc,
    required this.placeholder,
    this.autoTag,
    required this.onPosted,
  });

  /// The composer with NO profile context - the newsfeed.
  ///
  /// Nothing to be "on", so nothing to pre-tag and no wall to write on: it is
  /// simply your own composer, wearing the acting entity's face.
  factory ProfileComposerCard.forActingEntity({
    Key? key,
    required String placeholder,
    required VoidCallback onPosted,
  }) {
    final user = appStore.state.userAuth.user;
    final acting = user.activeEntity;
    return ProfileComposerCard(
      key: key,
      avatarId: user.entityId,
      avatarName: acting?.name ?? user.personalDisplayName,
      avatarSrc: acting?.profile ?? user.profile,
      placeholder: placeholder,
      onPosted: onPosted,
    );
  }

  /// The composer for a profile - person or page, one rule for both.
  ///
  /// [profile] is the profile being VIEWED, in the shape the tag picker
  /// speaks. Whether it counts as "yours" is decided by [isActingEntity]
  /// alone, and everything else follows from that: your own profile gets the
  /// plain placeholder and no pre-selected tag, anyone else's pre-tags them.
  ///
  /// The row always wears the ACTING entity's face, because that is who the
  /// post will be from - never the profile being looked at.
  factory ProfileComposerCard.forProfile({
    Key? key,
    required SearchResultUser profile,
    required VoidCallback onPosted,

    /// What the field says on your own profile. Differs by kind - a person
    /// shares a thought, a page publishes.
    String ownPlaceholder = "Share your thoughts…",
  }) {
    final user = appStore.state.userAuth.user;
    final acting = user.activeEntity;
    final own = isActingEntity(profile.entityId);
    final name =
        profile.displayName.isEmpty ? profile.username : profile.displayName;

    return ProfileComposerCard(
      key: key,
      avatarId: user.entityId,
      avatarName: acting?.name ?? user.personalDisplayName,
      avatarSrc: acting?.profile ?? user.profile,
      placeholder: own
          ? ownPlaceholder
          : profile.isRealm
              ? "Write on $name's page…"
              : "Write on $name's wall…",
      // Your own profile pre-tags nobody; everyone else's pre-tags them. See
      // the file header for why writing on a profile is a tag, not a wall post.
      autoTag: own ? null : profile,
      onPosted: onPosted,
    );
  }

  Future<void> _open(BuildContext context, {bool withMedia = false}) async {
    final created = await showCreatePostSheet(
      context,
      autoTag: autoTag,
      withMedia: withMedia,
    );
    if (created) onPosted();
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CLAvatar(
                id: avatarId,
                name: avatarName,
                src: avatarSrc,
                size: 38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => _open(context),
                  borderRadius: BorderRadius.circular(CLRadii.pill),
                  child: Container(
                    height: 38,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: p.input,
                      borderRadius: BorderRadius.circular(CLRadii.pill),
                      border: Border.all(color: p.border),
                    ),
                    child: Text(
                      placeholder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: CLType.body, color: p.text3),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: p.border),
          const SizedBox(height: 4),
          Row(
            // spaceBetween puts all the slack in ONE place - between the two -
            // so each sits on its own edge.
            //
            // A Spacer here did not: Flexible and Spacer each claim half the
            // free space, but Flexible is LOOSE, so Photo renders narrower than
            // its half and the leftover falls after Post, pushing it inward.
            // Flexible stays for the label, which still has to ellipsize at a
            // large text scale rather than overflow.
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left, like web's composer: an option you scan past on the way
              // to the field above, not a call to action competing with Post.
              Flexible(
                child: InkWell(
                  onTap: () => _open(context, withMedia: true),
                  borderRadius: BorderRadius.circular(CLRadii.sm),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image_outlined, size: 18, color: p.green),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            "Photo",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: CLType.label,
                              fontWeight: FontWeight.w600,
                              color: p.text2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              CLBtn(
                label: "Post",
                size: CLBtnSize.sm,
                onPressed: () => _open(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
