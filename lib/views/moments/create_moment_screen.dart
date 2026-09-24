import 'dart:io';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/moments_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_composer.dart';
import 'package:chatterloop_app/core/utils/upload_limits.dart';
import 'package:chatterloop_app/models/post_models/ephemeral_models.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/views/moments/moment_shared_post_card.dart';
import 'package:chatterloop_app/views/moments/moments_strip.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// New Moment - a full-bleed composer, the phone's way of doing web's Create
/// Moment modal: the media fills the screen, the caption sits on it, Share is
/// top-right, and who-can-see / replies are two pills underneath.
///
/// One photo or video (camera or gallery) - or, from a post's Share options,
/// that post ([sharedPost]). Up for 24 hours. The design's text / sticker /
/// crop tools are deferred.
class CreateMomentScreen extends StatefulWidget {
  final PostPreview? sharedPost;

  const CreateMomentScreen({super.key, this.sharedPost});

  @override
  State<CreateMomentScreen> createState() => _CreateMomentScreenState();
}

class _CreateMomentScreenState extends State<CreateMomentScreen> {
  final _caption = TextEditingController();
  PendingMedia? _media;
  VideoPlayerController? _video;
  late String _audience =
      appStore.state.userAuth.user.isPrivate == true ? "connections" : "public";
  bool _allowReplies = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _caption.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _caption.dispose();
    _video?.dispose();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  Future<void> _use(PendingMedia media) async {
    if (media.size > kMaxUploadBytes) {
      _toast("That file is over $kMaxUploadLabel");
      return;
    }
    final old = _video;
    _video = null;
    await old?.dispose();
    VideoPlayerController? video;
    if (media.isVideo) {
      video = VideoPlayerController.file(File(media.path));
      try {
        await video.initialize();
        await video.setLooping(true);
        await video.setVolume(0);
        await video.play();
      } catch (_) {}
    }
    if (!mounted) {
      await video?.dispose();
      return;
    }
    setState(() {
      _media = media;
      _video = video;
    });
  }

