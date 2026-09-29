import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/encoding_profile.dart';
import 'package:chatterloop_app/core/media/media_engine.dart';
import 'package:chatterloop_app/core/media/sequence_player.dart';
import 'package:chatterloop_app/core/media/still_image.dart';
import 'package:chatterloop_app/core/media/text_card_image.dart';
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
import 'package:chatterloop_app/views/moments/text_card_page.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
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
/// - played one after another; LAYERS - more photos and videos over them,
/// in lanes, a higher lane drawn on top; and MUSIC laid along under them,
/// in lanes that play together. On the timeline, all of them are cards:
/// trimmed by their ends, held and dragged to another place or lane (a clip
/// up into a layer, a layer down into the clips); split, duplicate, bring
/// forward / send back, volume and delete act on the picked card. A picked
/// clip slides to leave a blank - black and silent - and the moment runs
/// as long as whatever ends last, a layer or a song past the clips too.
/// Each clip and layer is framed on the canvas on its own - dragged,
/// pinched, twisted, fitted or filled - over a blurred or plain background.
/// Undo and Redo step through every change. Up to 2 minutes.
///
/// Upright, the canvas sits over the timeline; on its side, beside it.
///
/// It is rendered on the device into the MP4 that gets posted
/// (lib/core/media). Save puts a copy on the phone, with the watermark;
/// what is posted has none.
///
/// From a post's Share options it is that post instead ([sharedPost]),
/// posted as it is - no editor, no render.
class CreateMomentScreen extends StatefulWidget {
  final PostPreview? sharedPost;

  /// Tests only: open straight into editing this.
  @visibleForTesting
  final Composition? initialEdit;

  const CreateMomentScreen({super.key, this.sharedPost, this.initialEdit});

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

  /// A new layer starts as a picture-in-picture: the whole of it, smaller
  /// than the canvas, so what is under it still shows.
  static const _layerFraming = LayerTransform(scale: 0.6);

  /// How many steps back Undo goes.
  static const _historyLimit = 50;

  final _caption = TextEditingController();
  late String _audience =
      appStore.state.userAuth.user.isPrivate == true ? "connections" : "public";
  bool _allowReplies = true;

  // ---- The edit.
  /// This editor's temp folder (prepared photos, thumbnails); deleted on
  /// close.
  Directory? _workspace;
  Composition? _edit;

  /// Made in initState, not lazily: first touched in dispose() - the screen
  /// closed before anything was picked - it was made there, and making its
  /// ticker looked up a widget tree already coming down.
  late final SequencePlayer _player;
  TimelineSelection? _selection;

  /// A video file's picture for its timeline cards, by path.
  final Map<String, String> _thumbnails = {};
  bool _preparing = false;

  /// Playing when a scrub started - it plays on once let go.
  bool _resumeAfterScrub = false;

  // ---- Undo / redo: the edits before and after this one. Null is "no
  // edit yet" - undoing the first photos goes back to picking.
  final List<Composition?> _undo = [];
  final List<Composition?> _redo = [];

  /// A drag, pinch or slider under way, and the edit as it was when it
  /// began: the whole gesture is one step back, not one per frame.
  bool _inGesture = false;
  Composition? _gestureStart;

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
    _player = SequencePlayer(vsync: this)..addListener(_onPlayer);
    _caption.addListener(() => setState(() {}));
    final edit = widget.initialEdit;
    if (edit != null) {
      _edit = edit;
      _player.setEdit(edit);
    }
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

  void _toast(String text, {CLAlertType type = CLAlertType.warning}) {
    CLAlerts.show(text, type: type);
  }

  bool get _busy => _phase != _Phase.editing || _preparing;

  // ---------------------------------------------------------------- picking

  /// Time left before the moment reaches its 2 minutes.
  Duration get _room =>
      _edit?.remaining(_profile.maxDuration) ?? _profile.maxDuration;

  void _full() => _toast(
      "A moment can be up to ${TrimBar.lengthLabel(_profile.maxDuration)}");

  /// Where new things go in: the playhead - or the top, when the playhead
  /// is at the very end.
  Duration _insertAt(Composition edit) {
    final at = _player.position.value;
    return at >= edit.naturalDuration - minPiece ? Duration.zero : at;
  }

  /// A photo or video from the camera - no longer than [maxVideo].
  Future<List<_Picked>> _fromCamera(
      {required bool video, required Duration maxVideo}) async {
    final picker = ImagePicker();
    final file = video
        ? await picker.pickVideo(source: ImageSource.camera, maxDuration: maxVideo)
        : await picker.pickImage(source: ImageSource.camera, imageQuality: 95);
    return file == null ? const [] : [(path: file.path, video: video)];
  }

  /// The phone's gallery (Android's photo picker) - as many photos and
  /// videos as wanted, in the order picked.
  Future<List<_Picked>> _fromGallery() async {
    final List<XFile> files;
    try {
      files = await ImagePicker().pickMultipleMedia();
    } catch (_) {
      if (mounted) _toast("Couldn't open your gallery");
      return const [];
    }
    return [
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
    ];
  }

