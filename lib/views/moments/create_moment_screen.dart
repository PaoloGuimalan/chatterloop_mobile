import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/encoding_profile.dart';
import 'package:chatterloop_app/core/media/media_engine.dart';
import 'package:chatterloop_app/core/media/sequence_player.dart';
import 'package:chatterloop_app/core/media/still_image.dart';
import 'package:chatterloop_app/core/media/timeline.dart';
import 'package:chatterloop_app/core/media/widgets/edit_canvas.dart';
import 'package:chatterloop_app/core/media/widgets/timeline_view.dart';
import 'package:chatterloop_app/core/media/widgets/trim_bar.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/moments_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_composer.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/core/utils/gallery_saver.dart';
import 'package:chatterloop_app/models/post_models/ephemeral_models.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/views/moments/audio_trim_page.dart';
import 'package:chatterloop_app/views/moments/clip_trim_page.dart';
import 'package:chatterloop_app/views/moments/moment_shared_post_card.dart';
import 'package:chatterloop_app/views/moments/moments_strip.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

/// New Moment - a full-screen editor: a 9:16 canvas with the caption on it,
/// Save and Share top-right, a timeline under it, and who-can-see / replies
/// as two pills at the bottom.
///
/// An edit is a run of CLIPS - photos and videos picked from the gallery
/// (several at once) or the camera, each video first cut to the part wanted
/// - played one after another, plus MUSIC laid along under them. On the
/// timeline, clips and songs are cards: trimmed by their ends, clips
/// reordered by holding and dragging, songs dragged to where they should
/// play; split, duplicate, volume and delete act on the picked card. Each
/// clip is framed on the canvas on its own - dragged, pinched, twisted,
/// fitted or filled - over a blurred or plain background. Up to 2 minutes.
///
/// It is rendered on the device into the MP4 that gets posted
/// (lib/core/media). Save puts a copy on the phone, with the watermark;
/// what is posted has none.
///
/// From a post's Share options it is that post instead ([sharedPost]),
/// posted as it is - no editor, no render.
class CreateMomentScreen extends StatefulWidget {
  final PostPreview? sharedPost;

  const CreateMomentScreen({super.key, this.sharedPost});

  @override
  State<CreateMomentScreen> createState() => _CreateMomentScreenState();
}

/// Where Share (or Save to device) is up to.
enum _Phase { editing, rendering, uploading, posting, saving }

typedef _Upload = ({
  String url,
  String mediaType,
  String fileName,
  String? fileId,
});

typedef _Picked = ({String path, bool video});

