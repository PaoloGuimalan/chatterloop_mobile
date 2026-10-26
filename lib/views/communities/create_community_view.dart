import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';

class CreateCommunityView extends StatefulWidget {
  final CommunityApi? api;
  const CreateCommunityView({super.key, this.api});
  @override
  State<CreateCommunityView> createState() => _CreateCommunityViewState();
}

class _CreateCommunityViewState extends State<CreateCommunityView> {
  final _name = TextEditingController(),
      _slug = TextEditingController(),
      _description = TextEditingController();
  bool _private = false, _busy = false;
  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty) {
      CLAlerts.warning('Enter a community name');
      return;
    }
    if (_slug.text.trim().isEmpty) {
      CLAlerts.warning('Enter a community slug');
      return;
    }
    final actor = appStore.state.userAuth.user.entityId;
    setState(() {
      _busy = true;
    });
    try {
      final result = await (widget.api ?? CommunityApi()).create(
          name: _name.text.trim(),
          slug: _slug.text.trim(),
          description: _description.text.trim(),
          isPrivate: _private);
      if (!mounted || actor != appStore.state.userAuth.user.entityId) return;
      context.replace('/communities/${Uri.encodeComponent(result.realmId)}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
        });
        CLAlerts.requestError(e,
            fallback:
                'Could not create community. Check the name and slug and try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return CLScreen(
        backgroundColor: p.bg,
        appBar: AppBar(
            leadingWidth: 48,
            titleSpacing: 0,
            title: const Text('Create community')),
        body: Column(children: [
          Expanded(
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                      CLSpacing.contentGutter, 12, CLSpacing.contentGutter, 12),
                  children: [
                CLField(
                    controller: _name,
                    label: 'Community name',
                    placeholder: 'e.g. Photography Club'),
                const SizedBox(height: 12),
                CLField(
                    controller: _slug,
                    label: 'Slug',
                    placeholder: 'e.g. photography-club'),
                const SizedBox(height: 12),
                CLSegmentedChoice<bool>(
                    label: 'Privacy',
                    value: _private,
                    enabled: !_busy,
                    options: const [
                      CLSegmentedOption(false, 'Public', Icons.public),
                      CLSegmentedOption(true, 'Private', Icons.lock_outline),
                    ],
                    onChanged: (value) => setState(() => _private = value)),
                const SizedBox(height: 12),
                Text('Description',
                    style: TextStyle(
                        fontSize: CLType.caption,
                        color: p.text2,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                    controller: _description,
                    enabled: !_busy,
                    maxLines: 4,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(fontSize: CLType.bodySm, color: p.text),
                    decoration: InputDecoration(
                        hintText: 'Share what your community is about.',
                        hintStyle:
                            TextStyle(fontSize: CLType.caption, color: p.text3),
                        filled: true,
                        fillColor: p.input,
                        contentPadding: const EdgeInsets.all(14),
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: p.border),
                            borderRadius: BorderRadius.circular(CLRadii.sm)),
                        border: OutlineInputBorder(
                            borderSide: BorderSide(color: p.border),
                            borderRadius: BorderRadius.circular(CLRadii.sm)))),
                const SizedBox(height: 12),
                Text(
                    _private
                        ? 'Only members can see posts. New members request access.'
                        : 'Anyone can see posts. People can join freely.',
                    style: TextStyle(fontSize: CLType.caption, color: p.text2)),
              ])),
          Padding(
              padding: const EdgeInsets.fromLTRB(
                  CLSpacing.contentGutter, 8, CLSpacing.contentGutter, 12),
              child: CLBtn(
                  label: _busy ? 'Creating…' : 'Create community',
                  iconL: Icons.groups_outlined,
                  block: true,
                  size: CLBtnSize.lg,
                  onPressed: _busy ? null : _create)),
        ]));
  }
}