  /// Gallery, photo or video, as a sheet - then that source's files.
  Future<List<_Picked>> _pickFromSheet(
      {required String title, required Duration maxVideo}) async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: cl(context).surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(CLRadii.lg))),
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(title,
                    style: TextStyle(
                        fontSize: CLType.sectionTitle,
                        fontWeight: FontWeight.w800,
                        color: cl(sheetContext).text)),
              ),
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
      ),
    );
    return switch (choice) {
      0 => _fromCamera(video: false, maxVideo: maxVideo),
      1 => _fromCamera(video: true, maxVideo: maxVideo),
      2 => _fromGallery(),
      _ => Future.value(const <_Picked>[]),
    };
  }

  /// The empty canvas's buttons: straight to that source.
  Future<void> _startFrom(int source) async {
    final files = switch (source) {
      0 => await _fromCamera(video: false, maxVideo: _room),
      1 => await _fromCamera(video: true, maxVideo: _room),
      _ => await _fromGallery(),
    };
    if (files.isNotEmpty) await _addFiles(files);
  }

  /// More clips for the main run: the same three sources as the empty
  /// canvas, as a sheet.
  Future<void> _chooseSource() async {
    if (_room < minPiece) return _full();
    _player.pause();
    final files = await _pickFromSheet(title: "Add clips", maxVideo: _room);
    if (files.isNotEmpty) await _addFiles(files);
  }

  /// A picked file ready to be a clip: opened, a video cut to the part
  /// wanted - at most [room] of it - and its card's picture made. Null when
  /// it couldn't be opened or was skipped.
  Future<MediaLayer?> _prepareClip(
    _Picked file, {
    required Directory workspace,
    required Duration room,
    required LayerTransform Function(MediaSource) framing,
    String? step,
  }) async {
    final source =
        await _open(file.path, looksLikeVideo: file.video, into: workspace);
    if (!mounted) return null;
    if (source == null) {
      _toast("Couldn't open one of those");
      return null;
    }
    if (!source.isVideo) {
      return MediaLayer(
        source: source,
        transform: framing(source),
        duration: room < MediaLayer.defaultStill ? room : MediaLayer.defaultStill,
      );
    }
    setState(() => _preparing = false);
    final range = await ClipTrimPage.open(context,
        source: source, maxSpan: room, step: step);
    if (!mounted) return null;
    setState(() => _preparing = true);
    if (range == null) return null;
    if (!_thumbnails.containsKey(source.path)) {
      final thumb = await MediaEngine.instance
          .thumbnail(source.path, range.start, workspace);
      if (thumb != null) _thumbnails[source.path] = thumb;
    }
    return MediaLayer(source: source, transform: framing(source), trim: range);
  }

  /// Turns picked files into clips - each video first cut to the part
  /// wanted - and puts them in after the picked clip (else at the end),
  /// while there is room.
  Future<void> _addFiles(List<_Picked> files) async {
    if (_room < minPiece) return _full();
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
        final clip = await _prepareClip(
          file,
          workspace: workspace,
          room: room,
          framing: _initialTransform,
          step: files.length > 1 ? '${i + 1} of ${files.length}' : null,
        );
        if (!mounted) return;
        if (clip == null) continue;
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

  /// A LAYER: photos or videos over the main clips, from the playhead - on
  /// the lowest lane free there, else a lane of their own on top. Several
  /// follow one another.
  Future<void> _addLayer() async {
    final edit = _edit;
    if (edit == null) return;
    _player.pause();
    final from = _insertAt(edit);
    final slot = edit.overlaySlot(from, maxTotal: _profile.maxDuration);
    if (slot == null) {
      return _toast(edit.overlayLanes >= maxOverlayLanes
          ? "Up to $maxOverlayLanes layers over each other - "
              "move or trim one first"
          : "No room for a layer here");
    }
    final files =
        await _pickFromSheet(title: "Add a layer", maxVideo: slot.room);
    if (files.isEmpty || !mounted) return;

    setState(() => _preparing = true);
    var next = _edit!;
    var at = from;
    ({int lane, Duration start})? last;
    var ranOut = false;
    try {
      await SharedVideoControllers.releaseIdle();
      final workspace =
          _workspace ??= await MediaEngine.instance.createWorkspace();
      for (final (i, file) in files.indexed) {
        final room = next.overlaySlot(at, maxTotal: _profile.maxDuration);
        if (room == null) {
          ranOut = true;
          break;
        }
        final clip = await _prepareClip(
          file,
          workspace: workspace,
          room: room.room,
          framing: (_) => _layerFraming,
          step: files.length > 1 ? '${i + 1} of ${files.length}' : null,
        );
        if (!mounted) return;
        if (clip == null) continue;
        final placed =
            next.addOverlay(clip, at: at, maxTotal: _profile.maxDuration);
        if (placed == null) {
          ranOut = true;
          break;
        }
        next = placed;
        last = (lane: room.lane, start: room.start);
        // The next one straight after it.
        at += clip.length;
      }
    } catch (e) {
      debugPrint('CreateMoment: layer failed: $e');
      if (mounted) _toast("Couldn't open that file");
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
    if (!mounted) return;
    if (ranOut) _toast("Not all of them fit where they went");
    if (last == null) return;
    final landed = last;
    // All of them one step for Undo.
    _setEdit(next);
    final index = next.overlays
        .indexWhere((o) => o.lane == landed.lane && o.start == landed.start);
    if (index >= 0) setState(() => _selection = TimelineSelection.overlay(index));
    _player.seek(from);
  }

  /// How long new text shows, when there is room.
  static const _textLength = Duration(seconds: 3);

  /// Words over the moment from the playhead - a text layer, on the lowest
  /// lane free there, like any layer.
  Future<void> _addText() async {
    final edit = _edit;
    if (edit == null) return;
    _player.pause();
    final from = _insertAt(edit);
    final slot = edit.overlaySlot(from, maxTotal: _profile.maxDuration);
    if (slot == null) {
      return _toast(edit.overlayLanes >= maxOverlayLanes
          ? "Up to $maxOverlayLanes layers over each other - "
              "move or trim one first"
          : "No room for text here");
    }
    final card = await TextCardPage.open(context);
    if (card == null || !mounted) return;
    final source = await _drawText(card);
    if (source == null || !mounted) return;
    final clip = MediaLayer(
      source: source,
      duration: slot.room < _textLength ? slot.room : _textLength,
      transform: LayerTransform(
          scale: TextCardImage.framingScale(source, _profile.aspectRatio)),
    );
    final next = _edit!
        .addOverlay(clip, at: from, maxTotal: _profile.maxDuration, text: card);
    if (next == null) return _toast("No room for text here");
    _setEdit(next);
    final index = next.overlays.indexWhere((o) => identical(o.text, card));
    if (index >= 0) {
      setState(() => _selection = TimelineSelection.overlay(index));
    }
    _player.seek(from);
  }

  /// The text layer at [index]'s words changed - drawn again, its letters
  /// kept the size they were.
  Future<void> _editText(int index) async {
    final overlay = _edit?.overlays[index];
    final old = overlay?.text;
    if (overlay == null || old == null) return;
    _player.pause();
    final card = await TextCardPage.open(context, initial: old);
    if (card == null || card == old || !mounted) return;
    final source = await _drawText(card);
    if (source == null || !mounted) return;
    final edit = _edit!;
    final at = edit.overlays.indexOf(overlay);
    if (at < 0) return;
    final aspect = _profile.aspectRatio;
    final t = overlay.clip.transform;
    // The user's own zoom on it, kept.
    final zoom =
        t.scale / TextCardImage.framingScale(overlay.clip.source, aspect);
    _setEdit(edit.replaceOverlay(
      at,
      overlay.copyWith(
        clip: MediaLayer(
          source: source,
          duration: overlay.clip.length,
          transform: t.copyWith(
              scale: TextCardImage.framingScale(source, aspect) * zoom),
        ),
        text: card,
      ),
    ));
  }

  /// [card] drawn into a picture in the workspace - null, told, when it
  /// can't be.
  Future<MediaSource?> _drawText(TextCard card) async {
    final font = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    try {
      final workspace =
          _workspace ??= await MediaEngine.instance.createWorkspace();
      return await TextCardImage.render(card, workspace, fontFamily: font);
    } catch (e) {
      debugPrint('CreateMoment: text failed: $e');
      if (mounted) _toast("Couldn't add that text");
      return null;
    }
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
      // At the playhead, on the first lane free there - else a lane of its
      // own, heard with the others.
      final slot =
          current.trackSlot(_insertAt(current), maxTotal: _profile.maxDuration);
      if (slot == null) {
        _toast("Up to $maxAudioLanes songs at once - "
            "trim or move one first");
        return;
      }
      // The part of it to use, no longer than the room where it goes.
      if (!mounted) return;
      setState(() => _preparing = false);
      // It may run on past the clips (the moment grows, blank under it) -
      // but starts picked to the moment's length as it is, so adding a
      // long song doesn't make a long moment unasked.
      final toEnd = current.naturalDuration - slot.start;
      final range = await AudioTrimPage.open(
        context,
        path: path,
        name: name,
        length: length,
        maxSpan: slot.room,
        initialSpan: toEnd >= minPiece && toEnd < slot.room ? toEnd : null,
      );
      if (range == null || !mounted) return;
      final next = _edit!.addTrack(
        AudioTrack(path: path, name: name, fileLength: length, trim: range),
        at: slot.start,
        maxTotal: _profile.maxDuration,
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

  /// Every change to the edit comes through here - the preview follows, and
  /// it is a step for Undo. A [gesture]'s changes (a drag, a pinch, a
  /// slider) are one step together, taken when it ends - or when anything
  /// else changes the edit, so a gesture whose end never came can't swallow
  /// the steps after it.
  void _setEdit(Composition? next, {bool record = true, bool gesture = false}) {
    final previous = _edit;
    if (identical(previous, next)) return;
    if (gesture) {
      _beginGesture();
    } else {
      _endGesture();
      if (record) _remember(previous);
    }
    setState(() {
      _edit = next;
      _failed = false;
      _selection = _stillThere(_selection, next);
    });
    _player.setEdit(next);
  }

  /// [selection] when [edit] still has what it points at.
  static TimelineSelection? _stillThere(
      TimelineSelection? selection, Composition? edit) {
    if (selection == null || edit == null) return null;
    final count = switch (selection.kind) {
      TimelineKind.clip => edit.clips.length,
      TimelineKind.overlay => edit.overlays.length,
      TimelineKind.track => edit.audio.length,
    };
    return selection.index < count ? selection : null;
  }

  void _remember(Composition? state) {
    _undo.add(state);
    if (_undo.length > _historyLimit) _undo.removeAt(0);
    _redo.clear();
  }

  void _beginGesture() {
    if (_inGesture) return;
    _inGesture = true;
    _gestureStart = _edit;
  }

  void _endGesture() {
    if (!_inGesture) return;
    _inGesture = false;
    final start = _gestureStart;
    _gestureStart = null;
    if (!identical(start, _edit)) setState(() => _remember(start));
  }

  bool get _canUndo => _undo.isNotEmpty && !_busy;
  bool get _canRedo => _redo.isNotEmpty && !_busy;

  void _undoEdit() {
    _endGesture();
    if (!_canUndo) return;
    _player.pause();
    HapticFeedback.selectionClick();
    final back = _undo.removeLast();
    _redo.add(_edit);
    _selection = null;
    _setEdit(back, record: false);
  }

  void _redoEdit() {
    _endGesture();
    if (!_canRedo) return;
    _player.pause();
    HapticFeedback.selectionClick();
    final forward = _redo.removeLast();
    _undo.add(_edit);
    _selection = null;
    _setEdit(forward, record: false);
  }

  void _onTimelineEdit(Composition next) {
    if (_player.playing) _player.pause();
    // A trim or a move: one step, whenever it ends (onEditEnd).
    _setEdit(next, gesture: true);
  }

  void _startScrub() {
    _resumeAfterScrub = _player.playing;
    _player.pause();
  }

  void _endScrub() {
    if (_resumeAfterScrub) _player.play();
    _resumeAfterScrub = false;
  }

  /// The main clip on the canvas - the one under the playhead; null in a
  /// blank.
  int? get _current {
    final edit = _edit;
    final index = _player.currentIndex;
    return edit == null || index == null || index >= edit.clips.length
        ? null
        : index;
  }

  void _select(TimelineSelection? selection) {
    setState(() => _selection = selection);
    final edit = _edit;
    if (selection == null || edit == null) return;
    // The canvas shows the picked clip or layer: the playhead into it.
    final Duration start, end;
    switch (selection.kind) {
      case TimelineKind.clip:
        start = edit.clipStarts[selection.index];
        end = start + edit.clips[selection.index].length;
      case TimelineKind.overlay:
        final overlay = edit.overlays[selection.index];
        if (overlay.start >= edit.naturalDuration) return;
        start = overlay.start;
        end = overlay.end;
      case TimelineKind.track:
        return;
    }
    final at = _player.position.value;
    if (at < start || at >= end) _player.seek(start);
  }

  // ---------------------------------------------------------------- framing

  /// The layer the framing tools work on: the picked one while it shows -
  /// else none, and they work on the main clip under the playhead.
  int? get _framedLayer {
    final selected = _selection;
    final edit = _edit;
    if (selected == null || edit == null || !selected.isOverlay) return null;
    return edit.overlaysAt(_player.position.value).contains(selected.index)
        ? selected.index
        : null;
  }

  /// The clip the framing tools work on: that overlay ([layer]), or the
  /// main clip on the canvas - none in a blank.
  MediaLayer? _clipOf(int? layer) {
    if (layer != null) return _edit!.overlays[layer].clip;
    final index = _current;
    return index == null ? null : _edit!.clips[index];
  }

  /// Framing of the main clip on the canvas ([layer] null), or of that
  /// overlay.
  void _setTransform(int? layer, LayerTransform transform,
      {bool gesture = false}) {
    final edit = _edit!;
    if (layer == null) {
      final index = _current;
      if (index == null) return;
      _setEdit(
          edit.replaceClip(
              index, edit.clips[index].copyWith(transform: transform)),
          gesture: gesture);
    } else {
      final overlay = edit.overlays[layer];
      _setEdit(
          edit.replaceOverlay(
              layer,
              overlay.copyWith(
                  clip: overlay.clip.copyWith(transform: transform))),
          gesture: gesture);
    }
  }

  LayerTransform _defaultFraming(int? layer, MediaSource source) =>
      layer == null ? _initialTransform(source) : _layerFraming;

  /// Fills the canvas: no bars, straight, centred.
  bool _isFilled(int? layer) {
    final clip = _clipOf(layer);
    if (clip == null) return false;
    final fill = LayerTransform.fillScale(
        clip.source.width / clip.source.height, _profile.aspectRatio);
    final t = clip.transform;
    return (t.scale - fill).abs() < 0.01 &&
        t.cx == 0.5 &&
        t.cy == 0.5 &&
        t.rotationDeg % 360 == 0;
  }

  void _toggleFill(int? layer) {
    final source = _clipOf(layer)?.source;
    if (source == null) return;
    _setTransform(
        layer,
        _isFilled(layer)
            ? LayerTransform.fit
            : LayerTransform.fill(
                source.width / source.height, _profile.aspectRatio));
  }

  /// On to the next quarter turn clockwise (a twisted clip straightens to
  /// the next one first).
  void _rotateQuarter(int? layer) {
    final t = _clipOf(layer)?.transform;
    if (t == null) return;
    final next = ((t.rotationDeg / 90).floor() + 1) * 90.0;
    _setTransform(layer, t.copyWith(rotationDeg: next % 360));
  }

  bool _isPristine(int? layer) {
    final clip = _clipOf(layer);
    return clip == null ||
        clip.transform == _defaultFraming(layer, clip.source);
  }

  void _resetFraming(int? layer) {
    final clip = _clipOf(layer);
    if (clip != null) {
      _setTransform(layer, _defaultFraming(layer, clip.source));
    }
  }

  Future<void> _chooseBackground() async {
    final picked = await showModalBottomSheet<CompositionBackground>(
      context: context,
      backgroundColor: cl(context).surface,
      isScrollControlled: true,
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
    final next = switch (selected.kind) {
      TimelineKind.clip => edit.splitAt(at),
      TimelineKind.overlay => edit.splitOverlay(selected.index, at),
      TimelineKind.track => edit.splitTrack(selected.index, at),
    };
    if (next == null) {
      _toast(switch (selected.kind) {
        TimelineKind.clip => "Move the playhead inside the clip to split it",
        TimelineKind.overlay =>
          "Move the playhead inside the layer to split it",
        TimelineKind.track => "Move the playhead inside the song to split it",
      });
      return;
    }
    HapticFeedback.selectionClick();
    _setEdit(next);
  }

  void _duplicate() {
    final selected = _selection;
    final edit = _edit;
    if (selected == null || edit == null) return;
    if (selected.isClip) {
      final clip = edit.clips[selected.index];
      if (clip.length > _room) return _full();
      _setEdit(edit.insertClips([clip], index: selected.index + 1));
      setState(() => _selection = TimelineSelection.clip(selected.index + 1));
    } else if (selected.isOverlay) {
      final next = edit.duplicateOverlay(selected.index,
          maxTotal: _profile.maxDuration);
      if (next == null) return _toast("No room for a copy of this layer");
      _setEdit(next);
      final index = next.overlays.indexWhere((o) => !edit.overlays.contains(o));
      if (index >= 0) {
        setState(() => _selection = TimelineSelection.overlay(index));
      }
    }
  }

  /// The picked main clip out of the run, onto a layer over where it was.
  void _lift() {
    final selected = _selection;
    final edit = _edit;
    if (selected == null || edit == null || !selected.isClip) return;
    final clip = edit.clips[selected.index];
    final next =
        edit.liftClip(selected.index, maxTotal: _profile.maxDuration);
    if (next == null) return _toast("No free layer for it there");
    _setEdit(next);
    final index = next.overlays.indexWhere((o) => identical(o.clip, clip));
    setState(() => _selection =
        index < 0 ? null : TimelineSelection.overlay(index));
  }

  /// How far the picked card is from its neighbours on its row.
  static Blanks _blanksOf(Composition edit, TimelineSelection selected) =>
      switch (selected.kind) {
        TimelineKind.clip => edit.clipBlanks(selected.index),
        TimelineKind.overlay => edit.overlayBlanks(selected.index),
        TimelineKind.track => edit.trackBlanks(selected.index),
      };

  /// The picked card slid against the one before it (the start, when none
  /// is) - or [toNext], against the one after it: the blank between gone.
  /// It only ever sticks like this when asked - dragged, it goes just
  /// where it is put.
  void _anchor({required bool toNext}) {
    final selected = _selection;
    final edit = _edit;
    if (selected == null || edit == null) return;
    final blanks = _blanksOf(edit, selected);
    final by = toNext ? blanks.after : -blanks.before;
    if (by == null || by == Duration.zero) return;
    final max = _profile.maxDuration;
    final next = switch (selected.kind) {
      TimelineKind.clip => edit.slideClip(selected.index, by, maxTotal: max),
      TimelineKind.overlay =>
        edit.slideOverlay(selected.index, by, maxTotal: max),
      TimelineKind.track => edit.slideTrack(selected.index, by, maxTotal: max),
    };
    HapticFeedback.selectionClick();
    _setEdit(next);
  }

  /// The picked layer over the next one it shows with, or under it.
  void _restack({required bool forward}) {
    final selected = _selection;
    final edit = _edit;
    if (selected == null || edit == null || !selected.isOverlay) return;
    final overlay = edit.overlays[selected.index];
    final next = forward
        ? edit.bringForward(selected.index)
        : edit.sendBackward(selected.index);
    if (next == null) {
      return _toast(forward
          ? "Already on top"
          : "Only the main clips are under it");
    }
    HapticFeedback.selectionClick();
    _setEdit(next);
    final index = next.overlays.indexWhere(
        (o) => identical(o.clip, overlay.clip) && o.start == overlay.start);
    setState(() => _selection =
        index < 0 ? null : TimelineSelection.overlay(index));
  }

  /// The picked layer into the main run, at the clip edge nearest it.
  void _toMain() {
    final selected = _selection;
    final edit = _edit;
    if (selected == null || edit == null || !selected.isOverlay) return;
    final clip = edit.overlays[selected.index].clip;
    final next =
        edit.dropOverlay(selected.index, maxTotal: _profile.maxDuration);
    if (next == null) return _full();
    _setEdit(next);
    final index = next.clips.indexWhere((c) => identical(c, clip));
    setState(() =>
        _selection = index < 0 ? null : TimelineSelection.clip(index));
    if (index >= 0) _player.seek(next.clipStarts[index]);
  }

  void _delete() {
    final selected = _selection;
    final edit = _edit;
    if (selected == null || edit == null) return;
    setState(() => _selection = null);
    switch (selected.kind) {
      case TimelineKind.clip:
        // The last clip gone: back to picking (Undo brings it back).
        _setEdit(edit.removeClip(selected.index));
      case TimelineKind.overlay:
        _setEdit(edit.removeOverlay(selected.index));
      case TimelineKind.track:
        _setEdit(edit.removeTrack(selected.index));
    }
  }

  Future<void> _openVolume() async {
    final selected = _selection;
    final edit = _edit;
    if (selected == null || edit == null) return;
    final kind = selected.kind;
    final index = selected.index;
    // The slider's moves are one step for Undo, when the sheet closes.
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cl(context).surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(CLRadii.lg))),
      builder: (_) => _VolumeSheet(
        icon: kind == TimelineKind.track
            ? Icons.music_note_rounded
            : Icons.videocam_outlined,
        title: switch (kind) {
          TimelineKind.clip => "Video sound",
          TimelineKind.overlay => "Layer sound",
          TimelineKind.track => edit.audio[index].name ?? "Music",
        },
        value: switch (kind) {
          TimelineKind.clip => edit.clips[index].volume,
          TimelineKind.overlay => edit.overlays[index].clip.volume,
          TimelineKind.track => edit.audio[index].volume,
        },
        onChanged: (volume) {
          final now = _edit;
          if (now == null) return;
          switch (kind) {
            case TimelineKind.clip when index < now.clips.length:
              _setEdit(
                  now.replaceClip(
                      index, now.clips[index].copyWith(volume: volume)),
                  gesture: true);
            case TimelineKind.overlay when index < now.overlays.length:
              final overlay = now.overlays[index];
              _setEdit(
                  now.replaceOverlay(
                      index,
                      overlay.copyWith(
                          clip: overlay.clip.copyWith(volume: volume))),
                  gesture: true);
            case TimelineKind.track when index < now.audio.length:
              _setEdit(
                  now.replaceTrack(
                      index, now.audio[index].copyWith(volume: volume)),
                  gesture: true);
            default:
              break;
          }
        },
      ),
    );
    _endGesture();
  }

  // ------------------------------------------------------------------ share

  bool get _ready =>
      !_busy &&
      (widget.sharedPost != null || _edit != null) &&
      ephemeralCharCount(_caption.text.trim()) <= momentCaptionMaxLength;

  /// A single photo is a photo moment; anything more plays as a video - a
  /// blank before it, or a song running on past it, too (the viewer shows
  /// a photo moment as its first frame, for its length).
  static String _madeFrom(Composition edit) => edit.clips.length == 1 &&
          edit.allStills &&
          edit.overlays.isEmpty &&
          edit.clips.single.gapBefore == Duration.zero &&
          edit.naturalDuration == edit.clips.single.length
      ? 'photo'
      : 'video';

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
      isScrollControlled: true,
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
          child: LayoutBuilder(
            builder: (context, box) {
              final landscape = box.maxWidth > box.maxHeight;
              if (landscape && edit != null) {
                return _sideBySide(edit, holding: holding);
              }
              return Column(
                children: [
                  _header(holding: holding),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      // Upright, the 9:16 moment as it will be. On its side
                      // with nothing picked yet (or a post being shared),
                      // the whole width - a 9:16 box there was a sliver.
                      child: landscape
                          ? _stageBox()
                          : Center(
                              child: AspectRatio(
                                aspectRatio: _profile.aspectRatio,
                                child: _stageBox(),
                              ),
                            ),
                    ),
                  ),
                  if (edit != null) ...[
                    _transport(edit),
                    _timeline(edit,
                        maxHeight: math.max(150.0, box.maxHeight * 0.3)),
                    _selectionBar(edit),
                  ],
                  _pills(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Editing on a phone on its side: the moment as tall as the screen on
  /// the left - big enough to frame things in - and everything else beside
  /// it, scrolling when the screen is too short for it all.
  Widget _sideBySide(Composition edit, {required bool holding}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: AspectRatio(
            aspectRatio: _profile.aspectRatio,
            child: _stageBox(),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, side) {
            // Header, play row, the picked card's tools and the pills.
            const others = 56.0 + 50 + 52 + 50;
            final forTimeline = side.maxHeight - others;
            if (forTimeline >= 110) {
              return Column(
                children: [
                  _header(holding: holding),
                  _transport(edit),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _timeline(edit, maxHeight: forTimeline),
                    ),
                  ),
                  _selectionBar(edit),
                  _pills(),
                ],
              );
            }
            return SingleChildScrollView(
              child: Column(
                children: [
                  _header(holding: holding),
                  _transport(edit),
                  _timeline(edit, maxHeight: 150),
                  _selectionBar(edit),
                  _pills(),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _header({required bool holding}) {
    final edit = _edit;
    final editing = widget.sharedPost == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: holding ? null : () => context.pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              editing ? "New moment" : "Add to moment",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: CLType.screenTitle,
                  fontWeight: FontWeight.w800),
            ),
          ),
          // Back from picking again (the last clip deleted, the first ones
          // undone): Undo / Redo here, where the play row was.
          if (editing && edit == null && (_undo.isNotEmpty || _redo.isNotEmpty))
            ..._historyButtons(),
          if (editing && edit != null) ...[
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
    );
  }

  List<Widget> _historyButtons() => [
        IconButton(
          tooltip: "Undo",
          onPressed: _canUndo ? _undoEdit : null,
          color: Colors.white,
          disabledColor: Colors.white24,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.undo_rounded),
        ),
        IconButton(
          tooltip: "Redo",
          onPressed: _canRedo ? _redoEdit : null,
          color: Colors.white,
          disabledColor: Colors.white24,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.redo_rounded),
        ),
      ];

  /// The canvas, with the framing tools, the caption and any progress on
  /// it.
  Widget _stageBox() {
    final edit = _edit;
    final hasContent = widget.sharedPost != null || edit != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(CLRadii.lg),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _stage(),
          if (edit != null && _phase == _Phase.editing)
            Positioned(top: 10, right: 10, child: _tools()),
          if (hasContent)
            Positioned(left: 12, right: 12, bottom: 12, child: _captionField()),
          if (_phase != _Phase.editing) _progress(),
        ],
      ),
    );
  }

  Widget _timeline(Composition edit, {required double maxHeight}) =>
      TimelineView(
        edit: edit,
        position: _player.position,
        maxTotal: _profile.maxDuration,
        thumbnails: _thumbnails,
        selection: _selection,
        onSelect: _select,
        onEdit: _onTimelineEdit,
        onEditEnd: _endGesture,
        onSeek: _player.seek,
        onScrubStart: _startScrub,
        onScrubEnd: _endScrub,
        onAddMedia: _chooseSource,
        onAddAudio: _addAudio,
        maxHeight: maxHeight,
        enabled: !_busy,
      );

  /// Who can see it, replies, and how long it lasts.
  Widget _pills() {
    final audience = ephemeralAudiences.firstWhere((a) => a.key == _audience,
        orElse: () => ephemeralAudiences.first);
    return Padding(
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
                : () => setState(() => _allowReplies = !_allowReplies),
          ),
          const Spacer(),
          const Icon(Icons.timer_outlined, size: 16, color: Colors.white60),
          const SizedBox(width: 4),
          const Text("24h",
              style: TextStyle(color: Colors.white60, fontSize: CLType.caption)),
        ],
      ),
    );
  }

  /// Play / pause, where the playhead is of how long, and Undo / Redo.
  Widget _transport(Composition edit) {
    final total = edit.naturalDuration;
    final over = total > _profile.maxDuration;
    final clips = edit.clips.length;
    final layers = edit.overlays.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
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
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              over
                  ? "Only the first ${TrimBar.lengthLabel(_profile.maxDuration)} is kept"
                  : "$clips ${clips == 1 ? "clip" : "clips"}"
                      "${layers > 0 ? " · $layers ${layers == 1 ? "layer" : "layers"}" : ""}"
                      " · up to ${TrimBar.lengthLabel(_profile.maxDuration)}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: over ? const Color(0xFFFFB74D) : Colors.white54,
                  fontSize: CLType.caption),
            ),
          ),
          ..._historyButtons(),
        ],
      ),
    );
  }

  /// What can be done to the picked card - or, with none picked, what can
  /// be added.
  Widget _selectionBar(Composition edit) {
    final selected = _selection;
    final enabled = !_busy;
    if (selected == null) {
      return SizedBox(
        height: 52,
        child: Row(
          children: [
            const SizedBox(width: 8),
            _BarAction(
              icon: Icons.add_photo_alternate_outlined,
              label: "Clips",
              onTap: enabled ? _chooseSource : null,
            ),
            _BarAction(
              icon: Icons.layers_outlined,
              label: "Layer",
              onTap: enabled ? _addLayer : null,
            ),
            _BarAction(
              icon: Icons.music_note_rounded,
              label: "Music",
              onTap: enabled ? _addAudio : null,
            ),
            _BarAction(
              icon: Icons.text_fields_rounded,
              label: "Text",
              onTap: enabled ? _addText : null,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                "Tap a card to edit it · hold one to move it",
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white38, fontSize: CLType.meta),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      );
    }
    final isText =
        selected.isOverlay && edit.overlays[selected.index].isText;
    final MediaLayer? clip = switch (selected.kind) {
      TimelineKind.clip => edit.clips[selected.index],
      TimelineKind.overlay => edit.overlays[selected.index].clip,
      TimelineKind.track => null,
    };
    final hasSound =
        clip == null || (clip.source.isVideo && clip.source.hasAudio);
    // A blank either side of it, however small: it can be put against
    // what is there.
    final blanks = _blanksOf(edit, selected);
    final after = blanks.after;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _BarAction(
                    icon: Icons.content_cut_rounded,
                    label: "Split",
                    onTap: enabled ? _split : null,
                  ),
                  if (blanks.before > Duration.zero)
                    _BarAction(
                      icon: blanks.first
                          ? Icons.first_page_rounded
                          : Icons.align_horizontal_left_rounded,
                      label: blanks.first
                          ? "Anchor to start"
                          : "Anchor to previous",
                      onTap: enabled ? () => _anchor(toNext: false) : null,
                    ),
                  if (after != null && after > Duration.zero)
                    _BarAction(
                      icon: Icons.align_horizontal_right_rounded,
                      label: "Anchor to next",
                      onTap: enabled ? () => _anchor(toNext: true) : null,
                    ),
                  if (clip != null)
                    _BarAction(
                      icon: Icons.control_point_duplicate_rounded,
                      label: "Duplicate",
                      onTap: enabled ? _duplicate : null,
                    ),
                  if (selected.isClip)
                    _BarAction(
                      icon: Icons.layers_outlined,
                      label: "To layer",
                      onTap: enabled ? _lift : null,
                    ),
                  if (isText)
                    _BarAction(
                      icon: Icons.edit_rounded,
                      label: "Edit text",
                      onTap: enabled ? () => _editText(selected.index) : null,
                    ),
                  if (selected.isOverlay) ...[
                    _BarAction(
                      icon: Icons.flip_to_front_rounded,
                      label: "Forward",
                      onTap: enabled ? () => _restack(forward: true) : null,
                    ),
                    _BarAction(
                      icon: Icons.flip_to_back_rounded,
                      label: "Back",
                      onTap: enabled ? () => _restack(forward: false) : null,
                    ),
                    // Words go over the clips, never in among them.
                    if (!isText)
                      _BarAction(
                        icon: Icons.vertical_align_bottom_rounded,
                        label: "To main",
                        onTap: enabled ? _toMain : null,
                      ),
                  ],
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
                ],
              ),
            ),
          ),
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

  /// The framing tools, down the canvas's right edge - for the picked layer
  /// while it shows, else the main clip on it. In a blank with no layer
  /// picked there is nothing to frame: only the background.
  Widget _tools() {
    const gap = SizedBox(height: 8);
    final layer = _framedLayer;
    final framing = _clipOf(layer) != null;
    final filled = _isFilled(layer);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (framing) ...[
          _RoundAction(
            icon:
                filled ? Icons.fit_screen_outlined : Icons.zoom_out_map_rounded,
            tooltip: filled ? "Fit" : "Fill",
            onTap: () => _toggleFill(layer),
          ),
          gap,
          _RoundAction(
            icon: Icons.rotate_90_degrees_cw_outlined,
            tooltip: "Rotate",
            onTap: () => _rotateQuarter(layer),
          ),
          gap,
        ],
        _RoundAction(
          icon: _edit!.background.isBlur
              ? Icons.blur_on_rounded
              : Icons.format_color_fill_rounded,
          tooltip: "Background",
          onTap: _chooseBackground,
        ),
        if (!_isPristine(layer)) ...[
          gap,
          _RoundAction(
            icon: Icons.restart_alt_rounded,
            tooltip: "Reset framing",
            onTap: () => _resetFraming(layer),
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
          child: SingleChildScrollView(
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: CLType.label,
                          fontWeight: FontWeight.w600)),
                ),
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
        // shows its original - scaled down rather than overflowing, and no
        // wider than a phone's width on a screen on its side.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 90),
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: math.min(constraints.maxWidth, 420),
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
          // Scrolls rather than overflowing a short screen (a phone on its
          // side with the keyboard up).
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                      onTap: () => _startFrom(0),
                    ),
                    const SizedBox(width: 18),
                    _SourceButton(
                      icon: Icons.videocam_outlined,
                      label: "Video",
                      onTap: () => _startFrom(1),
                    ),
                    const SizedBox(width: 18),
                    _SourceButton(
                      icon: Icons.photo_library_outlined,
                      label: "Gallery",
                      onTap: () => _startFrom(2),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // The main clip under the playhead - none in a blank - then the layers
    // showing there.
    final main = _current;
    final showing = edit.overlaysAt(_player.position.value);
    final base = main == null ? 0 : 1;
    final layers = [
      if (main != null)
        CanvasLayer(edit.clips[main], video: _player.videoFor(main)),
      for (final i in showing)
        CanvasLayer(edit.overlays[i].clip, video: _player.overlayVideoFor(i)),
    ];
    /// Canvas layer -> overlay index (null: the main clip).
    int? overlayOf(int layer) => layer < base ? null : showing[layer - base];
    final picked = _selection;
    final outlined = picked != null && picked.isOverlay
        ? showing.indexOf(picked.index)
        : -1;

    return Stack(
      fit: StackFit.expand,
      children: [
        EditCanvas(
          layers: layers,
          hasBase: main != null,
          background: edit.background,
          outlined: outlined < 0 ? null : outlined + base,
          enabled: _phase == _Phase.editing && !_preparing,
          onGestureStart: (layer) {
            if (_player.playing) _player.pause();
            _beginGesture();
            // Touching a layer picks it (its card, its tools); touching the
            // main clip while a layer was picked picks the main clip.
            final overlay = overlayOf(layer);
            if (overlay != null) {
              setState(() => _selection = TimelineSelection.overlay(overlay));
            } else if (_selection?.isOverlay == true && main != null) {
              setState(() => _selection = TimelineSelection.clip(main));
            }
          },
          onTransform: (layer, transform) =>
              _setTransform(overlayOf(layer), transform, gesture: true),
          onGestureEnd: _endGesture,
          // A text layer: its words to change; else, fit or fill.
          onDoubleTap: (layer) {
            final overlay = overlayOf(layer);
            if (overlay != null && edit.overlays[overlay].isText) {
              _editText(overlay);
            } else {
              _toggleFill(overlay);
            }
          },
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