class _CreateMomentScreenState extends State<CreateMomentScreen>
    with TickerProviderStateMixin {
  static const _profile = EncodingProfile.moment;

  static const _backgrounds = <int>[
    0xFF000000,
    0xFFFFFFFF,
    0xFF14233B,
    0xFF3B6FE0,
    0xFF7C4DFF,
    0xFFE0457B,
    0xFFF5B83D,
    0xFF2E7D5B,
  ];

  final _caption = TextEditingController();
  late String _audience =
      appStore.state.userAuth.user.isPrivate == true ? "connections" : "public";
  bool _allowReplies = true;

  // ---- The edit.
  /// This editor's temp folder (prepared photos, thumbnails); deleted on
  /// close.
  Directory? _workspace;
  Composition? _edit;
  late final SequencePlayer _player = SequencePlayer(vsync: this)
    ..addListener(_onPlayer);
  TimelineSelection? _selection;

  /// A video file's picture for its timeline cards, by path.
  final Map<String, String> _thumbnails = {};
  bool _preparing = false;

  /// Playing when a scrub started - it plays on once let go.
  bool _resumeAfterScrub = false;

  // ---- Share / Save.
  _Phase _phase = _Phase.editing;
  double _renderProgress = 0;
  RenderJob<RenderResult>? _job;

  /// The last render and what it was made from (the edit as JSON, and
  /// whether watermarked): Retry after a failed upload or post reuses it
  /// instead of rendering again - and the uploads too, once made.
  RenderResult? _rendered;
  String? _renderedFor;
  _Upload? _uploadedVideo;
  String? _uploadedPoster;
  bool _failed = false;

  /// The render running is for Save to device, not Share.
  bool _savingToDevice = false;

  @override
  void initState() {
    super.initState();
    _caption.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _caption.dispose();
    _job?.cancel();
    _rendered?.dispose();
    _player
      ..removeListener(_onPlayer)
      ..dispose();
    final workspace = _workspace;
    if (workspace != null) workspace.delete(recursive: true).ignore();
    super.dispose();
  }

  void _onPlayer() {
    if (mounted) setState(() {});
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  bool get _busy => _phase != _Phase.editing || _preparing;

  // ---------------------------------------------------------------- picking

  /// Time left before the moment reaches its 2 minutes.
  Duration get _room =>
      _edit?.remaining(_profile.maxDuration) ?? _profile.maxDuration;

  void _full() => _toast(
      "A moment can be up to ${TrimBar.lengthLabel(_profile.maxDuration)}");

  Future<void> _fromCamera({required bool video}) async {
    if (_room < minPiece) return _full();
    final picker = ImagePicker();
    final file = video
        ? await picker.pickVideo(source: ImageSource.camera, maxDuration: _room)
        : await picker.pickImage(source: ImageSource.camera, imageQuality: 95);
    if (file == null) return;
    await _addFiles([(path: file.path, video: video)]);
  }

  /// The phone's gallery (Android's photo picker) - as many photos and
  /// videos as wanted, added in the order picked.
  Future<void> _fromGallery() async {
    if (_room < minPiece) return _full();
    final List<XFile> files;
    try {
      files = await ImagePicker().pickMultipleMedia();
    } catch (_) {
      if (mounted) _toast("Couldn't open your gallery");
      return;
    }
    if (files.isEmpty) return;
    await _addFiles([
      for (final file in files)
        (
          path: file.path,
          video: PendingMedia(
                  path: file.path,
                  name: file.name,
                  size: 0,
                  mimeType: file.mimeType)
              .isVideo,
        )
    ]);
  }

  /// More clips: the same three sources as the empty canvas, as a sheet.
  Future<void> _chooseSource() async {
    if (_room < minPiece) return _full();
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
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text("Choose from gallery"),
                subtitle: const Text("Pick as many as you like"),
                onTap: () => Navigator.pop(sheetContext, 2)),
            ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text("Take photo"),
                onTap: () => Navigator.pop(sheetContext, 0)),
            ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text("Record video"),
                onTap: () => Navigator.pop(sheetContext, 1)),
          ],
        ),
      ),
    );
    if (choice == 0) await _fromCamera(video: false);
    if (choice == 1) await _fromCamera(video: true);
    if (choice == 2) await _fromGallery();
  }

  /// Turns picked files into clips - each video first cut to the part
  /// wanted - and puts them in after the picked clip (else at the end),
  /// while there is room.
  Future<void> _addFiles(List<_Picked> files) async {
    _player.pause();
    setState(() => _preparing = true);
    final added = <MediaLayer>[];
    var room = _room;
    var ranOut = false;
    try {
      // The preview's players are its own, outside the app's shared pool -
      // so the pool's idle ones (feed videos just scrolled past) let go of
      // their decoders first.
      await SharedVideoControllers.releaseIdle();
      final workspace =
          _workspace ??= await MediaEngine.instance.createWorkspace();
      for (final (i, file) in files.indexed) {
        if (room < minPiece) {
          ranOut = true;
          break;
        }
        final source =
            await _open(file.path, looksLikeVideo: file.video, into: workspace);
        if (!mounted) return;
        if (source == null) {
          _toast("Couldn't open one of those");
          continue;
        }
        final MediaLayer clip;
        if (source.isVideo) {
          setState(() => _preparing = false);
          final range = await ClipTrimPage.open(
            context,
            source: source,
            maxSpan: room,
            step: files.length > 1 ? '${i + 1} of ${files.length}' : null,
          );
          if (!mounted) return;
          setState(() => _preparing = true);
          if (range == null) continue;
          clip = MediaLayer(
              source: source,
              transform: _initialTransform(source),
              trim: range);
          if (!_thumbnails.containsKey(source.path)) {
            final thumb = await MediaEngine.instance
                .thumbnail(source.path, range.start, workspace);
            if (thumb != null) _thumbnails[source.path] = thumb;
          }
        } else {
          clip = MediaLayer(
            source: source,
            transform: _initialTransform(source),
            duration: room < MediaLayer.defaultStill
                ? room
                : MediaLayer.defaultStill,
          );
        }
        added.add(clip);
        room -= clip.length;
      }
    } catch (e) {
      debugPrint('CreateMoment: open failed: $e');
      if (mounted) _toast("Couldn't open that file");
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
    if (!mounted) return;
    if (ranOut) {
      _toast("Not all of them fit - a moment can be up to "
          "${TrimBar.lengthLabel(_profile.maxDuration)}");
    }
    if (added.isEmpty) return;

    final edit = _edit;
    final selected = _selection;
    final at = edit == null
        ? 0
        : (selected != null && selected.isClip
            ? selected.index + 1
            : edit.clips.length);
    final next = edit == null
        ? Composition(clips: added)
        : edit.insertClips(added, index: at);
    _setEdit(next);
    setState(() => _selection = TimelineSelection.clip(at));
    _player.seek(next.clipStarts[at]);
  }

  /// A picked file as a clip's media: a photo decoded and prepared (upright,
  /// capped in size - see prepareStill), a video inspected by ffprobe.
  Future<MediaSource?> _open(
    String path, {
    required bool looksLikeVideo,
    required Directory into,
  }) async {
    MediaSource? source;
    if (!looksLikeVideo) {
      try {
        source = await prepareStill(path, into);
      } catch (_) {
        // Not a photo the platform can read - maybe a video by another
        // name; ffprobe decides below.
      }
    }
    return source ?? await _probeVideo(path);
  }

  Future<MediaSource?> _probeVideo(String path) async {
    try {
      final info = await MediaEngine.instance.probe(path);
      final length = info.duration ?? Duration.zero;
      if (!info.hasVideo || info.isImage || length <= Duration.zero) {
        return null;
      }
      if (info.width <= 0 || info.height <= 0) return null;
      return info.toSource();
    } on MediaEngineException {
      return null;
    }
  }

  /// Media close to the canvas's shape fills it; anything else fits whole,
  /// over the background.
  LayerTransform _initialTransform(MediaSource source) {
    final aspect = source.width / source.height;
    final canvas = _profile.aspectRatio;
    return LayerTransform.fillScale(aspect, canvas) <= 1.3
        ? LayerTransform.fill(aspect, canvas)
        : LayerTransform.fit;
  }

  // ------------------------------------------------------------------ music

  Future<void> _addAudio() async {
    final edit = _edit;
    if (edit == null) return;
    _player.pause();
    final result = await FilePicker.pickFiles(type: FileType.audio);
    final file = result?.files.firstOrNull;
    final path = file?.path;
    if (file == null || path == null || !mounted) return;
    setState(() => _preparing = true);
    try {
      final info = await MediaEngine.instance.probe(path);
      final length = info.duration;
      if (!info.hasAudio ||
          length == null ||
          length < const Duration(milliseconds: 500)) {
        _toast("Couldn't use that audio file");
        return;
      }
      final dot = file.name.lastIndexOf('.');
      final name = dot > 0 ? file.name.substring(0, dot) : file.name;
      final current = _edit!;
      final at = _player.position.value;
      // From the playhead - or the top, when the playhead is at the end.
      final from =
          at >= current.naturalDuration - minPiece ? Duration.zero : at;
      final slot =
          current.trackSlot(from) ?? current.trackSlot(Duration.zero);
      if (slot == null) {
        _toast("No room for more music - trim or move a song first");
        return;
      }
      // The part of it to use, no longer than the room where it goes.
      if (!mounted) return;
      setState(() => _preparing = false);
      final range = await AudioTrimPage.open(
        context,
        path: path,
        name: name,
        length: length,
        maxSpan: slot.room,
      );
      if (range == null || !mounted) return;
      final next = _edit!.addTrack(
        AudioTrack(path: path, name: name, fileLength: length, trim: range),
        at: slot.start,
      );
      if (next == null) return;
      _setEdit(next);
      final index = next.audio.indexWhere((t) => !current.audio.contains(t));
      if (index >= 0) setState(() => _selection = TimelineSelection.track(index));
    } on MediaEngineException {
      if (mounted) _toast("Couldn't use that audio file");
    } catch (e) {
      debugPrint('CreateMoment: song failed: $e');
      if (mounted) _toast("Couldn't use that audio file");
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  // ------------------------------------------------------------------ edits

  /// Every change to the edit comes through here - the preview follows.
  void _setEdit(Composition? next) {
    setState(() {
      _edit = next;
      _failed = false;
      final selected = _selection;
      if (next == null) {
        _selection = null;
      } else if (selected != null &&
          selected.index >=
              (selected.isClip ? next.clips.length : next.audio.length)) {
        _selection = null;
      }
    });
    _player.setEdit(next);
  }

  void _onTimelineEdit(Composition next) {
    if (_player.playing) _player.pause();
    _setEdit(next);
  }

  void _startScrub() {
    _resumeAfterScrub = _player.playing;
    _player.pause();
  }

  void _endScrub() {
    if (_resumeAfterScrub) _player.play();
    _resumeAfterScrub = false;
  }

  /// The clip on the canvas - the one under the playhead.
  int get _current =>
      _player.currentIndex.clamp(0, _edit!.clips.length - 1).toInt();

  MediaLayer get _currentClip => _edit!.clips[_current];

  void _select(TimelineSelection? selection) {
    setState(() => _selection = selection);
    final edit = _edit;
    if (selection == null || edit == null || !selection.isClip) return;
    // The canvas shows the picked clip: the playhead into it.
    final start = edit.clipStarts[selection.index];
    final end = start + edit.clips[selection.index].length;
    final at = _player.position.value;
    if (at < start || at >= end) _player.seek(start);
  }

  void _setTransform(LayerTransform transform) {
    final index = _current;
    _setEdit(_edit!.replaceClip(
        index, _edit!.clips[index].copyWith(transform: transform)));
  }

  double get _fillScale {
    final source = _currentClip.source;
    return LayerTransform.fillScale(
        source.width / source.height, _profile.aspectRatio);
  }

  /// Fills the canvas: no bars, straight, centred.
  bool get _isFilled {
    final t = _currentClip.transform;
    return (t.scale - _fillScale).abs() < 0.01 &&
        t.cx == 0.5 &&
        t.cy == 0.5 &&
        t.rotationDeg % 360 == 0;
  }

  void _toggleFill() {
    final source = _currentClip.source;
    _setTransform(_isFilled
        ? LayerTransform.fit
        : LayerTransform.fill(
            source.width / source.height, _profile.aspectRatio));
  }

  /// On to the next quarter turn clockwise (a twisted clip straightens to
  /// the next one first).
  void _rotateQuarter() {
    final t = _currentClip.transform;
    final next = ((t.rotationDeg / 90).floor() + 1) * 90.0;
    _setTransform(t.copyWith(rotationDeg: next % 360));
  }

  bool get _isPristine =>
      _currentClip.transform == _initialTransform(_currentClip.source);

  void _resetFraming() =>
      _setTransform(_initialTransform(_currentClip.source));

  Future<void> _chooseBackground() async {
    final picked = await showModalBottomSheet<CompositionBackground>(
      context: context,
      backgroundColor: cl(context).surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(CLRadii.lg))),
      builder: (sheetContext) => _BackgroundSheet(
        selected: _edit!.background,
        colors: _backgrounds,
        onPick: (bg) => Navigator.pop(sheetContext, bg),
      ),
    );
    if (picked != null && mounted) {
      _setEdit(_edit!.copyWith(background: picked));
    }
  }

  // ------------------------------------------------- the picked card's tools

  void _split() {
    final selected = _selection;
    final edit = _edit;
    if (selected == null || edit == null) return;
    final at = _player.position.value;
    final next = selected.isClip
        ? edit.splitAt(at)
        : edit.splitTrack(selected.index, at);
    if (next == null) {
      _toast(selected.isClip
          ? "Move the playhead inside the clip to split it"
          : "Move the playhead inside the song to split it");
      return;
    }
    HapticFeedback.selectionClick();
    _setEdit(next);
  }

  void _duplicate() {
    final selected = _selection;
    final edit = _edit;
    if (selected == null || edit == null || !selected.isClip) return;
    final clip = edit.clips[selected.index];
    if (clip.length > _room) return _full();
    _setEdit(edit.insertClips([clip], index: selected.index + 1));
    setState(() => _selection = TimelineSelection.clip(selected.index + 1));
  }

  void _delete() {
    final selected = _selection;
    final edit = _edit;
    if (selected == null || edit == null) return;
    setState(() => _selection = null);
    if (selected.isClip) {
      // The last clip gone: back to picking.
      _setEdit(edit.removeClip(selected.index));
    } else {
      _setEdit(edit.removeTrack(selected.index));
    }
  }

  Future<void> _openVolume() async {
    final selected = _selection;
    final edit = _edit;
    if (selected == null || edit == null) return;
    final isClip = selected.isClip;
    final index = selected.index;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cl(context).surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(CLRadii.lg))),
      builder: (_) => _VolumeSheet(
        icon: isClip ? Icons.videocam_outlined : Icons.music_note_rounded,
        title: isClip
            ? "Video sound"
            : (edit.audio[index].name ?? "Music"),
        value: isClip ? edit.clips[index].volume : edit.audio[index].volume,
        onChanged: (volume) {
          final now = _edit;
          if (now == null) return;
          if (isClip && index < now.clips.length) {
            _setEdit(now.replaceClip(
                index, now.clips[index].copyWith(volume: volume)));
          } else if (!isClip && index < now.audio.length) {
            _setEdit(now.replaceTrack(
                index, now.audio[index].copyWith(volume: volume)));
          }
        },
      ),
    );
  }

  // ------------------------------------------------------------------ share

  bool get _ready =>
      !_busy &&
      (widget.sharedPost != null || _edit != null) &&
      ephemeralCharCount(_caption.text.trim()) <= momentCaptionMaxLength;

  /// A single photo is a photo moment; anything more plays as a video.
  static String _madeFrom(Composition edit) =>
      edit.clips.length == 1 && edit.allStills ? 'photo' : 'video';

  Future<void> _share() async {
    if (!_ready) return;
    FocusScope.of(context).unfocus();
    if (widget.sharedPost != null) return _shareSharedPost();

    final edit = _edit!.withAutoFades();
    _player.pause();
    try {
      final rendered = await _renderFor(edit, watermark: false);
      if (rendered == null) {
        // Cancelled.
        _backToEditing(failed: false);
        return;
      }

      setState(() => _phase = _Phase.uploading);
      final api = ProfileApi();
      final video = _uploadedVideo ??= await api
          .uploadMediaRequest(rendered.videoPath, 'video', action: 'moment');
      if (video == null) return _fail("Couldn't upload your moment");
      final poster = _uploadedPoster ??= (await api.uploadMediaRequest(
              rendered.posterPath, 'image',
              action: 'moment_poster'))
          ?.url;
      if (poster == null) return _fail("Couldn't upload your moment");

      if (!mounted) return;
      setState(() => _phase = _Phase.posting);
      final error = await MomentsApi().createMomentRequest(
        mediaUrl: video.url,
        mediaType: video.mediaType,
        fileName: video.fileName,
        poster: (url: poster, width: rendered.width, height: rendered.height),
        source: _madeFrom(edit),
        hasAudio: rendered.hasSound,
        caption: _caption.text.trim(),
        privacy: _audience,
        allowReplies: _allowReplies,
      );
      if (error != null) return _fail(error);

      await _dropRender();
      if (!mounted) return;
      EphemeralEvents.moments.value++;
      _toast("Your moment is up for 24 hours");
      context.pop(true);
    } on MediaEngineException catch (e) {
      debugPrint('CreateMoment: render failed: ${e.message}\n${e.logs}');
      _backToEditing(failed: true);
      if (mounted) await _showRenderFailure(e);
    }
  }

  // ------------------------------------------------------- save to device

  bool get _canSave => !_busy && _edit != null;

  /// Whose moment it is, for under the watermark's logo: "@username", or
  /// the page's "@slug" while switched to one. Null when there is none.
  String? get _handle {
    final user = appStore.state.userAuth.user;
    final name =
        user.isActingAsEntity ? user.activeEntity?.slug : user.username;
    return name == null || name.trim().isEmpty ? null : '@${name.trim()}';
  }

  /// Renders the edit with the watermark - or takes that render if it is
  /// already made - and saves it to the gallery, without sharing.
  Future<void> _saveToDevice() async {
    if (!_canSave) return;
    FocusScope.of(context).unfocus();
    final edit = _edit!.withAutoFades();
    _player.pause();
    _savingToDevice = true;
    MediaEngineException? renderFailure;
    try {
      final rendered =
          await _renderFor(edit, watermark: true, handle: _handle);
      if (rendered != null && mounted) {
        setState(() => _phase = _Phase.saving);
        // A single photo with no sound is saved as the photo (the poster:
        // the frame the video holds); anything else as the video.
        final still = _madeFrom(edit) == 'photo' && !rendered.hasSound;
        final saved = await GallerySaver.save(
          still ? rendered.posterPath : rendered.videoPath,
          fileName:
              GallerySaver.fileNameFor(DateTime.now(), still ? 'jpg' : 'mp4'),
          mimeType: still ? 'image/jpeg' : 'video/mp4',
        );
        if (saved && mounted) _toast("Saved to your gallery");
      }
    } on MediaEngineException catch (e) {
      debugPrint('CreateMoment: render failed: ${e.message}\n${e.logs}');
      renderFailure = e;
    } catch (e) {
      if (mounted) _toast(GallerySaver.failureMessage(e));
    }
    _savingToDevice = false;
    // Share's Retry, if a share had failed, stays.
    _backToEditing(failed: _failed);
    if (renderFailure != null && mounted) {
      await _showRenderFailure(renderFailure);
    }
  }

  /// A render failure, with ffmpeg's own words for whoever has to fix it.
  Future<void> _showRenderFailure(MediaEngineException e) {
    final details = (e.logs ?? '').trim();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(e.message),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Try again, or try different photos or videos."),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 12),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cl(dialogContext).surface2,
                      borderRadius: BorderRadius.circular(CLRadii.sm),
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: SelectableText(
                        details,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: CLType.meta),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (details.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: details));
                Navigator.pop(dialogContext);
                _toast("Details copied");
              },
              child: const Text("Copy details"),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  /// The render of [edit] - the one already made when nothing changed since,
  /// else a new one. Null when cancelled.
  Future<RenderResult?> _renderFor(Composition edit,
      {required bool watermark, String? handle}) async {
    final key = '${jsonEncode(edit.toJson())}|watermark=$watermark|$handle';
    final previous = _rendered;
    if (previous != null && _renderedFor == key) return previous;
    await _dropRender();

    setState(() {
      _phase = _Phase.rendering;
      _renderProgress = 0;
    });
    // The preview's players let go of their decoders and memory while the
    // render needs them; they come back after (_backToEditing).
    _player.releaseVideos();
    final job = _job = MediaEngine.instance.render(edit,
        profile: _profile, watermark: watermark, handle: handle);
    void onProgress() {
      // Progress arrives with every frame encoded: the screen redraws only
      // when the percentage shown changes.
      final value = job.progress.value;
      if (mounted && (value * 100).floor() != (_renderProgress * 100).floor()) {
        setState(() => _renderProgress = value);
      }
    }

    job.progress.addListener(onProgress);
    try {
      final result = await job.result;
      if (!mounted) {
        await result.dispose();
        return null;
      }
      _rendered = result;
      _renderedFor = key;
      return result;
    } on RenderCancelled {
      return null;
    } finally {
      job.progress.removeListener(onProgress);
      if (identical(_job, job)) _job = null;
    }
  }

  /// Forgets the last render and its uploads (the edit changed, or it is
  /// posted).
  Future<void> _dropRender() async {
    final rendered = _rendered;
    _rendered = null;
    _renderedFor = null;
    _uploadedVideo = null;
    _uploadedPoster = null;
    await rendered?.dispose();
  }

  void _fail(String message) {
    if (!mounted) return;
    _toast(message);
    _backToEditing(failed: true);
  }

  void _backToEditing({required bool failed}) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.editing;
      _failed = failed;
    });
    _player.resume();
  }

  Future<void> _shareSharedPost() async {
    setState(() => _phase = _Phase.posting);
    final error = await MomentsApi().createMomentRequest(
      sharedPostId: widget.sharedPost!.postId,
      caption: _caption.text.trim(),
      privacy: _audience,
      allowReplies: _allowReplies,
    );
    if (!mounted) return;
    if (error != null) return _fail(error);
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

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final hasContent = widget.sharedPost != null || _edit != null;
    final audience = ephemeralAudiences.firstWhere((a) => a.key == _audience,
        orElse: () => ephemeralAudiences.first);
    final holding = _phase == _Phase.uploading ||
        _phase == _Phase.posting ||
        _phase == _Phase.saving;
    final edit = _edit;

    return PopScope(
      // A render can be abandoned (leaving cancels it); an upload or post
      // in flight can't be taken back, so it is waited out - and a save to
      // the gallery, which is copying the render leaving would delete.
      canPop: !holding,
      child: Scaffold(
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
                      onPressed: holding ? null : () => context.pop(),
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.sharedPost == null
                          ? "New moment"
                          : "Add to moment",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: CLType.screenTitle,
                          fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    if (widget.sharedPost == null && edit != null) ...[
                      IconButton(
                        tooltip: "Save to device",
                        onPressed: _canSave ? _saveToDevice : null,
                        color: Colors.white,
                        disabledColor: Colors.white38,
                        icon: const Icon(Icons.download_rounded),
                      ),
                      const SizedBox(width: 4),
                    ],
                    CLBtn(
                      label: _phase != _Phase.editing && !_savingToDevice
                          ? "Sharing…"
                          : _failed
                              ? "Retry"
                              : "Share",
                      size: CLBtnSize.sm,
                      onPressed: _ready ? _share : null,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _profile.aspectRatio,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(CLRadii.lg),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _stage(),
                            if (edit != null && _phase == _Phase.editing)
                              Positioned(
                                top: 10,
                                right: 10,
                                child: _tools(),
                              ),
                            if (hasContent)
                              Positioned(
                                left: 12,
                                right: 12,
                                bottom: 12,
                                child: _captionField(),
                              ),
                            if (_phase != _Phase.editing) _progress(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (edit != null) ...[
                _transport(edit),
                TimelineView(
                  edit: edit,
                  position: _player.position,
                  maxTotal: _profile.maxDuration,
                  thumbnails: _thumbnails,
                  selection: _selection,
                  onSelect: _select,
                  onEdit: _onTimelineEdit,
                  onEditEnd: () {},
                  onSeek: _player.seek,
                  onScrubStart: _startScrub,
                  onScrubEnd: _endScrub,
                  onAddMedia: _chooseSource,
                  onAddAudio: _addAudio,
                  enabled: !_busy,
                ),
                _selectionBar(edit),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
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
                          : () =>
                              setState(() => _allowReplies = !_allowReplies),
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
      ),
    );
  }

  /// Play / pause, and where the playhead is of how long.
  Widget _transport(Composition edit) {
    final total = edit.naturalDuration;
    final over = total > _profile.maxDuration;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 12, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: _player.playing ? "Pause" : "Play",
            onPressed: _busy ? null : _player.toggle,
            icon: Icon(
              _player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          ValueListenableBuilder<Duration>(
            valueListenable: _player.position,
            builder: (context, at, _) => Text(
              "${TrimBar.clock(at)} / ${TrimBar.clock(total)}",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: CLType.label,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          const Spacer(),
          Text(
            over
                ? "Only the first ${TrimBar.lengthLabel(_profile.maxDuration)} is kept"
                : "${edit.clips.length} ${edit.clips.length == 1 ? "clip" : "clips"}"
                    " · up to ${TrimBar.lengthLabel(_profile.maxDuration)}",
            style: TextStyle(
                color: over ? const Color(0xFFFFB74D) : Colors.white54,
                fontSize: CLType.caption),
          ),
        ],
      ),
    );
  }

  /// What can be done to the picked card - or how to pick one.
  Widget _selectionBar(Composition edit) {
    final selected = _selection;
    if (selected == null) {
      return const SizedBox(
        height: 52,
        child: Center(
          child: Text(
            "Tap a clip or song to edit it · hold a clip to move it",
            style: TextStyle(color: Colors.white38, fontSize: CLType.caption),
          ),
        ),
      );
    }
    final enabled = !_busy;
    final clip = selected.isClip ? edit.clips[selected.index] : null;
    final hasSound = clip == null || (clip.source.isVideo && clip.source.hasAudio);
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const SizedBox(width: 8),
          _BarAction(
            icon: Icons.content_cut_rounded,
            label: "Split",
            onTap: enabled ? _split : null,
          ),
          if (clip != null)
            _BarAction(
              icon: Icons.control_point_duplicate_rounded,
              label: "Duplicate",
              onTap: enabled ? _duplicate : null,
            ),
          if (hasSound)
            _BarAction(
              icon: Icons.volume_up_rounded,
              label: "Volume",
              onTap: enabled ? _openVolume : null,
            ),
          _BarAction(
            icon: Icons.delete_outline_rounded,
            label: "Delete",
            onTap: enabled ? _delete : null,
          ),
          const Spacer(),
          _BarAction(
            icon: Icons.check_rounded,
            label: "Done",
            onTap: () => _select(null),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// The clip's tools, down the canvas's right edge - for the clip on it.
  Widget _tools() {
    const gap = SizedBox(height: 8);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundAction(
          icon: _isFilled
              ? Icons.fit_screen_outlined
              : Icons.zoom_out_map_rounded,
          tooltip: _isFilled ? "Fit" : "Fill",
          onTap: _toggleFill,
        ),
        gap,
        _RoundAction(
          icon: Icons.rotate_90_degrees_cw_outlined,
          tooltip: "Rotate",
          onTap: _rotateQuarter,
        ),
        gap,
        _RoundAction(
          icon: _edit!.background.isBlur
              ? Icons.blur_on_rounded
              : Icons.format_color_fill_rounded,
          tooltip: "Background",
          onTap: _chooseBackground,
        ),
        if (!_isPristine) ...[
          gap,
          _RoundAction(
            icon: Icons.restart_alt_rounded,
            tooltip: "Reset framing",
            onTap: _resetFraming,
          ),
        ],
      ],
    );
  }

  Widget _progress() {
    final label = switch (_phase) {
      _Phase.rendering =>
        "Preparing your moment… ${(_renderProgress * 100).round()}%",
      _Phase.uploading => "Uploading…",
      _Phase.saving => "Saving to your gallery…",
      _ => "Sharing…",
    };
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  value: _phase == _Phase.rendering ? _renderProgress : null,
                  strokeWidth: 4,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                ),
              ),
              const SizedBox(height: 14),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: CLType.label,
                      fontWeight: FontWeight.w600)),
              if (_phase == _Phase.rendering) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => _job?.cancel(),
                  child: const Text("Cancel",
                      style: TextStyle(color: Colors.white70)),
                ),
              ],
            ],
          ),
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

    if (_preparing && _edit == null) {
      return const ColoredBox(
        color: Color(0xFF15181D),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final edit = _edit;
    if (edit == null) {
      return ColoredBox(
        color: const Color(0xFF15181D),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Add photos and videos",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: CLType.sectionTitle,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    "Pick several - they play one after another, up to "
                    "${TrimBar.lengthLabel(_profile.maxDuration)}. "
                    "Gone after 24 hours.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
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
        ),
      );
    }

    final index = _current;
    return Stack(
      fit: StackFit.expand,
      children: [
        EditCanvas(
          layer: edit.clips[index],
          background: edit.background,
          video: _player.videoFor(index),
          enabled: _phase == _Phase.editing && !_preparing,
          onTransform: _setTransform,
          onDoubleTap: _toggleFill,
        ),
        if (_preparing)
          const ColoredBox(
            color: Colors.black38,
            child:
                Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
      ],
    );
  }
}

