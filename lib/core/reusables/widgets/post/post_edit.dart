import 'dart:io';
import 'dart:math' as math;

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_composer.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/core/utils/post_updates.dart';
import 'package:chatterloop_app/core/utils/upload_limits.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Capture both the identity and its credential before the editor opens.
/// Upload completion, retries and the PUT all keep that credential.
class _PostEditIdentity {
  final accountId = appStore.state.userAuth.user.id;
  final entityId = appStore.state.userAuth.user.entityId;
  final session = PostUpdates.instance.session;
  final token = ApiClient.instance.readToken().catchError((_) => null);

  bool get isCurrent =>
      appStore.state.userAuth.auth == true &&
      appStore.state.userAuth.user.id == accountId &&
      appStore.state.userAuth.user.entityId == entityId &&
      PostUpdates.instance.session == session;

  Future<bool> matches(String? captured) async {
    try {
      return captured != null &&
          captured.isNotEmpty &&
          isCurrent &&
          await ApiClient.instance.readToken() == captured &&
          isCurrent;
    } catch (_) {
      return false;
    }
  }
}

/// Content editing is a route of its own. Audience stays a separate action.
Future<PostPreview?> openPostEditor(BuildContext context, PostPreview post) {
  FocusManager.instance.primaryFocus?.unfocus();
  return Navigator.of(context, rootNavigator: true).push<PostPreview>(
    MaterialPageRoute(
        builder: (_) =>
            PostEditScreen(post: PostUpdates.instance.resolve(post))),
  );
}

class PostEditScreen extends StatefulWidget {
  final PostPreview post;
  const PostEditScreen({super.key, required this.post});

  @override
  State<PostEditScreen> createState() => _PostEditScreenState();
}

class _PostEditScreenState extends State<PostEditScreen> {
  late final _caption = TextEditingController(text: widget.post.caption);
  late final _retained = List<PostReference>.of(widget.post.references);
  final _picked = <PendingMedia>[];
  // A failed PUT can be retried without uploading already completed files twice.
  final _uploaded = <String, String>{};
  final _pages = PageController();
  final _identity = _PostEditIdentity();
  int _index = 0;
  bool _saving = false;
  bool _allowPop = false;
  String _progress = '';

  bool get _fixed =>
      widget.post.isShared ||
      !const ['text', 'media'].contains(widget.post.contentType);
  bool get _dirty =>
      _caption.text != widget.post.caption ||
      _picked.isNotEmpty ||
      _retained.length != widget.post.references.length;
  bool get _nonempty =>
      _caption.text.trim().isNotEmpty ||
      _retained.isNotEmpty ||
      _picked.isNotEmpty;

