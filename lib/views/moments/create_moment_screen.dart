import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/encoding_profile.dart';
import 'package:chatterloop_app/core/media/media_engine.dart';
import 'package:chatterloop_app/core/media/still_image.dart';
import 'package:chatterloop_app/core/media/widgets/edit_canvas.dart';
import 'package:chatterloop_app/core/media/widgets/trim_bar.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/moments_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_composer.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/models/post_models/ephemeral_models.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/views/moments/moment_shared_post_card.dart';
import 'package:chatterloop_app/views/moments/moments_strip.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// New Moment - a full-screen editor, the phone's way of doing web's Create
/// Moment modal: a 9:16 canvas, the caption on it, Share top-right, and
/// who-can-see / replies as two pills underneath.
///
/// A photo or video from the device is EDITED here - dragged, pinched,
/// twisted, fitted or filled over a blurred or plain background, a video
/// trimmed, a photo given sound - and rendered on the device into the MP4
/// that gets posted (lib/core/media). A photo becomes a 30s video, or as
/// long as its sound. Up to 2 minutes.
///
/// From a post's Share options it is that post instead ([sharedPost]),
/// posted as it is - no editor, no render.
class CreateMomentScreen extends StatefulWidget {
  final PostPreview? sharedPost;

  const CreateMomentScreen({super.key, this.sharedPost});

  @override
  State<CreateMomentScreen> createState() => _CreateMomentScreenState();
}

/// Where Share is up to.
enum _Phase { editing, rendering, uploading, posting }

typedef _Upload = ({
  String url,
  String mediaType,
  String fileName,
  String? fileId,
});

class _CreateMomentScreenState extends State<CreateMomentScreen> {
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
  /// This editor's temp folder (prepared photos); deleted on close.
  Directory? _workspace;
  Composition? _edit;

  /// Where the layer started, for Reset.
  LayerTransform _initialTransform = LayerTransform.fit;
  VideoPlayerController? _video;
  AudioPlayer? _songPlayer;
  StreamSubscription<Duration>? _songPosition;
  StreamSubscription<void>? _songDone;
  String? _songName;
  Duration? _songLength;
  bool _preparing = false;

  // ---- Preview.
  /// Where each track's preview is - the cards' playheads.
  Duration? _videoAt;
  Duration? _songAt;
  bool _restarting = false;

  /// A trim thumb is held: the preview shows that edge instead of playing.
  bool _scrubbing = false;
  DateTime _lastScrubSeek = DateTime(0);

  /// What each sound goes back to when unmuted.
  double _videoVolume = 1;
  double _songVolume = 1;

  // ---- Share.
  _Phase _phase = _Phase.editing;
  double _renderProgress = 0;
  RenderJob? _job;

  /// The last render and the edit it was made from (as JSON): Retry after a
  /// failed upload or post reuses it instead of rendering again - and the
  /// uploads too, once made.
  RenderResult? _rendered;
  String? _renderedFor;
  _Upload? _uploadedVideo;
  String? _uploadedPoster;
  bool _failed = false;

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
    _video?.removeListener(_onVideoTick);
    _video?.dispose();
    _songPosition?.cancel();
    _songDone?.cancel();
    _songPlayer?.dispose();
    final workspace = _workspace;
    if (workspace != null) workspace.delete(recursive: true).ignore();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  bool get _busy => _phase != _Phase.editing || _preparing;

  // ---------------------------------------------------------------- picking

  Future<void> _fromCamera({required bool video}) async {
    final picker = ImagePicker();
    final file = video
        ? await picker.pickVideo(
            source: ImageSource.camera, maxDuration: _profile.maxDuration)
        : await picker.pickImage(source: ImageSource.camera, imageQuality: 95);
    if (file == null) return;
    await _open(file.path, looksLikeVideo: video);
  }

