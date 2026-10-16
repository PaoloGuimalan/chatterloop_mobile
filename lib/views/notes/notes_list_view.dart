import 'dart:async';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/notes_api.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/models/notes_models/note.dart';
import 'package:chatterloop_app/views/notes/writing_widgets.dart';
import 'package:chatterloop_app/views/notes/writing_skeletons.dart';
import 'package:chatterloop_app/views/notes/notes_masonry.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NotesListScreen extends StatefulWidget {
  const NotesListScreen({super.key, this.api});
  final NotesApi? api;
  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  NotesApi? _api;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final List<Note> _notes = [];
  Timer? _debounce;
  int _generation = 0;
  int _page = 1;
  int _count = 0;
  bool _next = false;
  bool _loading = true;
  bool _reordering = false;
  final _gridKey = GlobalKey();
  Map<String, Rect> _cardRects = {};
  List<Note>? _beforeDrag;
  String? _dragId;
  StreamSubscription? _accountSubscription;
  String? _error;
  @override
  void initState() {
    super.initState();
    _api = widget.api;
    _load(reset: true);
    _accountSubscription = appStore.onChange.listen((_) {
      if (_api != null && !_api!.isCurrent) {
        _api = null;
        _notes.clear();
        _next = false;
        _load(reset: true);
      }
    });
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300 && _next && !_loading) _load();
    });
  }

  @override
  void dispose() {
    _accountSubscription?.cancel();
    _generation++;
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    final generation = reset ? ++_generation : _generation;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _notes.clear();
    });
    try {
      final api = _api ??= await NotesApi.open();
      final page = reset ? 1 : _page + 1;
      final result = await api.list(page: page, search: _search.text.trim());
      if (!mounted || generation != _generation || !api.isCurrent) return;
      setState(() {
        final ids = _notes.map((n) => n.id).toSet();
        _notes.addAll(result.results.where((n) => ids.add(n.id)));
        _page = page;
        _next = result.hasNext;
        _count = result.count;
        _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = "Couldn't load notes. Retry";
          _loading = false;
        });
      }
    }
  }

  Future<void> _open([Note? note]) async {
    await context.push(note == null ? '/notes/new' : '/notes/${note.id}');
    if (mounted) _load(reset: true);
  }

  Future<void> _move(String id, String? before) async {
    if (_reordering || id == before || _search.text.trim().isNotEmpty) return;
    final previous = _beforeDrag ?? List<Note>.of(_notes);
    final api = _api!;
    final generation = _generation;
    setState(() {
      _reordering = true;
      _beforeDrag = null;
      _dragId = null;
      final index = _notes.indexWhere((n) => n.id == id);
      if (index >= 0) {
        final moved = _notes.removeAt(index);
        final target = before == null
            ? _notes.length
            : _notes.indexWhere((n) => n.id == before);
        _notes.insert(target < 0 ? _notes.length : target, moved);
      }
    });
    try {
      await api.reorder(id, before);
      // Keep cards mounted while refreshing the loaded prefix, so no blank
      // loading frame interrupts the animated drop.
      final pages = await Future.wait(
          List.generate(_page, (index) => api.list(page: index + 1)));
      if (mounted && generation == _generation && api.isCurrent) {
        setState(() {
          _notes
            ..clear()
            ..addAll(pages.expand((page) => page.results));
          _next = pages.last.hasNext;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation && api.isCurrent) {
        setState(() {
          _notes
            ..clear()
            ..addAll(previous);
          _error = "Couldn't reorder notes. Retry";
        });
      }
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  void _dragUpdate(Offset global) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _dragId == null) return;
    final local = box.globalToLocal(global);
    if (_cardRects.isEmpty) return;
    final hit = _cardRects.entries
        .where((entry) => entry.value.contains(local))
        .firstOrNull;
    final nearest = hit ??
        _cardRects.entries.reduce((a, b) =>
            (a.value.center - local).distanceSquared <=
                    (b.value.center - local).distanceSquared
                ? a
                : b);
    final target = _notes.indexWhere((note) => note.id == nearest.key);
    final current = _notes.indexWhere((note) => note.id == _dragId);
    if (current < 0 || target < 0 || current == target) return;
    setState(() => _notes.insert(target, _notes.removeAt(current)));
  }

  Future<void> _drop() async {
    final id = _dragId;
    if (id == null) return;
    final index = _notes.indexWhere((note) => note.id == id);
    var before = index + 1 < _notes.length ? _notes[index + 1].id : null;
    if (before == null && _next) {
      try {
        before = (await _api!.list(page: _page + 1)).results.firstOrNull?.id;
      } catch (_) {
        _cancelDrag();
        return;
      }
    }
    if (mounted) await _move(id, before);
  }

  void _cancelDrag() {
    if (!mounted || _beforeDrag == null) return;
    setState(() {
      _notes
        ..clear()
        ..addAll(_beforeDrag!);
      _beforeDrag = null;
      _dragId = null;
    });
  }

  Widget _animatedGrid(bool canMove) => DragTarget<String>(
        // Flutter checks the target before onDragStarted initializes _dragId.
        onWillAcceptWithDetails: (details) =>
            canMove && _notes.any((note) => note.id == details.data),
        onAcceptWithDetails: (_) => _drop(),
        builder: (context, candidates, rejected) => NotesMasonry(
          key: _gridKey,
          ids: _notes.map((note) => note.id).toList(),
          onLayout: (rects) => _cardRects = rects,
          itemBuilder: (context, index, width, height) =>
              LongPressDraggable<String>(
            data: _notes[index].id,
            maxSimultaneousDrags: canMove ? 1 : 0,
            delay: const Duration(milliseconds: 200),
            onDragStarted: () => setState(() {
              _dragId = _notes[index].id;
              _beforeDrag = List.of(_notes);
            }),
            onDragUpdate: (details) => _dragUpdate(details.globalPosition),
            onDragEnd: (details) {
              if (!details.wasAccepted) _cancelDrag();
            },
            feedback: Material(
                color: Colors.transparent,
                child: Transform.scale(
                    scale: 1.025,
                    child: SizedBox(
                        width: width,
                        height: height,
                        child: _card(_notes[index], false)))),
            childWhenDragging:
                Opacity(opacity: .22, child: _card(_notes[index], false)),
            child: _card(_notes[index], canMove),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final canMove = !_reordering && !_loading && _search.text.trim().isEmpty;
    return CLScreen(
        backgroundColor: p.bg,
        appBar: AppBar(
            centerTitle: false,
            leadingWidth: 48,
            titleSpacing: 4,
            title: Row(children: [
              Image.asset('assets/images/app-icon-notes.png',
                  width: 27, height: 27),
              const SizedBox(width: 9),
              const Text('Notes')
            ]),
            actions: [
              TextButton.icon(
                  onPressed: () => _open(),
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('New note'))
            ]),
        body: Column(children: [
          const WritingOwner(),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: WritingSearch(
                  controller: _search,
                  hint: 'Search notes',
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300),
                        () => _load(reset: true));
                  })),
          Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Row(children: [
                Text('$_count notes',
                    style: TextStyle(color: p.text3, fontSize: 11)),
                const Spacer(),
                Text(canMove ? 'Hold and drag to reorder' : 'Your notebook',
                    style: TextStyle(color: p.text3, fontSize: 11))
              ])),
          if (_error != null)
            TextButton(
                onPressed: () => _load(reset: true), child: Text(_error!)),
          Expanded(
              child: _loading && _notes.isEmpty
                  ? const NotesListSkeleton()
                  : _notes.isEmpty
                      ? Center(
                          child: Text(
                              _search.text.isEmpty
                                  ? 'A little space for your ideas.\nCreate your first note.'
                                  : 'No matching notes',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: p.text3)))
                      : RefreshIndicator(
                          onRefresh: () => _load(reset: true),
                          child: SingleChildScrollView(
                              controller: _scroll,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                              child: Column(children: [
                                _animatedGrid(canMove),
                                if (canMove)
                                  DragTarget<String>(
                                      onAcceptWithDetails: (details) =>
                                          _move(details.data, null),
                                      builder: (context, candidates,
                                              rejected) =>
                                          SizedBox(
                                              height: 48,
                                              child: Center(
                                                  child: Text('Move to end',
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: p.text3))))),
                                if (_next)
                                  TextButton(
                                      onPressed:
                                          _loading ? null : () => _load(),
                                      child: Text(
                                          _loading ? 'Loading…' : 'Load more')),
                              ])))),
        ]));
  }

  Widget _card(Note note, bool canMove) {
    final p = cl(context);
    final body = notePlainText(note.content);
    return InkWell(
        onTap: () => _open(note),
        borderRadius: BorderRadius.circular(14),
        child: Container(
            padding: const EdgeInsets.fromLTRB(12, 13, 8, 5),
            decoration: BoxDecoration(
                color: p.surface,
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(14)),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (note.title.trim().isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(note.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: p.text))),
                  if (body.isNotEmpty)
                    Text(body,
                        maxLines: 7,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, height: 1.65, color: p.text2)),
                  if (note.attachments.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                            '📎 ${note.attachments.first.fileName ?? 'Attachment'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: p.text3))),
                  Row(children: [
                    Expanded(
                        child: Text(
                            note.updatedAt == null
                                ? ''
                                : '${note.updatedAt!.month}/${note.updatedAt!.day}',
                            style: TextStyle(fontSize: 11, color: p.text3))),
                    PopupMenuButton<String>(
                        tooltip: 'Reorder note',
                        enabled: canMove,
                        icon: Icon(Icons.drag_indicator,
                            size: 18, color: p.text3),
                        onSelected: (value) => _move(
                            note.id, value == 'end' ? null : _notes.first.id),
                        itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'first', child: Text('Move to first')),
                              PopupMenuItem(
                                  value: 'end', child: Text('Move to end'))
                            ])
                  ]),
                ])));
  }
}