  Future<void> _fromCamera({required bool video}) async {
    final picker = ImagePicker();
    final file = video
        ? await picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(seconds: 60))
        : await picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (file == null) return;
    await _use(PendingMedia(
        path: file.path, name: file.name, size: await file.length()));
  }

  Future<void> _fromGallery() async {
    final result = await FilePicker.pickFiles(type: FileType.media);
    final file = result?.files.firstOrNull;
    if (file == null || file.path == null) return;
    await _use(
        PendingMedia(path: file.path!, name: file.name, size: file.size));
  }

  /// Replace: the same three sources as the empty stage, as a sheet.
  Future<void> _chooseSource() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: cl(context).surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(CLRadii.lg))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text("Take photo"),
                onTap: () => Navigator.pop(sheetContext, 0)),
            ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text("Record video"),
                onTap: () => Navigator.pop(sheetContext, 1)),
            ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text("Choose from gallery"),
                onTap: () => Navigator.pop(sheetContext, 2)),
          ],
        ),
      ),
    );
    if (choice == 0) await _fromCamera(video: false);
    if (choice == 1) await _fromCamera(video: true);
    if (choice == 2) await _fromGallery();
  }

  bool get _ready =>
      !_busy &&
      (widget.sharedPost != null || _media != null) &&
      ephemeralCharCount(_caption.text.trim()) <= momentCaptionMaxLength;

  Future<void> _share() async {
    if (!_ready) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    String? mediaUrl;
    String? mediaType;
    String? fileName;
    final media = _media;
    if (widget.sharedPost == null && media != null) {
      final uploaded = await ProfileApi()
          .uploadMediaRequest(media.path, media.mediaType, action: 'post');
      if (!mounted) return;
      if (uploaded == null) {
        setState(() => _busy = false);
        _toast("Couldn't upload ${media.name}");
        return;
      }
      mediaUrl = uploaded.url;
      mediaType = uploaded.mediaType;
      fileName = uploaded.fileName;
    }
    final error = await MomentsApi().createMomentRequest(
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      fileName: fileName,
      sharedPostId: widget.sharedPost?.postId,
      caption: _caption.text.trim(),
      privacy: _audience,
      allowReplies: _allowReplies,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() => _busy = false);
      _toast(error);
      return;
    }
    EphemeralEvents.moments.value++;
    _toast("Your moment is up for 24 hours");
    context.pop(true);
  }

  Future<void> _chooseAudience() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: cl(context).surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(CLRadii.lg))),
      builder: (sheetContext) => _AudienceSheet(
          selected: _audience,
          onPick: (key) {
            Navigator.pop(sheetContext, key);
          }),
    );
    if (picked != null && mounted) setState(() => _audience = picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = widget.sharedPost != null || _media != null;
    final audience = ephemeralAudiences.firstWhere((a) => a.key == _audience,
        orElse: () => ephemeralAudiences.first);

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _busy ? null : () => context.pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.sharedPost == null ? "New moment" : "Add to moment",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: CLType.screenTitle,
                        fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  CLBtn(
                    label: _busy ? "Sharing…" : "Share",
                    size: CLBtnSize.sm,
                    onPressed: _ready ? _share : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CLRadii.lg),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _stage(),
                      if (_media != null && !_busy)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: _RoundAction(
                            icon: Icons.swap_horiz_rounded,
                            tooltip: "Replace",
                            onTap: _chooseSource,
                          ),
                        ),
                      if (hasContent)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: _captionField(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  _Pill(
                    icon: audience.icon,
                    label: audience.label,
                    onTap: _busy ? null : _chooseAudience,
                  ),
                  const SizedBox(width: 8),
                  _Pill(
                    icon: _allowReplies
                        ? Icons.chat_bubble_outline_rounded
                        : Icons.speaker_notes_off_outlined,
                    label: _allowReplies ? "Replies on" : "Replies off",
                    onTap: _busy
                        ? null
                        : () => setState(() => _allowReplies = !_allowReplies),
                  ),
                  const Spacer(),
                  const Icon(Icons.timer_outlined,
                      size: 16, color: Colors.white60),
                  const SizedBox(width: 4),
                  const Text("24h",
                      style: TextStyle(
                          color: Colors.white60, fontSize: CLType.caption)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _captionField() {
    final count = ephemeralCharCount(_caption.text.trim());
    final over = count > momentCaptionMaxLength;
    return TextField(
      controller: _caption,
      enabled: !_busy,
      minLines: 1,
      maxLines: 3,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(
          color: Colors.white,
          fontSize: CLType.title,
          fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: "Add a caption…",
        hintStyle: const TextStyle(color: Colors.white70),
        isDense: true,
        filled: true,
        fillColor: Colors.black45,
        suffixText: count > 0 ? "$count/$momentCaptionMaxLength" : null,
        suffixStyle: TextStyle(
            color: over ? const Color(0xFFFF8A95) : Colors.white70,
            fontSize: CLType.meta),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CLRadii.md),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _stage() {
    final shared = widget.sharedPost;
    if (shared != null) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF14233B), Color(0xFF3B6FE0)],
          ),
        ),
        // The post as the moment will carry it - a video plays, a share
        // shows its original - scaled down rather than overflowing.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 90),
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: MomentSharedPostCard(post: shared, mediaHeight: 180),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final media = _media;
    if (media == null) {
      return ColoredBox(
        color: const Color(0xFF15181D),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Add a photo or video",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: CLType.sectionTitle,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text("It disappears after 24 hours.",
                  style: TextStyle(
                      color: Colors.white60, fontSize: CLType.caption)),
              const SizedBox(height: 22),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SourceButton(
                    icon: Icons.photo_camera_outlined,
                    label: "Photo",
                    onTap: () => _fromCamera(video: false),
                  ),
                  const SizedBox(width: 18),
                  _SourceButton(
                    icon: Icons.videocam_outlined,
                    label: "Video",
                    onTap: () => _fromCamera(video: true),
                  ),
                  const SizedBox(width: 18),
                  _SourceButton(
                    icon: Icons.photo_library_outlined,
                    label: "Gallery",
                    onTap: _fromGallery,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final video = _video;
    if (media.isVideo) {
      if (video == null || !video.value.isInitialized) {
        return const ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        );
      }
      return ColoredBox(
        color: Colors.black,
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: video.value.size.width,
            height: video.value.size.height,
            child: VideoPlayer(video),
          ),
        ),
      );
    }
    return Image.file(File(media.path), fit: BoxFit.cover);
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SourceButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white12,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: CLType.caption,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundAction(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
              color: Colors.black45, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _Pill({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(CLRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: CLType.label,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Who can see this - one option card per audience, with what it means.
class _AudienceSheet extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onPick;

  const _AudienceSheet({required this.selected, required this.onPick});

  static const _descriptions = {
    "public": "Anyone on ChatterLoop",
    "connections": "Only people in your contacts",
  };

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                    borderRadius: BorderRadius.circular(CLRadii.pill)),
              ),
            ),
            const SizedBox(height: 14),
            Text("Who can see this",
                style: TextStyle(
                    fontSize: CLType.sectionTitle,
                    fontWeight: FontWeight.w800,
                    color: p.text)),
            const SizedBox(height: 12),
            for (final a in ephemeralAudiences)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => onPick(a.key),
                  borderRadius: BorderRadius.circular(CLRadii.md),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(CLRadii.md),
                      color: a.key == selected ? p.brandSoft : null,
                      border: Border.all(
                          color: a.key == selected ? p.brand : p.border),
                    ),
                    child: Row(
                      children: [
                        Icon(a.icon, color: p.text2),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.label,
                                  style: TextStyle(
                                      fontSize: CLType.title,
                                      fontWeight: FontWeight.w700,
                                      color: p.text)),
                              Text(_descriptions[a.key] ?? "",
                                  style: TextStyle(
                                      fontSize: CLType.caption,
                                      color: p.text2)),
                            ],
                          ),
                        ),
                        Icon(
                          a.key == selected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: a.key == selected ? p.brand : p.border2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
