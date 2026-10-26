import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
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
  final _form = GlobalKey<FormState>();
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
    if (_busy || !_form.currentState!.validate()) return;
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
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: cl(context).bg,
      appBar: AppBar(
          leadingWidth: 48,
          titleSpacing: 0,
          title: const Text('Create community')),
      body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(14), children: [
            const Text('A place to belong',
                style: TextStyle(
                    fontSize: CLType.sectionTitle,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Bring people together around a shared interest.',
                style:
                    TextStyle(fontSize: CLType.body, color: cl(context).text2)),
            const SizedBox(height: 24),
            _label(context, 'Community name'),
            const SizedBox(height: 8),
            TextFormField(
                controller: _name,
                enabled: !_busy,
                style:
                    TextStyle(fontSize: CLType.bodySm, color: cl(context).text),
                decoration: _decoration(context, 'e.g. Photography Club'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter a community name'
                    : null),
            const SizedBox(height: 16),
            _label(context, 'Slug'),
            const SizedBox(height: 8),
            TextFormField(
                controller: _slug,
                enabled: !_busy,
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter a community slug'
                    : null,
                style:
                    TextStyle(fontSize: CLType.bodySm, color: cl(context).text),
                decoration: _decoration(context, 'e.g. photography-club')
                    .copyWith(helperText: 'Your community’s profile address')),
            const SizedBox(height: 16),
            _label(context, 'Description'),
            const SizedBox(height: 8),
            TextFormField(
                controller: _description,
                enabled: !_busy,
                style:
                    TextStyle(fontSize: CLType.bodySm, color: cl(context).text),
                textAlignVertical: TextAlignVertical.top,
                maxLines: 4,
                decoration: _decoration(
                    context, 'Share what your community is about.')),
            const SizedBox(height: 20),
            const Text('Privacy',
                style: TextStyle(
                    fontSize: CLType.sectionTitle,
                    fontWeight: FontWeight.w700)),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Private',
                    style: TextStyle(fontSize: CLType.label)),
                subtitle: Text(
                    _private
                        ? 'Only members can see posts. New members request access.'
                        : 'Anyone can see posts. People can join freely.',
                    style: TextStyle(
                        fontSize: CLType.caption, color: cl(context).text2)),
                value: _private,
                onChanged:
                    _busy ? null : (value) => setState(() => _private = value)),
            const SizedBox(height: 20),
            const Text(
                'You’ll manage this community through Manage Realm using your current profile.',
                style: TextStyle(fontSize: CLType.caption)),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: _busy ? null : _create,
                child: Text(_busy ? 'Creating…' : 'Create community',
                    style: const TextStyle(fontSize: CLType.label))),
          ])));

  Widget _label(BuildContext context, String text) => Text(text,
      style: TextStyle(
          fontSize: CLType.label,
          fontWeight: FontWeight.w600,
          color: cl(context).text));

  InputDecoration _decoration(BuildContext context, String hint) {
    final p = cl(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(CLRadii.sm),
      borderSide: BorderSide(color: p.border),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: CLType.caption, color: p.text3),
      contentPadding: const EdgeInsets.all(14),
      helperStyle: TextStyle(fontSize: CLType.caption, color: p.text3),
      errorStyle: TextStyle(fontSize: CLType.caption, color: p.pink),
      fillColor: p.surface,
      filled: true,
      border: border,
      enabledBorder: border,
    );
  }
}