  /// The phone's gallery (Android's photo picker) - one photo or video - not
  /// the file manager it used to open.
  Future<void> _fromGallery() async {
    final XFile? file;
    try {
      file = await ImagePicker().pickMedia();
    } catch (_) {
      if (mounted) _toast("Couldn't open your gallery");
      return;
    }
    if (file == null) return;
    await _open(
      file.path,
      looksLikeVideo: PendingMedia(
              path: file.path,
              name: file.name,
              size: 0,
              mimeType: file.mimeType)
          .isVideo,
    );
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

  /// Reads a picked file into an edit: a video is inspected by ffprobe, a
  /// photo decoded and prepared (upright, capped in size - see prepareStill).
  Future<void> _open(String path, {required bool looksLikeVideo}) async {
    setState(() => _preparing = true);
    try {
      final workspace =
          _workspace ??= await MediaEngine.instance.createWorkspace();
      MediaSource? source;
      if (!looksLikeVideo) {
        try {
          source = await prepareStill(path, workspace);
        } catch (_) {
          // Not a photo the platform can read - maybe a video by another
          // name; ffprobe decides below.
        }
      }
      source ??= await _probeVideo(path);
      if (source == null) {
        if (mounted) _toast("Couldn't open that file");
        return;
      }
      await _setSource(source);
    } catch (e) {
      debugPrint('CreateMoment: open failed: $e');
      if (mounted) _toast("Couldn't open that file");
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
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

  Future<void> _setSource(MediaSource source) async {
    await _removeSong();
    final old = _video;
    old?.removeListener(_onVideoTick);
    _video = null;
    _videoAt = null;
    _videoVolume = 1;
    await old?.dispose();

    final aspect = source.width / source.height;
    final canvas = _profile.aspectRatio;
    // Media close to the canvas's shape fills it; anything else fits whole,
    // over the blurred background.
    final initial = LayerTransform.fillScale(aspect, canvas) <= 1.3
        ? LayerTransform.fill(aspect, canvas)
        : LayerTransform.fit;

    TrimRange? trim;
    VideoPlayerController? video;
    if (source.isVideo) {
      final total = source.duration!;
      trim = TrimRange(Duration.zero,
          total > _profile.maxDuration ? _profile.maxDuration : total);
      // This preview is its own player, outside the app's shared pool - so
      // the pool's idle players (feed videos just scrolled past) let go of
      // their decoders first.
      await SharedVideoControllers.releaseIdle();
      // mixWithOthers: without it the video takes the device's audio focus
      // and the music player pauses it (and it the music) - the two would
      // never play together.
      video = VideoPlayerController.file(
        File(source.path),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      try {
        await video.initialize();
        await video.setVolume(source.hasAudio ? 1 : 0);
        await video.play();
        video.addListener(_onVideoTick);
      } catch (e) {
        debugPrint('CreateMoment: preview failed: $e');
      }
    }
    if (!mounted) {
      await video?.dispose();
      return;
    }
    setState(() {
      _initialTransform = initial;
      _edit = Composition(
        layer: MediaLayer(source: source, transform: initial, trim: trim),
      );
      _video = video;
      _failed = false;
    });
  }

  // ------------------------------------------------------------- previews
  //
  // The preview plays the edit as it will come out: the video's trimmed part
  // and the song's chosen part together from their starts, round and round,
  // at their volumes.

  /// Video ticks: its playhead, and the loop at the trimmed end.
  void _onVideoTick() {
    final video = _video;
    final trim = _edit?.layer.trim;
    if (video == null || trim == null) return;
    final value = video.value;
    if (!value.isInitialized) return;
    final pos = value.position;
    if (mounted &&
        ((_videoAt ?? Duration.zero) - pos).abs() >
            const Duration(milliseconds: 90)) {
      setState(() => _videoAt = pos);
    }
    if (_phase != _Phase.editing || _scrubbing) return;
    if ((value.isPlaying && pos >= trim.end) || value.isCompleted) {
      _restartPreview();
    }
  }

  void _onSongTick(Duration pos) {
    if (mounted) setState(() => _songAt = pos);
    final track = _edit?.audio;
    if (track == null || _phase != _Phase.editing || _scrubbing) return;
    if (pos >= track.trim.end) _songReachedEnd();
  }

  /// The song's part is over: over a photo it loops on its own; over a video
  /// it waits for the video to come round.
  void _songReachedEnd() {
    if (_edit?.layer.source.isVideo == true) {
      _songPlayer?.pause();
    } else {
      _restartPreview();
    }
  }

  /// Every track back to its start, playing.
  Future<void> _restartPreview() async {
    final edit = _edit;
    if (_restarting || edit == null || _phase != _Phase.editing) return;
    _restarting = true;
    try {
      final video = _video;
      final trim = edit.layer.trim;
      final ready = video != null && video.value.isInitialized;
      final track = edit.audio;
      final player = _songPlayer;
      if (ready && trim != null) {
        await video.pause();
        await video.seekTo(trim.start);
      }
      if (track != null && player != null) {
        await player.pause();
        await player.seek(track.trim.start);
      }
      if (!mounted || _phase != _Phase.editing || _scrubbing) return;
      _applyVolumes();
      await Future.wait([
        if (ready) video.play(),
        if (track != null && player != null) player.resume(),
      ]);
    } catch (e) {
      debugPrint('CreateMoment: preview restart failed: $e');
    } finally {
      _restarting = false;
    }
  }

  Future<void> _pausePreviews() async {
    await _video?.pause();
    await _songPlayer?.pause();
  }

  /// The edit's volumes on the preview players (which play at most 100%).
  void _applyVolumes() {
    final edit = _edit;
    if (edit == null) return;
    _video?.setVolume(
        edit.layer.soundHeard ? edit.layer.volume.clamp(0.0, 1.0) : 0);
    final track = edit.audio;
    if (track != null) _songPlayer?.setVolume(track.volume.clamp(0.0, 1.0));
  }

  void _startScrub() {
    _scrubbing = true;
    _pausePreviews();
  }

  void _endScrub() {
    _scrubbing = false;
    _restartPreview();
  }

  // ----------------------------------------------------------------- sound

  /// Short fades where the song is cut, so it doesn't start or stop on a
  /// click. (A song cut by a shorter video fades at the video's end - the
  /// renderer places the fade within the part actually used.)
  AudioTrack _withFades(AudioTrack track) => track.copyWith(
        fadeIn: track.trim.start > Duration.zero
            ? const Duration(milliseconds: 300)
            : Duration.zero,
        fadeOut: track.trim.length >= const Duration(seconds: 4)
            ? const Duration(seconds: 1)
            : Duration.zero,
      );

  /// The longest part of a song that can be used: a video's trimmed length
  /// (the song can't outlast it), else the 2-minute cap.
  Duration get _songMaxSpan {
    final layer = _edit!.layer;
    return layer.source.isVideo ? layer.trim!.length : _profile.maxDuration;
  }

  Future<void> _pickSong() async {
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
      final max = _songMaxSpan;
      final trim = TrimRange(Duration.zero, length > max ? max : length);
      final player = _songPlayer ??= AudioPlayer();
      // Plays alongside the video preview instead of taking audio focus
      // from it (see the video's mixWithOthers).
      await player.setAudioContext(
          AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
              .build());
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setSource(DeviceFileSource(path));
      _songPosition ??= player.onPositionChanged.listen(_onSongTick);
      _songDone ??= player.onPlayerComplete.listen((_) => _songReachedEnd());
      if (!mounted) return;
      _songVolume = 1;
      setState(() {
        _songName = file.name;
        _songLength = length;
        _songAt = Duration.zero;
        _edit = _edit!
            .copyWith(audio: _withFades(AudioTrack(path: path, trim: trim)));
        _failed = false;
      });
      // From the top, together with the video.
      await _restartPreview();
    } on MediaEngineException {
      if (mounted) _toast("Couldn't use that audio file");
    } catch (e) {
      debugPrint('CreateMoment: song failed: $e');
      if (mounted) _toast("Couldn't use that audio file");
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _removeSong() async {
    await _songPlayer?.stop();
    if (!mounted) return;
    setState(() {
      _songName = null;
      _songLength = null;
      _songAt = null;
      if (_edit?.audio != null) _edit = _edit!.copyWith(clearAudio: true);
    });
  }

  void _setVideoVolume(double volume) {
    if (volume > 0) _videoVolume = volume;
    final edit = _edit!;
    setState(() =>
        _edit = edit.copyWith(layer: edit.layer.copyWith(volume: volume)));
    _applyVolumes();
  }

  void _setSongVolume(double volume) {
    final track = _edit?.audio;
    if (track == null) return;
    if (volume > 0) _songVolume = volume;
    setState(
        () => _edit = _edit!.copyWith(audio: track.copyWith(volume: volume)));
    _applyVolumes();
  }

  void _toggleVideoMute() =>
      _setVideoVolume(_edit!.layer.volume > 0 ? 0 : _videoVolume);

  void _toggleSongMute() =>
      _setSongVolume((_edit!.audio?.volume ?? 0) > 0 ? 0 : _songVolume);

  Future<void> _openMixer() async {
    final edit = _edit!;
    final source = edit.layer.source;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cl(context).surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(CLRadii.lg))),
      builder: (_) => _SoundMixSheet(
        videoVolume:
            source.isVideo && source.hasAudio ? edit.layer.volume : null,
        videoRestore: _videoVolume,
        songVolume: edit.audio?.volume,
        songRestore: _songVolume,
        songName: _songName,
        onVideo: _setVideoVolume,
        onSong: _setSongVolume,
      ),
    );
  }

  // ------------------------------------------------------------------ edits

  void _setTransform(LayerTransform transform) {
    final edit = _edit;
    if (edit == null) return;
    setState(() => _edit =
        edit.copyWith(layer: edit.layer.copyWith(transform: transform)));
  }

  double get _fillScale {
    final source = _edit!.layer.source;
    return LayerTransform.fillScale(
        source.width / source.height, _profile.aspectRatio);
  }

  /// Fills the canvas: no bars, straight, centred.
  bool get _isFilled {
    final t = _edit!.layer.transform;
    return (t.scale - _fillScale).abs() < 0.01 &&
        t.cx == 0.5 &&
        t.cy == 0.5 &&
        t.rotationDeg % 360 == 0;
  }

  void _toggleFill() {
    final source = _edit!.layer.source;
    _setTransform(_isFilled
        ? LayerTransform.fit
        : LayerTransform.fill(
            source.width / source.height, _profile.aspectRatio));
  }

  /// On to the next quarter turn clockwise (a twisted layer straightens to
  /// the next one first).
  void _rotateQuarter() {
    final t = _edit!.layer.transform;
    final next = ((t.rotationDeg / 90).floor() + 1) * 90.0;
    _setTransform(t.copyWith(rotationDeg: next % 360));
  }

  void _setVideoTrim(TrimRange trim) {
    final edit = _edit!;
    final previous = edit.layer.trim!;
    _scrubTo(trim.start != previous.start
        ? trim.start
        : trim.end - const Duration(milliseconds: 40));
    // The song can't outlast the video: its part shrinks along with it.
    var track = edit.audio;
    if (track != null && track.trim.length > trim.length) {
      track = _withFades(track.copyWith(
          trim: TrimRange(track.trim.start, track.trim.start + trim.length)));
    }
    setState(() => _edit =
        edit.copyWith(layer: edit.layer.copyWith(trim: trim), audio: track));
  }

  /// While a video edge is dragged, the canvas shows the frame there (at
  /// most every 80ms - seeks are not free).
  void _scrubTo(Duration at) {
    final video = _video;
    final now = DateTime.now();
    if (video == null ||
        !video.value.isInitialized ||
        now.difference(_lastScrubSeek) < const Duration(milliseconds: 80)) {
      return;
    }
    _lastScrubSeek = now;
    video.seekTo(at < Duration.zero ? Duration.zero : at);
  }

  void _setSongTrim(TrimRange trim) {
    final track = _edit!.audio!;
    setState(() =>
        _edit = _edit!.copyWith(audio: _withFades(track.copyWith(trim: trim))));
  }

  void _reset() {
    setState(() {
      _edit = _edit!.copyWith(background: CompositionBackground.blur);
    });
    _setTransform(_initialTransform);
  }

  bool get _isPristine {
    final edit = _edit!;
    final t = edit.layer.transform, i = _initialTransform;
    return edit.background.isBlur &&
        t.cx == i.cx &&
        t.cy == i.cy &&
        t.scale == i.scale &&
        t.rotationDeg == i.rotationDeg;
  }

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
      setState(() => _edit = _edit!.copyWith(background: picked));
    }
  }