  @override
  void dispose() {
    _caption.dispose();
    _pages.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: cl(ctx).surface,
          title: Text('Discard changes?',
              style: TextStyle(
                  color: cl(ctx).text,
                  fontSize: CLType.screenTitle,
                  fontWeight: FontWeight.w600)),
          content: Text('Your changes to this post will be lost.',
              style: TextStyle(color: cl(ctx).text2, fontSize: CLType.body)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep editing',
                    style: TextStyle(fontSize: CLType.label))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Discard',
                    style: TextStyle(
                        color: cl(ctx).pink, fontSize: CLType.label))),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _pick() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final files = await ImagePicker().pickMultipleMedia();
      if (!mounted) return;
      var rejected = 0;
      final additions = <PendingMedia>[];
      for (final file in files) {
        final size = await File(file.path).length();
        if (size > UploadLimits.of(UploadFeature.postMedia).maxBytes) {
          rejected++;
          continue;
        }
        if (_picked.any((item) => item.path == file.path) ||
            additions.any((item) => item.path == file.path)) {
          continue;
        }
        additions.add(PendingMedia(
            path: file.path,
            name: file.name,
            size: size,
            mimeType: file.mimeType));
      }
      if (!mounted) return;
      setState(() => _picked.addAll(additions));
      if (rejected > 0) {
        CLAlerts.show(
            'Skipped $rejected file(s) over ${UploadLimits.of(UploadFeature.postMedia).label}',
            type: CLAlertType.warning);
      }
    } catch (_) {
      if (mounted) CLAlerts.error("Couldn't open your gallery");
    }
  }

  bool _sameIdentity() =>
      _identity.isCurrent && _identity.entityId == widget.post.author.entityId;

  Future<void> _save() async {
    if (_saving || !_dirty || !_nonempty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _progress = 'Saving changes…';
    });
    final token = await _identity.token;
    final valid = _sameIdentity() && await _identity.matches(token);
    if (!mounted) return;
    if (!valid) {
      setState(() => _saving = false);
      CLAlerts.error(
          'Switch back to the identity that owns this post to save.');
      return;
    }
    for (var i = 0; i < _picked.length; i++) {
      final item = _picked[i];
      if (_uploaded.containsKey(item.path)) continue;
      if (!_sameIdentity() || !await _identity.matches(token)) break;
      if (!mounted) return;
      setState(() => _progress = 'Uploading ${i + 1} of ${_picked.length}…');
      final upload = await ProfileApi().uploadMediaRequest(
          item.path, item.mimeType ?? item.mediaType,
          action: 'post', authToken: token);
      if (!mounted) return;
      if (upload == null) {
        setState(() => _saving = false);
        return;
      }
      _uploaded[item.path] = upload.url;
    }
    final stillCurrent = _sameIdentity() && await _identity.matches(token);
    if (!mounted) return;
    if (!stillCurrent) {
      setState(() => _saving = false);
      CLAlerts.error(
          'Switch back to the identity that owns this post to save.');
      return;
    }
    setState(() => _progress = 'Saving changes…');
    final mediaChanged =
        _picked.isNotEmpty || _retained.length != widget.post.references.length;
    final patch = await NewsfeedApi().updatePostRequest(
      postId: widget.post.postId,
      authToken: token,
      fields: {
        'caption': _caption.text.trim().isEmpty ? '' : _caption.text,
        if (!_fixed && mediaChanged)
          'references': [
            for (final ref in _retained) {'reference_id': ref.referenceId},
            for (final item in _picked) {'url': _uploaded[item.path]!},
          ],
      },
    );
    final current = await _identity.matches(token);
    if (patch != null && current) {
      PostUpdates.instance.apply(patch, forSession: _identity.session);
    }
    if (!mounted) return;
    if (patch == null || !current) {
      setState(() => _saving = false);
      return;
    }
    setState(() => _allowPop = true);
    final updated = widget.post.applyPatch(patch);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(updated);
    });
  }

  Widget _preview({PostReference? reference, PendingMedia? pending}) {
    final source = reference?.reference ?? pending!.path;
    final video = reference?.isVideo ?? pending!.isVideo;
    if (video) {
      return VideoPlayerScreen(
        key: ValueKey(source),
        videoUrl: source,
        isLocalFile: pending != null,
        anchorControlsToBounds: true,
      );
    }
    return CLNetworkImage(
        src: source,
        isLocal: pending != null,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity);
  }

  Widget _media() {
    final p = cl(context);
    if (_fixed) {
      final media = _retained.where((r) => r.isImage || r.isVideo).toList();
      if (media.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.post.isCoverPhotoPost ? 'Cover photo' : 'Profile photo',
            textAlign: TextAlign.start,
            style: TextStyle(color: p.text2, fontSize: CLType.caption)),
        const SizedBox(height: 10),
        Center(
            child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: widget.post.isCoverPhotoPost ? double.infinity : 248),
          child: AspectRatio(
              aspectRatio: widget.post.isCoverPhotoPost ? 16 / 7 : 1,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: _preview(reference: media.first))),
        )),
      ]);
    }
    final count = _retained.length + _picked.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
            child: Text('Photos and videos',
                textAlign: TextAlign.start,
                style: TextStyle(color: p.text2, fontSize: CLType.caption))),
        TextButton.icon(
            onPressed: _saving ? null : _pick,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Add media',
                style: TextStyle(fontSize: CLType.label))),
      ]),
      if (count == 0)
        OutlinedButton.icon(
            onPressed: _saving ? null : _pick,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text('Add photos or videos',
                    style: TextStyle(fontSize: CLType.label))))
      else
        ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                  color: p.surface2, border: Border.all(color: p.border)),
              child: Column(children: [
                SizedBox(
                    height: 250,
                    child: Stack(children: [
                      Positioned.fill(
                          child: PageView.builder(
                        controller: _pages,
                        itemCount: count,
                        physics: _saving
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        onPageChanged: (i) => setState(() => _index = i),
                        itemBuilder: (_, i) => i < _retained.length
                            ? _preview(reference: _retained[i])
                            : _preview(pending: _picked[i - _retained.length]),
                      )),
                      Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20)),
                            child: Text('${_index + 1} / $count',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: CLType.caption)),
                          )),
                      Positioned(
                          top: 3,
                          right: 3,
                          child: IconButton.filled(
                            tooltip: 'Remove attachment',
                            style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                                foregroundColor: Colors.white),
                            onPressed: _saving
                                ? null
                                : () {
                                    setState(() {
                                      if (_index < _retained.length) {
                                        _retained.removeAt(_index);
                                      } else {
                                        _picked.removeAt(
                                            _index - _retained.length);
                                      }
                                      _index = math.max(
                                          0, math.min(_index, count - 2));
                                    });
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (_pages.hasClients) {
                                        _pages.jumpToPage(_index);
                                      }
                                    });
                                  },
                            icon: const Icon(Icons.close, size: 20),
                          )),
                    ])),
                if (count > 1)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                                tooltip: 'Previous attachment',
                                onPressed: _saving || _index == 0
                                    ? null
                                    : () => _pages.previousPage(
                                        duration:
                                            const Duration(milliseconds: 180),
                                        curve: Curves.easeOut),
                                icon: const Icon(Icons.chevron_left)),
                            Text('${_index + 1} of $count',
                                style: TextStyle(
                                    color: p.text2, fontSize: CLType.caption)),
                            IconButton(
                                tooltip: 'Next attachment',
                                onPressed: _saving || _index == count - 1
                                    ? null
                                    : () => _pages.nextPage(
                                        duration:
                                            const Duration(milliseconds: 180),
                                        curve: Curves.easeOut),
                                icon: const Icon(Icons.chevron_right)),
                          ])),
              ]),
            )),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return PopScope<PostPreview>(
      canPop: _allowPop || (!_saving && !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          FocusManager.instance.primaryFocus?.unfocus();
        } else {
          _leave();
        }
      },
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: AppBar(
          centerTitle: false,
          leadingWidth: 48,
          titleSpacing: 4,
          backgroundColor: p.surface,
          foregroundColor: p.text,
          leading: IconButton(
              tooltip: 'Back',
              onPressed: _saving ? null : _leave,
              icon: const Icon(Icons.arrow_back)),
          title: const Text('Edit post',
              textAlign: TextAlign.start,
              style: TextStyle(
                  fontSize: CLType.title, fontWeight: FontWeight.w600)),
        ),
        body: SafeArea(
            top: false,
            child: Column(children: [
              Expanded(
                  child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                      children: [
                    Row(children: [
                      CLAvatar(
                          id: widget.post.author.entityId,
                          name: widget.post.author.displayName,
                          src: widget.post.author.profile,
                          kind: widget.post.author.type,
                          size: 38),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(widget.post.author.displayName,
                              textAlign: TextAlign.start,
                              style: TextStyle(
                                  color: p.text,
                                  fontSize: CLType.title,
                                  fontWeight: FontWeight.w600))),
                    ]),
                    const SizedBox(height: 22),
                    Text('Caption',
                        textAlign: TextAlign.start,
                        style: TextStyle(
                            color: p.text2,
                            fontSize: CLType.caption,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _caption,
                      textAlign: TextAlign.start,
                      enabled: !_saving,
                      minLines: 5,
                      maxLines: null,
                      onChanged: (_) => setState(() {}),
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(
                          color: p.text, fontSize: CLType.title, height: 1.6),
                      decoration: InputDecoration(
                        hintText: 'Say something about this…',
                        hintStyle: TextStyle(color: p.text3),
                        filled: true,
                        fillColor: p.surface2,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: p.border)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: p.border)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _media(),
                  ])),
              Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: p.border))),
                  child: CLBtn(
                      label: _saving ? _progress : 'Save changes',
                      block: true,
                      size: CLBtnSize.lg,
                      labelSize: CLType.label,
                      onPressed:
                          !_saving && _dirty && _nonempty ? _save : null)),
            ])),
      ),
    );
  }
}