/// A tool for the picked card, under the timeline.
class _BarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _BarAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? Colors.white38 : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CLRadii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: CLType.meta,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// One sound's level - a clip's own, or a song's - with a mute.
class _VolumeSheet extends StatefulWidget {
  final IconData icon;
  final String title;
  final double value;
  final ValueChanged<double> onChanged;

  const _VolumeSheet({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_VolumeSheet> createState() => _VolumeSheetState();
}

class _VolumeSheetState extends State<_VolumeSheet> {
  late double _value = widget.value;
  late double _restore = widget.value > 0 ? widget.value : 1;

  void _set(double value) {
    setState(() {
      _value = value;
      if (value > 0) _restore = value;
    });
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final muted = _value <= 0;
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
            Row(
              children: [
                Icon(widget.icon, size: 18, color: p.text2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: CLType.title,
                          fontWeight: FontWeight.w700,
                          color: p.text)),
                ),
                Text(muted ? "Muted" : "${(_value * 100).round()}%",
                    style: TextStyle(fontSize: CLType.caption, color: p.text2)),
                IconButton(
                  tooltip: muted ? "Unmute" : "Mute",
                  onPressed: () => _set(muted ? _restore : 0),
                  icon: Icon(
                    muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: muted ? p.text2 : p.brand,
                  ),
                ),
              ],
            ),
            Slider(
              value: _value.clamp(0.0, 1.0),
              divisions: 20,
              onChanged: _set,
            ),
          ],
        ),
      ),
    );
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

/// What fills the canvas around the media: the blurred media, or a colour.
class _BackgroundSheet extends StatelessWidget {
  final CompositionBackground selected;
  final List<int> colors;
  final ValueChanged<CompositionBackground> onPick;

  const _BackgroundSheet({
    required this.selected,
    required this.colors,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    Widget swatch({
      required bool isSelected,
      required VoidCallback onTap,
      required Widget child,
      Color? color,
      String? label,
    }) {
      return Tooltip(
        message: label ?? '',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? p.brand : p.border2,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: child,
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
            Text("Background",
                style: TextStyle(
                    fontSize: CLType.sectionTitle,
                    fontWeight: FontWeight.w800,
                    color: p.text)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                swatch(
                  label: "Blur",
                  isSelected: selected.isBlur,
                  onTap: () => onPick(CompositionBackground.blur),
                  color: p.surface2,
                  child: Icon(Icons.blur_on_rounded, color: p.text2),
                ),
                for (final argb in colors)
                  swatch(
                    isSelected: !selected.isBlur && selected.argb == argb,
                    onTap: () => onPick(CompositionBackground.color(argb)),
                    color: Color(argb),
                    child: const SizedBox.shrink(),
                  ),
              ],
            ),
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