  // ------------------------------------------------------------------ share

  bool get _ready =>
      !_busy &&
      (widget.sharedPost != null || _edit != null) &&
      ephemeralCharCount(_caption.text.trim()) <= momentCaptionMaxLength;

  Future<void> _share() async {
    if (!_ready) return;
    FocusScope.of(context).unfocus();
    if (widget.sharedPost != null) return _shareSharedPost();

    final edit = _edit!;
    await _pausePreviews();
    try {
      final rendered = await _renderFor(edit);
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
        source: edit.layer.source.isVideo ? 'video' : 'photo',
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
              const Text("Try again, or try a different photo or video."),
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
  Future<RenderResult?> _renderFor(Composition edit) async {
    final key = jsonEncode(edit.toJson());
    final previous = _rendered;
    if (previous != null && _renderedFor == key) return previous;
    await _dropRender();

    setState(() {
      _phase = _Phase.rendering;
      _renderProgress = 0;
    });
    final job = _job = MediaEngine.instance.render(edit, profile: _profile);
    void onProgress() {
      if (mounted) setState(() => _renderProgress = job.progress.value);
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
    _restartPreview();
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
    final uploading = _phase == _Phase.uploading || _phase == _Phase.posting;

    return PopScope(
      // A render can be abandoned (leaving cancels it); an upload or post
      // in flight can't be taken back, so it is waited out.
      canPop: !uploading,
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
                      onPressed: uploading ? null : () => context.pop(),
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
                    CLBtn(
                      label: _phase != _Phase.editing
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
                            if (_edit != null && _phase == _Phase.editing)
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
              if (_edit != null) _timeline(),
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
                          : () =>
                              setState(() => _allowReplies = !_allowReplies),
                    ),
                    const Spacer(),
                    if (_edit != null) ...[
                      const Icon(Icons.movie_outlined,
                          size: 16, color: Colors.white60),
                      const SizedBox(width: 4),
                      Text(_lengthLabel(),
                          style: const TextStyle(
                              color: Colors.white60, fontSize: CLType.caption)),
                      const SizedBox(width: 10),
                    ],
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

  String _lengthLabel() {
    final natural = _edit!.naturalDuration;
    return TrimBar.lengthLabel(
        natural > _profile.maxDuration ? _profile.maxDuration : natural);
  }

  /// The edit's tools, down the canvas's right edge.
  Widget _tools() {
    final edit = _edit!;
    final source = edit.layer.source;
    const gap = SizedBox(height: 8);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundAction(
          icon: Icons.swap_horiz_rounded,
          tooltip: "Replace",
          onTap: _chooseSource,
        ),
        gap,
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
          icon: edit.background.isBlur
              ? Icons.blur_on_rounded
              : Icons.format_color_fill_rounded,
          tooltip: "Background",
          onTap: _chooseBackground,
        ),
        if ((source.isVideo && source.hasAudio) || edit.audio != null) ...[
          gap,
          _RoundAction(
            icon: Icons.tune_rounded,
            tooltip: "Sound mix",
            onTap: _openMixer,
          ),
        ],
        if (!_isPristine) ...[
          gap,
          _RoundAction(
            icon: Icons.restart_alt_rounded,
            tooltip: "Reset",
            onTap: _reset,
          ),
        ],
      ],
    );
  }

  /// Under the canvas, one card per track, stacked like an editor's
  /// timeline: the video (trim + its sound), then the music (its part + its
  /// volume) - or a button to add music.
  Widget _timeline() {
    final edit = _edit!;
    final source = edit.layer.source;
    final track = edit.audio;
    final enabled = _phase == _Phase.editing && !_preparing;
    final cards = <Widget>[
      if (source.isVideo)
        TrimBar(
          icon: Icons.videocam_outlined,
          title: "Video",
          total: source.duration!,
          range: edit.layer.trim!,
          maxSpan: _profile.maxDuration,
          position: _videoAt,
          enabled: enabled,
          onChangeStart: (_) => _startScrub(),
          onChanged: _setVideoTrim,
          onChangeEnd: (_) => _endScrub(),
          actions: [
            if (source.hasAudio)
              _SoundButton(
                volume: edit.layer.volume,
                onTap: enabled ? _toggleVideoMute : null,
                onLongPress: enabled ? _openMixer : null,
              ),
          ],
        ),
      if (track != null && _songLength != null)
        TrimBar(
          icon: Icons.music_note_rounded,
          title: _songName ?? "Music",
          total: _songLength!,
          range: track.trim,
          maxSpan: _songMaxSpan,
          position: _songAt,
          enabled: enabled,
          onChangeStart: (_) => _startScrub(),
          onChanged: _setSongTrim,
          onChangeEnd: (_) => _endScrub(),
          actions: [
            _SoundButton(
              volume: track.volume,
              onTap: enabled ? _toggleSongMute : null,
              onLongPress: enabled ? _openMixer : null,
            ),
            IconButton(
              tooltip: "Remove music",
              visualDensity: VisualDensity.compact,
              onPressed: enabled ? _removeSong : null,
              icon: const Icon(Icons.close_rounded,
                  size: 18, color: Colors.white70),
            ),
          ],
        )
      else
        Align(
          alignment: Alignment.centerLeft,
          child: _Pill(
            icon: Icons.music_note_rounded,
            label: "Add music",
            onTap: enabled ? _pickSong : null,
          ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, card) in cards.indexed) ...[
            if (i > 0) const SizedBox(height: 6),
            card,
          ],
        ],
      ),
    );
  }