Future<PostPreview?> showPostAudienceSheet(
    BuildContext context, PostPreview post) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<PostPreview>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: cl(context).surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => PostAudienceSheet(post: PostUpdates.instance.resolve(post)),
  );
}

class PostAudienceSheet extends StatefulWidget {
  final PostPreview post;
  const PostAudienceSheet({super.key, required this.post});
  @override
  State<PostAudienceSheet> createState() => _PostAudienceSheetState();
}

class _PostAudienceSheetState extends State<PostAudienceSheet> {
  final _identity = _PostEditIdentity();
  late String _audience = widget.post.privacyStatus;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final token = await _identity.token;
    final valid = _identity.entityId == widget.post.author.entityId &&
        await _identity.matches(token);
    if (!mounted) return;
    if (!valid) {
      setState(() => _saving = false);
      CLAlerts.error(
          'Switch back to the identity that owns this post to save.');
      return;
    }
    final patch = await NewsfeedApi().updatePostRequest(
        postId: widget.post.postId,
        fields: {'privacy_status': _audience},
        authToken: token);
    final current = await _identity.matches(token);
    if (patch != null && current) {
      PostUpdates.instance.apply(patch, forSession: _identity.session);
    }
    if (!mounted) return;
    if (patch == null || !current) {
      setState(() => _saving = false);
      return;
    }
    Navigator.pop(context, widget.post.applyPatch(patch));
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    const choices = [
      ('public', 'Public', 'Anyone can see this post', Icons.public),
      (
        'connections',
        'Contacts only',
        'Only your contacts can see this post',
        Icons.group_outlined
      ),
      ('private', 'Only me', 'Only you can see this post', Icons.lock_outline),
    ];
    return PopScope(
        canPop: !_saving,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, clSheetBottomGap(context, minimum: 24)),
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Center(
                    child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: p.border2,
                            borderRadius: BorderRadius.circular(3)))),
                const SizedBox(height: 20),
                Text('Change audience',
                    textAlign: TextAlign.start,
                    style: TextStyle(
                        color: p.text,
                        fontSize: CLType.screenTitle,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('Choose who can see this post.',
                    textAlign: TextAlign.start,
                    style: TextStyle(color: p.text2, fontSize: CLType.body)),
                const SizedBox(height: 14),
                for (final choice in choices)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                        backgroundColor: p.surface2,
                        child: Icon(choice.$4, color: p.text2, size: 20)),
                    title: Text(choice.$2,
                        textAlign: TextAlign.start,
                        style:
                            TextStyle(color: p.text, fontSize: CLType.title)),
                    subtitle: Text(choice.$3,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                            color: p.text2, fontSize: CLType.caption)),
                    trailing: Icon(
                        _audience == choice.$1
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: _audience == choice.$1 ? p.brand : p.text3),
                    selected: _audience == choice.$1,
                    onTap: _saving
                        ? null
                        : () => setState(() => _audience = choice.$1),
                  ),
                const SizedBox(height: 12),
                Text('Changing the audience won’t mark this post as edited.',
                    textAlign: TextAlign.start,
                    style: TextStyle(color: p.text2, fontSize: CLType.caption)),
                const SizedBox(height: 20),
                CLBtn(
                    label: _saving ? 'Saving…' : 'Save audience',
                    block: true,
                    size: CLBtnSize.lg,
                    labelSize: CLType.label,
                    onPressed:
                        !_saving && _audience != widget.post.privacyStatus
                            ? _save
                            : null),
              ])),
        ));
  }
}