  Widget _progress() {
    final label = switch (_phase) {
      _Phase.rendering =>
        "Preparing your moment… ${(_renderProgress * 100).round()}%",
      _Phase.uploading => "Uploading…",
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

    return Stack(
      fit: StackFit.expand,
      children: [
        EditCanvas(
          composition: edit,
          video: _video,
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

/// A track card's sound: tap mutes / unmutes, long-press opens the mix.
/// Shows the level when it is neither full nor off.
class _SoundButton extends StatelessWidget {
  final double volume;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _SoundButton({required this.volume, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final muted = volume <= 0;
    final partial = !muted && (volume - 1).abs() > 0.005;
    return Tooltip(
      message: muted ? "Unmute" : "Mute",
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(CLRadii.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 18,
                color: muted ? Colors.white54 : Colors.white,
              ),
              if (partial) ...[
                const SizedBox(width: 2),
                Text("${(volume * 100).round()}%",
                    style: const TextStyle(
                        color: Colors.white70, fontSize: CLType.meta)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The sound mix: the video's own sound and the music, each with a level and
/// a mute - mute one, both, or blend them.
class _SoundMixSheet extends StatefulWidget {
  /// Null when there is no such sound (a photo, a silent video, no music).
  final double? videoVolume;
  final double? songVolume;

  /// The levels unmuting goes back to.
  final double videoRestore;
  final double songRestore;
  final String? songName;
  final ValueChanged<double> onVideo;
  final ValueChanged<double> onSong;

  const _SoundMixSheet({
    required this.videoVolume,
    required this.songVolume,
    required this.videoRestore,
    required this.songRestore,
    required this.songName,
    required this.onVideo,
    required this.onSong,
  });

  @override
  State<_SoundMixSheet> createState() => _SoundMixSheetState();
}

class _SoundMixSheetState extends State<_SoundMixSheet> {
  late double? _video = widget.videoVolume;
  late double? _song = widget.songVolume;
  late double _videoRestore = widget.videoRestore;
  late double _songRestore = widget.songRestore;

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    Widget row({
      required IconData icon,
      required String label,
      required double value,
      required double restore,
      required ValueChanged<double> onChanged,
    }) {
      final muted = value <= 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: p.text2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: CLType.title,
                          fontWeight: FontWeight.w700,
                          color: p.text)),
                ),
                Text(muted ? "Muted" : "${(value * 100).round()}%",
                    style: TextStyle(fontSize: CLType.caption, color: p.text2)),
                IconButton(
                  tooltip: muted ? "Unmute" : "Mute",
                  onPressed: () => onChanged(muted ? restore : 0),
                  icon: Icon(
                    muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: muted ? p.text2 : p.brand,
                  ),
                ),
              ],
            ),
            Slider(
              value: value.clamp(0.0, 1.0),
              divisions: 20,
              onChanged: onChanged,
            ),
          ],
        ),
      );
    }

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
            Text("Sound mix",
                style: TextStyle(
                    fontSize: CLType.sectionTitle,
                    fontWeight: FontWeight.w800,
                    color: p.text)),
            const SizedBox(height: 4),
            Text("Both play together - lower one to hear the other.",
                style: TextStyle(fontSize: CLType.caption, color: p.text2)),
            const SizedBox(height: 12),
            if (_video != null)
              row(
                icon: Icons.videocam_outlined,
                label: "Video sound",
                value: _video!,
                restore: _videoRestore,
                onChanged: (v) {
                  setState(() {
                    _video = v;
                    if (v > 0) _videoRestore = v;
                  });
                  widget.onVideo(v);
                },
              ),
            if (_song != null)
              row(
                icon: Icons.music_note_rounded,
                label: widget.songName ?? "Music",
                value: _song!,
                restore: _songRestore,
                onChanged: (v) {
                  setState(() {
                    _song = v;
                    if (v > 0) _songRestore = v;
                  });
                  widget.onSong(v);
                },
              ),
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
